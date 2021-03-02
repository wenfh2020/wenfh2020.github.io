---
layout: post
title:  "[redis 源码走读] raft 一致性算法"
categories: redis
tags: redis raft 
author: wenfh2020
---

raft 一致性算法，它是分布式系统中一种高可用算法策略。只单纯看论文算法，很难掌握它的工作流程，有兴趣的话，可以阅读 redis sentinel 哨兵源码实现，当理解了 sentinel 的工作原理后，raft 算法自然就理解了。




* content
{:toc}

---

## 1. 算法文档

* raft 算法官网[《The Raft Consensus Algorithm》](https://raft.github.io/)（连接可能需要翻墙）
* raft 算法中文翻译[《寻找一种易于理解的一致性算法（扩展版）》](https://github.com/maemual/raft-zh_cn/blob/master/raft-zh_cn.md)
* raft 算法[《动画 ppt》](http://thesecretlivesofdata.com/raft/)

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
  
  1. [《[redis 源码走读] 主从数据复制（上）》](https://wenfh2020.com/2020/05/17/redis-replication/)
  2. [《[redis 源码走读] 主从数据复制（下）》](https://wenfh2020.com/2020/05/31/redis-replication-next/)
