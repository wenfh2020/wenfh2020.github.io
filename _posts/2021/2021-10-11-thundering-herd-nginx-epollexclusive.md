---
layout: post
title:  "探索惊群 ⑤ - nginx - NGX_EXCLUSIVE_EVENT"
categories: nginx
tags: linux nginx thundering herd
author: wenfh2020
---

`EPOLLEXCLUSIVE` 是 2016 年 4.5+ 内核新添加的一个 epoll 的标识（<font color=gray>代码改动较小，详看：</font>[github](https://github.com/torvalds/linux/commit/df0108c5da561c66c333bb46bfe3c1fc65905898)）。

它解决了多个进程/线程通过 epoll_ctl 添加共享 fd 引发的惊群问题，保证一个事件发生时，只唤醒一个正在 epoll_wait 阻塞等待唤醒的进程/线程。

而 Ngnix 在 1.11.3 之后相应添加了 `NGX_EXCLUSIVE_EVENT` 功能标识（<font color=gray>代码改动也比较小，详看：</font>[github](https://github.com/nginx/nginx/commit/5c2dd3913aad5c4bf7d9056e1336025c2703586b)），它使用 EPOLLEXCLUSIVE 特性去避免惊群问题。

对比 nginx 在应用层的解决方案：accept_mutex，NGX_EXCLUSIVE_EVENT 它从内核层面解决惊群问题，它更简洁，付出的代价更小。





* content
{:toc}

---

## 1. 内核

### 1.1. 概述

看看 linux 在 [github](https://github.com/torvalds/linux/commit/df0108c5da561c66c333bb46bfe3c1fc65905898) 提交的 EPOLLEXCLUSIVE 功能描述要点：

1. EPOLLEXCLUSIVE 是 2016 年 4.5+ 内核新添加的一个 epoll 的标识。
2. epoll 通过 epoll_ctl 添加共享 fd 时，需要添加 EPOLLEXCLUSIVE 标识即可，使用相对简单。
3. 它是解决 epoll_ctl 添加共享 fd 导致惊群问题的方案：保证带有 EPOLLEXCLUSIVE 标识的共享 fd，它发生一个事件时，只唤醒一个正在 epoll_wait 阻塞等待的进程/线程。这样虽然避免了惊群，效率也不错，但只有一个进程/线程在 accept 链接资源，也限制了并行的吞吐。
4. 该标识测试性能成果：程序负载从原来时长 860 秒 降低到 24 秒。（<font color=gray>这么强大❓</font>）

```shell
epoll: add EPOLLEXCLUSIVE flag
Currently, epoll file descriptors or epfds (the fd returned from
epoll_create[1]()) that are added to a shared wakeup source are always
added in a non-exclusive manner.  This means that when we have multiple
epfds attached to a shared fd source they are all woken up.  This creates
thundering herd type behavior.

Introduce a new 'EPOLLEXCLUSIVE' flag that can be passed as part of the
'event' argument during an epoll_ctl() EPOLL_CTL_ADD operation.  This new
flag allows for exclusive wakeups when there are multiple epfds attached
to a shared fd event source.

The implementation walks the list of exclusive waiters, and queues an
event to each epfd, until it finds the first waiter that has threads
blocked on it via epoll_wait().  The idea is to search for threads which
are idle and ready to process the wakeup events.  Thus, we queue an event
to at least 1 epfd, but may still potentially queue an event to all epfds
that are attached to the shared fd source.

Performance testing was done by Madars Vitolins using a modified version
of Enduro/X.  The use of the 'EPOLLEXCLUSIVE' flag reduce the length of
this particular workload from 860s down to 24s.

Sample epoll_clt text:

EPOLLEXCLUSIVE

  Sets an exclusive wakeup mode for the epfd file descriptor that is
  being attached to the target file descriptor, fd.  Thus, when an event
  occurs and multiple epfd file descriptors are attached to the same
  target file using EPOLLEXCLUSIVE, one or more epfds will receive an
  event with epoll_wait(2).  The default in this scenario (when
  EPOLLEXCLUSIVE is not set) is for all epfds to receive an event.
  EPOLLEXCLUSIVE may only be specified with the op EPOLL_CTL_ADD.
...
 v4.5-rc1
@almostivan
@torvalds
almostivan authored and torvalds committed on 21 Jan 2016 
```

---

### 1.2. 原理

epoll_ctl 关注添加 fd 的事件时，通过 add_wait_queue_exclusive 函数，将 `WQ_FLAG_EXCLUSIVE` 标识的等待事件添加到 fd 的等待唤醒队列中。

当 fd 发生对应的事件时，wake_up_interruptible_all (<font color=gray>__wake_up_common</font>) 遍历 fd 的等待事件队列，但只唤醒一个带有 WQ_FLAG_EXCLUSIVE 标识的等待事件的进程。

> 详细流程可以参考下图：EPOLLEXCLUSIVE 的工作流程。

<center>
    <img style="border-radius: 0.3125em;
    box-shadow: 0 2px 4px 0 rgba(34,36,38,.12),0 2px 10px 0 rgba(34,36,38,.08);"
    src="/images/2021-10-16-15-40-23.png" data-action="zoom">
    <br>
    <div style="color:orange; border-bottom: 1px solid #d9d9d9;
    display: inline-block;
    color: #999;
    padding: 2px;">EPOLLEXCLUSIVE 工作流程</div>
</center>

---

小结：惊群问题其实就是一个等待唤醒的问题。

* 添加等待事件：

  1. 等待 socket 事件发生：epoll_ctl -> add_wait_queue_exclusive -> socket.wq
  2. 等待阻塞的进程唤醒：epoll_wait -> __add_wait_queue_exclusive ->eventpoll.wq

* 唤醒:
  
  tcp_v4_rcv -> wake_up_interruptible_all -> socket.wq -> ep_poll_callback -> wake_up_locked -> eventpoll.wq -> epoll_wait

---

#### 1.2.1. fd 等待队列

因为是分析 tcp 协议的 nginx 程序，这个 fd 指向的是 socket 数据结构。

而进程通过 epoll_ctl 关注的是 fd 事件，当进程在等待 fd 的事件时，会将等待事件添加到 socket 的等待队列 `socket.wq` 中去，当 socket 触发事件时会通过等待事件唤醒进程。

---

流程：epoll_ctl -> listen socket -> `add_wait_queue_exclusive` <+ep_poll_callback+> -> socket.wq

```c
/* include/linux/net.h*/
struct socket {
    ...
    struct socket_wq *wq; /* socket 等待队列。 */
    ...
};

/* Set exclusive wakeup mode for the target file descriptor 
 * include/uapi/linux/eventpoll.h*/
#define EPOLLEXCLUSIVE ((__force __poll_t)(1U << 28))

/* fs/eventpoll.c 
 * This is the callback that is used to add our wait queue to the
 * target file wakeup lists.
 * 
 * 添加等待事件到 fd 的等待唤醒队列中。这个 fd 是通过 epoll_ctl 关注的，
 * 而 ep_poll_callback 是触发等待事件回调函数。
 */
static void ep_ptable_queue_proc(struct file *file, wait_queue_head_t *whead, poll_table *pt) {
    struct epitem *epi = ep_item_from_epqueue(pt);
    struct eppoll_entry *pwq;

    if (epi->nwait >= 0 && (pwq = kmem_cache_alloc(pwq_cache, GFP_KERNEL)) {
        init_waitqueue_func_entry(&pwq->wait, ep_poll_callback);
        pwq->whead = whead;
        pwq->base = epi;
        /* 添加排它性（WQ_FLAG_EXCLUSIVE）等待事件到 fd 的等待队列。 */
        if (epi->event.events & EPOLLEXCLUSIVE)
            add_wait_queue_exclusive(whead, &pwq->wait);
        ...
    }
    ...
}

/* kernel/sched/wait.c 
 * 添加排它性等待事件到等待队列。*/
void add_wait_queue_exclusive(struct wait_queue_head *wq_head, struct wait_queue_entry *wq_entry) {
    unsigned long flags;
    wq_entry->flags |= WQ_FLAG_EXCLUSIVE;
    spin_lock_irqsave(&wq_head->lock, flags);
    __add_wait_queue_entry_tail(wq_head, wq_entry);
    spin_unlock_irqrestore(&wq_head->lock, flags);
}
```

---

#### 1.2.2. epoll_wait 等待事件

epoll_wait -> __add_wait_queue_exclusive -> eventpoll.wq

```c
/* epoll 结构对象。*/
struct eventpoll {
    ...
    /* 使用当前 epoll 的进程等待队列。 */
    wait_queue_head_t wq;
    ...
};

/* fs/eventpoll.c */
static int ep_poll(struct eventpoll *ep, struct epoll_event __user *events,
           int maxevents, long timeout) {
    ...
fetch_events:
    ...
    /* 如果没有就绪事件，进程将进入睡眠等待状态，添加等待事件到等待队列。
     * 当 epoll 关注的文件有对应的事件发生，会触发 ep_poll_callback 函数（epoll_ctl 里绑定的），
     * 唤醒等待队列里的对应进程。 */
    if (!waiter) {
        waiter = true;
        init_waitqueue_entry(&wait, current);
        spin_lock_irq(&ep->wq.lock);
        /* epoll 往等待队列中，添加当前进程的等待事件，等待唤醒。 */
        __add_wait_queue_exclusive(&ep->wq, &wait);
        spin_unlock_irq(&ep->wq.lock);
    }

    for (;;) {
        /* 将进程设置为可被中断唤醒的睡眠状态。 */
        set_current_state(TASK_INTERRUPTIBLE);
        ...
        /* 再检查是否有就绪事件发生，如果有就不睡了。 */
        eavail = ep_events_available(ep);
        if (eavail)
            break;
        ...
        /* 进入超时等待睡眠状态。 */
        if (!schedule_hrtimeout_range(to, slack, HRTIMER_MODE_ABS)) {
            timed_out = 1;
            break;
        }
    }

    /* 上面循环退出，进程恢复运行状态。 */
    __set_current_state(TASK_RUNNING);

send_events:
    ...
    if (waiter) {
        spin_lock_irq(&ep->wq.lock);
        /* epoll 从等待队列中，删除当前进程的等待事件。 */
        __remove_wait_queue(&ep->wq, &wait);
        spin_unlock_irq(&ep->wq.lock);
    }
}
```

#### 1.2.3. 唤醒流程

socket 触发等待事件，唤醒 socket.wq 等待队列上的进程。
  
流程：tcp_v4_rcv -> wake_up_interruptible_all -> socket.wq -> ep_poll_callback -> wake_up_locked -> eventpoll.wq -> epoll_wait

```c
/* fs/eventpoll.c
 * This is the callback that is passed to the wait queue wakeup
 * mechanism. It is called by the stored file descriptors when they
 * have events to report.
 */
static int ep_poll_callback(wait_queue_entry_t *wait, unsigned mode, int sync, void *key) {
    ...
    int ewake = 0;
    ...
    /* If this file is already in the ready list we exit soon */
    if (!ep_is_linked(epi)) {
        list_add_tail(&epi->rdllink, &ep->rdllist);
        ep_pm_stay_awake_rcu(epi);
    }
    ...
    if (waitqueue_active(&ep->wq)) {
        if ((epi->event.events & EPOLLEXCLUSIVE) &&
                    !(pollflags & POLLFREE)) {
            switch (pollflags & EPOLLINOUT_BITS) {
            case EPOLLIN:
                if (epi->event.events & EPOLLIN)
                    ewake = 1;
                break;
            case EPOLLOUT:
                if (epi->event.events & EPOLLOUT)
                    ewake = 1;
                break;
            case 0:
                ewake = 1;
                break;
            }
        }
        /* 唤醒 epoll_wait 阻塞等待的进程。 */
        wake_up_locked(&ep->wq);
    }
    ...

out_unlock:
    ...
    if (!(epi->event.events & EPOLLEXCLUSIVE))
        ewake = 1;
    ...
    return ewake;
}

/* kernel/sched/wait.c
 * This is the callback that is passed to the wait queue wakeup
 * mechanism. It is called by the stored file descriptors when they
 * have events to report. */
static int __wake_up_common(struct wait_queue_head *wq_head, unsigned int mode,
            int nr_exclusive, int wake_flags, void *key,
            wait_queue_entry_t *bookmark) {
    wait_queue_entry_t *curr, *next;
    int cnt = 0;
    ...
    /* 遍历等待队列，调用唤醒函数去唤醒进程。 */
    list_for_each_entry_safe_from(curr, next, &wq_head->head, entry) {
        unsigned flags = curr->flags;
        int ret;
        ...
        /* 调用进程唤醒回调函数：ep_poll_callback。*/
        ret = curr->func(curr, mode, wake_flags, key);
        if (ret < 0)
            break;
        /* 检测 WQ_FLAG_EXCLUSIVE 属性，是否只唤醒一个进。*/
        if (ret && (flags & WQ_FLAG_EXCLUSIVE) && !--nr_exclusive)
            break;
        ...
    }
    ...
}
```
