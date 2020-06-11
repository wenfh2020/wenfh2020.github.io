---
layout: post
title:  "epoll LT 与 ET 模式区别"
categories: 网络
tags: epoll LT ET 区别
author: wenfh2020
---

走读内核源码，看看 epoll 的 LT 和 ET 模式区别。



* content
{:toc}

---

## 1. 原理

`epoll_wait` 内核源码，核心逻辑在 `ep_send_events_proc` 函数里实现。

* epoll 监控的 fd 产生事件，fd 信息被添加进就绪列表。
* epoll_wait 发现有就绪事件，进程持续执行，或者被唤醒工作。
* epoll 将 fd 信息从就绪列表中删除。
* fd 对应就绪事件信息从内核空间拷贝到用户空间。
* 拷贝完成后，检查事件模式是 LT 还是 ET，如果不是 ET，重新将 fd 信息添加回就绪列表，下次重新触发。

---

## 2. 源码实现流程

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

// 检查就绪队列，如果就绪队列有就绪事件，就将事件信息从内核空间发送到用户空间。
static int ep_poll(struct eventpoll *ep, struct epoll_event __user *events, int maxevents, long timeout) {
    ...
    // 检查就绪队列，如果有就绪事件就进入发送环节。
    ...
send_events:
    // 有就绪事件就发送到用户空间，否则继续获取数据直到超时。
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

    // 遍历事件就绪列表，发送就绪事件到用户空间。
    ep_scan_ready_list(ep, ep_send_events_proc, &esed, 0, false);
    return esed.res;
}

static __poll_t ep_scan_ready_list(struct eventpoll *ep,
                  __poll_t (*sproc)(struct eventpoll *,
                       struct list_head *, void *),
                  void *priv, int depth, bool ep_locked) {
    ...
    // 将就绪队列分片链接到 txlist 链表中。
    list_splice_init(&ep->rdllist, &txlist);
    // 执行 ep_send_events_proc
    res = (*sproc)(ep, &txlist, priv);
    ...
}

static __poll_t ep_send_events_proc(struct eventpoll *ep, struct list_head *head, void *priv) {
    ...
    // 遍历处理 txlist（原 ep->rdllist 数据）就绪队列结点，获取事件拷贝到用户空间。
    list_for_each_entry_safe (epi, tmp, head, rdllink) {
        if (esed->res >= esed->maxevents)
            break;
        ...
        // 先从就绪队列中删除 epi，如果是 LT 模式，就绪事件还没处理完，再把它添加回去。
        list_del_init(&epi->rdllink);

        // 获取 epi 对应 fd 的就绪事件。
        revents = ep_item_poll(epi, &pt, 1);
        if (!revents)
            continue;

        // 内核空间向用户空间传递数据。__put_user 成功拷贝返回 0。
        if (__put_user(revents, &uevent->events) ||
            __put_user(epi->event.data, &uevent->data)) {
            // 如果拷贝失败，继续保存在就绪列表里。
            list_add(&epi->rdllink, head);
            ep_pm_stay_awake(epi);
            if (!esed->res)
                esed->res = -EFAULT;
            return 0;
        }

        // 成功处理就绪事件的 fd 个数。
        esed->res++;
        uevent++;
        if (epi->event.events & EPOLLONESHOT)
            // #define EP_PRIVATE_BITS (EPOLLWAKEUP | EPOLLONESHOT | EPOLLET | EPOLLEXCLUSIVE)
            epi->event.events &= EP_PRIVATE_BITS;
        else if (!(epi->event.events & EPOLLET)) {
            /* lt 模式下，当前事件被处理完后，不会从就绪列表中删除，留待下一次 epoll_wait
             * 调用，再查看是否还有事件没处理，如果没有事件了就从就绪列表中删除。
             * 在遍历事件的过程中，不能写 ep->rdllist，因为已经上锁，只能把新的就绪信息
             * 添加到 ep->ovflist */
            list_add_tail(&epi->rdllink, &ep->rdllist);
            ep_pm_stay_awake(epi);
        }
    }

    return 0;
}
```

---

## 3. 参考

* [[epoll 源码走读] epoll 实现原理](https://wenfh2020.com/2020/04/23/epoll-code/)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
