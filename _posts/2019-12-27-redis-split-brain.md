---
layout: post
title:  "[redis 源码走读] sentinel 哨兵 - 脑裂处理方案"
categories: redis
tags: split brain redis sentinel
author: wenfh2020
---

哨兵模式的 redis 集群，假如原来只有一个主服务，经过故障转移后，产生多个主服务，这样脑裂现象出现了。




* content
{:toc}

---

## 1. 原理

### 1.1. 概述

哨兵模式的 redis 集群有三种角色：sentinel/master/slave，它们通过 tcp 链接，相互建立联系。

sentinel 作为高可用集群管理者，它的功能主要是：检查故障，发现故障，故障转移。

---

### 1.2. 故障转移流程

1. 在 redis 集群中，当 sentinel 检测到 master 出现故障，那么 sentinel 需要对集群进行故障转移。
2. 当一个 sentinel 发现 master 下线，它会将下线的 master 确认为**主观下线**。
3. 当“法定个数”（quorum）sentinel 已经发现该 master 节点下线，那么 sentinel 会将其确认为**客观下线**。
4. 多个 sentinel 根据一定的逻辑，选举出一个 sentinel 作为代表，由它去进行故障转移，将原来连接已客观下线 master 最优的一个 slave 提升为新 master 角色。旧  master 如果重新激活，它将被降级为 slave。

