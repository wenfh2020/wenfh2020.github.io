---
layout: post
title:  "[redis 源码走读] 多线程通信 I/O"
categories: redis
tags: reids mutithreading I/O
author: wenfh2020
---

本章重点走读 redis 网络 I/O 的**多线程**部分源码。

`key - value` 哈希表 + 内存数据库 + 非阻塞系统调用 + 多路复用 I/O 事件驱动，使得 redis 单线程处理主逻辑足够高效。当并发上来后，数据的逻辑处理肯定要占用大量时间，那样，客户端与服务端通信处理就会变得迟钝。所以在合适的时候（根据任务量自适应）采用多线程处理，充分地利用多核优势，分担主线程压力，使得客户端和服务端通信更加敏捷。

---

redis 6.0 新增多线程处理网络 I/O，默认是关闭的，需要修改配置开启。对于这个新特性，redis 作者建议：如果项目确实遇到性能问题，再开启多线程处理网络读写事件。否则开启没什么意义，还会浪费 CPU 资源。线程数量不要超过 cpu 核心数量 - 1，预留一个核心。



* content
{:toc}

---

## 1. 配置

多线程这两个设置项，默认是关闭的。

```shell
# redis.conf

# 配置多线程处理线程个数，数量最好少于 cpu 核心，默认 4。
# io-threads 4
#
# 多线程是否处理读事件，默认关闭。
# io-threads-do-reads no
```

redis 作者建议：

* 配置线程数量，最好少于 cpu 核心。起码预留一个空闲核心处理系统其它业务，线程数量超过 cpu 核心对 redis 性能有一定影响，因为 redis 主线程处理主逻辑，如果被系统频繁切换，效率会降低。
* 提供了多线程处理网络读事件开关。多线程处理网络读事件，对 redis 性能影响不大。redis 作为缓存，查询操作的频率比较大，系统的网络瓶颈一般在查询返回数据，根据系统实际应用场景进行配置吧。

---

## 2. 主线程工作流程

![redis 多线程I/O通信流程](/images/2020-04-20-07-25-44.png){: data-action="zoom"}{: data-action="zoom"}

1. 主线程通过事件驱动从内核获取就绪事件，记录下需要延时操作的客户端连接。
2. 多线程并行处理延时读事件。
3. 多线程处理延时写事件。
4. 重新执行第一步，循环执行。

---

* 加载循环事件管理。

```c
int main(int argc, char **argv) {
    ...
    server.el = aeCreateEventLoop(server.maxclients+CONFIG_FDSET_INCR);
    ...
    aeSetBeforeSleepProc(server.el,beforeSleep);
    aeSetAfterSleepProc(server.el,afterSleep);
    aeMain(server.el);
    aeDeleteEventLoop(server.el);
    return 0;
}
```

* 事件循环管理。

```c
void aeMain(aeEventLoop *eventLoop) {
    eventLoop->stop = 0;
    while (!eventLoop->stop) {
        if (eventLoop->beforesleep != NULL)
            eventLoop->beforesleep(eventLoop);
        // 向内核获取就绪的可读可写事件事件进行处理，处理时钟事件。
        aeProcessEvents(eventLoop, AE_ALL_EVENTS|AE_CALL_AFTER_SLEEP);
    }
}
```

* 获取就绪事件处理和处理时钟事件。

```c
int aeProcessEvents(aeEventLoop *eventLoop, int flags) {
    ...
    // 从内核中取出就绪的可读可写事件。
    numevents = aeApiPoll(eventLoop, tvp);

    if (eventLoop->aftersleep != NULL && flags & AE_CALL_AFTER_SLEEP)
        eventLoop->aftersleep(eventLoop);

    for (j = 0; j < numevents; j++) {
        // 处理读写事件。
    }
    ...
    // 处理时钟事件。
    if (flags & AE_TIME_EVENTS)
        processed += processTimeEvents(eventLoop);
    ...
}
```

* 读写逻辑处理。

