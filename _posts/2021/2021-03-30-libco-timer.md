---
layout: post
title:  "[libco] libco 定时器（时间轮）"
categories: libco
tags: libco timer
author: wenfh2020
mathjax: true
---

[libco](https://github.com/Tencent/libco) 定时器核心数据结构：数组 + 链表，有点像哈希表，通过空间换时间，查询数据时间复杂度为 $O(1)$。

libco 定时器也被称为时间轮，我们看看这个 “轮” 是怎么转的。




* content
{:toc}

---

## 1. 概述

libco 定时器核心数据结构：数组 + 双向链表（左图）。

数组以毫秒为单位，默认大小 60 * 1000，主要保存一分钟以内到期的事件数据。相同到期时间的事件，会保存在双向链表里，当时间到期时，到期事件链表会一起取出来。

当然超过一分钟的到期事件也支持保存，通过取模路由，有可能与一分钟以内到期的数据耦合在一起，一起取出来后，再检查，没到期的重新写回去即可。

> 一般的应用场景，超时事件也是 1 分钟以内，超过这个时间事件的处理方案，虽然有点笨，但是代码维护代价比较小。

---

libco 定时器也被称为时间轮（右图）：因为数组数据结构，下标是以毫秒为单位，当前时间下标 `stTimeout_t.llStartIdx`，沿着这个下标，随着时间推移，顺时针读写数据。

<div align=center><img src="/images/2021-03-30-14-03-54.png" data-action="zoom"/></div>

> 图片来源：[processon](https://www.processon.com/view/6062b09e1e085332583e7783)

---

## 2. 定时器源码分析

* 数据结构。

```c
struct stCoEpoll_t {
    ...
    struct stTimeout_t *pTimeout; /* 定时器。 */
    ...
};

/* 定时器。 */
struct stTimeout_t {
    stTimeoutItemLink_t *pItems; /* 数组。 */
    int iItemSize;               /* 数组大小。 */
    unsigned long long ullStart; /* 上一次获取到期事件的时间。 */
    long long llStartIdx;        /* 上一次获取到期事件的数组下标。 */
};

/* 到期事件双向链表。 */
struct stTimeoutItemLink_t {
    stTimeoutItem_t *head;
    stTimeoutItem_t *tail;
};
```

* 初始化定时器数据结构，数组大小 60000。一般应用场景，定时任务都在 1 分钟（60000 毫秒）以内，那么超过一分钟的怎么办？看下面 `AddTimeout` 的源码实现。

```c
stCoEpoll_t *AllocEpoll() {
    ...
    ctx->pTimeout = AllocTimeout(60 * 1000);
    ...
}

stTimeout_t *AllocTimeout(int iSize) {
    stTimeout_t *lp = (stTimeout_t *)calloc(1, sizeof(stTimeout_t));
    lp->iItemSize = iSize;
    lp->pItems = (stTimeoutItemLink_t *)calloc(1, sizeof(stTimeoutItemLink_t) * lp->iItemSize);
    lp->ullStart = GetTickMS();
    lp->llStartIdx = 0;
    return lp;
}
```

* 添加到期事件。

```c
int AddTimeout(stTimeout_t *apTimeout, stTimeoutItem_t *apItem, unsigned long long allNow) {
    ...
    unsigned long long diff = apItem->ullExpireTime - apTimeout->ullStart;
    if (diff >= (unsigned long long)apTimeout->iItemSize) {
        /* 超过一分钟的事件，应该排在轮子尾部，最后才检查的，
         * 因为轮子是“圆”的，所以尾部就是当前数组下标（llStartIdx）的前一个下标。
         * （这里有点绕...） */
        diff = apTimeout->iItemSize - 1;
        ...
    }
    AddTail(apTimeout->pItems + (apTimeout->llStartIdx + diff) % apTimeout->iItemSize, apItem);
    return 0;
}
```

* 获取到期事件。

```c
/* 获取到期事件。 */
inline void TakeAllTimeout(stTimeout_t *apTimeout, unsigned long long allNow, stTimeoutItemLink_t *apResult) {
    ...
    /* 处理当前时间与上一次处理时间间隔内到期的时间事件。 */
    int cnt = allNow - apTimeout->ullStart + 1;
    if (cnt > apTimeout->iItemSize) {
        cnt = apTimeout->iItemSize;
    }
    ...
    for (int i = 0; i < cnt; i++) {
        int idx = (apTimeout->llStartIdx + i) % apTimeout->iItemSize;
        Join<stTimeoutItem_t, stTimeoutItemLink_t>(apResult, apTimeout->pItems + idx);
    }
    /* 刷新当前数据。 */
    apTimeout->ullStart = allNow;
    apTimeout->llStartIdx += cnt - 1;
}

/* 事件循环，处理事件。 */
void co_eventloop(stCoEpoll_t *ctx, pfn_co_eventloop_t pfn, void *arg) {
    ...
    for (;;) {
        int ret = co_epoll_wait(ctx->iEpollFd, result, stCoEpoll_t::_EPOLL_SIZE, 1);
        ...
        /* 取出当前时间到期事件。 */
        unsigned long long now = GetTickMS();
        TakeAllTimeout(ctx->pTimeout, now, timeout);
        ...
        /* 标识这个时间是到期事件，因为 fd 事件和事件耦合在一起了（!^_^）。 */
        stTimeoutItem_t *lp = timeout->head;
        while (lp) {
            lp->bTimeout = true;
            lp = lp->pNext;
        }

        Join<stTimeoutItem_t, stTimeoutItemLink_t>(active, timeout);

        lp = active->head;
        while (lp) {
            /* 遍历处理活跃事件。（fd 事件，到期事件。） */
            PopHead<stTimeoutItem_t, stTimeoutItemLink_t>(active);
            if (lp->bTimeout && now < lp->ullExpireTime) {
                /* 因为时间轮数组只有 60000 个下标，一般存储 1 分钟以内的到期事件，
                 * 但是超过 1 分钟到期的事件也支持存储，这样有可能这些事件经过取模，
                 * 与 1 分钟以内到期事件存储在同一个双向链表里，被取出来了，
                 * 所以这些没到期的事件，应该重新存回去。 */
                int ret = AddTimeout(ctx->pTimeout, lp, now);
                if (!ret) {
                    lp->bTimeout = false;
                    lp = active->head;
                    continue;
                }
            }
            ...
            lp = active->head;
        }
    }
}
```

---

## 3. 缺点

* 时间轮数组默认大小是 60 * 1000。以毫秒为单位，最大时间间隔是一分钟，但是如果超过了一分钟以内的事件，效率就降低了，例如 session，它的过期时间就经常超过 1 分钟。
* libco 的定时器设计主要是为了它内部协程切换使用，添加一个定时事件以后，无法通过查找方式，删除指定时间事件，只有等到事件触发了，事件才会从双向链表中删除。
* 综合上述两个问题，这也很好解析了，为啥有的开源通过小堆去维护定时器，例如 libev。

---

## 4. 小结

libco 的定时器设计非常优秀，在一定的范围内，非常高效，虽然有些小缺点，但是瑕不掩瑜。

---

## 5. 参考

* [libco 的定时器实现：时间轮](cyhone.com/articles/time-wheel-in-libco/)