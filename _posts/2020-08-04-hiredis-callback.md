---
layout: post
title:  "[hiredis 源码走读] 异步回调机制剖析"
categories: redis
tags: hiredis redis callback
author: wenfh2020
---

hiredis 是 redis 的一个 c - client，异步通信非常高效。单链接异步压测，轻松并发 10w+，具体请参考《[hiredis + libev 异步测试](https://wenfh2020.com/2018/06/17/redis-hiredis-libev/)》。本章主要剖析 hiredis 异步回调机制原理，围绕三个问题，展开描述。

1. 异步回调原理。
2. 异步回调如何保证 request/response 时序。
3. 单链接异步读写 redis，为何能并发 10w+。




* content
{:toc}

---

## 1. 异步回调原理

先看看异步通信流程。

![高性能异步框架通信流程](/images/2020-06-11-21-28-24.png){:data-action="zoom"}

> 设计图来源：《[异步服务框架通信流程](https://www.processon.com/view/5ee1d7de7d9c084420107b53)》

---

### 1.1. demo

hiredis 的 demo，支持大部分主流事件库。它非常实用，从另一方面说 hiredis 它不是一个独立的实现，它是一个在主流的第三方库基础上进行二次封装的套件。

```shell
[wenfh2020:~/src/other/hiredis/examples]$ tree
.
├── CMakeLists.txt
├── example-ae.c
├── example-glib.c
├── example-ivykis.c
├── example-libev.c
├── example-libevent-ssl.c
├── example-libevent.c
├── example-libuv.c
├── example-macosx.c
├── example-qt.cpp
├── example-qt.h
├── example-ssl.c
└── example.c
```

---

### 1.2. 使用

hiredis 回调接口使用简单，做得非常精简。例如结合 `libev` 实现异步回调 [demo](https://github.com/redis/hiredis/blob/master/examples/example-libev.c)，只要绑定三个接口即可。

```c++
int main (int argc, char **argv) {
#ifndef _WIN32
    signal(SIGPIPE, SIG_IGN);
#endif

    redisAsyncContext *c = redisAsyncConnect("127.0.0.1", 6379);
    if (c->err) {
        /* Let *c leak for now... */
        printf("Error: %s\n", c->errstr);
        return 1;
    }

    redisLibevAttach(EV_DEFAULT_ c);
    redisAsyncSetConnectCallback(c,connectCallback);
    redisAsyncSetDisconnectCallback(c,disconnectCallback);
    redisAsyncCommand(c, NULL, NULL, "SET key %b", argv[argc-1], strlen(argv[argc-1]));
    redisAsyncCommand(c, getCallback, (char*)"end-1", "GET key");
    ev_loop(EV_DEFAULT_ 0);
    return 0;
}
```

---

### 1.3. 回调接口

hiredis 异步通信上下文 `redisAsyncContext` 结构，三个回调接口分别是：

1. 链接回调 `redisConnectCallback`。
2. 断开链接回调 `redisConnectCallback`。
3. 正常数据通信回调 `redisCallbackFn`。

```c
// async.h
/* Reply callback prototype and container */
typedef void (redisCallbackFn)(struct redisAsyncContext*, void*, void*);
typedef void (redisDisconnectCallback)(const struct redisAsyncContext*, int status);
typedef void (redisConnectCallback)(const struct redisAsyncContext*, int status);

typedef struct redisCallback {
    struct redisCallback *next; /* simple singly linked list */
    redisCallbackFn *fn;
    int pending_subs;
    void *privdata;
} redisCallback;

/* List of callbacks for either regular replies or pub/sub */
typedef struct redisCallbackList {
    redisCallback *head, *tail;
} redisCallbackList;

/* Context for an async connection to Redis */
typedef struct redisAsyncContext {
    ...
    /* Called when either the connection is terminated due to an error or per
     * user request. The status is set accordingly (REDIS_OK, REDIS_ERR). */
    redisDisconnectCallback *onDisconnect;

    /* Called when the first write event was received. */
    redisConnectCallback *onConnect;

    /* Regular command callbacks */
    redisCallbackList replies;
    ...
};
```

---

### 1.4. 回调流程

* 请求。每个命令请求回调接口被添加到回调列表 `redisCallbackList`。

```c
int redisAsyncCommand(redisAsyncContext *ac, redisCallbackFn *fn, void *privdata, const char *format, ...) {
    ...
    status = redisvAsyncCommand(ac, fn, privdata, format, ap);
    ...
}

int redisvAsyncCommand(redisAsyncContext *ac, redisCallbackFn *fn, void *privdata, const char *format, va_list ap) {
    ...
    // 格式化命令。
    len = redisvFormatCommand(&cmd, format, ap);
    // 异步发送。
    status = __redisAsyncCommand(ac, fn, privdata, cmd, len);
    ...
}

static int __redisAsyncCommand(redisAsyncContext *ac, redisCallbackFn *fn, void *privdata, const char *cmd, size_t len) {
    ...
    // 回调对象。
    redisCallback cb;
    ...
    /* Setup callback */
    cb.fn = fn;
    cb.privdata = privdata;
    cb.pending_subs = 1;
    ...
    // request 关联回调，将每个请求回调添加到上下文的回调链表中。
    __redisPushCallback(&ac->replies, &cb);
    ...
}

/* Helper functions to push/shift callbacks */
static int __redisPushCallback(redisCallbackList *list, redisCallback *source) {
    redisCallback *cb;

    /* Copy callback from stack to heap */
    cb = malloc(sizeof(*cb));
    if (cb == NULL)
        return REDIS_ERR_OOM;

    if (source != NULL) {
        memcpy(cb, source, sizeof(*cb));
        cb->next = NULL;
    }

    /* Store callback in list */
    if (list->head == NULL)
        list->head = cb;
    if (list->tail != NULL)
        list->tail->next = cb;
    list->tail = cb;
    return REDIS_OK;
}
```

* 回复。读数据 -> 解包 -> 从回调链表中取头部节点进行回调逻辑处理。

```c
void redisProcessCallbacks(redisAsyncContext *ac) {
    redisContext *c = &(ac->c);
    redisCallback cb = {NULL, NULL, 0, NULL};
    void *reply = NULL;
    int status;

    // 对接收数据进行解包。
    while ((status = redisGetReply(c, &reply)) == REDIS_OK) {
        ...
        // 从回调链表结构中取头部节点。
        /* Even if the context is subscribed, pending regular callbacks will
         * get a reply before pub/sub messages arrive. */
        if (__redisShiftCallback(&ac->replies, &cb) != REDIS_OK) {
            ...
        }

        if (cb.fn != NULL) {
            // 处理回调逻辑。
            __redisRunCallback(ac, &cb, reply);
            ...
        }
        ...
    }
    ...
}

// 从链表中，取头部节点。
static int __redisShiftCallback(redisCallbackList *list, redisCallback *target) {
    redisCallback *cb = list->head;
    if (cb != NULL) {
        list->head = cb->next;
        if (cb == list->tail)
            list->tail = NULL;

        /* Copy callback from heap to stack */
        if (target != NULL)
            memcpy(target, cb, sizeof(*cb));
        free(cb);
        return REDIS_OK;
    }
    return REDIS_ERR;
}

// 调用回调函数。
static void __redisRunCallback(redisAsyncContext *ac, redisCallback *cb, redisReply *reply) {
    redisContext *c = &(ac->c);
    if (cb->fn != NULL) {
        c->flags |= REDIS_IN_CALLBACK;
        cb->fn(ac, reply, cb->privdata);
        c->flags &= ~REDIS_IN_CALLBACK;
    }
}
```

---

## 2. 请求时序

上文已经将请求回调的基本流程描述清楚，请求回调结构是用链表顺序保存的，然而 redis 命令没有提供任何 privdata 参数。那么请求和回调是如何保证时序的？主要基于以下两个条件：

1. tcp 链接。redis 采用 tcp 协议进行通信，tcp 通信具有时序性，链接的每个包是顺序发出去的，不存在乱序问题，所以这样可以保证顺序发送。

2. redis 单进程处理命令。因为 redis 是单进程主线程处理命令的，所以顺序发送的命令，将会被顺序处理，这样可以保证顺序回复。
   > redis 6.0 增加的多线程功能，也是每个 client 的命令数据包被独立放在一个线程里面处理，所以命令也是顺序处理的。详细请参考《[[redis 源码走读] 多线程通信 I/O](https://wenfh2020.com/2020/04/13/redis-multithreading-mode/)》

结合上面两点，可以保证 hiredis 请求异步回调时序。

---

> **【注意】** redis 是单进程主线程处理命令逻辑的，但是很多 redis proxy，并不一定是单进程的单线程，所以 proxy 需要解决请求和回调的时序性。

---

## 3. 高性能原理

单链接异步读写 redis，为何能并发 10w+，主要三个原因：

1. 非阻塞网络通信。
2. redis 高性能特性。
3. 多路复用技术。

---

### 3.1. redis 性能

hiredis 异步回调快，是建立在 redis 快的基础上的，详细请参考《[redis 为啥这么快](https://wenfh2020.com/2020/05/29/redis-fast/)》。

---

### 3.2. 多路复用技术

![hiredis + libev 工作流程](/images/2020-08-07-08-37-03.png){:data-action="zoom"}

首先通信链接 socket 被设置为非阻塞的。

hiredis 不是一个独立实现的 c - client，它基于第三方库。例如它结合 `libev`，Linux 系统下，libev 默认用 epoll 多路复用技术处理读写事件。用户调用 hiredis 的发送数据接口，并不会马上将数据发送出去，而是先保存在发送缓冲区，然后当 libev 触发写事件，才会将发送缓冲区的数据发送出去。

而 redis 的网络事件也是通过多路复用事件驱动处理，client 当收到写事件，它向 redis 服务发送了一个命令集合，相当于 redis 的 `pipline` 管道技术，将多个命令打包发送。redis 接收处理完，将回复命令集合通过epoll 触发写事件进行发送。相当于每次通信都能处理多个命令，减少了大量 RTT(Round-Trip Time) 往返时间。

```c
// 向事件库注册 socket 对应的读写事件。
static int redisLibevAttach(EV_P_ redisAsyncContext *ac) {
    ...
    /* Initialize read/write events */
    ev_io_init(&e->rev,redisLibevReadEvent,c->fd,EV_READ);
    ev_io_init(&e->wev,redisLibevWriteEvent,c->fd,EV_WRITE);
    return REDIS_OK;
}
```

---

## 4. 参考

* [hiredis + libev 异步测试](https://wenfh2020.com/2018/06/17/redis-hiredis-libev/)
* [redis 为啥这么快](https://wenfh2020.com/2020/05/29/redis-fast/)
* [高性能服务异步通信逻辑](https://wenfh2020.com/2020/06/11/server-async-logic/)
* [[redis 源码走读] 多线程通信 I/O](https://wenfh2020.com/2020/04/13/redis-multithreading-mode/)
