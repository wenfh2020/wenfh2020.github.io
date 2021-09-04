---
layout: post
title:  "深入理解 epoll 回调用户数据"
categories: epoll
tags: epoll
author: wenfh2020
---

epoll 多路复用驱动是异步事件处理，在用户层它提供了用户数据（`epoll_data`），方便事件触发后回调给用户处理。

* glibc

```c
/* sys/epoll.h */
typedef union epoll_data
{
  void *ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
} epoll_data_t;

struct epoll_event
{
  uint32_t events;    /* Epoll events */
  epoll_data_t data;  /* User data variable */
} __EPOLL_PACKED;
```

* 内核

```c
/* eventpoll.h */
struct epoll_event {
    __poll_t events;
    __u64 data;
} EPOLL_PACKED;
```



* content
{:toc}

---

## 1. epoll_data

我们来看看 epoll 事件和接口，`epoll_data` 是用户数据，内核并不会处理，只与对应的 fd 绑定，当 fd 产生事件后，epoll_wait 会回调回来。

```c
/* 用户数据。*/
typedef union epoll_data {
  void *ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
} epoll_data_t;

/* 事件。 */
struct epoll_event {
  uint32_t events;   /* Epoll events */
  epoll_data_t data; /* User data variable */
} __EPOLL_PACKED;


/* 事件控制接口。 */
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);

/* 事件监控回调接口 */
int epoll_wait(int epfd, struct epoll_event* events, int maxevents. int timeout);
```

---

## 2. 内核

