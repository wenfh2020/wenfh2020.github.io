---
layout: post
title:  "[Redis] Redis 并发模型"
categories: redis
author: wenfh2020
---

很多朋友以为 Redis 是单线程程序，事实上它是 `多进程 + 多线程` 混合并发模型。

* 子进程持久化：重写 aof 文件 / 保存 rdb 文件。
* 多线程：主线程 + 后台惰性处理线程 + IO 额外线程（Redis 6.0）。



---



* content
{:toc}

---

## 1. 并发模型

Redis 使用了 多进程 + 多线程混合并发模型。

* 子进程持久化：重写 aof 文件 / 保存 rdb 文件。
* 多线程：主线程 + 后台惰性处理线程 + IO 额外线程（Redis 6.0）。

---

## 2. 多进程

子进程持久化：重写 aof 文件 / 保存 rdb 文件。

多进程优点：

1. 简单性：多进程模型相比于多线程模型在编程上更为简单。在多线程模型中，线程间的共享状态会导致复杂的同步问题，而在多进程模型中，进程间的状态是隔离的，这大大简化了编程的复杂性。

2. 内存复制：当Redis进行fork操作时，操作系统会创建一个与父进程拥有完全相同内存的子进程。这个过程中，操作系统使用了写时复制（Copy-On-Write，COW）技术，只有当数据被修改时，才会复制一份数据，这样可以节省大量的内存空间。

3. 稳定性：如果持久化过程中出现问题，使用子进程可以保证主进程的稳定性。因为子进程是主进程的完全复制品，所以即使子进程崩溃，也不会影响到主进程的运行。

4. 高效的磁盘I/O：Redis的持久化操作主要是磁盘I/O操作，而磁盘I/O操作在多线程环境下并不能得到有效的提升，反而可能因为线程切换带来额外的开销。而多进程模型可以更好地利用多核CPU，提高磁盘I/O的效率。

> 部分文字来源：ChatGPT

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

从 Redis 调试代码中，我们可以看到，Reids 线程主要分为 3 类：

1. 主线程：负责程序的主逻辑，当然也负责 IO。
2. 后台线程：延时回收耗时的系统资源。
3. IO 线程：Redis 6.0 版本增加的额外 IO 线程，主要为了减轻主线程的工作量，利用多核资源实现 IO 并发处理。

```c
// debug.c
void killThreads(void) {
    killMainThread();
    bioKillThreads();
    killIOThreads();
}
```

> 从上面 Redis 内部代码可以看出线程的类型。

---

### 3.1. 惰性后台线程

后台线程个数为 3 个（BIO_NUM_OPS），通过消息队列实现多线程的生产者和消费者工作方式，主线程生产，后台线程消费。

它主要执行三种类型操作：

1. 关闭文件。例如打开了 aof 和 rdb 这种大型的持久化文件，需要关闭。
2. aof 文件刷盘。aof 持久化方式，主线程定时将新增内容追加到 aof 文件，只将数据写入内核缓存，并没有执行将其刷入磁盘，这种阻塞耗时的脏活累活需要后台线程去做。
3. 释放量大的数据。key-value 数据结构，主线程将 key 和 value 解除关系，value 很小的话，主线程实时释放，如果 value 很大，那么需要后台线程惰性释放，减轻主线程的工作量。

```c
// bio.c

/* Background job opcodes */
#define BIO_CLOSE_FILE    0 /* Deferred close(2) syscall. */
#define BIO_AOF_FSYNC     1 /* Deferred AOF fsync. */
#define BIO_LAZY_FREE     2 /* Deferred objects freeing. */
#define BIO_NUM_OPS       3

void *bioProcessBackgroundJobs(void *arg) {
    bio_job *job;
    unsigned long type = (unsigned long) arg;
    ...
    while(1) {
        listNode *ln;

        /* The loop always starts with the lock hold. */
        if (listLength(bio_jobs[type]) == 0) {
            pthread_cond_wait(&bio_newjob_cond[type], &bio_mutex[type]);
            continue;
        }
        /* Pop the job from the queue. */
        ln = listFirst(bio_jobs[type]);
        job = ln->value;
        /* It is now possible to 
         * unlock the background system as we know have
         * a stand alone job structure to process.*/
        pthread_mutex_unlock(&bio_mutex[type]);

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

### 3.2. IO 读写线程

#### 3.2.1. 配置

io-threads 线程配置，redis.conf 配置文件默认是不开放的，默认只有一个线程在工作，这个线程就是 `主线程`。

如果开放多线程配置，`io-threads 4` 那么 IO 处理线程共有 4 个，包括主线程。也就是额外创建的 IO 线程有 3 个。

> IO 额外线程默认不开放 `读` 操作，因为 Redis 作为缓存服务，一般读入数据是非常小的，写出数据非常大。

```shell
# redis.conf

# 配置多线程处理线程个数，默认 4。
# io-threads 4
#
# 多线程是否处理读事件，默认关闭。
# io-threads-do-reads no
```

---

#### 3.2.2. 必要性

额外的 IO 线程有存在的必要吗？

有！且不说普通的读数据，下面的一主多从框架，A 图的 master 与 slaves 断开一段时间，重连后 slaves 需要向 master 全量同步数据。4 个 slaves 节点同时要求传输整个 rdb 持久化文件，master 的写 IO 压力山大！！

当然您的框架可以设置为 B 模型。但是 master 如果还是主线程负责 IO，既当爸又当妈的压力，只有当事进程才知道~~~

<div align=center><img src="/images/2023/2023-09-20-15-33-50.png" data-action="zoom"/></div>

---

#### 3.2.3. 实现

```shell

```

---

## 4. 优化

1. 处理器个数。避免线程频繁切换，增加线程了线程切换的开销，而且主线程获得的时间片将会减少！
2. 处理器亲和性设置。经过大佬的压测，发现整体性能可以提升 15%。[Redis 如何绑定 CPU](https://www.yisu.com/zixun/672271.html)

---

## 5. 参考
