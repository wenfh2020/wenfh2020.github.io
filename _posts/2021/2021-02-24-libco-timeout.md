---
layout: post
title:  "[libco] libco 不干活也费 CPU"
categories: libco
tags: libco workflow
author: wenfh2020
---

在 Linux 系统，libco 调用 epoll_wait 有点用力过猛，虽然 libco 针对大并发，但是小问题的处理，略显粗糙。



* content
{:toc}

---

## 1. 问题

co_epoll_wait 的 timeout 这里默认为 1，在循环里，每毫秒执行事件处理。

```c
void co_eventloop(stCoEpoll_t *ctx, pfn_co_eventloop_t pfn, void *arg) {
    ...
    for (;;) {
        int ret = co_epoll_wait(ctx->iEpollFd, result, stCoEpoll_t::_EPOLL_SIZE, 1);
        ...
   }
   ...
}
```

---

## 2. 建议

应该先捞一个快到期的事件，当前时间与到期的时间差进行等待。

详细可以参考 redis 的事件处理： [numevents = aeApiPoll(eventLoop, tvp);](https://github.com/redis/redis/blob/049cf8cdf4e9e0abecf137dc1e3362089439f414/src/ae.c#L395)

---

## 3. 测试

### 3.1. 测试代码

```c
int co_sleep(int ms) {
    struct pollfd pf = {0};
    pf.fd = -1;
    pf.events = -1;
    return poll(&pf, 1, ms);
}

void* co_handle_timer(void* arg) {
    co_enable_hook_sys();

    for (;;) {
        co_sleep(1000);
    }

    return 0;
}

int main() {
    stCoRoutine_t* co;
    co_create(&co, NULL, co_handle_timer, nullptr);
    co_resume(co);
    co_eventloop(co_get_epoll_ct(), 0, 0);
    return 0;
}
```

---

### 3.2. cpu

<div align=center><img src="/images/2021-02-24-09-56-39.png" data-action="zoom"/></div>

---

### 3.3. 性能火焰图

<div align=center><img src="/images/2021-02-24-09-52-08.png" data-action="zoom"/></div>

> 火焰图参考：[如何生成火焰图🔥](https://wenfh2020.com/2020/07/30/flame-diagram/)
