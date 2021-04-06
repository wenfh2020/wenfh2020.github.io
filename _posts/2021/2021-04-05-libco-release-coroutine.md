---
layout: post
title:  "[libco] libco 删除协程的正确姿势"
categories: libco
tags: libco release coroutine
author: wenfh2020
mathjax: true
---

如果你认为只要简单调用 `co_release` 就能将 [libco](https://github.com/Tencent/libco) 的协程删除，那等待你的可能就是定时炸弹 💣。




* content
{:toc}

---

## 1. 正确姿势

什么情况下才是删除协程的正确姿势？

禁止删除一个正在工作的协程；删除已经停止工作（`stCoRoutine_t.cEnd == 1`）的协程是比较安全的。

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

因为协程在工作过程中可能触发 `poll` 功能。它主要处理了两种类型事件：socket 事件和定时器事件，这些事件都是异步回调的。当事件触发后，发现协程被释放了，那么协程指针变成了野指针！

```c
int co_poll_inner(stCoEpoll_t *ctx, struct pollfd fds[], nfds_t nfds, int timeout, poll_pfn_t pollfunc) {
    ...
    int ret = co_epoll_ctl(epfd, EPOLL_CTL_ADD, fds[i].fd, &ev);
    ...
    int ret = AddTimeout(ctx->pTimeout, &arg, now);
    ...
    co_epoll_ctl(epfd, EPOLL_CTL_DEL, fd, &arg.pPollItems[i].stEvent);
    ...
}
```
