---
layout: post
title:  "[Redis] 浅析 Redis 并发模型"
categories: redis
author: wenfh2020
---

很多朋友以为 Redis 是单线程程序，事实上它是 `多进程 + 多线程` 混合并发模型。

* 子进程持久化：重写 aof 文件 / 保存 rdb 文件。
* 多线程：主线程 + 后台线程 + 新增网络 IO 线程（Redis 6.0）。

> 本文使用的 Redis 版本：[6.0.20](https://codeload.github.com/redis/redis/tar.gz/refs/tags/6.0.20)。

---



* content
{:toc}

---

## 1. 并发模型

Redis 使用了 多进程 + 多线程混合并发模型。

* 子进程持久化：重写 aof 文件 / 保存 rdb 文件。
* 多线程：主线程 + 后台线程 + 新增网络 IO 线程。

<div align=center><img src="/images/2023/2023-12-28-08-47-16.png" data-action="zoom"></div>

---

## 2. 多进程

子进程持久化：重写 aof 文件 / 保存 rdb 文件。

为了性能和安全，一般情况下，Redis 同一时刻只允许创建一个子进程在工作。

* bgsave 命令，保存 rdb 文件。

```c
// rdb.c
int rdbSaveBackground(int req, char *filename, rdbSaveInfo *rsi, int rdbflags) {
    pid_t childpid;
    ...
    if ((childpid = redisFork(CHILD_TYPE_RDB)) == 0) {
        ...
    }
}
```

* master 通过 rdb 文件，全量同步数据到 slave。

```c
// rdb.c
int rdbSaveToSlavesSockets(int req, rdbSaveInfo *rsi) {
    pid_t childpid;
    ...
    if ((childpid = redisFork(CHILD_TYPE_RDB)) == 0) {
        ...
    }
    ...
}
```

* 重写 aof 文件部分内容为 rdb 数据。

```c
// aof.c
int rewriteAppendOnlyFileBackground(void) {
    pid_t childpid;
    ...
    if ((childpid = redisFork(CHILD_TYPE_AOF)) == 0) {
        ...
    }
    ...
}
```

---

## 3. 多线程

从 Redis 调试代码中，我们可以看到，Redis 线程主要分为 3 类：

1. 主线程：负责程序的主逻辑，当然也负责 IO。
2. 后台线程：延时回收耗时的系统资源。
3. 网络 IO 线程：Redis 6.0 版本增加的 IO 线程，利用多核资源，实现 IO 并发。

```c
// debug.c
void killThreads(void) {
    killMainThread();
    bioKillThreads();
    killIOThreads();
}
```

---

### 3.1. 后台线程

后台线程个数为 3 个（BIO_NUM_OPS），通过消息队列实现多线程的生产者和消费者工作方式 ——主线程生产，后台线程消费。

它主要执行三种类型操作：

1. 关闭文件。例如打开了 aof 和 rdb 这种大型的持久化文件，需要关闭。
2. aof 文件刷盘。aof 持久化方式，主线程定时将新增内容追加到 aof 文件，只将数据写入内核缓存，并没有将其刷入磁盘，这种阻塞耗时的脏活累活需要后台线程去做。
3. 释放体量大的数据。key-value 数据结构，主线程将 key 和 value 解除关系后，如果 value 很小的话，主线程实时释放，否则需要后台线程惰性释放。

```c
// bio.c

/* Background job opcodes */
#define BIO_CLOSE_FILE    0 /* Deferred close(2) syscall. */
#define BIO_AOF_FSYNC     1 /* Deferred AOF fsync. */
#define BIO_LAZY_FREE     2 /* Deferred objects freeing. */
#define BIO_NUM_OPS       3

void *bioProcessBackgroundJobs(void *arg) {
    ...
    while(1) {
        ...
        /* Process the job accordingly to its type. */
        if (type == BIO_CLOSE_FILE) {
            if (job->fd_args.need_fsync) {
                redis_fsync(job->fd_args.fd);
            }
            ...
            close(job->fd_args.fd);
        } else if (type == BIO_AOF_FSYNC) {
            /* The fd may be closed by main thread and reused for another
             * socket, pipe, or file. We just ignore these errno because
             * aof fsync did not really fail. */
            if (redis_fsync(job->fd_args.fd) == -1 &&
                errno != EBADF && errno != EINVAL) {
                ...
            } 
        } else if (type == BIO_LAZY_FREE) {
            job->free_args.free_fn(job->free_args.free_args);
        }
        ...
    }
    ...
}
```

---

### 3.2. 网络 IO 线程

开启网络 IO 线程并发，是为了利用多核资源，提高程序整体性能，并减轻主线程的负载。

---

#### 3.2.1. 主线程异步网络 IO

下图描述了 Redis 客户端与服务端主线程异步通信流程，有兴趣的朋友可以参考：[《[redis 源码走读] 异步通信流程-单线程》](https://wenfh2020.com/2020/04/30/redis-async-communication/)，这里不详细展开了。

<div align=center><img src="/images/2020/2020-05-04-01-19-51.png" data-action="zoom"></div>

---

#### 3.2.2. 多线程配置

io-threads 线程配置，redis.conf 配置文件默认是不开放的，默认只有一个线程在工作，这个线程就是 `主线程`。

如果开放多线程配置，`io-threads 4` 那么 IO 处理线程默认共有 4 个，包括主线程。也就是说，新增的 IO 线程有 3 个。

> IO 线程默认不开放 `读` 操作，因为 Redis 作为数据缓存服务，一般它读入数据量是非常小的，写出数据量却非常大。

```shell
# redis.conf

# 配置多线程处理线程个数，默认 4。
# io-threads 4
#
# 多线程是否处理读事件，默认关闭。
# io-threads-do-reads no
```

---

#### 3.2.3. 实现

##### 3.2.3.1. 配置

如果 redis.conf 文件开启 io-threads 配置项，那么从配置中读取线程个数，否则网络 IO 线程默认为 1，只有主线程。

```c
// config.c
standardConfig static_configs[] = {
    ...
    /* Single threaded by default */
    createIntConfig("io-threads", NULL, \
        DEBUG_CONFIG | IMMUTABLE_CONFIG, 1, 128, \
        server.io_threads_num, 1, INTEGER_CONFIG, NULL, NULL),
    ...
}
```

---

##### 3.2.3.2. 主逻辑

* 如果没开启多线程，那么 Redis 只会使用主线程处理网络 IO，主线程单线程处理网络 IO 是串行的。
* 为了保证主逻辑处理方式整体不变，多线程 IO 工作方式，不允许同时并发读写操作，同一时刻只允许读或只允许写。
* 如果开启了多线程，而且等待处理的 client 数量很少，新增的网络 IO 线程会被挂起，仍然使用主线程工作；否则启用多线程工作，将等待的 clients，平均分配给多个线程（主线程+新增线程）并行处理。
* 任务分配完以后，主线程将处理自己的任务，并等待新增线程都处理完任务后，才会执行下一个步骤的其它操作，这样做的目的是为了保证整体逻辑串行；不因为引入多线程处理方式改变了原来的主逻辑，尽力将多线程并行逻辑的影响减少到最小。

<div align=center><img src="/images/2023/2023-12-26-16-01-34.png" data-action="zoom"></div>

```shell
# 主线程。
|-- main
  |-- aeMain
    |-- aeProcessEvents
      |-- beforeSleep
        # 多线程读 IO（与多线程写 IO 实现方式类似）。
        |-- handleClientsWithPendingReadsUsingThreads
        # 多线程写 IO。
        |-- handleClientsWithPendingWritesUsingThreads
          # 如果配置没开启多线程，使用主线程处理。
          # 如果开启了多线程，但等待传输数据的 client 数量很少，
          # 挂起开启的新线程，使用主线程处理。
          |-- if (server.io_threads_num == 1 || stopThreadedIOIfNeeded())
            # 主线程写 IO。
            |-- handleClientsWithPendingWrites
          # 如果已开启多线程，并且等待处理的 clients 很多，采用多线程写 IO。
          |-- if (!server.io_threads_active) startThreadedIO();
>>>>>>>>> |-- # 多线程写 IO 逻辑，
              # 将等待发送数据的 clients 平均分配给 n 个线程分别处理。
              # 主线程处理自己的任务。
          |-- while(...) { writeToClient(c,0); }
      # 事件驱动获取就绪的读写事件。
      |-- aeApiPoll
      |-- afterSleep
        # 多线程读 IO。
        |-- handleClientsWithPendingReadsUsingThreads
      # 处理从事件驱动获取的读写事件。
      |-- fe->rfileProc
      |-- fe->wfileProc

>>>>>>>>>
# 新增 IO 线程处理函数。
|-- IOThreadMain
  |-- if (io_threads_op == IO_THREADS_OP_WRITE)
    |-- writeToClient(c,0);
  |-- else if (io_threads_op == IO_THREADS_OP_READ)
    |-- readQueryFromClient(c->conn);
```

---

## 4. 优化

### 4.1. 线程个数

默认开启多线程 IO 方式：

线程个数：主线程 + 3 个后台线程 + 3 个 IO 线程 = 7 个线程。

进程个数：主进程 + 1 个子进程 = 2 进程。

> 当然可以根据实际需要设置 IO 线程个数。

`默认` 开启多线程 IO 后，经过统计线程共有 7 个，子进程有 1 个。理论上 CPU 的核心最少得 8 个, Redis 跑起来才能发挥最佳性能。

要避免 CPU 核心太少，或者线程太多，导致线程调度频繁切换，性能开销增加，每个线程获得的时间片减少！

---

### 4.2. 压测

开启默认 IO 多线程，经过压测（参考下图），有 4 个 IO 线程正在运行（<font color=green>R</font>），符合预期。

上面线程个数统计，Redis 应该有 7 个线程在运行，压测发现 Redis 启动了 9 个线程？！原来 Redis 默认使用自带的第三方内存库：`jemalloc`，它也创建了 2 线程。

所以 CPU 的核心多配几个是没错的。

* 压测数据。

<div align=center><img src="/images/2023/2023-12-27-11-44-38.png" data-action="zoom"></div>

* 线程调试。

<div align=center><img src="/images/2023/2023-12-27-11-46-08.png" data-action="zoom"></div>

---

### 4.3. 处理器亲和性

Redis 6.0 引入 IO 多线程后，增加了处理器亲和性的设置功能。

进程/线程绑定指定的处理器（亲和性）优点：

1. 提高 CPU 高速缓存命中率。
2. 保证 CPU 高速缓存数据一致性。

经过某大佬压测，发现开启 CPU 亲缘性设置，Redis QPS 可以提升 15%（参考：[Redis 如何绑定 CPU](https://www.yisu.com/zixun/672271.html)）。

* 配置。

```shell
# Set redis server/io threads to cpu affinity 0,2,4,6:
# server_cpulist 0-7:2
#
# Set bio threads to cpu affinity 1,3:
# bio_cpulist 1,3
#
# Set aof rewrite child process to cpu affinity 8,9,10,11:
# aof_rewrite_cpulist 8-11
#
# Set bgsave child process to cpu affinity 1,10,11
# bgsave_cpulist 1,10-11
```

* CPU 亲和性设置代码。

```c
// setcpuaffinity.c
void setcpuaffinity(const char *cpulist) {
    ...
#ifdef __linux__
    cpu_set_t cpuset;
#endif
    ...
#ifdef __linux__
    sched_setaffinity(0, sizeof(cpuset), &cpuset);
#endif
    ...
}

// server.c
void redisSetCpuAffinity(const char *cpulist) {
#ifdef USE_SETCPUAFFINITY
    setcpuaffinity(cpulist);
#else
    UNUSED(cpulist);
#endif
}
```

* 亲和性应用场景。

```c
// 主线程。
int main(int argc, char **argv) { ... }

// IO 线程。
void *IOThreadMain(void *myid) { ... }

// 后台线程。
void *bioProcessBackgroundJobs(void *arg) { ... }

// 子进程。
int rdbSaveBackground(
    int req, char *filename, 
    rdbSaveInfo *rsi, int rdbflags) { ... }
int rewriteAppendOnlyFileBackground(void) { ... }
int rdbSaveToSlavesSockets(int req, rdbSaveInfo *rsi) { ... }
```

---

## 5. 参考

* [Redis 如何绑定 CPU](https://www.yisu.com/zixun/672271.html)