```c
void beforeSleep(struct aeEventLoop *eventLoop) {
    ...
    // write
    handleClientsWithPendingWritesUsingThreads();
    ...
}

void afterSleep(struct aeEventLoop *eventLoop) {
    ...
    // read
    handleClientsWithPendingReadsUsingThreads();
}
```

---

## 3. 多线程协作

![redis 多线程I/O通信流程](/images/2020-04-20-07-25-44.png){: data-action="zoom"}{: data-action="zoom"}

### 3.1. 特点

主线程实现主逻辑，子线程辅助实现任务。

* redis 主线程实现主逻辑。
* 主线程与子线程共同处理延时客户端网络读写事件。
* 主线程根据写事件用户量大小，开启/关闭多线程模式。
* 虽然多线程是并行处理逻辑，但是 redis 整体工作流程是串行的。
* 当主线程处理延时读写事件时，把一次大任务进行取模切割成小任务，平均分配给（主+子）线程处理。这样每个客户端连接被独立的一个线程处理，不会出现多个线程同时处理一个客户端连接逻辑。
* 主线程限制多线程子线程同一个时间段只能并行处理一种类型操作：读/写。
* 主线程先等待子线程处理完任务了，再进行下一步，处理分配给自己的等待事件。
* 主线程在等待子线程处理任务过程中，它不是通过 `sleep` 挂起线程让出使用权，而是通过 `for` 循环进行忙等，不断检测所有子线程处理的任务是否已经完成，如果完成再进行下一步，处理自己的任务。相当于主线程在等待过程中，并没有做其它任务，只是让帮手去干活，帮手都把活干完了，它再干自己的，然后做一些善后工作。主线程在这里的角色有点像代理商或者包工头。
* 子线程在完成分配的任务后，也会通过 `for` 循环忙等，检测主线程的工作调度，如果任务很少了，等待主线程通过锁，把自己挂起。

---

### 3.2. 忙等

多线程模式，存在忙等现象，这个处理有点超出了常规思维。

---

#### 3.2.1. 源码实现

* 主线程分配完任务后，等待所有子线程完成任务后，再进行下一步操作。

```c
// write
int handleClientsWithPendingWritesUsingThreads(void) {
    ...
    while(1) {
        unsigned long pending = 0;
        for (int j = 1; j < server.io_threads_num; j++)
            pending += io_threads_pending[j];
        if (pending == 0) break;
    }
    ...
}

// read
int handleClientsWithPendingReadsUsingThreads(void) {
    ...
    while(1) {
        unsigned long pending = 0;
        for (int j = 1; j < server.io_threads_num; j++)
            pending += io_threads_pending[j];
        if (pending == 0) break;
    }
    ...
}
```

* 子线程完成任务后，保持繁忙状态，等待主线程上锁挂起自己。

```c
void *IOThreadMain(void *myid) {
    ...
    while(1) {
        for (int j = 0; j < 1000000; j++) {
            if (io_threads_pending[id] != 0) break;
        }

        if (io_threads_pending[id] == 0) {
            pthread_mutex_lock(&io_threads_mutex[id]);
            pthread_mutex_unlock(&io_threads_mutex[id]);
            continue;
        }
        ...
    }
}
```

---

#### 3.2.2. 优缺点

* 优点：

  1. 实现简单，主线程可以通过锁开启/暂停多线程工作模式，不需要复杂的通信。
  2. redis 读写事件处理基本都是内存级别操作，而且非阻塞，多线程处理任务非常快。
  3. 反应快，有任务能实时处理。
  4. 宏观上看，主线程是串行处理逻辑，逻辑清晰：读写逻辑顺序处理。主线程把一次大任务进行取模切割成小任务，分配给子线程处理。主线程等子线程完成所有任务后，再完成自己的任务，再进行下一步。
  5. 因为多线程处理的是客户端链接的延时读写逻辑，redis 服务应用场景作为缓存，接入对象一般是服务端级别，而不是面向普通用户的客户端，所以链接不会太多。而等待的读写链接通过取模分散到不同的线程去处理，那每个线程处理的链接就会相对较少。每个线程处理任务也很快。

