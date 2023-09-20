---
layout: post
title:  "[redis 源码走读] raft 一致性算法"
categories: redis
tags: redis raft 
author: wenfh2020
---

raft 一致性算法，它是分布式系统中一种高可用算法策略，只单纯看算法论文，很难掌握它的工作流程。

有兴趣的朋友，可以阅读 redis sentinel 源码，当理解了 sentinel 的工作原理，raft 算法自然理解了。




* content
{:toc}

---

## 1. raft 算法

### 1.1. 概念

Raft 是一种用于分布式一致性的共识算法。它被设计用于在分布式系统中实现容错性，并确保系统中的所有节点达成一致的状态。Raft 算法由 Stanford 大学的 Diego Ongaro 和 John Ousterhout 于 2013 年提出，并已成为分布式系统领域中的重要研究课题。

Raft 算法的目标是提供一种易于理解和实现的共识算法，以替代复杂的 Paxos 算法。它通过将一致性问题分解为几个独立的子问题来实现这一目标。Raft 算法的核心是领导者选举、日志复制和安全性。

在 Raft 中，节点通过选举一个领导者来协调操作。领导者负责接收客户端请求，并将其复制到其他节点的日志中。一旦大多数节点确认了日志条目，它就会被提交并应用到状态机中。如果领导者失去联系或无法正常工作，Raft 算法会自动触发新的领导者选举。

Raft 算法的另一个关键特性是日志复制。当领导者接收到客户端请求时，它会将该请求附加到其日志中，并将其复制到其他节点的日志中。这种复制机制确保了系统中的所有节点具有相同的日志顺序，从而实现了一致性。

此外，Raft 算法还提供了安全性保证。它使用了一种称为领导者完整性检查的机制，以防止脑裂问题的发生。领导者完整性检查可以检测到网络分区或节点故障，并防止多个领导者同时存在。

总的来说，Raft 算法是一种可靠且易于理解的共识算法，适用于构建分布式系统。它通过领导者选举、日志复制和安全性保证来实现一致性。

> 部分文字来源：[The Raft Consensus Algorithm](https://raft.github.io/)

---

### 1.2. 要点

raft 算法的核心要点：leader 选举，日志复制，数据安全性。

* 领导选举：Raft 算法通过选举一个领导者来协调分布式系统中的操作。选举过程中，每个节点都可以成为候选者，并通过投票来选择领导者。
* 日志复制：Raft 算法使用日志来记录系统状态的变化。领导者负责接收客户端的请求，并将其作为日志条目附加到自己的日志中。然后，领导者将这些日志条目发送给其他节点，以便复制它们的日志。
* 安全性：Raft 算法确保在正常情况下，只有领导者可以接受客户端的请求，并将其复制到其他节点。这样可以保证系统的一致性和安全性。
* 高可用性：Raft 算法允许系统在领导者失效时选择新的领导者，以确保系统的高可用性。
* 成员变更：Raft 算法允许动态地添加或删除节点，以适应系统的变化。

> 部分文字来源：ChatGPT。

---

### 1.3. 文档

个人只是简单浏览了一下 raft 算法的相关文档和论文，并没研读细节。B 站有个视频（[动画：Raft算法Leader选举、脑裂后选举、日志复制、修复不一致日志和数据安全](https://www.bilibili.com/video/BV1so4y1r7eM/?spm_id_from=333.880.my_history.page.click&vd_source=a2a56cf0a934465d3945d595a71e68dc)） 对 raft 算法的讲解还是挺通俗易懂的。

* raft 算法官网[《The Raft Consensus Algorithm》](https://raft.github.io/)
* raft 算法中文翻译[《寻找一种易于理解的一致性算法（扩展版）》](https://github.com/maemual/raft-zh_cn/blob/master/raft-zh_cn.md)
* raft 算法[《动画 ppt》](http://thesecretlivesofdata.com/raft/)
* [动画：Raft算法Leader选举、脑裂后选举、日志复制、修复不一致日志和数据安全](https://www.bilibili.com/video/BV1so4y1r7eM/?spm_id_from=333.880.my_history.page.click&vd_source=a2a56cf0a934465d3945d595a71e68dc)

---

## 2. redis 系列

### 2.1. sentinel
  
  1. [《[redis 源码走读] sentinel 哨兵 - 原理》](https://wenfh2020.com/2020/06/06/redis-sentinel/)
  2. [《[redis 源码走读] sentinel 哨兵 - 节点链接流程》](https://wenfh2020.com/2020/06/12/redis-sentinel-nodes-contact/)
  3. [《[redis 源码走读] sentinel 哨兵 - 主客观下线》](https://wenfh2020.com/2020/06/15/redis-sentinel-master-down/)
  4. [《[redis 源码走读] sentinel 哨兵 - 选举投票》](https://wenfh2020.com/2020/09/26/redis-sentinel-vote/)
  5. [《[redis 源码走读] sentinel 哨兵 - 故障转移》](https://wenfh2020.com/2020/09/27/redis-sentinel-failover/)
  6. [《[redis 源码走读] sentinel 哨兵 - 通知第三方》](https://wenfh2020.com/2020/10/09/redis-sentinel-script/)
  7. [《[redis 源码走读] sentinel 哨兵 - 脑裂处理方案》](https://wenfh2020.com/2019/12/27/redis-split-brain/)

---

### 2.2. 主从数据复制
  
  1. [《[redis 源码走读] 主从数据复制 ①》](https://wenfh2020.com/2020/05/17/redis-replication/)
  2. [《[redis 源码走读] 主从数据复制 ②》](https://wenfh2020.com/2020/05/31/redis-replication-next/)
