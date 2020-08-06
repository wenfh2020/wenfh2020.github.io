---
layout: post
title:  "redis 脑裂现象"
categories: redis
tags: split brain
author: wenfh2020
--- 

由于网络问题，集群节点失去联系。主从节点数据不同步；重新平衡选举，产生多个主服务，导致数据不一致。



* content
{:toc}

---

## 1. 解决方案

比较简单的方案，修改 redis 配置 [redis.conf](https://github.com/antirez/redis/blob/unstable/redis.conf) :

```shell
# master 至少有 N 个副本连接。
min-slaves-to-write 3
# 数据复制和同步的延迟不能超过 M 秒。
min-slaves-max-lag 10
```

> **注意：高版本 redis 已经修改这个两个选项**
>
>```shell
># min-replicas-to-write 3
># min-replicas-max-lag 10
>```

---

redis.conf 相关解析

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

---

## 2. 实现流程

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

## 3. 参考

* [Replication](https://redis.io/topics/replication)
* [redis 脑裂等极端情况分析](https://www.cnblogs.com/yjmyzz/p/redis-split-brain-analysis.html)
* [redis 3.2.8 的源码注释](https://github.com/menwengit/redis_source_annotation)

---

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/2019/12/27/redis-split-brain/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