* 缺点：
  
  忙等最大的问题是以浪费一定 cpu 性能为代价，如果 redis 链接并发量不是很高，redis 作者不建议开启多线程模式，所以主逻辑会根据写事件链接数量大小来开启/暂停多线程工作模式。

```c
int stopThreadedIOIfNeeded(void) {
    int pending = listLength(server.clients_pending_write);

    // 如果单线程模式就直接返回。
    if (server.io_threads_num == 1) return 1;

    if (pending < (server.io_threads_num*2)) {
        if (io_threads_active) stopThreadedIO();
        return 1;
    } else {
        return 0;
    }
}
```

---

### 3.3. 源码分析

#### 3.3.1. 概述

* 网络读写核心接口：

    | 接口                | 描述                 |
    | :------------------ | :------------------- |
    | readQueryFromClient | 服务读客户端数据。   |
    | writeToClient       | 服务向客户端写数据。 |

* 多线程工作模式核心接口(`networking.c`)，其它延时处理逻辑也有一部分源码。

    | 接口                                       | 描述                                       |
    | :----------------------------------------- | :----------------------------------------- |
    | IOThreadMain                               | 子线程处理逻辑。                           |
    | initThreadedIO                             | 主线程创建挂起子线程。                     |
    | startThreadedIO                            | 主线程开启多线程工作模式。                 |
    | stopThreadedIO                             | 主线程暂停多线程工作模式。                 |
    | stopThreadedIOIfNeeded                     | 主线程根据写并发量是否关闭多线程工作模式。 |
    | handleClientsWithPendingWritesUsingThreads | 主线程多线程处理延时写事件。               |
    | handleClientsWithPendingReadsUsingThreads  | 主线程多线程处理延时读事件。               |

* 其它延时处理逻辑，看看下面这些变量和宏在代码中的逻辑，这里不会详细展开。

    | 变量/宏                      | 描述                             |
    | :--------------------------- | :------------------------------- |
    | server.clients_pending_read  | 延时处理读事件的客户端连接链表。 |
    | server.clients_pending_write | 延时处理写事件的客户端连接链表。 |
    | CLIENT_PENDING_READ          | 延时处理读事件标识。             |
    | CLIENT_PENDING_WRITE         | 延时处理写事件标识。             |
    | CLIENT_PENDING_COMMAND       | 延时处理命令逻辑标识。           |

---

#### 3.3.2. 源码

* 变量/宏
  
  `io_threads_mutex` 互斥变量数组，为了方便主线程唤醒/挂起控制子线程。
  `io_threads_pending` 原子变量，方便主线程统计子线程是否已经处理完所有任务。

```c
// 最大线程个数。
#define IO_THREADS_MAX_NUM 128

// 线程读操作。
#define IO_THREADS_OP_READ 0

// 线程写操作。
#define IO_THREADS_OP_WRITE 1

// 线程数组。
pthread_t io_threads[IO_THREADS_MAX_NUM];

// 互斥变量数组，提供主线程上锁和解锁子线程工作。
pthread_mutex_t io_threads_mutex[IO_THREADS_MAX_NUM];

// 原子变量数组，分别存储每个线程要处理的延时处理链接数量。主线程用来统计线程是否处理完等待事件，从而进行下一步操作。
_Atomic unsigned long io_threads_pending[IO_THREADS_MAX_NUM];

// 是否启动了多线程处理模式。
int io_threads_active;

// 线程操作类型。多线程每次只能处理一种类型的操作：读/写。
int io_threads_op;

// 子线程列表，子线程个数为 IO_THREADS_MAX_NUM - 1，因为主线程也会处理延时任务。
list *io_threads_list[IO_THREADS_MAX_NUM];
```

---

* 主线程创建子线程

