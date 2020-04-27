---
layout: post
title:  "[redis 源码走读] 事件 - 文件事件"
categories: redis
tags: redis 文件事件 event epoll
author: wenfh2020
---

redis 服务底层采用了`异步事件`管理（`aeEventLoop`）：管理时间事件和文件事件。对于大量网络文件描述符（fd）的事件管理，redis 建立在安装系统对应的事件驱动基础上（例如 Linux 的 `epoll`）。

> * 关于事件驱动，本章主要讲述 Linux 系统的 epoll 事件驱动。
> * 关于事件处理，本章主要讲述文件事件，时间事件可以参考帖子 [[redis 源码走读] 事件 - 定时器](https://wenfh2020.com/2020/04/06/ae-timer/)。



* content
{:toc}

---

## 1. 事件驱动

redis 根据安装系统选择对应的事件驱动。

```c
// ae.c
/* Include the best multiplexing layer supported by this system.
 * The following should be ordered by performances, descending. */
#ifdef HAVE_EVPORT
#include "ae_evport.c"
#else
    #ifdef HAVE_EPOLL
    #include "ae_epoll.c"
    #else
        #ifdef HAVE_KQUEUE
        #include "ae_kqueue.c"
        #else
        #include "ae_select.c"
        #endif
    #endif
#endif
```

---

## 2. 异步事件管理

`epoll` 是异步事件驱动，上层逻辑操作和下层事件驱动要通过 fd 文件描述符串联起来。异步事件管理（`aeEventLoop`），对 epoll 做了一些封装，方便异步事件回调处理。

> 有关 epoll 工作流程，可以参考我的帖子：[epoll 多路复用 I/O工作流程](https://wenfh2020.com/2020/04/14/epoll-workflow/)

![redis 文件事件封装](/images/2020-04-09-22-04-00.png){: data-action="zoom"}

| 层次       | 描述                                                                |
| :--------- | :------------------------------------------------------------------ |
| ae.c       | 关联异步业务事件和 epoll 接口，处理 fd 对应事件逻辑。               |
| ae_epoll.c | 对 epoll 接口进行封装，方便上层操作。                               |
| epoll      | Linux 内核多路复用 I/O 模型，主要为了高效处理大批量文件描述符事件。 |

---

### 2.1. 数据结构

```c
// ae.c

// 文件事件结构
typedef struct aeFileEvent {
    int mask; // 事件类型组合（one of AE_(READABLE|WRITABLE|BARRIER)）
    aeFileProc *rfileProc; // 读事件回调操作。
    aeFileProc *wfileProc; // 写事件回调操作。
    void *clientData;      // 业务传入的私有数据。方便回调使用。
} aeFileEvent;

// 就绪事件
typedef struct aeFiredEvent {
    int fd;   // 文件描述符。
    int mask; // 事件类型组合。
} aeFiredEvent;

// 事件管理结构
typedef struct aeEventLoop {
    int maxfd;   // 监控的最大文件描述符。
    int setsize; // 处理文件描述符个数。
    ...
    aeFileEvent *events; // 根据 fd 监听事件。
    aeFiredEvent *fired; // 从内核取出的就绪事件。
    ...
} aeEventLoop;
```

| 结构         | 描述                                                                                                                       |
| :----------- | :------------------------------------------------------------------------------------------------------------------------- |
| aeEventLoop  | 文件事件和时间事件管理。                                                                                                   |
| aeFileEvent  | 文件事件结构，方便异步回调逻辑调用。aeEventLoop 会创建一个 aeFileEvent 数组，数组下标是 fd，fd 对应 aeFileEvent 数据结构。 |
| aeFiredEvent | 从内核获取的就绪事件。（例如 Linux 系统通过 epoll_wait 接口获取就绪事件，每个事件分别存储在 aeFiredEvent 数组中）          |

---

### 2.2. 创建事件管理对象

创建事件管理对象，对监控的文件数量设置了上限。

* 文件监控上限配置。

```shell
# redis.conf
#
# Set the max number of connected clients at the same time. By default
# this limit is set to 10000 clients, however if the Redis server is not
# able to configure the process file limit to allow for the specified limit
# the max number of allowed clients is set to the current file limit
# minus 32 (as Redis reserves a few file descriptors for internal uses).
#
# Once the limit is reached Redis will close all the new connections sending
# an error 'max number of clients reached'.
#
# maxclients 10000
```

* 创建事件管理对象。

```c
#define CONFIG_MIN_RESERVED_FDS 32
#define CONFIG_FDSET_INCR (CONFIG_MIN_RESERVED_FDS+96)

// server.c
void initServer(void) {
    ...
    server.el = aeCreateEventLoop(server.maxclients+CONFIG_FDSET_INCR);
    ...
}

int main(int argc, char **argv) {
    ...
    initServer();
    ...
}
```

---

### 2.3. 事件处理流程

* 循环处理事件

```c
// server.c
int main(int argc, char **argv) {
    ...
    aeMain(server.el);
    ...
}

// ae.c
// 循环处理事件
void aeMain(aeEventLoop *eventLoop) {
    eventLoop->stop = 0;
    while (!eventLoop->stop) {
        if (eventLoop->beforesleep != NULL)
            eventLoop->beforesleep(eventLoop);
        aeProcessEvents(eventLoop, AE_ALL_EVENTS|AE_CALL_AFTER_SLEEP);
    }
}
```

* 添加事件，关联 fd 事件与异步回调相关信息。

```c
int aeCreateFileEvent(aeEventLoop *eventLoop, int fd, int mask,
        aeFileProc *proc, void *clientData) {
    if (fd >= eventLoop->setsize) {
        errno = ERANGE;
        return AE_ERR;
    }
    aeFileEvent *fe = &eventLoop->events[fd];

    // 调用底层 epoll_ctl 注册事件。
    if (aeApiAddEvent(eventLoop, fd, mask) == -1)
        return AE_ERR;
    fe->mask |= mask;
    if (mask & AE_READABLE) fe->rfileProc = proc;
    if (mask & AE_WRITABLE) fe->wfileProc = proc;
    fe->clientData = clientData;
    if (fd > eventLoop->maxfd)
        eventLoop->maxfd = fd;
    return AE_OK;
}
```

* 删除事件，删除对应 fd 的事件。

```c
void aeDeleteFileEvent(aeEventLoop *eventLoop, int fd, int mask) {
    if (fd >= eventLoop->setsize) return;
    aeFileEvent *fe = &eventLoop->events[fd];
    if (fe->mask == AE_NONE) return;

    // 如果删除的是写事件，要把写事件优先处理的事件也去掉，恢复优先处理读事件，再处理写事件逻辑。
    if (mask & AE_WRITABLE) mask |= AE_BARRIER;

    // 调用底层 epoll_ctl 修改删除事件。
    aeApiDelEvent(eventLoop, fd, mask);
    fe->mask = fe->mask & (~mask);
    if (fd == eventLoop->maxfd && fe->mask == AE_NONE) {
        /* Update the max fd */
        int j;

        for (j = eventLoop->maxfd-1; j >= 0; j--)
            if (eventLoop->events[j].mask != AE_NONE) break;
        eventLoop->maxfd = j;
    }
}
```

---

### 2.4. 事件处理逻辑

文件事件处理逻辑，从内核取出就绪事件，根据事件的读写类型，分别进行回调处理相关业务逻辑。

```c
// ae.c
int aeProcessEvents(aeEventLoop *eventLoop, int flags) {
    ...
    // 多路复用接口，从内核取出就绪事件。
    numevents = aeApiPoll(eventLoop, tvp);
    ...
    for (j = 0; j < numevents; j++) {
        // 根据就绪事件 fd，取出对应的异步文件事件进行逻辑处理。
        aeFileEvent *fe = &eventLoop->events[eventLoop->fired[j].fd];
        int mask = eventLoop->fired[j].mask;
        int fd = eventLoop->fired[j].fd;
        int fired = 0; /* Number of events fired for current fd. */

        /* AE_BARRIER 表示优先可写事件。正常情况，一般先读后写。
         * AE_BARRIER 使用场景，有兴趣的朋友，可以查找源码关键字：CONN_FLAG_WRITE_BARRIER
         * 理解这部分的逻辑。 */
        int invert = fe->mask & AE_BARRIER;

        if (!invert && fe->mask & mask & AE_READABLE) {
            fe->rfileProc(eventLoop,fd,fe->clientData,mask);
            fired++;
        }

        if (fe->mask & mask & AE_WRITABLE) {
            if (!fired || fe->wfileProc != fe->rfileProc) {
                fe->wfileProc(eventLoop,fd,fe->clientData,mask);
                fired++;
            }
        }

        if (invert && fe->mask & mask & AE_READABLE) {
            if (!fired || fe->wfileProc != fe->rfileProc) {
                fe->rfileProc(eventLoop,fd,fe->clientData,mask);
                fired++;
            }
        }
        ...
    }
    ...
}
```

---

### 2.5. 获取待处理事件

通过 `epoll_wait` 从系统内核取出就绪文件事件进行处理。

```c
// ae_epoll.c
static int aeApiPoll(aeEventLoop *eventLoop, struct timeval *tvp) {
    aeApiState *state = eventLoop->apidata;
    int retval, numevents = 0;

    // 从内核取出就绪文件事件进行处理。
    retval = epoll_wait(state->epfd,state->events,eventLoop->setsize,
            tvp ? (tvp->tv_sec*1000 + tvp->tv_usec/1000) : -1);
    if (retval > 0) {
        int j;

        numevents = retval;
        for (j = 0; j < numevents; j++) {
            int mask = 0;
            struct epoll_event *e = state->events+j;

            if (e->events & EPOLLIN) mask |= AE_READABLE;
            if (e->events & EPOLLOUT) mask |= AE_WRITABLE;
            if (e->events & EPOLLERR) mask |= AE_WRITABLE|AE_READABLE;
            if (e->events & EPOLLHUP) mask |= AE_WRITABLE|AE_READABLE;

            // 就绪事件和fd保存到 fired。
            eventLoop->fired[j].fd = e->data.fd;
            eventLoop->fired[j].mask = mask;
        }
    }
    return numevents;
}
```

---

## 3. 总结

* redis 没有使用第三方库，实现跨平台的异步事件驱动。对文件事件驱动封装也比较简洁高效。

---

## 4. 参考

* [用 gdb 调试 redis](https://wenfh2020.com/2020/01/05/redis-gdb/)
* [UML类图与类的关系详解](http://www.uml.org.cn/oobject/201104212.asp)
* 《redis 设计与实现》
* [Redis 多线程的 Redis](https://ruby-china.org/topics/38957)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)