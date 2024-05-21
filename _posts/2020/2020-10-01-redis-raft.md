---
layout: post
title:  "[redis 源码走读] redis 与 raft 算法"
categories: redis
tags: redis raft 
author: wenfh2020
---

redis 是否使用了 raft 一致性算法呢？

使用了，但不是严格意义上的 raft，然而 raft 算法的核心要点：领导者选举，日志复制，安全性，你都可以在 redis 中找到相似的实现。

下面将探索一下 redis 关于 raft 算法的有关实现。




* content
{:toc}

---

## 1. raft 算法

### 1.1. 概念

Raft 是一种用于分布式一致性的共识算法。它被设计用于在分布式系统中实现容错性，并确保系统中的所有节点达成一致的状态。Raft 算法由 Stanford 大学的 Diego Ongaro 和 John Ousterhout 于 2013 年提出，并已成为分布式系统领域中的重要研究课题。

Raft 算法的目标是提供一种易于理解和实现的共识算法，以替代复杂的 Paxos 算法。它通过将一致性问题分解为几个独立的子问题来实现这一目标。

Raft 算法的核心是 `领导者选举`、`日志复制` 和 `安全性`。

在 Raft 中，节点通过选举一个领导者来协调操作。领导者负责接收客户端请求，并将其复制到其他节点的日志中。一旦大多数节点确认了日志条目，它就会被提交并应用到状态机中。如果领导者失去联系或无法正常工作，Raft 算法会自动触发新的领导者选举。

Raft 算法的另一个关键特性是日志复制。当领导者接收到客户端请求时，它会将该请求附加到其日志中，并将其复制到其他节点的日志中。这种复制机制确保了系统中的所有节点具有相同的日志顺序，从而实现了一致性。

此外，Raft 算法还提供了安全性保证。它使用了一种称为领导者完整性检查的机制，以防止脑裂问题的发生。领导者完整性检查可以检测到网络分区或节点故障，并防止多个领导者同时存在。

总的来说，Raft 算法是一种可靠且易于理解的共识算法，适用于构建分布式系统。它通过领导者选举、日志复制和安全性保证来实现一致性。

> 部分文字来源：[The Raft Consensus Algorithm](https://raft.github.io/)，如果觉得文字抽象的朋友可以观看 [B 站的视频](https://www.bilibili.com/video/BV1so4y1r7eM/?spm_id_from=333.880.my_history.page.click&vd_source=a2a56cf0a934465d3945d595a71e68dc)。

---

### 1.2. 角色

Raft 算法中有三个角色：领导者（leader）、候选人（candidate）、跟随者（follower）。

* **领导者（leader）**：负责处理客户端请求，并将日志复制到其他节点。
* **候选人（candidate）**：是在选举过程中的临时角色，它负责发起选举并尝试成为新的领导者。
* **跟随者（follower）**：只是被动地接受来自领导者的指令，并将日志复制到自己的日志中。

> 部分文字来源：ChatGPT。

---

## 2. redis

试着从 raft 算法的几个特点（领导选举，日志复制，安全性）去理解一下 redis。

### 2.1. 领导选举

* raft 算法，当集群节点发现领导者故障下线，健康节点会重新选举，选出新的领导选举，由它去协调分布式系统操作。

---

* redis 哨兵选举策略与 raft 算法大同小异，都是通过（多轮）选举，选出票数超过半数（法定人数可配）的候选人作为领导选举。
* 而 redis（哨兵）集群节点有三种角色：master/slave/sentinel，sentinel 主要负责检测 master 故障，一旦发现 master [客观下线](https://wenfh2020.com/2020/06/15/redis-sentinel-master-down/)，sentinel 马上进入 [投票选举](https://wenfh2020.com/2020/09/26/redis-sentinel-vote/) 环节，从多个 sentinel 节点中选出领导选举，由它去执行 master 的 [故障转移](https://wenfh2020.com/2020/09/27/redis-sentinel-failover/)。

---

### 2.2. 日志复制

* raft 算法的数据复制是 `强一致`，领导者接收客户端的请求，将日志复制到其他节点，并确保被复制节点上的数据日志顺序一致。
* 当半数以上的其他节点成功接收日志，领导者才会确认该条日志提交成功，并修改其它节点上的日志状态为提交成功，通过这样的方式保证集群的数据一致性。

---

* redis 的数据复制是 `最终一致`，master 负责接收客户端的请求，将数据写入内存后，异步复制数据到 slave。
* slave 初始或断线重连 master，发现数据不一致后，会根据 slave 当前的数据偏移量或 master 节点 ID，向 master 实现增量同步或者全量同步。
* 如果 slave 正常链接 master，master 数据发生变化会正常发送给对应 slave，但不需要半数以上的 slave 节点确认接收才确认数据同步成功。
* redis 是高性能服务，它需要在保证性能的前提下进行数据复制，因此数据的 `最终一致` < `强一致`。

---

### 2.3. 安全性

* raft 算法的日志复制是强一致，安全性明显要比 redis 要好。
* raft 算法的领导选举，需要确保日志的 term 和日志的 index 最优的健康的节点当选领导者。

---

* redis 数据复制是最终一致，master 设置数据积压缓冲区和数据偏移量，与 slave 的数据量进行对比，进行数据复制实现最终一致。
* redis master 故障下线后，redis 哨兵重新选举，选出新的哨兵领导者。哨兵领导者在下线 master 的 slave 节点中筛选出最优（网络链接正常，优先级低，数据偏移量最大）的 slave 将其晋升为 master。

---

## 3. 小结

* redis 里并没有严格使用 raft 算法，它某些特点与 raft 算法相似。
* redis 哨兵的领导者选举与 raft 算法大同小异。
* redis 数据复制是最终一致，raft 算法是强一致。

---

## 4. 参考

* raft 算法官网[《The Raft Consensus Algorithm》](https://raft.github.io/)
* raft 算法中文翻译[《寻找一种易于理解的一致性算法（扩展版）》](https://github.com/maemual/raft-zh_cn/blob/master/raft-zh_cn.md)
* raft 算法[《动画 ppt》](http://thesecretlivesofdata.com/raft/)
* [动画：Raft算法Leader选举、脑裂后选举、日志复制、修复不一致日志和数据安全](https://www.bilibili.com/video/BV1so4y1r7eM/?spm_id_from=333.880.my_history.page.click&vd_source=a2a56cf0a934465d3945d595a71e68dc)

---

* [《[redis 源码走读] sentinel 哨兵 - 原理》](https://wenfh2020.com/2020/06/06/redis-sentinel/)
* [《[redis 源码走读] sentinel 哨兵 - 节点链接流程》](https://wenfh2020.com/2020/06/12/redis-sentinel-nodes-contact/)
* [《[redis 源码走读] sentinel 哨兵 - 主客观下线》](https://wenfh2020.com/2020/06/15/redis-sentinel-master-down/)
* [《[redis 源码走读] sentinel 哨兵 - 选举投票》](https://wenfh2020.com/2020/09/26/redis-sentinel-vote/)
* [《[redis 源码走读] sentinel 哨兵 - 故障转移》](https://wenfh2020.com/2020/09/27/redis-sentinel-failover/)
* [《[redis 源码走读] 主从数据复制 ①》](https://wenfh2020.com/2020/05/17/redis-replication/)
* [《[redis 源码走读] 主从数据复制 ②》](https://wenfh2020.com/2020/05/31/redis-replication-next/)
