---
layout: post
title:  "[知乎回答] epoll的EPOLLEXCLUSIVE真的能防住惊群吗？"
categories: 知乎 nginx epoll
tags: working
author: wenfh2020
---

[**知乎问题**](https://www.zhihu.com/question/454169064/answer/2257067584)：

看网上的说法，在LT模式+EPOLLEXCLUSIVE的情况下，当有新事件发生的时候，线程被唤醒，之后会调用ep_scan_ready_list，主要做两个事情：

调用传入的回调参数ep_send_events_proc把确实可读/写的事件从ready list挪到用户空间，如果是LT模式，那么会把事件留在ready list中
如果发现ready list没有为空的话，那么wake_up一下epoll中的等待队列，在EPOLLEXCLUSIVE情况下是唤醒一个，否则全部唤醒
如果我上面说的大概没错。。。我的问题是，假设LT+EPOLLEXCLUSIVE前提下，3个线程都在epoll_wait等一个fd，现在fd出现可写事件，线程A被唤醒，线程A从epoll_wait返回的路上会按照上文所说的情况，再次唤醒一个线程。这样线程B也被唤醒，同理线程B从epoll_wait返回的路上还会唤醒线程C。

这样的话，岂不还是惊群？小白求解答

我看的代码: [https://code.woboq.org/linux/li](https://code.woboq.org/linux/linux/fs/eventpoll.c.html)




* content
{:toc}

---

## 1. EPOLLEXCLUSIVE 能防住惊群吗？

这是个好问题，如果提问作者能在问题上附加上自己的测试结果就更好了。

下面我回答一下这个问题。

—— `能`。

惊群的本质是：睡眠和唤醒问题。它是典型的观察者模式：进程/线程通过等待事件，挂在关注的对象的等待队列上，当对象有资源到来时，就唤醒它的等待队列上的进程/线程。而是否产生惊群，关键在于内核通过 __wake_up_common 是否无差别地遍历唤醒等待队列上的多个进程/线程。

显然 EPOLLEXCLUSIVE （详看 2016 年 4.5+ 内核添加的 patch）的逻辑不会无差别地唤醒所有进程/线程，它只唤醒一个正在睡眠的进程/线程处理新来的资源，所以它能防住惊群吗？它能！

---

## 2. LT+EPOLLEXCLUSIVE 会出现连环唤醒现象吗？

LT+EPOLLEXCLUSIVE 会出现连环唤醒现象吗？—— 不一定，取决于用户的使用方式。

问题描述的应用场景不清楚：“3个线程都在epoll_wait等一个fd”，这三个线程每个线程都独立调用了 epoll_create 创建了自己的 epoll 实例吗？还是说整个程序只有一个 epoll 实例，多线程共享这个实例。这个很重要，如果每个线程都有独立的 epoll 实例，将不会出现 LT 的连环唤醒问题，否则就会出现。

因为 epoll 实例有唤醒等待队列：eventpoll.wq，如果每个线程都创建了自己的 epoll 实例，每个线程上只有一个 epoll_wait，那么 epoll_wait 只会往 eventpoll.wq 添加一个等待事件，换句话说，eventpoll.wq 上只有一个等待事件，LT 模式也只能唤醒一个等待的线程，不存在什么连环唤醒问题。否则 eventpoll.wq 上有多个等待事件，就会出现连环唤醒问题。

---

## 3. nginx

nginx 也有 EPOLLEXCLUSIVE 解决惊群问题的方案，跟问题提到的应用场景很像，可以研究一下。

* nginx 的 EPOLLEXCLUSIVE 工作模型。

<div align=center><img src="/images/2021-11-04-11-07-09.png" data-action="zoom"/></div>

* socket 唤醒流程。

<div align=center><img src="/images/2021-11-04-11-33-40.png" data-action="zoom"/></div>

* 结合源码看下图，（黄色序号）步骤 2 和步骤 4，epoll 是如何添加等待事件的，步骤 6 是如何唤醒的。

<center>
    <img style="border-radius: 0.3125em;
    box-shadow: 0 2px 4px 0 rgba(34,36,38,.12),0 2px 10px 0 rgba(34,36,38,.08);"
    src="/images/2021-11-09-11-26-53.png" data-action="zoom">
    <br>
    <div style="color:orange; border-bottom: 1px solid #d9d9d9;
    display: inline-block;
    color: #999;
    padding: 2px;">EPOLLEXCLUSIVE 工作流程</div>
</center>

## 4. 参考

* [探索惊群 ⑤ - nginx - NGX_EXCLUSIVE_EVENT](https://wenfh2020.com/2021/10/11/thundering-herd-nginx-epollexclusive/)