```c
void initThreadedIO(void) {
    io_threads_active = 0; /* We start with threads not active. */

    if (server.io_threads_num == 1) return;

    // 检查配置的线程数量是否超出限制。
    if (server.io_threads_num > IO_THREADS_MAX_NUM) {
        serverLog(LL_WARNING,"Fatal: too many I/O threads configured. "
                             "The maximum number is %d.", IO_THREADS_MAX_NUM);
        exit(1);
    }

    // 创建 server.io_threads_num - 1 个子线程。
    for (int i = 0; i < server.io_threads_num; i++) {
        io_threads_list[i] = listCreate();

        // 0 号线程不创建，0 号就是主线程，主线程也会处理任务逻辑。
        if (i == 0) continue;

        // 创建子线程，主线程先对子线程上锁，挂起子线程，不让子线程进入工作模式。
        pthread_t tid;
        pthread_mutex_init(&io_threads_mutex[i],NULL);
        io_threads_pending[i] = 0;
        pthread_mutex_lock(&io_threads_mutex[i]);
        if (pthread_create(&tid,NULL,IOThreadMain,(void*)(long)i) != 0) {
            serverLog(LL_WARNING,"Fatal: Can't initialize IO thread.");
            exit(1);
        }
        io_threads[i] = tid;
    }
}
```

* 开启多线程模式

```c
void startThreadedIO(void) {
    serverAssert(io_threads_active == 0);
    for (int j = 1; j < server.io_threads_num; j++)
        // 子线程因为上锁等待主线程解锁，当主线程解锁子线程，子线程重新进入工作状态。
        pthread_mutex_unlock(&io_threads_mutex[j]);
    io_threads_active = 1;
}
```

* 子线程逻辑处理

```c
void *IOThreadMain(void *myid) {
    // 每个线程在创建的时候会产生一个业务 id。
    long id = (unsigned long)myid;

    while(1) {
        // 替代 sleep，用忙等，这样能实时处理业务。但是也付出了耗费 cpu 的代价。
        for (int j = 0; j < 1000000; j++) {
            if (io_threads_pending[id] != 0) break;
        }

        // 留机会给主线程上锁，挂起当前子线程。
        if (io_threads_pending[id] == 0) {
            pthread_mutex_lock(&io_threads_mutex[id]);
            pthread_mutex_unlock(&io_threads_mutex[id]);
            continue;
        }

        serverAssert(io_threads_pending[id] != 0);

        // 根据操作类型，处理对应的读/写逻辑。
        listIter li;
        listNode *ln;
        listRewind(io_threads_list[id],&li);
        while((ln = listNext(&li))) {
            client *c = listNodeValue(ln);
            if (io_threads_op == IO_THREADS_OP_WRITE) {
                writeToClient(c,0);
            } else if (io_threads_op == IO_THREADS_OP_READ) {
                readQueryFromClient(c->conn);
            } else {
                serverPanic("io_threads_op value is unknown");
            }
        }
        listEmpty(io_threads_list[id]);
        io_threads_pending[id] = 0;
    }
}
```

* 是否需要停止多线程模式

```c
int stopThreadedIOIfNeeded(void) {
    int pending = listLength(server.clients_pending_write);

    // 如果单线程模式就直接返回。
    if (server.io_threads_num == 1) return 1;

    if (pending < (server.io_threads_num*2)) {
        if (io_threads_active) stopThreadedIO();
        return 1;
    } else {
        return 0;
    }
}
```

* 暂停多线程处理模式

```c
void stopThreadedIO(void) {
    // 在停止线程前，仍然有等待处理的延时读数据处理，需要先处理再停止线程。
    handleClientsWithPendingReadsUsingThreads();

    serverAssert(io_threads_active == 1);

    // 主给子线程上锁，挂起子线程。
    for (int j = 1; j < server.io_threads_num; j++)
        pthread_mutex_lock(&io_threads_mutex[j]);
    io_threads_active = 0;
}
```

* 处理延时的读事件

