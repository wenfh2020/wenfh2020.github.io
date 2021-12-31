---
layout: post
title:  "tcp + epoll 内核睡眠唤醒工作流程"
categories: kernel
tags: tcp epoll kernel
author: wenfh2020
---

本章整理了一下服务端 tcp 的第三次握手和 epoll 内核的等待唤醒工作流程。



* content
{:toc}

---

## 1. 流程

<div align=center><img src="/images/2021-12-31-12-44-05.png" data-action="zoom"/></div>

1. 进程通过 epoll_create 创建 eventpoll 对象。
2. 进程通过 epoll_ctl 添加关注 listen socket 的 EPOLLIN 可读事件。
3. 接步骤 2，epoll_ctl 还将 epoll 的 socket 唤醒等待事件（唤醒函数：ep_poll_callback）通过 add_wait_queue 函数添加到 socket.wq 等待队列。
   > 当 listen socket 有链接资源时，内核通过 __wake_up_common 调用 epoll 的 ep_poll_callback 唤醒函数，唤醒进程。
4. 进程通过 epoll_wait 等待就绪事件，往 eventpoll.wq 等待队列中添加当前进程的等待事件，当 epoll_ctl 监控的 socket 产生对应的事件时，被唤醒返回。
5. 客户端通过 tcp connect 链接服务端，三次握手成功，第三次握手在服务端进程产生新的链接资源。
6. 服务端进程根据 socket.wq 等待队列，唤醒正在等待资源的进程处理。例如 nginx 的惊群现象，__wake_up_common 唤醒等待队列上的两个等待进程，调用 ep_poll_callback 去唤醒 epoll_wait 阻塞等待的进程。
7. ep_poll_callback 唤醒回调会检查 listen socket 的完全队列是否为空，如果不为空，那么就将 epoll_ctl 监控的 listen socket 的节点 epi 添加到 `就绪队列`：eventpoll.rdllist，然后唤醒 eventpoll.wq 里通过 epoll_wait 等待的进程，处理 eventpoll.rdllist 上的事件数据。
8. 睡眠在内核的 epoll_wait 被唤醒后，内核通过 ep_send_events 将就绪事件数据，从内核空间拷贝到用户空间，然后进程从内核空间返回到用户空间。
9. epoll_wait 被唤醒，返回用户空间，读取 listen socket 返回的 EPOLLIN 事件，然后 accept listen socket 完全队列上的链接资源。

---

## 2. 内核调试环境搭建

授人以鱼不如授人以渔，要深入理解 Linux 内核的工作原理，除了阅读调试源码，貌似没有更好的方法了。

> 参考：[搭建 Linux 内核网络调试环境（vscode + gdb + qemu）](https://wenfh2020.com/2021/12/03/ubuntu-qemu-linux/)

<iframe class="bilibili" src="//player.bilibili.com/player.html?aid=592292865&bvid=BV1Sq4y1q7Gv&cid=461543929&page=1&high_quality=1" scrolling="no" border="0" frameborder="no" framespacing="0" allowfullscreen="true"> </iframe>
