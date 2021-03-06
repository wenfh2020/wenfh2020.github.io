---
layout: post
title:  "redis 为啥这么快"
categories: redis
tags: redis fast
author: wenfh2020
---

redis 为啥那么快？redis 单进程轻松并发 10w+ ([《hiredis + libev 异步测试》](https://wenfh2020.com/2018/06/17/redis-hiredis-libev/))。本章从这几个角度进行分析：单进程，单线程，多线程，多进程，多实例。



* content
{:toc}

---

## 1. 单进程

redis 核心逻辑在单进程主线程里实现。

---

### 1.1. 单线程

* 数据存储在内存。

  > redis 一般作为缓存，它的数据存储在内存，而 cpu 访问内存速度非常快。

* 哈希表。
  
  > redis 是 Nosql 数据库，数据访问模式是 `key - value`，数据索引是哈希表，搜索数据的时间复杂度是 O(1)。

* 多路复用技术。

  > redis 运用了多路复用技术对事件进行管理。例如：Linux 用 `epoll`。

* 非阻塞异步 I/O。

  > 主逻辑在单进程，单线程，需要尽量减少有阻塞的缓慢操作，所以网络通信大部分设置为非阻塞模式。

* pipeline。
  
  > 支持客户端一次发送多个命令。减少了客户端和服务端通信的 RTT (Round-Trip Time) 往返时间；一次发送和接收多个数据，减少了 read()/write() 内核函数的调用，降低系统性能损耗。
  >
  > 详细请参考官方文档：《[Using pipelining to speedup Redis queries](https://redis.io/topics/pipelining)》

---

### 1.2. 多线程

redis 有部分场景需要子进程和子线程辅助。

* 后台回收数据线程。

  > redis 惰性异步回收数据。回收数据量比较大的数据集，redis 会通过后台线程（[bio](https://github.com/antirez/redis/blob/unstable/src/bio.c)）进行回收。先从哈希表删除 key，切断数据与主逻辑的联系，再把数据（value）放进后台线程里异步回收。这样不影响主线程主业务的运行。

* 多线程读写通信。
  
  > redis 6.0 增加多线程读写网络事件功能。[《[redis 源码走读] 多线程通信 I/O》](https://wenfh2020.com/2020/04/13/redis-multithreading-mode/)

---

## 2. 多进程

redis 主服务是单进程的。单进程不能充分利用系统 cpu 核心，可以通过多开实例提高系统的并发能力。

---

### 2.1. 子进程

redis 有持久化功能：aof 和 rdb 方式。持久化需要将内存数据写入磁盘，写磁盘是缓慢的 I/O，为了避免影响主进程性能，有些需要对整个内存数据集落地的操作，会通过 fork 子进程进行。例如 aof 的 rewrite 操作，rdb 持久化。

---

### 2.2. 多实例

* 主从副本（replication）。

  > 主从复制数据，使得服务数据有多个数据副本，可以进行读写分离。

* 高可用。

  > 1. sentinel 哨兵模式。
  > 2. redis cluster 自带集群模式。
  > 3. 第三方代理模式（例如 codis）。

* proxy

  > redis 可以开多个实例，提高系统并发能力，这些实例通过第三方代理（例如 [codis](https://github.com/CodisLabs/codis)）进行扩容缩容，对数据进行分片管理。

* redis cluster

  > redis 自带集群 cluster 无中心架构，通过 Gossip 协议将多个实例数据分片建立成一个整体。

---

## 3. 总结

从以上几个视角分析了 redis 快的主要原因。天下大事，必作于细，redis 的快，还建立在很多细节的优化上，有兴趣可以通过阅读它的源码去详细了解。
