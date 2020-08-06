---
layout: post
title:  "redis 持久化方式 - aof 和 rdb 区别"
categories: redis
tags: redis aof rdb difference
author: wenfh2020
---

aof 和 rdb 是 redis 持久化的两种方式。我们看看它们的特点和具体应用场景区别。



* content
{:toc}

---

## 1. 持久化特点

### 1.1. aof

* aof 是写命令追加到持久化文件的方式。
* aof 支持几种持久化策略，其中每秒数据增量存盘一次效率比较高。
* aof 支持 rdb 混合型存储（需要重写处理）。
* aof 一定程度上记录了 redis 的写操作流水，一段时间内文件冗余数据比较大需要重写解决问题。

---

### 1.2. rdb

* rdb 快照，一个时间点的 redis 内存数据全盘落地（快照）。
* rdb 文件是二进制数据压缩文件，数据落地速度快（相对），体积小。
* 因为 redis 内存是全部数据落地，操作频率不能太高，通过配置持久化频率，几分钟到几小时不等。

---

## 2. 使用场景区别

根据 aof 和 rdb 持久化特点，我们看看应用场景主要区别：

* 数据恢复
  
  redis 服务异常，aof 比 rdb 更有利于数据恢复。aof 默认每秒将数据增量追加到文件末存盘一次，rdb 是一个时间点的数据快照，时间跨度比较大。

* 数据备份
  
  rdb 是 redis 内存数据快照，速度快，体积小。更适合于数据备份存储。

* redis 服务启动速度
  
  redis 启动加载 rdb 文件 比 aof 快。 因为 aof 文件有冗余命令，rdb 是数据集合。

* 持久化速度
  
  aof 默认每秒存盘和 rdb 持久化都是异步存储，基本不影响主线程主逻辑功能。如果 aof 采用写命令实时存盘，将会严重影响 redis 服务性能。

* 集群节点间全量同步
  
  集群节点间数据全量同步，需要拷贝服务进程的内存数据，根据 rdb 持久化特点：速度快，体积小，显然 rdb 更适合于集群间数据传输。
  
---

## 3. 持久化详细文档

redis 持久化 aof 和 rdb 区别，详细文档可以参考 redis 作者的文章 [Redis Persistence](https://redis.io/topics/persistence#how-durable-is-the-append-only-file) 

> 链接可能被墙，用国内搜索引擎搜索下

要了解更多的细节，可以查看 redis 源码实现。redis 持久化源码理解，可以参考我的帖子：

* [[redis 源码走读] aof 持久化 (上)](https://wenfh2020.com/2020/03/29/redis-aof-prev/)

* [[redis 源码走读] aof 持久化 (下)](https://wenfh2020.com/2020/03/29/redis-aof-next/)

* [[redis 源码走读] rdb 持久化 - 文件结构](https://wenfh2020.com/2020/03/19/redis-rdb-struct/)

* [[redis 源码走读] rdb 持久化 - 应用场景](https://wenfh2020.com/2020/03/19/redis-rdb-application/)

---

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/2020/04/01/redis-persistence-diff/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