```c
int handleClientsWithPendingReadsUsingThreads(void) {
    if (!io_threads_active || !server.io_threads_do_reads) return 0;
    int processed = listLength(server.clients_pending_read);
    if (processed == 0) return 0;

    // 将等待处理的链接，通过取模放进不同的队列中去。
    listIter li;
    listNode *ln;
    listRewind(server.clients_pending_read,&li);
    int item_id = 0;
    while((ln = listNext(&li))) {
        client *c = listNodeValue(ln);
        int target_id = item_id % server.io_threads_num;
        listAddNodeTail(io_threads_list[target_id],c);
        item_id++;
    }

    // 分别统计每个队列要处理链接的个数。
    io_threads_op = IO_THREADS_OP_READ;
    for (int j = 1; j < server.io_threads_num; j++) {
        int count = listLength(io_threads_list[j]);
        io_threads_pending[j] = count;
    }

    // 主线程处理第一个队列。
    listRewind(io_threads_list[0],&li);
    while((ln = listNext(&li))) {
        client *c = listNodeValue(ln);
        // 读客户端发送的数据到缓存。
        readQueryFromClient(c->conn);
    }
    listEmpty(io_threads_list[0]);

    // 主线程处理完任务后，忙等其它线程，全部线程处理完任务后，再处理命令实现逻辑。
    while(1) {
        unsigned long pending = 0;
        for (int j = 1; j < server.io_threads_num; j++)
            pending += io_threads_pending[j];
        if (pending == 0) break;
    }

    /* 主线程处理命令逻辑，因为链接都标识了等待状态，读完数据后命令对应的业务逻辑还没有被处理。
     * 这里去掉等待标识，处理命令业务逻辑。*/
    listRewind(server.clients_pending_read,&li);
    while((ln = listNext(&li))) {
        client *c = listNodeValue(ln);
        c->flags &= ~CLIENT_PENDING_READ;
        if (c->flags & CLIENT_PENDING_COMMAND) {
            c->flags &= ~ CLIENT_PENDING_COMMAND;
            // 读取数据，解析协议取出命令参数，执行命令，填充回复缓冲区。
            processCommandAndResetClient(c);
        }
        // 继续解析协议，取出命令参数，执行命令，填充回复缓冲区。
        processInputBufferAndReplicate(c);
    }
    listEmpty(server.clients_pending_read);
    return processed;
}
```

* 处理延时的写事件

```c
int handleClientsWithPendingWritesUsingThreads(void) {
    int processed = listLength(server.clients_pending_write);
    if (processed == 0) return 0;

    // 如果延时写事件对应的 client 链接很少，关闭多线程模式，用主线程处理异步逻辑。
    if (stopThreadedIOIfNeeded()) {
        // 处理延时写事件。
        return handleClientsWithPendingWrites();
    }

    if (!io_threads_active) startThreadedIO();

    // 将等待处理的链接，通过取模放进不同的队列中去，去掉延迟写标识。
    listIter li;
    listNode *ln;
    listRewind(server.clients_pending_write,&li);
    int item_id = 0;
    while((ln = listNext(&li))) {
        client *c = listNodeValue(ln);
        c->flags &= ~CLIENT_PENDING_WRITE;
        int target_id = item_id % server.io_threads_num;
        listAddNodeTail(io_threads_list[target_id],c);
        item_id++;
    }

    // 线程处理写事件。
    io_threads_op = IO_THREADS_OP_WRITE;

    // 分别统计每个队列要处理链接的个数。
    for (int j = 1; j < server.io_threads_num; j++) {
        int count = listLength(io_threads_list[j]);
        io_threads_pending[j] = count;
    }

    // 主线程处理第一个队列。
    listRewind(io_threads_list[0],&li);
    while((ln = listNext(&li))) {
        client *c = listNodeValue(ln);
        // 写数据，发送给回复给客户端。
        writeToClient(c,0);
    }
    listEmpty(io_threads_list[0]);

    // 主线程处理完任务后，忙等其它线程，全部线程处理完任务后，再处理命令实现逻辑。
    while(1) {
        unsigned long pending = 0;
        for (int j = 1; j < server.io_threads_num; j++)
            pending += io_threads_pending[j];
        if (pending == 0) break;
    }

    listRewind(server.clients_pending_write,&li);
    while((ln = listNext(&li))) {
        client *c = listNodeValue(ln);

        // 如果缓存中还有没有发送完的数据，继续发送或者下次继续发，否则从事件驱动删除 fd 注册的可写事件。
        if (clientHasPendingReplies(c)
            && connSetWriteHandler(c->conn, sendReplyToClient) == AE_ERR) {
            freeClientAsync(c);
        }
    }
    listEmpty(server.clients_pending_write);
    return processed;
}
```

