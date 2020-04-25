---
layout: post
title:  "[redis 源码走读] aof 持久化 (上)"
categories: redis
tags: redis aof
author: wenfh2020
---

aof (Append Only File) 是 redis 持久化的其中一种方式。

服务器接收的每个写入操作命令，都会追加记录到 aof 文件末尾，当服务器重新启动时，记录的命令会重新载入到服务器内存还原数据。这一章我们走读一下源码，看看 aof 持久化的数据结构和应用场景是怎样的。

> 主要源码逻辑在 `aof.c` 文件中。



* content
{:toc}

---

在了解 redis 持久化功能前，可以先看看 redis 作者这两篇文章：

* [Redis Persistence](https://redis.io/topics/persistence#how-durable-is-the-append-only-file)
* [Redis persistence demystified](http://oldblog.antirez.com/post/redis-persistence-demystified.html)

> 链接可能被墙，可以用国内搜索引擎搜索下对应的文章题目。

---

## 开启 aof 持久化模式

可以看一下 [redis.conf](https://github.com/antirez/redis/blob/unstable/redis.conf) 有关 aof 持久化配置，有redis 作者丰富的注释内容。

```shell
# 持久化方式 (yes - aof) / (no - rdb)
appendonly yes

# aof 文件名，默认 "appendonly.aof"
appendfilename "appendonly.aof"
```

---

## 结构

### aof 文件结构

![aof 文件结构](/images/2020-03-28-15-38-27.png)

**aof 文件可以由 redis 协议命令组成文本文件**。 第一次启动 redis，执行第一个写命令： `set key1111 1111`。我们观察一下 aof 文件：

* redis 记录了 `select` 数据库命令，`^M` 是 `cat` 命令打印的 `\r\n`。

```shell
# cat -v appendonly.aof
*2^M
$6^M
SELECT^M
$1^M
0^M
*3^M
$3^M
set^M
$7^M
key1111^M
$4^M
1111^M
```

* 命令存储文本。

```shell
# set key1111 1111
*3\r\n$3\r\nset\r\n$7\r\nkey1111$4\r\n$1111\r\n
```

* RESP 协议格式，以 `\r\n` 作为分隔符，有一个作用：可以用 `fgets`，将文件数据一行一行读出来。

```shell
*<命令参数个数>\r\n$<第1个参数字符串长度>\r\n$<第1个参数字符串>\r\n$<第2个参数字符串长度>\r\n$<第2个参数字符串>\r\n$<第n个参数字符串长度>\r\n$<第n个参数字符串>
```

* aof 追加命令记录源码。

```c
sds catAppendOnlyGenericCommand(sds dst, int argc, robj **argv) {
    char buf[32];
    int len, j;
    robj *o;

    // 命令参数个数
    buf[0] = '*';
    len = 1+ll2string(buf+1,sizeof(buf)-1,argc);
    buf[len++] = '\r';
    buf[len++] = '\n';
    dst = sdscatlen(dst,buf,len);

    for (j = 0; j < argc; j++) {
        o = getDecodedObject(argv[j]);
        // 参数字符串长度
        buf[0] = '$';
        len = 1+ll2string(buf+1,sizeof(buf)-1,sdslen(o->ptr));
        buf[len++] = '\r';
        buf[len++] = '\n';
        dst = sdscatlen(dst,buf,len);
        // 参数
        dst = sdscatlen(dst,o->ptr,sdslen(o->ptr));
        dst = sdscatlen(dst,"\r\n",2);
        decrRefCount(o);
    }
    return dst;
}
```

---

### aof 和 rdb 混合结构

![rdb aof 混合结构](/images/2020-03-28-16-19-34.png)

**redis 支持 aof 和 rdb 持久化同时使用**，rdb 和 aof 存储格式同时存储在一个 aof 文件中。

rdb 持久化速度快，而且落地文件小，这个优势理应加强使用。redis 持久化目前有两种方式，最终结合为一种方式，使其更加高效，这是 redis 作者一直努力的目标。

> 有关 rdb 持久化，可以参考帖子：
> 
> [[redis 源码走读] rdb 持久化 - 文件结构](https://wenfh2020.com/2020/03/19/redis-rdb-struct/)
> 
> [[redis 源码走读] rdb 持久化 - 应用场景](https://wenfh2020.com/2020/03/19/redis-rdb-application/)

* 可以通过配置，aof 持久化模式下，内存数据可以重写存储为 rdb 格式的 aof 文件。

```shell
# redis.conf

# 开启 aof 持久化模式
appendonly yes

# [RDB file][AOF tail] 支持 aof 和 rdb 混合持久化。
aof-use-rdb-preamble yes
```

```c
// rdb 持久化时，添加 aof 标识。
int rdbSaveInfoAuxFields(rio *rdb, int rdbflags, rdbSaveInfo *rsi) {
    ...
    if (rdbSaveAuxFieldStrInt(rdb,"aof-preamble",aof_preamble) == -1) return -1;
    ...
}
```

* redis 第一次启动后，执行第二个命令 `bgrewriteaof` 重写 aof 文件。

```shell
# cat -v appendonly.aof
REDIS0009�      redis-ver^K999.999.999�
redis-bits�@�^Ectime�M-^J�}^�^Hused-mem�^Pl^Q^@�^Laof-preamble
�^A�^@�^A^@^@^Gkey1111�W^D��^L�6Afi�
```

* redis 第一次启动后，执行第三个命令 `set key2222 2222`，aof 文件结构展示了 rdb 和 aof 结合存储方式。

```shell
# cat -v appendonly.aof
REDIS0009�      redis-ver^K999.999.999�
redis-bits�@�^Ectime�M-^J�}^�^Hused-mem�^Pl^Q^@�^Laof-preamble
�^A�^@�^A^@^@^Gkey1111�W^D��^L�6Afi�*2^M
$6^M
SELECT^M
$1^M
0^M
*3^M
$3^M
set^M
$7^M
key2222^M
$4^M
2222^M
```

---

## 持久化策略

### 策略

磁盘 I/O 速度慢，redis 作为高性能的缓存数据库，在平衡性能和持久化上，提供了几个存储策略：

> aof 持久化，每秒刷新一次缓存到磁盘，这是 redis aof 持久化默认的操作，兼顾性能和持久化。如果使用场景数据很重要，可以设置每条命令刷新磁盘一次，但是速度会非常慢。如果 redis 只作为缓存，持久化不那么重要，那么刷盘行为交给 Linux 系统管理。

* 每秒将新命令缓存刷新到磁盘。速度足够快，如果 redis 发生异常，您可能会丢失1秒的数据。

```shell
# redis.conf
appendfsync everysec
```

* 每次将新命令刷新到磁盘，非常非常慢，但是非常安全。

```shell
# redis.conf
appendfsync always
```

* redis 不主动刷新文件缓存到磁盘，只需将数据交给操作系统即可。速度更快，但是更不安全。一般情况下，Linux 使用此配置每30秒刷新一次数据。

```shell
# redis.conf
appendfsync no
```

### 流程原理

* 文件数据刷新到磁盘原理：
  
  传统的 UNIX 实现在内核中设有缓冲存储器，⼤多数磁盘 I/O 都通过缓存进⾏。
  
  当将数据写到文件上时，通常该数据先由内核复制到缓存中，如果该缓存尚未写满，则并不将其排入输出队列，⽽是等待其写满或者当内核需要重⽤该缓存以便存放其他磁盘块数据时，再将该缓存排入输出队列，然后待其到达队首时，才进⾏实际的 I/O 操作。这种输出⽅式被称之为延迟写(delayed write)。
  
  延迟写减少了磁盘读写次数，但是却降低了文件内容的更新速度，使得欲写到⽂件中的数据在⼀段时间内并没有写到磁盘上。当系统发⽣生故障时，这种延迟可能造成⽂件更新内容的丢失。为了保证磁盘上实际文件系统与缓存中内容的一致性，UNIX系统提供了 sync 和 fsync 两个系统调⽤函数。
  
  sync 只是将所有修改过的块的缓存排入写队列，然后就返回，它并不等待实际 I/O操作结束。系统精灵进程 (通常称为 update)一般每隔 30秒调⽤一次 sync 函数。这就保证了定期刷新内核的块缓存。
  
  函数fsync 只引⽤单个文件，它等待I/O结束，然后返回。fsync 可用于数据库这样的应用程序，它确保修改过的块⽴即写到磁盘上。
  
  > 上文引用自 《UNINX 环境高级编程》 4.24

![数据持久化流程](/images/2020-03-29-19-12-04.png)

* 文件数据刷新到磁盘流程。

1. client 向 redis 服务发送写命令。
2. redis 服务接收到 client 发送的写命令，存储于 redis 进程内存中（redis 服务缓存）。
3. redis 服务调用接口 write 将进程内存数据写入文件。

    ```c
    void flushAppendOnlyFile(int force) {
        ...
        nwritten = aofWrite(server.aof_fd,server.aof_buf,sdslen(server.aof_buf));
        ...
    }
    ```

4. redis 服务调用接口(`redis_fsync`)，将文件在内核缓冲区的数据刷新到磁盘缓冲区中。

    ```c
    /* Define redis_fsync to fdatasync() in Linux and fsync() for all the rest */
    #ifdef __linux__
    #define redis_fsync fdatasync
    #else
    #define redis_fsync fsync
    #endif
    ```

5. 磁盘控制器将磁盘缓冲区数据写入到磁盘物理介质中。

---

流程走到第 5 步，数据才算真正持久化成功。其中 2-4 步骤，一般情况下，系统会提供对外接口给服务控制，但是第 5 步没有接口，redis 服务控制不了磁盘缓存写入物理介质。一般情况下，进程正常退出或者崩溃退出，第 5 步机器系统会执行的。但是如果断电情况或其他物理异常，这样磁盘数据还是会丢失一部分。

如果用 `appendfsync everysec` 配置，正常情况程序退出可能会丢失 1 - 2 秒数据，但是断电等物理情况导致系统终止，丢失的数据就不可预料了。

> 参考 [Redis persistence demystified](http://oldblog.antirez.com/post/redis-persistence-demystified.html)

---

### 策略实现

```c
#define AOF_WRITE_LOG_ERROR_RATE 30 /* Seconds between errors logging. */

// 刷新缓存到磁盘。
void flushAppendOnlyFile(int force) {
    ssize_t nwritten;
    int sync_in_progress = 0;
    mstime_t latency;

    // 新的命令数据是先写入 aof 缓冲区的，所以先判断缓冲区是否有数据需要刷新到磁盘。
    if (sdslen(server.aof_buf) == 0) {
        /* 每秒刷新策略，有可能存在缓冲区是空的，但是还有数据没刷新磁盘的情况，需要执行刷新操作。
         * 当异步线程还有刷盘任务没有完成，新的刷盘任务是不会执行的，但是 aof_buf 已经写进了
         * 文件缓存，aof_buf 缓存任务已经完成需要清空。只是文件缓存还没刷新到磁盘，数据只在文件缓存
         * 里，还算不上最终落地，需要调用 redis_fsync 才会将文件缓存刷新到磁盘。* aof_fsync_offset 才会最后更新到刷盘的位置*/
        if (server.aof_fsync == AOF_FSYNC_EVERYSEC &&
            server.aof_fsync_offset != server.aof_current_size &&
            server.unixtime > server.aof_last_fsync &&
            !(sync_in_progress = aofFsyncInProgress())) {
            goto try_fsync;
        } else {
            return;
        }
    }

    // 每秒刷新策略，采用的是后台线程刷新方式，检查后台线程是否还有刷新任务没完成。
    if (server.aof_fsync == AOF_FSYNC_EVERYSEC)
        sync_in_progress = aofFsyncInProgress();

    // 部分操作需要 force 强制写入，不接受延时。例如退出 redis 服务。
    if (server.aof_fsync == AOF_FSYNC_EVERYSEC && !force) {
        if (sync_in_progress) {
            if (server.aof_flush_postponed_start == 0) {
                // 如果后台线程还有刷新任务，当前刷新需要延后操作。
                server.aof_flush_postponed_start = server.unixtime;
                return;
            } else if (server.unixtime - server.aof_flush_postponed_start < 2) {
                // 延时操作不能超过 2 秒，否则强制执行。
                return;
            }

            // 延时超时，强制执行。
            server.aof_delayed_fsync++;
            serverLog(LL_NOTICE,"Asynchronous AOF fsync is taking too long (disk is busy?). Writing the AOF buffer without waiting for fsync to complete, this may slow down Redis.");
        }
    }

    ...

    // 写缓冲区数据到文件。
    nwritten = aofWrite(server.aof_fd,server.aof_buf,sdslen(server.aof_buf));
    ...
    /* We performed the write so reset the postponed flush sentinel to zero. */
    server.aof_flush_postponed_start = 0;

    // 处理写文件异常
    if (nwritten != (ssize_t)sdslen(server.aof_buf)) {
        static time_t last_write_error_log = 0;
        int can_log = 0;

        // 设置异常日志打印频率
        if ((server.unixtime - last_write_error_log) > AOF_WRITE_LOG_ERROR_RATE) {
            can_log = 1;
            last_write_error_log = server.unixtime;
        }

        /* Log the AOF write error and record the error code. */
        if (nwritten == -1) {
            if (can_log) {
                serverLog(LL_WARNING,"Error writing to the AOF file: %s",
                    strerror(errno));
                server.aof_last_write_errno = errno;
            }
        } else {
            if (can_log) {
                serverLog(LL_WARNING,"Short write while writing to "
                                       "the AOF file: (nwritten=%lld, "
                                       "expected=%lld)",
                                       (long long)nwritten,
                                       (long long)sdslen(server.aof_buf));
            }

            /* 写入了部分数据，新写入的数据有可能是不完整的命令。这样会导致 redis 启动时，
             * 解析 aof 文件失败，所以需要将文件截断到上一次有效写入的位置。*/
            if (ftruncate(server.aof_fd, server.aof_current_size) == -1) {
                if (can_log) {
                    serverLog(LL_WARNING, "Could not remove short write "
                             "from the append-only file.  Redis may refuse "
                             "to load the AOF the next time it starts.  "
                             "ftruncate: %s", strerror(errno));
                }
            } else {
                /* If the ftruncate() succeeded we can set nwritten to
                 * -1 since there is no longer partial data into the AOF. */
                nwritten = -1;
            }
            server.aof_last_write_errno = ENOSPC;
        }

        // 处理错误
        if (server.aof_fsync == AOF_FSYNC_ALWAYS) {
            // 命令实时更新策略下，如果出现写文件错误，需要关闭服务。
            serverLog(LL_WARNING,"Can't recover from AOF write error when the AOF fsync policy is 'always'. Exiting...");
            exit(1);
        } else {
            /* 其它策略，出现写入错误，更新写入成功部分，没写成功部分则在时钟里定时检查，重新写入。*/
            server.aof_last_write_status = C_ERR;

            if (nwritten > 0) {
                server.aof_current_size += nwritten;
                sdsrange(server.aof_buf,nwritten,-1);
            }
            return; /* We'll try again on the next call... */
        }
    } else {
        // 之前持久化异常，现在已经正常恢复，解除异常标识。
        if (server.aof_last_write_status == C_ERR) {
            serverLog(LL_WARNING,
                "AOF write error looks solved, Redis can write again.");
            server.aof_last_write_status = C_OK;
        }
    }
    server.aof_current_size += nwritten;

    // 持久化成功，清空 aof 缓冲区。
    if ((sdslen(server.aof_buf)+sdsavail(server.aof_buf)) < 4000) {
        sdsclear(server.aof_buf);
    } else {
        sdsfree(server.aof_buf);
        server.aof_buf = sdsempty();
    }

try_fsync:
    // 检查当有子进程在操作时是否允许刷新文件缓存到磁盘。
    if (server.aof_no_fsync_on_rewrite && hasActiveChildProcess())
        return;

    // 刷新文件缓存到磁盘。
    if (server.aof_fsync == AOF_FSYNC_ALWAYS) {
        latencyStartMonitor(latency);
        redis_fsync(server.aof_fd); /* Let's try to get this data on the disk */
        latencyEndMonitor(latency);
        latencyAddSampleIfNeeded("aof-fsync-always",latency);
        server.aof_fsync_offset = server.aof_current_size;
        server.aof_last_fsync = server.unixtime;
    } else if ((server.aof_fsync == AOF_FSYNC_EVERYSEC &&
                server.unixtime > server.aof_last_fsync)) {
        if (!sync_in_progress) {
            // 将刷新文件缓存到磁盘操作添加到异步线程处理。
            aof_background_fsync(server.aof_fd);
            server.aof_fsync_offset = server.aof_current_size;
        }
        server.aof_last_fsync = server.unixtime;
    }
}
```

---

## 异步持久化

redis 作为高性能缓存系统，它的主逻辑都在主进程主线程中实现运行的。而持久化写磁盘是一个低效缓慢操作，因此redis 一般情况下不允许这个操作在主线程中运行。这样 redis 开启了后台线程，用来异步处理任务，保障主线程可以高速运行。

* 添加异步任务

```c
/* Define redis_fsync to fdatasync() in Linux and fsync() for all the rest */
#ifdef __linux__
#define redis_fsync fdatasync
#else
#define redis_fsync fsync
#endif

void flushAppendOnlyFile(int force) {
    ...
    else if ((server.aof_fsync == AOF_FSYNC_EVERYSEC &&
                server.unixtime > server.aof_last_fsync)) {
        // 每秒刷新缓存到磁盘一次。
        if (!sync_in_progress) {
            // 添加任务到后台线程。
            aof_background_fsync(server.aof_fd);
            server.aof_fsync_offset = server.aof_current_size;
        }
        server.aof_last_fsync = server.unixtime;
    }
    ...
}

// 添加异步任务
void aof_background_fsync(int fd) {
    bioCreateBackgroundJob(BIO_AOF_FSYNC,(void*)(long)fd,NULL,NULL);
}
```

* 异步线程刷新缓存到磁盘。

```c
// 后台异步线程创建
void bioInit(void) {
    ...
    for (j = 0; j < BIO_NUM_OPS; j++) {
        void *arg = (void*)(unsigned long) j;
        // 创建线程
        if (pthread_create(&thread,&attr,bioProcessBackgroundJobs,arg) != 0) {
            serverLog(LL_WARNING,"Fatal: Can't initialize Background Jobs.");
            exit(1);
        }
        bio_threads[j] = thread;
    }
}

// 添加异步任务
void bioCreateBackgroundJob(int type, void *arg1, void *arg2, void *arg3) {
    struct bio_job *job = zmalloc(sizeof(*job));

    job->time = time(NULL);
    job->arg1 = arg1;
    job->arg2 = arg2;
    job->arg3 = arg3;
    pthread_mutex_lock(&bio_mutex[type]);
    listAddNodeTail(bio_jobs[type],job);
    bio_pending[type]++;
    pthread_cond_signal(&bio_newjob_cond[type]);
    pthread_mutex_unlock(&bio_mutex[type]);
}

// 线程处理
void *bioProcessBackgroundJobs(void *arg) {
    ...
    else if (type == BIO_AOF_FSYNC) {
        // 刷新内核缓存到磁盘。
        redis_fsync((long)job->arg1);
    }
    ...
}
```

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
