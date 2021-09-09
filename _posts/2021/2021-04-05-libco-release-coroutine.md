---
layout: post
title:  "[libco] 删除协程的正确姿势"
categories: libco
tags: libco release coroutine
author: wenfh2020
---

如果你认为只需要简单调用 `co_release` 就能将 [libco](https://github.com/Tencent/libco) 的协程删除，那等待你的可能就是定时炸弹 💣。




* content
{:toc}

---

## 1. 正确姿势

如何才能安全删除一个协程？

禁止删除一个正在工作的协程，删除已经停止工作（`stCoRoutine_t.cEnd == 1`）的协程是比较安全的。

```c
/* 协程数据结构。 */
struct stCoRoutine_t {
    ...
    char cEnd; /* 协程是否结束。 */
    ...
};

/* 协程运行函数。 */
static int CoRoutineFunc(stCoRoutine_t *co, void *) {
    if (co->pfn) {
        co->pfn(co->arg);
    }
    co->cEnd = 1; /* 协程工作函数退出后，协程就已经结束了。 */

    stCoRoutineEnv_t *env = co->env;
    co_yield_env(env);
    return 0;
}
```

---

## 2. 原因

为啥删除工作中的协程是不安全？

因为协程在工作过程中可能触发 `poll` 功能。它主要处理了两种类型事件：socket 事件和定时器事件，这些事件都是异步回调的。当事件触发后，如果协程被释放了，那么保存的协程指针变成了 `野指针`!

```c
int co_poll_inner(stCoEpoll_t *ctx, struct pollfd fds[], nfds_t nfds, int timeout, poll_pfn_t pollfunc) {
    ...
    stPoll_t &arg = *((stPoll_t *)malloc(sizeof(stPoll_t)));
    ...
    /* 保存当前协程指针。 */
    arg.pArg = GetCurrCo(co_get_curr_thread_env());
    ...
    /* 添加关注的 socket 事件。 */
    int ret = co_epoll_ctl(epfd, EPOLL_CTL_ADD, fds[i].fd, &ev);
    ...
    /* 添加定时器事件。 */
    int ret = AddTimeout(ctx->pTimeout, &arg, now);
    ...
    /* 切出当前协程。 */
    co_yield_env(co_get_curr_thread_env());
    ...
    /* 删除定时器事件。 */
    RemoveFromLink<stTimeoutItem_t, stTimeoutItemLink_t>(&arg);
    ...
    /* 删除关注的 socket 事件。 */
    co_epoll_ctl(epfd, EPOLL_CTL_DEL, fd, &arg.pPollItems[i].stEvent);
    ...
}
```
