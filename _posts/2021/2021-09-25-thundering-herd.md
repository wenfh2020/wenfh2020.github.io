---
layout: post
title:  "探索惊群 ①"
categories: network
tags: thundering herd
author: wenfh2020
stickie: true
---

惊群比较抽象，类似于抢红包 😁。它多出现在高性能的多进程/多线程服务中，例如：nginx。

`探索惊群` 系列文章将深入 Linux (5.0.1) 内核，透过 `多进程模型` 去剖析惊群现象、惊群原理、惊群的解决方案。




* content
{:toc}

---

1. [探索惊群 ①（★）](https://wenfh2020.com/2021/09/25/thundering-herd/)
2. [探索惊群 ② - accept](https://wenfh2020.com/2021/09/27/thundering-herd-accept/)
3. [探索惊群 ③ - nginx 惊群现象](https://wenfh2020.com/2021/09/29/nginx-thundering-herd/)
4. [探索惊群 ④ - nginx - accept_mutex](https://wenfh2020.com/2021/10/10/nginx-thundering-herd-accept-mutex/)
5. [探索惊群 ⑤ - nginx - NGX_EXCLUSIVE_EVENT](https://wenfh2020.com/2021/10/11/thundering-herd-nginx-epollexclusive/)
6. [探索惊群 ⑥ - nginx - reuseport](https://wenfh2020.com/2021/10/12/thundering-herd-tcp-reuseport/)
7. [探索惊群 ⑦ - 文件描述符透传](https://wenfh2020.com/2021/10/13/thundering-herd-transfer-socket/)

---

## 1. 概述

### 1.1. 惊群现象

多进程睡眠等待 `共享` 资源，当资源到来时，多个进程被 `无差别` 唤醒，争抢处理资源。

---

### 1.2. 惊群影响

惊群导致软件系统工作效率低下：

1. 部分进程被频繁唤醒却获取资源失败，导致进程上下文频繁切换，系统资源开销大。
2. 多进程争抢共享资源，有的抢得多，有的抢得少，资源分配不均。

---

### 1.3. 惊群原因

进程睡眠 `唤醒` 时机问题，详细请参考：[探索惊群 ③ - nginx 惊群现象](https://wenfh2020.com/2021/09/29/nginx-thundering-herd/)

---

## 2. 解决方案

需要围绕两个方面去展开。

1. 避免共享资源争抢（独占）。
2. 资源尽量合理分配。

换个角度去思考，如果红包私发，而不是扔进群组里... 这个思路应该是解决惊群问题的关键。😎

---

我们可以参考 nginx 解决惊群问题的经典方案：

1. [探索惊群 ④ - nginx - accept_mutex](https://wenfh2020.com/2021/10/10/nginx-thundering-herd-accept-mutex/)
2. [探索惊群 ⑤ - nginx - NGX_EXCLUSIVE_EVENT](https://wenfh2020.com/2021/10/11/thundering-herd-nginx-epollexclusive/)
3. [探索惊群 ⑥ - nginx - reuseport](https://wenfh2020.com/2021/10/12/thundering-herd-tcp-reuseport/)

---

### 2.1. reuseport

内核解决惊群问题，目前 nginx 最好的惊群解决方案，基于 linux 内核 `so_reuseport` 端口重用网络特性。

1. 每个子进程拥有独立的 listen socket 资源队列，避免资源争抢；多个队列也提升了并发吞吐。
2. 新链接通过网络四元组通过哈希分配到各个子进程的 listen socket 资源队列，资源分配相对合理（负载均衡）。

<div align=center><img src="/images/2021/2021-07-31-19-20-51.png" data-action="zoom"/></div>

---

### 2.2. NGX_EXCLUSIVE_EVENT

内核解决惊群问题，基于 linux 4.5+ 内核增加的 epoll 属性 EPOLLEXCLUSIVE 独占资源属性。

原理非常简单，只唤醒一个睡眠等待的进程处理资源。避免无差别地唤醒多个进程，尽量使得各个进程忙碌起来。

缺点：

1. 多个进程争抢一个 listen socket 的共享资源。
2. 单个资源队列，将会是并发吞吐瓶颈。

<div align=center><img src="/images/2021/2021-11-04-11-33-40.png" data-action="zoom"/></div>

---

### 2.3. accept_mutex

应用层解决惊群问题，多个子进程通过应用层抢锁，成功者可以独占 listen socket 获取资源的权利。

优点：有效地避免了惊群。

缺点：

1. 因为抢锁时机问题，原来抢到锁的进程下次抢到锁的概率很高，导致有些进程很忙，有些没那么忙，负载不均，资源利用率比较低。
2. 一个时间段内，只有一个子进程独占 listen socket 的共享资源，无法同时利用多核优势。
3. 单个资源队列，将会是并发吞吐瓶颈。

<div align=center><img src="/images/2021/2021-10-11-12-57-59.png" data-action="zoom"/></div>

---

## 3. 参考

* [Nginx惊群效应引起的系统高负载](https://zhuanlan.zhihu.com/p/401910162)
