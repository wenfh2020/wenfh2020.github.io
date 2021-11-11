---
layout: post
title:  "探索惊群 ⑦ - 文件描述符透传"
categories: network
tags: linux thundering herd transfer socket
author: wenfh2020
---

文件描述符透传，它始终由一个进程（主进程）独占 listen socket，由它去获取资源，然后分派给其它的子进程。




* content
{:toc}

---

## 1. 原理

比较典型的多进程架构（master/workers）模型，就是一个进程去 accept listener 的完全队列资源，然后通过 socket pair 管道进行文件描述符传输给它的子进程，相当于客户端间接链接到子进程上去工作。

如下图，master 主进程负责 listener 资源的 accept，当主进程获得资源，按照一定的策略（取模/一致性哈希/...）负载均衡，分派给相应的子进程。

<div align=center><img src="/images/2021-11-11-09-31-35.png" data-action="zoom"/></div>

> 参考：《[[kimserver] 父子进程传输文件描述符](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)》

---

## 2. 优点

1. 因为 master 只负责简单的进程管理和资源 accept 并发送，所以资源处理比较高效，有效地避免惊群。
2. 主进程可以灵活地调整资源分配策略：轮询，取模，一致性哈希，等等。

---

## 3. 缺点

1. 依然是一个进程处理资源，限制了多进程的并行吞吐，例如：密集的短链接高并发场景。
2. 文件描述符的传输也需要用户额外编写代码维护。
3. 文件描述符传输也有一定的系统资源消耗。

---

## 4. 参考

* [[kimserver] 父子进程传输文件描述符](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)
