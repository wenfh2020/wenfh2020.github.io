---
layout: post
title:  "[redis 源码走读] maxclients 最大连接数限制"
categories: redis
tags: redis maxclients
author: wenfh2020
---

Linux 系统，每个进程有打开文件数量限制，所以 redis 作为一个服务程序，它运行时需要限制外部链接数量。




* content
{:toc}

---

## 1. 进程最大打开文件数量

当进程打开文件数量超出限制，系统将会给进程发送信号（例如：SIGSTOP 信号），强制其退出。

`ulimit -a` 查看 `open files` 信息。

```shell
# ulimit -a
core file size          (blocks, -c) 0
data seg size           (kbytes, -d) unlimited
scheduling priority             (-e) 0
file size               (blocks, -f) unlimited
pending signals                 (-i) 14959
max locked memory       (kbytes, -l) 64
max memory size         (kbytes, -m) unlimited
# 默认进程最大打开文件数量。
open files                      (-n) 1024
pipe size            (512 bytes, -p) 8
POSIX message queues     (bytes, -q) 819200
real-time priority              (-r) 0
stack size              (kbytes, -s) 8192
cpu time               (seconds, -t) unlimited
max user processes              (-u) 14959
virtual memory          (kbytes, -v) unlimited
file locks                      (-x) unlimited
```

---

## 2. 进程启动设置限制

Linux 系统一切皆文件，所以 socket 本质也是文件，redis 作为服务程序，它会打开多种不同类型的文件，例如：客户端连接，listen 监听，日志，父子进程管道通信连接，等等。但是客户端连接是外部接入，不可控，所以重点要限制它的数量。

redis 对文件数量限制主要分两类:

* client 连接数量：server.maxclients。
* 程序正常运行预计需要打开文件的数量（listen，日志，管道...）：CONFIG_MIN_RESERVED_FDS。

---

### 2.1. 配置

* redis.conf 默认设置 10000 个。

```shell
################################### CLIENTS ####################################

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

```c
standardConfig configs[] = {
    ...
    /* Unsigned int configs */
    createUIntConfig("maxclients", NULL, MODIFIABLE_CONFIG, 1, UINT_MAX, server.maxclients, 10000, INTEGER_CONFIG, NULL, updateMaxclients),
    ...
}
```

* 启动。

```c
int main(int argc, char **argv) {
    ...
    initServer();
    ...
}

void initServer(void) {
    ...
    /* 设置文件限制。 */
    adjustOpenFilesLimit();
    ...
}
```

---

`adjustOpenFilesLimit` 是限制设置的具体实现，限制数量不能超过 `ulimit -a` 里的 `open files`，在这个基础上，尽可能设置一个最优的限制数量，这个文件数量是 server.maxclients + CONFIG_MIN_RESERVED_FDS。

```c
#define CONFIG_MIN_RESERVED_FDS 32

/* This function will try to raise the max number of open files accordingly to
 * the configured max number of clients. It also reserves a number of file
 * descriptors (CONFIG_MIN_RESERVED_FDS) for extra operations of
 * persistence, listening sockets, log files and so forth.
 *
 * If it will not be possible to set the limit accordingly to the configured
 * max number of clients, the function will do the reverse setting
 * server.maxclients to the value that we can actually handle. */
void adjustOpenFilesLimit(void) {
    rlim_t maxfiles = server.maxclients+CONFIG_MIN_RESERVED_FDS;
    struct rlimit limit;

    if (getrlimit(RLIMIT_NOFILE,&limit) == -1) {
        serverLog(LL_WARNING,"Unable to obtain the current NOFILE limit (%s), assuming 1024 and setting the max clients configuration accordingly.",
            strerror(errno));
        server.maxclients = 1024-CONFIG_MIN_RESERVED_FDS;
    } else {
        rlim_t oldlimit = limit.rlim_cur;

        /* Set the max number of files if the current limit is not enough
         * for our needs. */
        if (oldlimit < maxfiles) {
            rlim_t bestlimit;
            int setrlimit_error = 0;

            /* Try to set the file limit to match 'maxfiles' or at least
             * to the higher value supported less than maxfiles. */
            bestlimit = maxfiles;
            while(bestlimit > oldlimit) {
                rlim_t decr_step = 16;

                limit.rlim_cur = bestlimit;
                limit.rlim_max = bestlimit;
                if (setrlimit(RLIMIT_NOFILE,&limit) != -1) break;
                setrlimit_error = errno;

                /* We failed to set file limit to 'bestlimit'. Try with a
                 * smaller limit decrementing by a few FDs per iteration. */
                if (bestlimit < decr_step) break;
                bestlimit -= decr_step;
            }

            /* Assume that the limit we get initially is still valid if
             * our last try was even lower. */
            if (bestlimit < oldlimit) bestlimit = oldlimit;

            if (bestlimit < maxfiles) {
                unsigned int old_maxclients = server.maxclients;
                server.maxclients = bestlimit-CONFIG_MIN_RESERVED_FDS;
                /* maxclients is unsigned so may overflow: in order
                 * to check if maxclients is now logically less than 1
                 * we test indirectly via bestlimit. */
                if (bestlimit <= CONFIG_MIN_RESERVED_FDS) {
                    serverLog(LL_WARNING,"Your current 'ulimit -n' "
                        "of %llu is not enough for the server to start. "
                        "Please increase your open file limit to at least "
                        "%llu. Exiting.",
                        (unsigned long long) oldlimit,
                        (unsigned long long) maxfiles);
                    exit(1);
                }
                ...
            } else {
                serverLog(LL_NOTICE,"Increased maximum number of open files "
                    "to %llu (it was originally set to %llu).",
                    (unsigned long long) maxfiles,
                    (unsigned long long) oldlimit);
            }
        }
    }
}

```

---

## 3. 关闭超量连接

```c
static void acceptCommonHandler(connection *conn, int flags, char *ip) {
    ...
    /* 链接数超出限制，关闭 fd。 */
    if (listLength(server.clients) >= server.maxclients) {
        ...
        server.stat_rejected_conn++;
        connClose(conn);
        return;
    }
    ...
}
```