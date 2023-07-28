---
layout: post
title:  "[知乎回答] socket的任意event都会导致epoll_wait的惊群效应吗？"
categories: 知乎 kernel epoll
tags: working
author: wenfh2020
---

[**知乎问题**](https://www.zhihu.com/question/414313102/answer/2229115248)：

1.网上针对epoll_wait的惊群讨论几乎都是围绕listen socket的accpet来做讨论的，socket是否只有此种情况会导致惊群？ 将accpet返回的socket加入到epoll中，这个socket的可读，可写事件是否也会导致惊群？

2.如果1中描述的accept返回的socket的可读，可写事件不会导致惊群。那么是否可以采用 ①一个listen socket加入到一个epoll（1）中，并且自始至终只用一个线程(1)来调用epollwait和accpet；② accpet返回的所有套接字都加入到另外一个epoll(2)中，然后线程2-N同时针对第2个epoll调用epoll_wait 的方式来应对连接数多但不是同时connect的开发场景？





* content
{:toc}

---

## 1. 问题分析

问题问得很好。我通过多进程模型回答一下你提到的几个问题：

1. 为啥惊群会围绕 listen socket 的 accept 做讨论呢？因为一般的服务程序，如果有多个 epoll，多个 epoll_create 创建实例后，第一件事就是 epoll_ctl 添加 listen socket 这个 fd。从某种意义上说，listen socket 就是共享的了。既然有多个 epoll 关注这个 listen socket，那么如果只有一个链接过来，触发 listen socket 可读事件，这时内核是唤醒一个 epoll 处理呢？还是唤醒多个呢？正常来说唤醒一个是合理的，唤醒多个就不合理了，因为只有一个资源啊，只要其中一个进程 accept 了，其它的就肯定失败，这样惊群就出现了。如果没有什么特别设置的话，多个 epoll 通过 epoll_ctl 关注共享的 listen socket，只要 listen socket 有资源到来，内核都会默认采用惊群方式，唤醒多个进程 accept。

2. 那 accept 到的 socket 被 epoll_ctl 添加的可读/可写事件是否会导致惊群呢？一般不会，因为 accept 到的 client fd，只被一个进程的 epoll_ctl 添加，它不共享，所以不会产生惊群。

3. 自始至终使用一个进程 epoll_wait 和 accept 是没有问题的，也不会产生惊群，这个方案一般情况是没有问题的。但是如果你的服务是高并发短链接服务，就很可能遇到问题了，因为一个进程只能利用一个核心的资源，限制了多核的并发。如果你细心的话，在编写服务程序时，你会发现，listen 这个接口有两个参数，第二个参数 backlog，一定程度上限制了完全队列的长度，换句话说，就是 listen socket 接收新链接的队列不是无限的，填充满了就会返回错误给客户端，所以要快速 accept 处理掉这个 listen socket 完全队列上的链接数据，所以惊群可以使得多个进程同时工作，利用多核的优势，这就是惊群为啥一直存在的原因。但是只要进程多了，惊群对软件性能影响会很大，因为多进程争抢 listen socket 的共享资源，其实内核里面到处都是锁 ，性能和效率都会降低，而且如果进程被无差别地唤醒，经常 accept 不到资源，那就浪费了系统资源了，因为进程频繁上下文切换系统开销也很大，有鉴于此，我们又不得不解决惊群问题。(想想一个红包丢进几个人的群组和丢进百人群组能一样么....)

---

## 2. 解决方案

把惊群比喻成抢红包 ，个人觉得还是比较形象的。

在群组里抢红包，可能会有两个结果：

* 有人抢到，有人抢不到。（无差别地唤醒多个进程，导致有些进程获取资源失败，做无用功。）
* 有人抢得多，有人抢得少。（资源负载均衡问题。）

那么如何解决抢红包的这两个问题？红包私发，不就完了？！ ——这就是解决惊群的思路 。

惊群的解决方案，可以参考 nginx 比较经典的三个解决方案：

* [reuseport](https://wenfh2020.com/2021/10/12/thundering-herd-tcp-reuseport/).（目前比较优秀的解决方案：多个 listen socket 资源队列，链接资源多个进程负载均衡。）

<div align=center><img src="/images/2021/2021-07-31-19-20-51.png" data-action="zoom"/></div>

* [epollexclusive](https://wenfh2020.com/2021/10/11/thundering-herd-nginx-epollexclusive/)（Linux 4.5+ 增加的 epoll 属性，只唤醒一个睡眠的进程去 accept 共享的资源）。

<div align=center><img src="/images/2021/2021-11-04-11-33-40.png" data-action="zoom"/></div>

* [accept_mutex](https://wenfh2020.com/2021/10/10/nginx-thundering-herd-accept-mutex/)（通过共享锁，使得一个时间段内，只有一个子进程 accept 资源）。

<div align=center><img src="/images/2021/2021-10-11-12-57-59.png" data-action="zoom"/></div>

---

## 3. 内核源码

前面已经概述了惊群原理和解决方案，如果深入内核，其实惊群问题本质上是：进程 `睡眠和唤醒` 问题。

睡眠和唤醒也是典型的观察者模式。进程创建 epoll 实例，然后通过 epoll_ctl 添加关注 socket 事件，内核里的实现：调用了 `add_wait_queue` 函数将当前进程的等待唤醒事件，添加到 socket 的 socket.wq 等待队列，当 socket 有对应的事件发生时，内核就根据 socket.wq 等待队列上的等待事件唤醒对应的进程。而惊群产生的原因：共享 listen socket 的 socket.wq 等待队列上添加了多个进程等待事件，被内核通过 `__wake_up_common` 函数遍历唤醒了。详细可以参考下图的黄色图标第 3 个步骤和第 6 个步骤。

<div align=center><img src="/images/2021/2021-12-31-12-44-05.png" data-action="zoom"/></div>

> 详细请参考文章：[tcp + epoll 内核睡眠唤醒工作流程](https://wenfh2020.com/2021/12/16/tcp-epoll-wakeup/)。

---

当 socket 对应的事件发生时，内核能不能只唤醒一个进程呢？可以的，方法也很简单，把 add_wait_queue 换成 add_wait_queue_exclusive 就可以了，这个函数添加了一个比较重要的（独占）排它性标识 WQ_FLAG_EXCLUSIVE。

其实这也是 epollexclusive 解决方案的做法，通过 epoll_ctl 添加 EPOLLEXCLUSIVE 属性，不过 EPOLLEXCLUSIVE 是 2016 年 4.5+ 内核版本新添加的一个 epoll 标识，目前比较普及的 Linux 稳定版本大部分是 3.x + ，还不支持，道理还是那个道理，可以通过这个 Linux patch (github)了解下。

```c
/* include/linux/wait.h */
static inline void
__add_wait_queue_exclusive(struct wait_queue_head *wq_head, struct wait_queue_entry *wq_entry) {
    /* 唤醒事件，增加了 WQ_FLAG_EXCLUSIVE 排它性唤醒属性。*/
    wq_entry->flags |= WQ_FLAG_EXCLUSIVE;
    __add_wait_queue(wq_head, wq_entry);
}

/* kernel/sched/wait.c */
static int __wake_up_common(struct wait_queue_head *wq_head, unsigned int mode,
            int nr_exclusive, int wake_flags, void *key,
            wait_queue_entry_t *bookmark) {
    wait_queue_entry_t *curr, *next;
    int cnt = 0;
    ...
    list_for_each_entry_safe_from(curr, next, &wq_head->head, entry) {
        unsigned flags = curr->flags;
        int ret;
        ...
        /* 唤醒进程。 */
        ret = curr->func(curr, mode, wake_flags, key);
        if (ret < 0)
            break;
        /* 排它性唤醒属性，而且 nr_exclusive == 1，也就是只唤醒一个睡眠进程，然后退出循环。 */
        if (ret && (flags & WQ_FLAG_EXCLUSIVE) && !--nr_exclusive)
            break;
        ...
    }
    ...
}
```

---

## 4. 参考

* [探索惊群 ④ - nginx - accept_mutex](https://wenfh2020.com/2021/10/10/nginx-thundering-herd-accept-mutex/)
* [探索惊群 ⑤ - nginx - NGX_EXCLUSIVE_EVENT](https://wenfh2020.com/2021/10/11/thundering-herd-nginx-epollexclusive/)
* [探索惊群 ⑥ - nginx - reuseport](https://wenfh2020.com/2021/10/12/thundering-herd-tcp-reuseport/)
* [tcp + epoll 内核睡眠唤醒工作流程](https://wenfh2020.com/2021/12/16/tcp-epoll-wakeup/)

