---
layout: post
title:  "探索惊群 ⑦ - 文件描述符透传"
categories: network
tags: linux thundering herd transfer socket
author: wenfh2020
---

惊群的两大核心问题，多进程/多线程争抢公共资源，还有资源分配的负载均衡问题。换个角度思考问题：既然是多个争抢，那么只有一个进程/线程获取资源，这样就不存在资源争抢问题了。

与 nginx 的 accept_mutex 解决方案不同的是，它的 listen socket 不共享，始终由一个进程独占工作。

有一种文件描述传递的多进程架构，就是这样做的。




* content
{:toc}

---

## 1. 原理

比较典型的多进程架构(master/children)的服务模型，就是一个进程去 accept listener 的完全队列资源，然后通过 socket pair 管道进行文件描述符传输给它的子进程。相当于客户端链接间接分派到子进程上去工作了。

如下图，master 主进程负责 listener 资源的 accept，当主进程获得资源，按照一定的策略（负载均衡），分派给相应的子进程。

<div align=center><img src="/images/2021-09-28-14-10-47.png" data-action="zoom"/></div>

> 参考：《[[kimserver] 父子进程传输文件描述符](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)》

---

## 2. 优点

因为 master 只负责简单的进程管理和资源 accept 并发送，所以资源处理比较高效，不仅巧妙地避免了资源的争抢开销，还能用户自行处理资源的分配。

---

## 3. 缺点

虽然方法很巧妙，但是依然是一个进程处理资源，限制了多进程的并行吞吐，例如：密集的短链接高并发场景。而且文件描述符的传输也需要用户额外编写代码维护，文件描述符传输也有一定的系统资源消耗。

---

## 4. 参考

* [[kimserver] 父子进程传输文件描述符](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)