> 详细请参考：《[[redis 源码走读] sentinel 哨兵 - 故障转移](https://wenfh2020.com/2020/09/27/redis-sentinel-failover/)》

---

### 1.3. 脑裂场景

我们看看下面的部署：两个机器，分别部署了 redis 的三个角色。

* 如果我们将集群部署在两个机器上（redis 集群部署情况如下图）。
* sentinel 配置 `quorum = 1`，也就是一个 sentinel 发现故障，也可以选举自己为代表，进行故障转移。

| 节点  | 描述                         |
| :---: | :--------------------------- |
|   M   | redis 主服务 master          |
|   R   | redis 副本 replication/slave |
|   S   | redis 哨兵 sentinel          |
|   C   | 链接 redis 客户端            |

```shell
+----+         +----+
| M1 |---------| R1 |
| S1 |         | S2 |
+----+         +----+
```

* 因为某种原因，两个机器断开链接，S2 将同机器的 R1 提升角色为 master，这样集群里，出现了两个 master 服务同时工作 —— 脑裂出现了。不同的 client 链接到不同的 redis 进行读写，那么在两台机器上的 redis 数据，就出现了不一致的现象了。

```shell
+----+           +------+
| M1 |----//-----| [M1] |
| S1 |           |  S2  |
+----+           +------+
```

---

## 2. 解决方案

### 2.1. sentienl 部署

1. sentinel 节点个数最好 >= 3。
2. sentinel 节点个数最好是基数。
3. sentinel 的选举法定人数设置为 (n/2 + 1)。

* 配置

```shell
# sentinel.conf
# sentinel monitor <master-name> <ip> <redis-port> <quorum>
```

* quorum

\<quorum\> 是`法定人数`。作用：多个 sentinel 进行相互选举，有超过一定`法定人数`选举某人为代表，那么他就成为 sentinel 的代表，代表负责故障转移。这个法定人数，可以配置，一般是 sentinel 个数一半以上 (n/2 + 1) 比较合理。

> 如果 sentinel 个数总数为 3，那么最好 quorum == 2，这样最接近真实：少数服从多数，不会出现两个票数一样的代表同时被选上，进行故障转移。
>
>```shell
># sentinel.conf
>sentinel monitor mymaster >127.0.0.1 6379 2
>```

---

### 2.2. redis 配置

#### 2.2.1. 问题

按照上述的 sentinel 部署方案，下面三个机器，任何一个机器出现问题，只要两个 sentinel 能相互链接，故障转移是正常的。

```shell
       +----+
       | M1 |
       | S1 |
       +----+
          |
+----+    |    +----+
| R2 |----+----| R3 |
| S2 |         | S3 |
+----+         +----+

Configuration: quorum = 2
```

假如 M1 机器与其它机器断开链接了，S2 和 S3 两个 sentinel 能相互链接，sentinel 能正常进行故障转移，sentinel 将 R2 提升为新的 master 角色 [M2]。但是客户端 C1 仍然能读写 M1，这样仍然会出现问题，所以我们不得不对 M1 进行限制。

```shell
         +----+
         | M1 |
         | S1 | <- C1 (writes will be lost)
         +----+
            |
            /
            /
+------+    |    +----+
| [M2] |----+----| R3 |
| S2   |         | S3 |
+------+         +----+
```

---

#### 2.2.2. 解决方案

限制 M1 比较简单的方案，修改 redis 配置 [redis.conf](https://github.com/antirez/redis/blob/unstable/redis.conf)，检查 master 节点与其它副本的联系。当 master 与其它副本在一定时间内失去联系，那么禁止 master 进行写数据。

> 但是这个方案也不是完美的，`min-slaves-to-write` 依赖于副本的链接个数，如果 slave 个数设置不合理，那么集群很难故障转移成功。

##### 2.2.2.1. 配置

* redis.conf

```shell
# It is possible for a master to stop accepting writes if there are less than
# N slaves connected, having a lag less or equal than M seconds.
#
# The N slaves need to be in "online" state.
#
# The lag in seconds, that must be <= the specified value, is calculated from
# the last ping received from the slave, that is usually sent every second.
#
# This option does not GUARANTEE that N replicas will accept the write, but
# will limit the window of exposure for lost writes in case not enough slaves
# are available, to the specified number of seconds.
#
# For example to require at least 3 slaves with a lag <= 10 seconds use:
#
# min-slaves-to-write 3
# min-slaves-max-lag 10
#
# Setting one or the other to 0 disables the feature.
#
# By default min-slaves-to-write is set to 0 (feature disabled) and
# min-slaves-max-lag is set to 10.
```

```shell
# master 至少有 x 个副本连接。
min-slaves-to-write x
# 数据复制和同步的延迟不能超过 x 秒。
min-slaves-max-lag x
```

> **注意：高版本 redis 已经修改这个两个选项**
>
>```shell
># min-replicas-to-write x
># min-replicas-max-lag x
>```

---

##### 2.2.2.2. 源码实现流程

* 时钟定期检查副本链接健康情况。

```c
#define run_with_period(_ms_) if ((_ms_ <= 1000/server.hz) || !(server.cronloops%((_ms_)/(1000/server.hz))))

int serverCron(struct aeEventLoop *eventLoop, long long id, void *clientData) {
  run_with_period(1000) replicationCron();
}

/* Replication cron function, called 1 time per second. */
// 复制周期执行的函数，每秒调用1次。
void replicationCron(void) {
    // 更新延迟至 lag 小于 min-slaves-max-lag 的从服务器数量
    refreshGoodSlavesCount();
}

/* This function counts the number of slaves with lag <= min-slaves-max-lag.
 * If the option is active, the server will prevent writes if there are not
 * enough connected slaves with the specified lag (or less). */
// 更新延迟至 lag 小 于min-slaves-max-lag 的从服务器数量
void refreshGoodSlavesCount(void) {
    listIter li;
    listNode *ln;
    int good = 0;

    // 没设置限制则返回。
    if (!server.repl_min_slaves_to_write ||
        !server.repl_min_slaves_max_lag) return;

    listRewind(server.slaves,&li);
    // 遍历所有的从节点 client。
    while((ln = listNext(&li))) {
        client *slave = ln->value;
        // 计算延迟值
        time_t lag = server.unixtime - slave->repl_ack_time;

        // 计数小于延迟限制的个数。
        if (slave->replstate == SLAVE_STATE_ONLINE &&
            lag <= server.repl_min_slaves_max_lag) good++;
    }
    server.repl_good_slaves_count = good;
}
```

* 超出配置范围，master 禁止写命令。

```c
int processCommand(client *c) {
    ...
    /* Don't accept write commands if there are not enough good slaves and
     * user configured the min-slaves-to-write option. */
    if (server.masterhost == NULL &&
        server.repl_min_slaves_to_write &&
        server.repl_min_slaves_max_lag &&
        c->cmd->flags & CMD_WRITE &&
        server.repl_good_slaves_count < server.repl_min_slaves_to_write)
    {
        flagTransaction(c);
        addReply(c, shared.noreplicaserr);
        return C_OK;
    }
    ...
}
```

---

## 3. 小结

* redis 脑裂主要表现为：同一个 redis 集群，原来的 master，经过故障转移后，出现多个 master。
* 解决方案主要通过 sentinel 哨兵的配置和 redis 的配置去解决问题。
* 上述方案也是有不足的地方，例如 redis 配置限制可能会受到副本个数的影响，所以具体设置，要看具体的业务场景。主要是怎么通过比较小的代价去解决问题，或者降低出现问题的概率。
* redis 虽然已经发布了 gossip 协议的无中心集群，sentinel 哨兵模式还是比较常用的，我们不建议直接使用 sentinel，可以考虑使用 codis。

---

## 4. 参考

* [Redis Sentinel Documentation](https://redis.io/topics/sentinel)
* [Replication](https://redis.io/topics/replication)
* [redis 脑裂等极端情况分析](https://www.cnblogs.com/yjmyzz/p/redis-split-brain-analysis.html)
* [redis 3.2.8 的源码注释](https://github.com/menwengit/redis_source_annotation)