---

## 4. 数据结构

`redisServer` 和 `client` 分别 redis 是服务端和客户端的数据结构，理解结构的成员作用是走读源码逻辑的关键。有兴趣的朋友下个断点跑下逻辑，细节就不详细展开了。

> [用 gdb 调试 redis](https://wenfh2020.com/2020/01/05/redis-gdb/)

* 客户端结构

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

* 服务端结构

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

---

## 5. 测试

8 核心，16G 内存， mac book 本地测试。

redis 服务默认开 4 线程，压测工具开 2 线程。有剩余核心处理机器的其它业务，这样不影响 redis 工作。

> Linux 系统，如果安装不了 redis 最新版本，请升级系统 `gcc` 版本。

* 配置，多线程模式测试，开启读写两个选项；单线程模式测试则会关闭。

```shell
# redis.conf

io-threads 4
io-threads-do-reads yes
```

* 压测命令，会针对客户端链接数/测试包体大小进行测试。
  
> 命令逻辑已整理成脚本，放到 [github](https://github.com/wenfh2020/shell/blob/master/redis/benchmark.sh)，顺手录制了测试视频：[压力测试 redis 多线程处理网络 I/O](https://www.bilibili.com/video/BV1r5411t7QF/)。

```shell
# 压测工具会模拟多个终端，防止超出限制，被停止。
ulimit -n 16384

# 可以设置对应的链接数/包体大小进行测试。
./redis-benchmark -c xxxx -r 1000000 -n 100000 -t set,get -q --threads 2  -d yyyy
```

* 压测结果

在 mac book 上测试，从测试结果看，**多线程没有单线程好**。看到网上很多同学用压测工具测试，性能有很大的提升，有时间用其它机器跑下。可能是机器配置不一样，但是至少一点，这个多线程功能目前还有很大的优化空间，所以新特性，还需要放到真实环境中测试过，才能投产。

![redis 压测过程](/images/2020-04-21-14-19-22.png){: data-action="zoom"}

---

## 6. 总结

* 多线程模式使得网络读写快速处理。
* 多线程模式会浪费一定 cpu，并发量不高不建议开启多线程模式。
* 主线程实现主逻辑，子线程辅助完成任务。
* redis 即便开启多线程模式处理网络读写事件，宏观逻辑还是串行的。
* 实践是检验真理的试金石，压测过程中，单线程比多线程优秀，没有体现出多线程应有的性能提升，其它尚待验证。

---

## 7. 参考

* [用 gdb 调试 redis](https://wenfh2020.com/2020/01/05/redis-gdb/)
* [epoll 多路复用 I/O工作流程](https://wenfh2020.com/2020/04/14/epoll-workflow/)
* [[redis 源码走读] 事件 - 文件事件](https://wenfh2020.com/2020/04/09/redis-ae-file/)
* [[redis 源码走读] 事件 - 定时器](https://wenfh2020.com/2020/04/06/ae-timer/)
* [How fast is Redis?](https://redis.io/topics/benchmarks)
* [redis 压力测试多线程读写脚本](https://github.com/wenfh2020/shell/blob/master/redis/benchmark.sh)
* [压力测试 redis 多线程处理网络 I/O](https://www.bilibili.com/video/BV1r5411t7QF/)
* [yum 更新 gcc 到版本 8](https://blog.csdn.net/wfx15502104112/article/details/96508940)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
