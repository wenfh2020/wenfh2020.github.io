---
layout: post
title:  "高性能服务异步通信逻辑"
categories: 网络
tags: async
author: wenfh2020
---

最近整理了一下服务程序异步通信逻辑思路。异步逻辑与同步逻辑处理差别比较大，异步逻辑可能涉及多次回调才能完成一个请求处理，逻辑被碎片化，切分成串行的步骤。习惯了写同步逻辑的朋友，有可能思维上转不过来。



* content
{:toc}

---

## 1. 逻辑

* 高性能异步非阻塞服务，底层一般用多路复用 I/O 模型对事件进行管理，Linux 平台用 epoll。
* epoll 支持异步事件逻辑。epoll_wait 会将就绪事件从内核中取出进行处理。
* 服务处理事件，每个 fd 对应一个事件处理器 callback 处理取出的 events。
* callback 逻辑被分散为逻辑步骤 `step`，这些步骤一般是异步串行处理，时序跟同步差不多，只是异步逻辑可能需要回调多次才能处理完一个完整的逻辑。

![高性能异步框架通信流程](/images/2020-06-11-21-28-24.png){:data-action="zoom"}

> 设计图来源：《[异步服务框架通信流程](https://www.processon.com/view/5ee1d7de7d9c084420107b53)》

---

## 2. 源码

正常逻辑一般有 N 个步骤，异步逻辑不同之处，通过 callback 逻辑实现，与同步比较确实有点反人类。callback 回调回来还能定位到原来执行体，关键点在于 `privdata`。

我们看看 redis 的 callback 逻辑。（[github 源码](https://github.com/redis/redis/blob/unstable/src/sentinel.c)）

* 事件结构。

```c
typedef struct redisAeEvents {
    redisAsyncContext *context;
    aeEventLoop *loop;
    int fd;
    int reading, writing;
} redisAeEvents;
```

* 添加读事件，将 privdata (`redisAeEvents`) 与对应事件，对应回调函数绑定。

```c
static void redisAeAddRead(void *privdata) {
    redisAeEvents *e = (redisAeEvents*)privdata;
    aeEventLoop *loop = e->loop;
    if (!e->reading) {
        e->reading = 1;
        aeCreateFileEvent(loop,e->fd,AE_READABLE,redisAeReadEvent,e);
    }
}
```

* 回调。

```c
static void redisAeReadEvent(aeEventLoop *el, int fd, void *privdata, int mask) {
    ((void)el); ((void)fd); ((void)mask);

    redisAeEvents *e = (redisAeEvents*)privdata;
    redisAsyncHandleRead(e->context);
}
```

---

## 3. 参考

* [[redis 源码走读] 事件 - 文件事件](https://wenfh2020.com/2020/04/09/redis-ae-file/)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/2020/06/11/server-async-logic/)
