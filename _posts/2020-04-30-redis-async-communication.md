---
layout: post
title:  "[redis 源码走读] 异步通信流程-单线程"
categories: redis
tags: reids async network
author: wenfh2020
---

| 重点              | 描述                                                     |
| :---------------- | :------------------------------------------------------- |
| 服务异步通信核心  | 非阻塞 + 异步事件驱动。                                  |
| 事件驱动核心源码  | ae.c                                                     |
| 网络通信核心源码  | connection.h / connection.c，networking.h / connection.c |
| 读/写数据核心函数 | readQueryFromClient / writeToClient                      |

> 本文主要讲述 Linux 平台下的 redis 客户端与服务端异步通信（单线程），不包括 redis 集群间的通信。



* content
{:toc}

---

## 1. 异步服务工作流程

redis 客户端与服务端异步通信流程，整体逻辑有点复杂，先看看流程图，后面再抓抓重点。

![异步服务工作流程](/images/2020-05-04-01-19-51.png){:data-action="zoom"}

> 流程图来源： 《[redis 异步网络通信流程 - 单线程](https://www.processon.com/view/5eab75227d9c0869dab46472)》

---

## 2. 非阻塞

### 2.1. socket 非塞设置

redis 客户端与服务端通过 TCP 协议进行通信。服务监听端口创建的 socket，客户端接入服务的 socket，都需要设置非阻塞。

```c
int anetNonBlock(char *err, int fd) {
    return anetSetBlock(err,fd,1);
}

int anetSetBlock(char *err, int fd, int non_block) {
    int flags;

    if ((flags = fcntl(fd, F_GETFL)) == -1) {
        anetSetError(err, "fcntl(F_GETFL): %s", strerror(errno));
        return ANET_ERR;
    }

    if (non_block)
        flags |= O_NONBLOCK;
    else
        flags &= ~O_NONBLOCK;

    if (fcntl(fd, F_SETFL, flags) == -1) {
        anetSetError(err, "fcntl(F_SETFL,O_NONBLOCK): %s", strerror(errno));
        return ANET_ERR;
    }
    return ANET_OK;
}
```

---

### 2.2. 网络通信函数

socket 非阻塞设置后，部分默认阻塞的函数，变成非阻塞，数据一次没有处理完的情况下，函数返回结果 `-1`，错误 `errno` 是 `EAGAIN` 或 `EWOULDBLOCK`。

* accept

```c
void acceptTcpHandler(aeEventLoop *el, int fd, void *privdata, int mask) {
    ...
    while(max--) {
        cfd = anetTcpAccept(server.neterr, fd, cip, sizeof(cip), &cport);
        if (cfd == ANET_ERR) {
            if (errno != EWOULDBLOCK)
                serverLog(LL_WARNING,
                    "Accepting client connection: %s", server.neterr);
            return;
        }
        ...
    }
}

static int anetGenericAccept(char *err, int s, struct sockaddr *sa, socklen_t *len) {
    int fd;
    while(1) {
        fd = accept(s,sa,len);
        if (fd == -1) {
            if (errno == EINTR)
                continue;
            else {
                anetSetError(err, "accept: %s", strerror(errno));
                return ANET_ERR;
            }
        }
        break;
    }
    return fd;
}
```

* read

```c
static int connSocketRead(connection *conn, void *buf, size_t buf_len) {
    int ret = read(conn->fd, buf, buf_len);
    if (!ret) {
        conn->state = CONN_STATE_CLOSED;
    } else if (ret < 0 && errno != EAGAIN) {
        conn->last_errno = errno;
        conn->state = CONN_STATE_ERROR;
    }

    return ret;
}
```

* write

```c
static int connSocketWrite(connection *conn, const void *data, size_t data_len) {
    int ret = write(conn->fd, data, data_len);
    if (ret < 0 && errno != EAGAIN) {
        conn->last_errno = errno;
        conn->state = CONN_STATE_ERROR;
    }

    return ret;
}
```

---

## 3. 事件驱动

redis 服务通过事件驱动监控 fd 读写事件。redis 在 Linux 系统事件驱动默认选择 `epoll`。

### 3.1. epoll 接口

| 接口         | 描述                                                           |
| :----------- | :------------------------------------------------------------- |
| epoll_create | 创建 epoll 事件驱动。                                          |
| epoll_ctl    | 事件驱动对 fd 对应事件进行增删改管理。                         |
| epoll_wait   | 阻塞从内核获取就绪事件。接口有时间参数，可以设置阻塞等待时间。 |

---

### 3.2. epoll 使用逻辑

socket 设置非阻塞后，write / read，有可能不是一次性将数据读写完成再返回（参考 2.2 章节）。redis 采用 `epoll` 默认模式是 `LT`，当数据没处理完，内核重复通知事件给服务处理。

* read 数据，只要没有读取完成 fd 对应的所有接收数据，内核会不停通知 `EPOLLIN` 读事件。即 `epoll_wait` 不停取出读事件要求读数据，直到 read 所有接收到的数据，才会停止 `EPOLLIN` 读事件通知。
* write 数据，服务一次发送不完，那么需要服务主动调用 `epoll_ctl` 监控写事件，下次 `epoll_wait` 会通知 `EPOLLOUT` 事件，服务继续处理写事件，直到将数据发送完毕为止。数据发送完毕后，再通过 `epoll_ctl` 取消监控 `EPOLLOUT` 写事件。（参考 `sendReplyToClient`源码实现逻辑）

![epoll 使用流程](/images/2020-05-11-16-57-43.png){:data-action="zoom"}

> 图片来源：《[epoll 多路复用 I/O工作流程](https://wenfh2020.com/2020/04/14/epoll-workflow/)》

---

### 3.3. 异步回调

redis 对事件驱动封装了一层，核心代码在 `ae.c`，目的有两个：跨平台，异步回调。

#### 3.3.1. 跨平台

跨平台，不同平台可以根据预编译宏，选择对应平台的事件驱动。

```c
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

#### 3.3.2. 事件回调异步逻辑

事件驱动异步回调的核心逻辑是 fd + 事件 + 事件对应处理函数。参考源码：

1. 数据结构：`aeFileEvent`，`client`， `connection`。
2. 回调函数：`acceptTcpHandler`，`readQueryFromClient`， `sendReplyToClient`。

* 服务端回调流程

```shell
aeEventLoop -> epoll_wait(fd + events) -> aeFileEvent.rfileProc -> acceptTcpHandler
```

* 客户端回调流程

```shell
aeEventLoop -> epoll_wait(fd + events) -> aeFileEvent.rfileProc/wfileProc -> client.connection.ae_handler
```

* 事件结构

```c
// events 是一个以 fd 为下标的事件数组。
typedef struct aeEventLoop {
    ...
    aeFileEvent *events; // 事件数组。
    ...
} aeEventLoop;

/* File event structure */
typedef struct aeFileEvent {
    int mask; /* one of AE_(READABLE|WRITABLE|BARRIER) */
    aeFileProc *rfileProc; // 读回调函数。
    aeFileProc *wfileProc; // 写回调函数。
    void *clientData; // client 的 connection 指针。
} aeFileEvent;
```

> fd 文件描述符在内核里也相当于一个下标，递增的，它对应的是文件。Linux 一切皆文件，所以 socket 本质上也是一个文件。

```c
// file.c
void fd_install(unsigned int fd, struct file *file) {
    __fd_install(current->files, fd, file);
}
```

---

## 4. 服务数据结构

redis 的异步逻辑挺多细节的，结合上图，重点理解下列数据结构的一些成员。

### 4.1. 服务端结构

```c
struct redisServer {
    ...
    list *clients;              /* List of active clients */
    list *clients_to_close;     /* Clients to close asynchronously */
    list *clients_pending_write; /* There is to write or install handler. */
    list *clients_pending_read;  /* Client has pending read socket buffers. */
    ...
}
```

| 成员                  | 描述                                                                                                                                                                                                                                      |
| :-------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| clients               | 客户端链表，客户端新连接会存储在链表里。                                                                                                                                                                                                  |
| clients_to_close      | 客户端关闭链表， 放在 `beforeSleep` 里进行异步关闭。                                                                                                                                                                                      |
| clients_pending_write | 延迟写数据客户端链表，异步操作，数据并不是读出来进行处理后就马上发送的，服务处理完逻辑后会将回复数据写入 client 的写入缓冲区（buf/reply），并记录下当前客户端，在 `beforeSleep` 里进行统一发送。（参考 `clientInstallWriteHandler` 源码） |
| clients_pending_read  | 延迟读数据客户端链表，异步读数据，服务开启多线程处理读数据处理方式才会用到。（参考 `postponeClientRead` 源码）                                                                                                                            |

---

### 4.2. 客户端结构

当客户端连接 redis 服务，redis 服务用 `client` 结构保存了客户端通信的相关信息。

```c
// server.h
typedef struct client {
    uint64_t id;            /* Client incremental unique ID. */
    connection *conn;
    ...
    sds querybuf;           /* Buffer we use to accumulate client queries. */
    size_t qb_pos;          /* The position we have read in querybuf. */
    int argc;               /* Num of arguments of current command. */
    robj **argv;            /* Arguments of current command. */
    struct redisCommand *cmd, *lastcmd;  /* Last command executed. */
    list *reply;            /* List of reply objects to send to the client. */
    unsigned long long reply_bytes; /* Tot bytes of objects in reply list. */
    ...
    /* Response buffer */
    int bufpos;
    char buf[PROTO_REPLY_CHUNK_BYTES];
    ...
}
```

| 成员        | 描述                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| :---------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| id          | redis 服务分配的递增 id。（参考 `createClient` 源码）                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| conn        | 客户端链接对象，封装了网络相关操作：读写数据，事件驱动接口调用，网络事件回调逻辑等。                                                                                                                                                                                                                                                                                                                                                                                                           |
| querybuf    | 读缓存，服务读取客户端发送的数据然后写入 client.querybuf 缓存。                                                                                                                                                                                                                                                                                                                                                                                                                                |
| qb_pos      | 读缓存处理位置，客户端发送给服务的可能是命令，redis 服务读取数据后，需要进行逻辑处理，因为是非阻塞操作，并不是每次 read 都能把客户端发送的数据全部读取出来，也有可能因为 tcp 通信，遇到粘包问题，很可能客户端连续发了 2 个命令，服务端只 read 出了 1 个半命令，另外一部分下次再 read。这时候服务端可以先处理完一个命令，标记 querybuf 处理的位置 qb_pos，然后对 querybuf 数据所在 qb_pos 位置进行截断，剩下那半个命令，下次读出完整的命令后再进行逻辑处理。 （参考 `processInputBuffer` 源码） |
| argc        | 当前命令参数个数。 redis 有自己的通信协议 RESP，服务读取数据后，需要将 RESP 协议参数解析出来。argc 存放了命令由多少个字符串组成的。                                                                                                                                                                                                                                                                                                                                                            |
| argv        | 当前命令参数数组。参考 argc 解析。例如命令 `set key123 value123`，argc 命令参数个数是 3，argv 字符串数组分别为 ["set","key123","123"]。                                                                                                                                                                                                                                                                                                                                                        |
| cmd         | 当前命令对象指针。redis 解析 RESP 协议数据后，解析出对应的命令参数，那么需要进行 redis 对应命令的逻辑处理，例如 `set` 命令对应 `setCommnad` 命令处理函数。（参考 `struct redisCommand` 源码）                                                                                                                                                                                                                                                                                                  |
| reply       | 回复数据链表，这是一个动态内存结构，一般回复数据比较短( < 16k )的情况下，不会用到它，用 buf 处理就够了，但是数据很多的情况下，那么就要分配动态内存去管理这些数据。每次申请一个连续内存的数据块，进行存储，用完了，再申请一个新的数据块，然后这些数据块通过链表顺序串联起来管理。（参考 `_addReplyProtoToList` 源码）                                                                                                                                                                           |
| reply_bytes | reply 链表上的回复数据占用内存总和。                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| bufpos      | buf 回复缓存数据位置，记录 buf 的数据长度。（ 参考 `_addReplyToBuffer` 源码）                                                                                                                                                                                                                                                                                                                                                                                                                  |
| buf         | 回复数据缓存，一般回复数据长度小于 16k 会保存在 buf。（`#define PROTO_REPLY_CHUNK_BYTES (16*1024)`），回复数据 16k 以内的使用频率比较高。buf 和 reply 分开处理，比较高效。                                                                                                                                                                                                                                                                                                                     |

---

## 5. 参考

* redis 6.0 源码
* [[redis 源码走读] 事件 - 文件事件](https://wenfh2020.com/2020/04/09/redis-ae-file/)
* [epoll 多路复用 I/O工作流程](https://wenfh2020.com/2020/04/14/epoll-workflow/)
* [[redis 源码走读] 事件 - 定时器](https://wenfh2020.com/2020/04/06/ae-timer/)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/2020/04/30/redis-async-communication/)