走读 [epoll 源码](https://github.com/torvalds/linux/blob/master/fs/eventpoll.c)，简单走一下 epoll 事件的添加和回调流程。

> 参考：《[[epoll 源码走读] epoll 实现原理](https://wenfh2020.com/2020/04/23/epoll-code/)》

### 2.1. epoll_ctl

监控的 fd 事件信息，被添加到内核红黑树节点进行监控。

```c
/* eventpoll.c */
SYSCALL_DEFINE4(epoll_ctl, int, epfd, int, op, int, fd, struct epoll_event __user *, event) {
    struct epoll_event epds;

    if (ep_op_has_event(op) &&
        copy_from_user(&epds, event, sizeof(struct epoll_event)))
        return -EFAULT;

    return do_epoll_ctl(epfd, op, fd, &epds, false);
}

int do_epoll_ctl(int epfd, int op, int fd, struct epoll_event *epds, bool nonblock) {
    ...
    switch (op) {
    case EPOLL_CTL_ADD:
        if (!epi) {
            epds->events |= EPOLLERR | EPOLLHUP;
            error = ep_insert(ep, epds, tf.file, fd, full_check);
        }
        ...
    }
    ...
}

static int ep_insert(struct eventpoll *ep, const struct epoll_event *event,
             struct file *tfile, int fd, int full_check) {
    ...
    struct epitem *epi;
    ...
    if (!(epi = kmem_cache_alloc(epi_cache, GFP_KERNEL)))
        return -ENOMEM;
    ...
    /* 监控的事件信息被添加到 epi 红黑树节点。 */
    ep_set_ffd(&epi->ffd, tfile, fd);
    epi->event = *event;
    ...
    ep_rbtree_insert(ep, epi);
    ...
}
```

---

### 2.2. epoll_wait

内核检测到 fd 有事件发生，唤醒进程，epoll_wait 将 fd 对应事件从内核拷贝（__put_user）到用户层。

```c
/* eventpoll.c */
SYSCALL_DEFINE4(epoll_wait, int, epfd, struct epoll_event __user *, events, int,
        maxevents, int, timeout) {
    return do_epoll_wait(epfd, events, maxevents, timeout);
}

static int do_epoll_wait(int epfd, struct epoll_event __user *events,
             int maxevents, int timeout) {
    ...
    /* Time to fish for events ... */
    error = ep_poll(ep, events, maxevents, timeout);
    ...
}

static int ep_poll(struct eventpoll *ep, struct epoll_event __user *events,
           int maxevents, long timeout) {
    ...
    /* 网络驱动检测到有事件发生，唤醒进程，通知用户。 */
    write_lock_irq(&ep->lock);
    eavail = ep_events_available(ep);
    write_unlock_irq(&ep->lock);
    if (eavail)
        goto send_events;
    ...
send_events:
    res = ep_send_events(ep, events, maxevents);
    ...
}

static int ep_send_events(struct eventpoll *ep,
              struct epoll_event __user *events, int maxevents) {
    struct ep_send_events_data esed;

    esed.maxevents = maxevents;
    esed.events = events;

    /* 遍历就绪列表，发送就绪事件到用户态。 */
    ep_scan_ready_list(ep, ep_send_events_proc, &esed, 0, false);
    return esed.res;
}

/* 遍历事件就绪列表。 */
static __poll_t ep_scan_ready_list(struct eventpoll *ep,
                   __poll_t (*sproc)(struct eventpoll *,
                             struct list_head *,
                             void *),
                   void *priv, int depth, bool ep_locked)
{
    ...
    /* 就绪列表（ep->rdllist）数据分片到 txlist 进行发送处理。 */
    write_lock_irq(&ep->lock);
    list_splice_init(&ep->rdllist, &txlist);
    WRITE_ONCE(ep->ovflist, NULL);
    write_unlock_irq(&ep->lock);

    /* ep_send_events_proc */
    res = (*sproc)(ep, &txlist, priv);
    ...
}

static __poll_t ep_send_events_proc(
    struct eventpoll *ep, struct list_head *head, void *priv) {

    struct ep_send_events_data *esed = priv;
    ...
    struct epoll_event __user *uevent = esed->events;
    ...
    /* epi 是 fd 对应的红黑树节点，遍历就绪列表，拷贝事件。 */
    list_for_each_entry_safe (epi, tmp, head, rdllink) {
        ...
        revents = ep_item_poll(epi, &pt, 1);
        ...
        /* 数据从内核空间拷贝到用户空间。 */
        if (__put_user(revents, &uevent->events) ||
            __put_user(epi->event.data, &uevent->data)) {
            ...
        }
        ...
    }
    ...
}
```

---

## 3. 开源

epoll_data 在用户层是一个 union 值，那么用户应该如何传参？我们参考一下其它开源项目是如何处理的。

---

### 3.1. libco

Linux 系统的 epoll_wait 回调数据，data 是一个 `stTimeoutItem_t` 指针。

传指针缺点：如果程序在 epoll_wait 回调前，把指针释放了，那么 epoll_wait 回调后回传的指针就变成<font color=red> 野指针 </font>了。

```c
/* co_coroutine.cpp */
void co_eventloop(stCoEpoll_t *ctx, pfn_co_eventloop_t pfn, void *arg) {
    ...
    co_epoll_res *result = ctx->result;
    ...
    for (;;) {
        int ret = co_epoll_wait(ctx->iEpollFd, result, stCoEpoll_t::_EPOLL_SIZE, 1);
        ...
        for (int i = 0; i < ret; i++) {
            /* data 值是 stTimeoutItem_t 指针。 */
            stTimeoutItem_t *item = (stTimeoutItem_t *)result->events[i].data.ptr;
            ...
        }
    }
    ...
}
```

---

### 3.2. redis

epoll_event.data 传的是 fd。

传 fd 缺点：我们日常使用，fd 并不是用户的唯一标识，因为当旧的 fd 被 close 掉后，它会被系统回收重复使用，导致新来的用户可能重用原来的 fd，如果逻辑处理不好，也可能会出现问题。

```c
/* ae_epoll.c */
static int aeApiPoll(aeEventLoop *eventLoop, struct timeval *tvp) {
    aeApiState *state = eventLoop->apidata;
    int retval, numevents = 0;

    retval = epoll_wait(state->epfd, state->events, eventLoop->setsize,
                        tvp ? (tvp->tv_sec * 1000 + tvp->tv_usec / 1000) : -1);
    if (retval > 0) {
        int j;
        numevents = retval;
        for (j = 0; j < numevents; j++) {
            ...
            struct epoll_event *e = state->events + j;
            ...
            /* data 传的是 fd。 */
            eventLoop->fired[j].fd = e->data.fd;
            ...
        }
    }
    return numevents;
}
```

---

### 3.3. libev

libev epoll_event.data 传的是 fd 和索引的（uint64_t）组合，这样添加一个索引对数据进行保护，感觉更安全一些。

```c
/* ev_epoll.c */
static void
epoll_modify (EV_P_ int fd, int oev, int nev) {
  struct epoll_event ev;
  ...
  /* store the generation counter in the upper 32 bits, the fd in the lower 32 bits */
  ev.data.u64 = (uint64_t)(uint32_t)fd
              | ((uint64_t)(uint32_t)++anfds[fd].egen << 32);
  ev.events   = (nev & EV_READ  ? EPOLLIN  : 0)
              | (nev & EV_WRITE ? EPOLLOUT : 0);

  if (ecb_expect_true (!epoll_ctl (backend_fd, oev && oldmask != nev ? EPOLL_CTL_MOD : EPOLL_CTL_ADD, fd, &ev)))
    return;
  ...
}

static void
epoll_poll (EV_P_ ev_tstamp timeout) {
    ...
    eventcnt = epoll_wait (backend_fd, epoll_events, epoll_eventmax, EV_TS_TO_MSEC (timeout));
    ...
    for (i = 0; i < eventcnt; ++i) {
        struct epoll_event *ev = epoll_events + i;

        int fd = (uint32_t)ev->data.u64; /* mask out the lower 32 bits */
        int want = anfds [fd].events;
        ...
        /*
        * check for spurious notification.
        * this only finds spurious notifications on egen updates
        * other spurious notifications will be found by epoll_ctl, below
        * we assume that fd is always in range, as we never shrink the anfds array
        */
        if (ecb_expect_false ((uint32_t)anfds [fd].egen != (uint32_t)(ev->data.u64 >> 32))) {
            /* recreate kernel state */
            postfork |= 2;
            continue;
        }
        ...
    }
}
```

---

### 3.4. nginx

nginx epoll_event.data 传的是指针，这样也会存在“野指针”的风险，它与 libco 不同的地方，nginx 处理这个指针，根据内存对齐规则，利用指针末位一个 bit 的标识进行保护，以此来检查 fd 的时效性。

```c
struct ngx_event_s {
    ...
    /* used to detect the stale events in kqueue and epoll */
    unsigned         instance:1;
    ...
};

static ngx_int_t
ngx_epoll_add_event(ngx_event_t *ev, ngx_int_t event, ngx_uint_t flags) {
    ...
    struct epoll_event ee;
    ...
    ee.events = events | (uint32_t)flags;
    ee.data.ptr = (void *) ((uintptr_t) c | ev->instance);
    ...
    if (epoll_ctl(ep, op, c->fd, &ee) == -1) {
        ngx_log_error(NGX_LOG_ALERT, ev->log, ngx_errno,
                      "epoll_ctl(%d, %d) failed", op, c->fd);
        return NGX_ERROR;
    }
    ...
}

static ngx_int_t
ngx_epoll_process_events(ngx_cycle_t *cycle, ngx_msec_t timer, ngx_uint_t flags) {
    ...
    events = epoll_wait(ep, event_list, (int) nevents, timer);
    ...
    for (i = 0; i < events; i++) {
        c = event_list[i].data.ptr;

        instance = (uintptr_t) c & 1;
        c = (ngx_connection_t *) ((uintptr_t) c & (uintptr_t) ~1);

        rev = c->read;

        /* 检查 instance 值。 */
        if (c->fd == -1 || rev->instance != instance) {
            /*
             * the stale event from a file descriptor
             * that was just closed in this iteration
             */
            ngx_log_debug1(NGX_LOG_DEBUG_EVENT, cycle->log, 0,
                           "epoll: stale event %p", c);
            continue;
        }
        ...
    }
    ...
}
```

---

## 4. 小结

* 其实无论传什么参数，做底层的事件驱动逻辑，需要缜密的思维，只要逻辑错误，无论传的是啥参数一样会出现错误。
* 走读源码，可以深层次理解作者代码设计思路，通过对比，加深对代码的理解。
* 现实使用，我们可以参考开源的实现。

---

## 5. 参考

* [vscode + gdb 远程调试 linux (EPOLL) 内核源码](https://www.bilibili.com/video/bv1yo4y1k7QJ)
* [《epoll 多路复用 I/O工作流程》](https://wenfh2020.com/2020/04/14/epoll-workflow/)
* [《[epoll 源码走读] epoll 实现原理》](https://wenfh2020.com/2020/04/23/epoll-code/)
