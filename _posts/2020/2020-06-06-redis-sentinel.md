---
layout: post
title:  "[redis 源码走读] sentinel 哨兵 - 原理"
categories: redis
tags: redis sentinel
author: wenfh2020
---

redis 有主从数据复制功能。多个实例通过读写分离，使得单进程的 redis 可以充分利用多核性能。

当某些 redis 实例出现故障怎么办，服务还能正常工作吗？这时候故障管理者 `sentinel` 应运而生。它负责 redis 集群管理工作：检查故障，发现故障，转移故障，从而保证集群高可用。



* content
{:toc}

---

## 1. sentinel 作用

1. 监控： 检查 redis 节点健康状况。
2. 故障转移：当 redis 集群节点出现故障时，及时自动进行故障转移。
3. 通知：检测到 redis 实例出现故障，通过 api 进行通知用户。
4. 提供配置：用户可以通过命令查询当前 redis 集群相关信息。

---

## 2. 集群

### 2.1. 角色关系

redis 高可用集群，有三种角色：`master`，`slave`，`sentinel`。

* slave 与 master 通信，为了数据复制。
* sentinel 与 master / slave 通信，为了对 master / slave 进行管理：检查故障，发现故障，转移故障。
* sentinel 节点之间通信，为了选举 leader，通过 leader 进行集群故障转移。

<div align=center><img src="/images/2023/2023-09-23-18-43-29.png" data-action="zoom"></div>

---

### 2.2. 节点链接

sentinel 只要配置 redis 主服务（master）信息即可与三个角色建立联系。

```shell
# sentinel.conf
# sentinel monitor <master-name> <ip> <redis-port> <quorum>
sentinel monitor mymaster 127.0.0.1 6379 2
```

>\<quorum\> 是`法定人数`。作用：多个 sentinel 进行相互选举，有超过一定`法定人数`选举某人为领导，那么他就成为 sentinel 的领导，领导负责故障转移。这个法定人数，可以配置，一般是 sentinel 个数一半以上 (n/2 + 1) 比较合理。

<div align=center><img src="/images/2023/2023-09-23-18-42-14.png" data-action="zoom"></div>

```shell
sentinel <--> master，sentinel <--> slave，sentinel A <--> sentinel B
```

* sentinel 向 master 获取 slave 信息，与 slave 建立连接。

   master 与 slave 是主从关系，master 拥有所有 slave 的链接信息。sentinel 只要配置 master 的 ip 和 port，链接 master，并通过 `info` 命令就能获得 slave 的 ip 和 port 信息。这样 sentinel 就可以与 slave 建立链接。

* 多个 sentinel 相互链接。

   通过以上步骤，sentinel 可以链接 master / slave。而多个 sentinel 通过发布/订阅 master / slave 的 `__sentinel__:hello` 频道进行发布和接收信息。多个 sentinel 不需要配置对方的信息，就能获得通过这个流程获得其它 sentinel 的信息并进行相互链接。

> 详细流程，可以参考 《[[redis 源码走读] sentinel 哨兵 - 节点链接流程](https://wenfh2020.com/2020/06/12/redis-sentinel-nodes-contact/)》

---

## 3. 故障

sentinel 监控流程：检测故障 -> 发现故障 -> 处理故障。

redis 集群三个角色 sentinel / master / slave 都可能出现故障，当 redis master 出现故障，sentinel leader 对集群进行故障转移。

---

### 3.1. 检测故障

角色节点之间建立了联系，那么 sentinel 与其它节点通过定期发送相应命令（`PING / INFO / PUBLISH`）进行相互通信。

---

### 3.2. 发现故障

1. 当对方（master）命令回复异常或者长期收不到对方回复，那么 sentinel 发现了故障，暂时将该节点标记为主动下线。
2. sentinel 向其它 sentinel 节点询问，是否同样检测到该结点出现故障。
3. 其它节点回复确认故障，当前 sentinel 将该节点标记为客观下线。

<div align=center><img src="/images/2023/2023-09-23-18-47-21.png" data-action="zoom"></div>

---

### 3.3. 故障转移

* sentinel 选举 leader。
* sentinel leader 根据规则筛选合适的 slave 作为 master。
* 通知其它 slave 链接新的 master。
* 旧 master 如果重新上线，被 sentinel 设置成为新 master 的 slave。

---

## 4. 参考

* [Redis Sentinel Documentation](https://redis.io/topics/sentinel)
* [[redis 源码走读] 主从数据复制 ①](https://wenfh2020.com/2020/05/17/redis-replication/)
* [[redis 源码走读] 主从数据复制 ②](https://wenfh2020.com/2020/05/31/redis-replication-next/)
* 《redis 实现与设计》
* [分布式算法之选举算法Raft](https://blog.csdn.net/cainaioaaa/article/details/79881296)
* [10分钟弄懂Raft算法](http://blog.itpub.net/31556438/viewspace-2637112/)
* [Redis开发与运维之第九章哨兵(四)--配置优化](https://blog.csdn.net/cuiwjava/article/details/99405508)
* [用 gdb 调试 redis](https://wenfh2020.com/2020/01/05/redis-gdb/)
