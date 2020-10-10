---
layout: post
title:  "[redis 源码走读] raft 一致性算法"
categories: redis
tags: redis raft 
author: wenfh2020
---

raft 一致性算法，它是分布式系统中一种高可用算法策略。如果只单纯看论文算法，很难掌握它的工作流程。在 redis 里 raft 算法主要体现在：**redis 主从复制** 和 **sentinel 故障转移**，如果你有兴趣，可以研究对应 redis 源码，当这两个点理解了，raft 算法自然就理解了。




* content
{:toc}

---

* raft 算法官网[《The Raft Consensus Algorithm》](https://raft.github.io/)（连接可能需要翻墙）
* raft 算法中文翻译[《寻找一种易于理解的一致性算法（扩展版）》](https://github.com/maemual/raft-zh_cn/blob/master/raft-zh_cn.md)
* raft 算法[《动画 ppt》](http://thesecretlivesofdata.com/raft/)

* sentinel 系列：

    [《[redis 源码走读] sentinel 哨兵 - 故障转移》](https://wenfh2020.com/2020/09/27/redis-sentinel-failover/)

    [《[redis 源码走读] sentinel 哨兵 - 选举投票》](https://wenfh2020.com/2020/09/26/redis-sentinel-vote/)

    [《[redis 源码走读] sentinel 哨兵 - 主客观下线》](https://wenfh2020.com/2020/06/15/redis-sentinel-master-down/)

    [《[redis 源码走读] sentinel 哨兵 - 节点链接流程》](https://wenfh2020.com/2020/06/12/redis-sentinel-nodes-contact/)

    [《[redis 源码走读] sentinel 哨兵 - 原理》](https://wenfh2020.com/2020/06/06/redis-sentinel/)

    [《[redis 源码走读] sentinel 哨兵 - 脑裂处理方案》](https://wenfh2020.com/2019/12/27/redis-split-brain/)

* redis 主从复制。

    [《[redis 源码走读] 主从数据复制（下）》](https://wenfh2020.com/2020/05/31/redis-replication-next/)

    [《[redis 源码走读] 主从数据复制（上）》](https://wenfh2020.com/2020/05/17/redis-replication/)


---

> 🔥 文章来源：[《[redis 源码走读] sentinel 哨兵 - 故障转移》](https://wenfh2020.com/2020/09/27/redis-sentinel-failover/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
