---
layout: post
title:  "[内核源码] epoll LT 与 ET 模式区别"
categories: kernel epoll
tags: epoll LT ET difference kernel
author: wenfh2020
---

走读内核源码，看看 epoll 的 LT 和 ET 模式区别。

1. et/lt 模式，事件通知方式不同，lt 通知多次直到处理事件完毕，et 只通知一次，不管事件是否处理完毕。
2. et 模式，可以避免共享 "epoll fd" 场景下，发生类似惊群问题。

> 详细信息可以参考文章《[[epoll 源码走读] epoll 实现原理](https://wenfh2020.com/2020/04/23/epoll-code/)》，现在将部分代码提取出来。



* content
{:toc}

---

## 1. 原理

核心逻辑在 `epoll_wait` 的内核实现 `ep_send_events_proc` 函数里，关键在 <font color=red> 就绪列表 </font>。

`epoll_wait` 的相关工作流程：

* 监控的 fd 产生用户关注的事件，内核将 fd (epi)节点信息添加进就绪列表。
* 内核发现就绪列表有数据，唤醒进程工作。
* 内核将 fd 信息从就绪列表中删除。
* fd 对应就绪事件信息从内核空间拷贝到用户空间。
* 事件数据拷贝完成后，检查事件模式是 LT 还是 ET，如果不是 ET，重新将 fd 信息添加回就绪列表，下次重新触发。

---

## 2. 源码实现流程

```shell
epoll_wait
|-- do_epoll_wait
    |-- ep_poll
        |-- ep_send_events
            |-- ep_scan_ready_list
                |-- ep_send_events_proc
```

```c
SYSCALL_DEFINE4(epoll_wait, int, epfd, struct epoll_event __user *, events,
        int, maxevents, int, timeout) {
    return do_epoll_wait(epfd, events, maxevents, timeout);
}

static int do_epoll_wait(int epfd, struct epoll_event __user *events,
             int maxevents, int timeout) {
    ...
    error = ep_poll(ep, events, maxevents, timeout);
    ...
}

/* 检查就绪列表，如果就绪列表有就绪事件，就将事件信息从内核空间发送到用户空间。 */
static int ep_poll(struct eventpoll *ep, struct epoll_event __user *events, int maxevents, long timeout) {
    ...
    /* 检查就绪列表，如果有就绪事件就进入发送环节。 */
    ...
send_events:
    /* 有就绪事件就发送到用户空间，否则继续获取数据直到超时。 */
    if (!res && eavail && !(res = ep_send_events(ep, events, maxevents)) &&
        !timed_out)
        goto fetch_events;
    ...
}

static int ep_send_events(struct eventpoll *ep,
              struct epoll_event __user *events, int maxevents) {
    struct ep_send_events_data esed;

    esed.maxevents = maxevents;
    esed.events = events;

    /* 遍历事件就绪列表，发送就绪事件到用户空间。 */
    ep_scan_ready_list(ep, ep_send_events_proc, &esed, 0, false);
    return esed.res;
}

static __poll_t ep_scan_ready_list(struct eventpoll *ep,
                  __poll_t (*sproc)(struct eventpoll *,
                       struct list_head *, void *),
                  void *priv, int depth, bool ep_locked) {
    ...
    /* 将就绪列表分片链接到 txlist 链表中。 */
    list_splice_init(&ep->rdllist, &txlist);
    /* 执行 ep_send_events_proc */
    res = (*sproc)(ep, &txlist, priv);
    ...
}

static __poll_t ep_send_events_proc(struct eventpoll *ep, struct list_head *head, void *priv) {
    ...
    // 遍历处理 txlist（原 ep->rdllist 数据）就绪列表结点，获取事件拷贝到用户空间。
    list_for_each_entry_safe (epi, tmp, head, rdllink) {
        if (esed->res >= esed->maxevents)
            break;
        ...
        /* 先从就绪列表中删除 epi，如果是 LT 模式，就绪事件还没处理完，再把它添加回去。 */
        list_del_init(&epi->rdllink);

        /* 获取 epi 对应 fd 的就绪事件。 */
        revents = ep_item_poll(epi, &pt, 1);
        if (!revents)
            /* 如果没有就绪事件就返回（这时候，epi 已经从就绪列表中删除了。） */
            continue;

        /* 内核空间向用户空间传递数据。__put_user 成功拷贝返回 0。 */
        if (__put_user(revents, &uevent->events) ||
            __put_user(epi->event.data, &uevent->data)) {
            /* 如果拷贝失败，继续保存在就绪列表里。 */
            list_add(&epi->rdllink, head);
            ep_pm_stay_awake(epi);
            if (!esed->res)
                esed->res = -EFAULT;
            return 0;
        }

        /* 成功处理就绪事件的 fd 个数。 */
        esed->res++;
        uevent++;
        if (epi->event.events & EPOLLONESHOT)
            /* #define EP_PRIVATE_BITS (EPOLLWAKEUP | EPOLLONESHOT | EPOLLET | EPOLLEXCLUSIVE) */
            epi->event.events &= EP_PRIVATE_BITS;
        else if (!(epi->event.events & EPOLLET)) {
            /* lt 模式下，当前事件被处理完后，不会从就绪列表中删除，留待下一次 epoll_wait
             * 调用，再查看是否还有事件没处理，如果没有事件了就从就绪列表中删除。*/
            list_add_tail(&epi->rdllink, &ep->rdllist);
            ep_pm_stay_awake(epi);
        }
    }

    return 0;
}
```

---

## 3. 区别

### 3.1. 通知

如果我们看 `ep_send_events_proc` 源码，最大区别就是，事件通知。

当用户关注的 fd 事件发生时，et 模式，只通知用户一次，不管这个事件是否已经被用户处理完毕，用户如果继续关注这个事件，那么只能通过 `epoll_ctl` 重新关注事件。而 lt 模式，会不停地通知用户，直到用户把事件处理完毕。那么对比 lt 模式，et 模式用户可以控制得更多一些。
  
---

### 3.2. 类似惊群问题

我们仔细看 `ep_scan_ready_list` 源码，当 `ep->rdllist` 不为空时，会唤醒进程。

当多个进程共享同一个 "epoll fd" 时，多个进程同时在等待资源，当某个事件触发时，会唤醒进程处理事件；

如果是 lt 模式，epoll 在下一个 `epoll_wait` 执行前，fd 事件节点仍然会存在就绪列表中，不管事件是否处理完成，那么唤醒进程 A 处理事件时，如果 B 进程也在等待资源，那么同样的事件有可能将 B 进程也唤醒处理，

<center>
    <img style="border-radius: 0.3125em;
    box-shadow: 0 2px 4px 0 rgba(34,36,38,.12),0 2px 10px 0 rgba(34,36,38,.08);"
    src="/images/2021-07-06-10-23-40.png" data-action="zoom">
    <br>
    <div style="color:orange; border-bottom: 1px solid #d9d9d9;
    display: inline-block;
    color: #999;
    padding: 2px;">多进程共享 epoll fd 框架</div>
</center>

举个🌰：

epoll lt 模式的多进程共享 epoll fd 的服务程序，如果只有一个客户端连接到服务，当进程 A 已经被唤醒，将要 accept 某个 socket（注意，这时候逻辑还在内核里，epoll_wait 还没返回到用户空间执行用户空间的逻辑，而 lt 模式的就绪列表上的数据还没有被删除），内核如果再唤醒进程 B，显然只有一个进程能成功 accept 到资源，而另外一个将会失败。

这不是用户愿意看到的。所以为了避免发生类似问题，et 模式就有存在的必要，因为 et 模式，事件只处理一次，就会从就绪列表删除。所以同样的 fd 事件，不会唤醒多个进程同时处理。避免了类似的“惊群”问题。

这样，我们就理解 nginx 为什么会使用 et 模式。

```c
/* epoll_wait 执行逻辑。 */
static int ep_poll(struct eventpoll *ep, struct epoll_event __user *events,
            int maxevents, long timeout) {
    ...
    /* epoll_wait 处理就绪事件前，先添加等待唤醒事件。 */
    if (!waiter) {
        waiter = true;
        /* current 是当前进程。 */
        init_waitqueue_entry(&wait, current);

        spin_lock_irq(&ep->wq.lock);
        __add_wait_queue_exclusive(&ep->wq, &wait);
        spin_unlock_irq(&ep->wq.lock);
    }
    ...
    /* 就绪列表有事件，处理就绪事件逻辑。 */
    if (!res && eavail &&
        !(res = ep_send_events(ep, events, maxevents)) && !timed_out)
        goto fetch_events;
    ...
    /* 处理完逻辑，从等待唤醒事件队列，删除自己的等待事件。 */
    if (waiter) {
        spin_lock_irq(&ep->wq.lock);
        __remove_wait_queue(&ep->wq, &wait);
        spin_unlock_irq(&ep->wq.lock);
    }
    ...
}

static int ep_send_events(struct eventpoll *ep,
              struct epoll_event __user *events, int maxevents) {
    struct ep_send_events_data esed;

    esed.maxevents = maxevents;
    esed.events = events;

    /* 遍历事件就绪列表，发送就绪事件到用户空间。 */
    ep_scan_ready_list(ep, ep_send_events_proc, &esed, 0, false);
    return esed.res;
}

static __poll_t ep_scan_ready_list(struct eventpoll *ep,
                  __poll_t (*sproc)(struct eventpoll *,
                       struct list_head *, void *),
                  void *priv, int depth, bool ep_locked) {
    ...
    /* 将就绪列表分片链接到 txlist 链表中。 */
    list_splice_init(&ep->rdllist, &txlist);
    /* 执行 ep_send_events_proc，唤醒进程 A。 */
    res = (*sproc)(ep, &txlist, priv);
    ...
    if (!list_empty(&ep->rdllist)) {
        if (waitqueue_active(&ep->wq))
            /* A 进程已被唤醒，但是就绪列表（ep->rdllist）还有数据，
            * 进程 B，也在等待队列中，那么唤醒进程 B。 */
            wake_up_locked(&ep->wq);
        ...
    }
    ...
}
```

---

## 4. 小结

写些小心得吧，使用 epoll 已经很长一段时间了，一直困扰着 LT 与 ET 模式的区别，直到这两年，深入阅读内核源码，才慢慢地理解它的工作原理，其实逻辑不是想象的那么复杂，可见阅读内核源码的重要性！

这几个月，花了不少力气，将 [内核的调试环境](https://www.bilibili.com/video/bv1yo4y1k7QJ) 搭建起来，一边看内核源码，一边调试验证源码逻辑——感觉忽然开窍了~

---

## 5. 参考

* [[epoll 源码走读] epoll 实现原理](https://wenfh2020.com/2020/04/23/epoll-code/)
* [vscode + gdb 远程调试 linux (EPOLL) 内核源码](https://www.bilibili.com/video/bv1yo4y1k7QJ)