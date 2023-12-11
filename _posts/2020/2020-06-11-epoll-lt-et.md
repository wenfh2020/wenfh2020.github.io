---
layout: post
title:  "[内核源码] epoll lt / et 模式区别"
categories: kernel epoll
tags: epoll lt et difference kernel
author: wenfh2020
---

走读 Linux 内核源码（5.0.1），理解 epoll 的 lt / et 模式区别：

1. 两个模式，事件通知方式不同，lt 持续通知直到处理事件完毕，et 一般只通知一次，不管事件是否处理完毕。

   > 【注意】et 模式，在事件通知后，该事件没有被再次触发的情况下只通知一次。
   >
   > 举个栗子：内核接收了 64k 数据，用户只读取了 16k，那么剩下 48k 数据在内核缓存里，内核不会再次通知用户处理，除非读操作后，又来了新的数据，重新触发了读事件。

2. et 模式，可以使得就绪队列上的新的就绪事件能被快速处理。
3. et 模式，可以避免共享 "epoll fd" 场景下，发生类似 [惊群问题](https://wenfh2020.com/2021/09/25/thundering-herd/)。

> epoll 详细信息参考《[[epoll 源码走读] epoll 实现原理](https://wenfh2020.com/2020/04/23/epoll-code/)》。



* content
{:toc}

---

## 1. 原理

### 1.1. 逻辑

lt/et 模式区别的核心逻辑在 `epoll_wait` 的内核实现 `ep_send_events_proc` 函数里，划重点：`就绪队列`。

epoll_wait 的相关工作流程：

* 当内核监控的 fd 产生用户关注的事件，内核将 fd (`epi`)节点信息添加进就绪队列。
* 内核发现就绪队列有数据，唤醒进程工作。
* 内核先将 fd 信息从就绪队列中删除。
* 然后将 fd 对应就绪事件信息从内核空间拷贝到用户空间。
* 事件数据拷贝完成后，内核检查事件模式是 lt 还是 et，如果不是 et，重新将 fd 信息添加回就绪队列，下次重新触发 epoll_wait。

<div align=center><img src="/images/2021/2021-12-31-12-44-05.png" data-action="zoom"/></div>

> 图片来源：[tcp + epoll 内核睡眠唤醒工作流程](https://wenfh2020.com/2021/12/16/tcp-epoll-wakeup/)

---

### 1.2. 源码实现流程

```shell
#------------------- *用户空间* ---------------------------
epoll_wait
#------------------- *内核空间* ---------------------------
|-- do_epoll_wait
    |-- ep_poll
        |-- ep_send_events
            |-- ep_scan_ready_list
                |-- ep_send_events_proc
```

```c
/* fs/eventpoll.c */
SYSCALL_DEFINE4(epoll_wait, int, epfd, struct epoll_event __user *, events, int,
                maxevents, int, timeout) {
    return do_epoll_wait(epfd, events, maxevents, timeout);
}

/* fs/eventpoll.c */
static int do_epoll_wait(int epfd, struct epoll_event __user *events,
                         int maxevents, int timeout) {
    ...
    error = ep_poll(ep, events, maxevents, timeout);
    ...
}

/* 检查就绪队列，如果就绪队列有就绪事件，就将事件信息从内核空间发送到用户空间。*/
static int ep_poll(struct eventpoll *ep, struct epoll_event __user *events,
                   int maxevents, long timeout) {
    ...
    /* 检查就绪队列，如果有就绪事件就进入发送环节。 */
    ...
send_events:
    /* 有就绪事件就发送到用户空间，否则继续获取数据，直到阻塞等待超时。 */
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

    /* 遍历事件就绪队列，发送就绪事件到用户空间。 */
    ep_scan_ready_list(ep, ep_send_events_proc, &esed, 0, false);
    return esed.res;
}

static __poll_t ep_scan_ready_list(struct eventpoll *ep,
                                   __poll_t (*sproc)(struct eventpoll *,
                                                     struct list_head *,
                                                     void *),
                                   void *priv, int depth, bool ep_locked) {
    ...
    /* 将就绪队列分片链接到 txlist 链表中。 */
    list_splice_init(&ep->rdllist, &txlist);
    /* 执行 ep_send_events_proc，事件数据从内核空间拷贝到内核空间的逻辑。*/
    res = (*sproc)(ep, &txlist, priv);
    ...
}

static __poll_t ep_send_events_proc(struct eventpoll *ep,
                                    struct list_head *head, void *priv) {
    ...
    /* 遍历处理 txlist（原 ep->rdllist 数据）就绪队列结点，
     * 获取事件拷贝到用户空间。 */
    list_for_each_entry_safe(epi, tmp, head, rdllink) {
        if (esed->res >= esed->maxevents) break;
        ...
        /* 先从就绪队列中删除 epi，如果是 lt
         * 模式，就绪事件还没处理完，再把它添加回去。 */
        list_del_init(&epi->rdllink);

        /* 获取 epi 对应 fd 的就绪事件。 */
        revents = ep_item_poll(epi, &pt, 1);
        if (!revents) {
            /* 如果没有就绪事件就返回（这时候，epi 已经从就绪队列中删除了。） */
            continue;
        }

        /* 内核空间通过 __put_user 向用户空间拷贝传递数据。 */
        if (__put_user(revents, &uevent->events) ||
            __put_user(epi->event.data, &uevent->data)) {
            /* 如果拷贝失败，将 epi 重新保存回就绪队列，以便下一次处理。 */
            list_add(&epi->rdllink, head);
            ep_pm_stay_awake(epi);
            if (!esed->res) {
                esed->res = -EFAULT;
            }
            return 0;
        }

        /* 增加成功处理就绪事件的个数。 */
        esed->res++;
        uevent++;
        if (epi->event.events & EPOLLONESHOT)
            /* #define EP_PRIVATE_BITS (EPOLLWAKEUP | EPOLLONESHOT | EPOLLET |
             * EPOLLEXCLUSIVE) */
            epi->event.events &= EP_PRIVATE_BITS;
        else if (!(epi->event.events & EPOLLET)) {
            /* lt 模式，重新将前面从就绪队列删除的 epi 添加回去。
             * 等待下一次 epoll_wait 调用，重新走上面的逻辑。
             * et 模式，前面从就绪队列里删除的 epi 将不会被重新添加，
             * 直到用户关注的事件再次发生。*/
            list_add_tail(&epi->rdllink, &ep->rdllist);
            ep_pm_stay_awake(epi);
        }
    }

    return 0;
}
```

---

## 2. 区别

### 2.1. 通知

通过阅读 `ep_send_events_proc` 源码，最大区别就是，事件通知。

当用户关注的 fd 事件发生时，et 模式，只通知用户一次，不管这个事件是否已经被用户处理完毕，直到该事件再次发生，或者用户通过 `epoll_ctl` 重新关注该 fd 对应的事件；而 lt 模式，会不停地通知用户，直到用户把事件处理完毕。

```c
static __poll_t ep_send_events_proc(struct eventpoll *ep,
                                    struct list_head *head, void *priv) {
    ...
    /* 遍历处理 txlist（原 ep->rdllist 数据）就绪队列结点，获取事件拷贝到用户空间。 */
    list_for_each_entry_safe(epi, tmp, head, rdllink) {
        if (esed->res >= esed->maxevents) break;
        ...
        /* 先从就绪队列中删除 epi。*/
        list_del_init(&epi->rdllink);

        /* 获取 epi 对应 fd 的就绪事件。 */
        revents = ep_item_poll(epi, &pt, 1);
        if (!revents)
            /* 如果没有就绪事件，说明就绪事件已经处理完了，就返回。（这时候，epi
             * 已经从就绪队列中删除了。） */
            continue;
        ...
        else if (!(epi->event.events & EPOLLET)) {
            /* lt 模式，前面删除掉了的就绪事件节点，重新追加到就绪队列尾部。*/
            list_add_tail(&epi->rdllink, &ep->rdllist);
            ...
        }
    }

    return 0;
}
```
  
---

### 2.2. 快速处理

为什么说 et 模式会使得新的就绪事件能快速被处理呢？可以看下图 epoll_wait 的工作时序，假如 epoll_wait 每次最大从内核取一个事件。

如果是 lt 模式，epi 节点刚开始在内核被删除，然后数据从内核空间拷贝到用户空间后，内核马上将这个被删除的节点重新追加回就绪队列，这个速度很快，所以后面来的新的就绪事件很大几率会排在已经处理过的事件后面。

而 et 模式呢，数据从内核拷贝到用户空间后，内核不会重新将就绪事件节点添加回就绪队列，当事件在用户空间处理完后，用户空间根据需要重新将这个事件通过 epoll_ctl 添加回就绪队列（又或者这个节点因为有新的数据到来，重新触发了就绪事件而被添加）。从节点被删除到重新添加，这中间的过程是比较“漫长”的，所以新来的其它事件节点能排在旧的节点前面，能快速处理。

> 这个道理有点像排队打饭，一个队列上，有些同学要打包两份饭，如果每次只能打包一份，lt 模式就是，这些同学打包了一份之后，马上重新回去排队，再打一份。et 模式是，这些同学先打包一份，然后拿回去吃掉了，再回来排队，在高峰期显然整个排队的效率和结果不一样。

<div align=center><img src="/images/2023/2023-07-01-16-02-17.png" data-action="zoom"></div>

---

不要小看这个处理时序，在高并发系统里，海量事件，每个后来者都希望自己的事件快点被处理，而 et 模式可以一定程度上提高新事件被处理的速度。

同时如果我们仔细观察服务程序的 [listen 接口](https://wenfh2020.com/2021/07/21/kernel-sys-listen/)，它有一个 backlog 参数，代表 listen socket 就绪链接的已完成队列的长度，这说明队列是有限制的，当它满了就会返回错误给客户端，所以完全队列的数据当然越快得到处理越好。

所以我们可以观察一下 nginx 的 epoll_ctl 系统调用，除了 listen socket 的操作是 lt 模式，其它的 socket 处理几乎所有都是 et 模式。

---

### 2.3. 类似惊群问题

我们仔细看 `ep_scan_ready_list` 源码，当 `ep->rdllist` 不为空时，会唤醒进程。

当多个进程共享同一个 "epoll fd" 时，多个进程同时在等待资源，也就是多个进程通过 epoll_wait 将自己当前进程的等待事件挂在内核 epoll 实例 eventpoll.wq 等待队列上，换句话说，eventpoll.wq 等待队列上挂着多个多个进程的等待事件，当某个事件触发时，等待队列上的进程会被唤醒。

如果是 lt 模式，epoll 在下一个 epoll_wait 执行前，fd 事件节点仍然会存在就绪队列中，不管事件是否处理完成，那么唤醒进程 A 处理事件时，如果 B 进程也在等待资源，那么同样的事件有可能将 B 进程也唤醒处理，然后 B 又是同样的逻辑唤醒 C —— 连环唤醒问题，这种情况可能是用户不愿意看到的。

* 惊群现象。

<div align=center><img src="/images/2021/2021-11-05-10-49-41.png" data-action="zoom"/></div>

* lt 模式连环唤醒。

<center>
    <img style="border-radius: 0.3125em;
    box-shadow: 0 2px 4px 0 rgba(34,36,38,.12),0 2px 10px 0 rgba(34,36,38,.08);"
    src="/images/2021/2021-07-06-10-23-40.png" data-action="zoom">
    <br>
    <div style="color:orange; border-bottom: 1px solid #d9d9d9;
    display: inline-block;
    color: #999;
    padding: 2px;">多进程共享 epoll fd 框架</div>
</center>

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
    /* 如果就绪队列没有就绪事件了，那么进程进入睡眠状态，等待唤醒。 */
    for (;;) {
        /* 进程设置为可中断睡眠状态。 */
        set_current_state(TASK_INTERRUPTIBLE);
        ...
        eavail = ep_events_available(ep);
        if (eavail)
            break;
        ...
        /* 没有就绪事件了，超时阻塞睡眠，等待唤醒。 */
        if (!schedule_hrtimeout_range(to, slack, HRTIMER_MODE_ABS)) {
            timed_out = 1;
            break;
        }
    }

    /* 进程设置为唤醒状态。 */
    __set_current_state(TASK_RUNNING);
    ...
    /* 就绪队列有事件，处理就绪事件逻辑。 */
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

    /* 遍历事件就绪队列，发送就绪事件到用户空间。 */
    ep_scan_ready_list(ep, ep_send_events_proc, &esed, 0, false);
    return esed.res;
}

static __poll_t ep_scan_ready_list(struct eventpoll *ep,
                  __poll_t (*sproc)(struct eventpoll *,
                       struct list_head *, void *),
                  void *priv, int depth, bool ep_locked) {
    ...
    /* 将就绪队列分片链接到 txlist 链表中。 */
    list_splice_init(&ep->rdllist, &txlist);
    /* 执行 ep_send_events_proc，唤醒进程 A。 */
    res = (*sproc)(ep, &txlist, priv);
    ...
    if (!list_empty(&ep->rdllist)) {
        if (waitqueue_active(&ep->wq))
            /* A 进程已被唤醒，但是就绪队列（ep->rdllist）还有数据，
            * 进程 B，也在等待队列中，那么唤醒进程 B。 */
            wake_up_locked(&ep->wq);
        ...
    }
    ...
}
```

---

## 3. 小结

1. epoll 的 lt / et 模式实现逻辑在内核的 epoll_wait 里。
2. epoll_wait 的关键数据结构是事件就绪队列。
3. lt / et 模式区别主要有：通知方式，新事件快速处理，避免类似惊群问题。

---

## 4. 后记

使用 epoll 已经很长时间了，一直困扰着 lt / et 模式的区别，直到深入阅读内核源码后，才慢慢地理解它的工作原理，其实逻辑不是想象的那么复杂，可见阅读内核源码的重要性！

最近花了不少力气，将内核的 [调试环境](https://wenfh2020.com/2021/12/03/ubuntu-qemu-linux/) 搭建起来了，边看内核源码，边调试验证逻辑，一个字：爽啊 😁！

---

## 5. 参考

* [[epoll 源码走读] epoll 实现原理](https://wenfh2020.com/2020/04/23/epoll-code/)
* [搭建 Linux 内核网络调试环境（vscode + gdb + qemu）](https://wenfh2020.com/2021/12/03/ubuntu-qemu-linux/)