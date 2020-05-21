---
layout: post
title:  "[redis 源码走读] 主从复制（数据同步）"
categories: redis
tags: redis replication
author: wenfh2020
---

redis 主从模式主要作用：

* 读写分离，提高系统的负载能力。
* 集群模式或哨兵模式，保证服务高可用。

本章主要走读源码，理解 redis 主从数据同步流程。

* 握手流程。
* 全量同步，非全量同步流程。
* 数据同步完成后，实时数据同步流程。
* 断线重连后的同步流程。



* content
{:toc}

---

## 1. 命令

`replicaof`/`slaveof` 命令，可以使得两个 redis 实例产生主从关系。

```shell
# 建立副本关系。
replicaof host port

# 取消副本关系。
replicaof no one
```

---

[replicaof](https://redis.io/commands/replicaof) 和 [slaveof](https://redis.io/commands/slaveof) 命令实现方法相同，但是不支持 redis `cluster` 集群模式下使用。

```c
// replicaof 和 slaveof 命令功能实现相同。
struct redisCommand redisCommandTable[] = {
    ...
    {"slaveof",replicaofCommand,3,
     "admin no-script ok-stale",
     0,NULL,0,0,0,0,0,0},

    {"replicaof",replicaofCommand,3,
     "admin no-script ok-stale",
     0,NULL,0,0,0,0,0,0},
    ...
}

// 不支持 cluster 集群模式。
void replicaofCommand(client *c) {
    if (server.cluster_enabled) {
        addReplyError(c,"REPLICAOF not allowed in cluster mode.");
        return;
    }
    ...
}
```

---

## 2. 流程

主从数据同步主要分两种：全量同步，增量同步。先跑一下，跟踪它的工作流程，然后再走读源码。

客户端 client 将 redis-server1 设置成 redis-server2 的副本。

* redis-server1: 端口 6379
* redis-server2: 端口 16379
* client

```shell
# 链接 6379 端口服务。
./src/redis-cli -h 127.0.0.1 -p 6379

# 设置主从关系。
replicaof 127.0.0.1 16379
```

---

1. slave 和 master 双方握手建立连接。
2. 链接成功后，slave 发送命令 `psync` 要求 master 数据同步。
3. `master` 检查 slave 的数据偏移量，确认是否全量同步，还是局部数据同步。
4. 全量同步，master 给 slave 回复 `+FULLRESYNC`，并且通过 bgsave 命令将当前内存数据存储为一个 rdb 文件快照，准备发送给 slave。
5. slave 收到全量同步回复，创建临时 rdb 文件，等待 master 发送 rdb 文件进行数据同步。
6. master 成功产生 rdb 文件，给 slave 发送文件。
7. slave 接收 rdb 文件，进行数据同步。
8. slave 接收完 rdb 文件后，将 rdb 数据重新加载到 redis 内存。
9. slave 通知 master 数据复制完成。

---

### 2.1. 全量同步

slave 与 master 第一次建立主从关系，数据全量同步。

* slave (127.0.0.1:6379)

```shell
# strace 抓取底层通信接口的调用。
strace -p 19836 -s 512 -o /tmp/connect.slave

# 太多时间接口调用了。可以通过 sed 过滤这些数据。
sed '/gettimeofday/d' /tmp/connect.slave >  /tmp/connect.slave.bak
```

```shell
...
# 接收到 client 发送的 replicaof 命令。
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 1000) = 1
read(7, "*3\r\n$9\r\nreplicaof\r\n$9\r\n127.0.0.1\r\n$5\r\n16379\r\n", 16384) = 45
write(1, "19836:S 20 May 2020 06:53:07.745 * Before turning into a replica, using my own master parameters to synthesize a cached master: I may be able to synchronize with the new master with just a partial transfer.\n", 207) = 207
getpeername(7, {sa_family=AF_INET, sin_port=htons(13832), sin_addr=inet_addr("127.0.0.1")}, [16]) = 0
# 给客户端返回 ack，服务开始与 master 进行通信连接。
write(7, "+OK\r\n", 5)                  = 5
# -------------------------------------------
epoll_wait(5, [], 10128, 757)           = 0
write(1, "19836:S 20 May 2020 06:53:08.507 * Connecting to MASTER 127.0.0.1:16379\n", 72) = 72
# 创建 socket 进行连接。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 8
setsockopt(8, SOL_SOCKET, SO_REUSEADDR, [1], 4) = 0
fcntl(8, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(8, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
bind(8, {sa_family=AF_INET, sin_port=htons(0), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
# 连接，注意这里的通信是阻塞的。
connect(8, {sa_family=AF_INET, sin_port=htons(16379), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
# 连接成功后发送数据。
epoll_ctl(5, EPOLL_CTL_ADD, 8, {EPOLLOUT, {u32=8, u64=8}}) = 0
write(1, "19836:S 20 May 2020 06:53:08.508 * MASTER <-> REPLICA sync started\n", 67) = 67
epoll_wait(5, [{EPOLLOUT, {u32=8, u64=8}}], 10128, 1000) = 1
# ？
getsockopt(8, SOL_SOCKET, SO_ERROR, [0], [4]) = 0
epoll_ctl(5, EPOLL_CTL_DEL, 8, 0x7fff69ce0c24) = 0
write(1, "19836:S 20 May 2020 06:53:08.508 * Non blocking connect for SYNC fired the event.\n", 82) = 82
# 监听连接是否有可读数据。master 回复的数据。
epoll_ctl(5, EPOLL_CTL_ADD, 8, {EPOLLIN, {u32=8, u64=8}}) = 0
# 连接成功后，走握手流程。发送 'PING'。
write(8, "*1\r\n$4\r\nPING\r\n", 14)    = 14
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 1000) = 1
# master 回复 '+PONG'。
read(8, "+", 1)                         = 1
read(8, "P", 1)                         = 1
read(8, "O", 1)                         = 1
read(8, "N", 1)                         = 1
read(8, "G", 1)                         = 1
read(8, "\r", 1)                        = 1
read(8, "\n", 1)                        = 1
write(1, "19836:S 20 May 2020 06:53:08.511 * Master replied to PING, replication can continue...\n", 87) = 87
# 回复 master 本服务监听的端口。
write(8, "*3\r\n$8\r\nREPLCONF\r\n$14\r\nlistening-port\r\n$4\r\n6379\r\n", 49) = 49
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 996) = 1
# master 回复确认。
read(8, "+", 1)                         = 1
read(8, "O", 1)                         = 1
read(8, "K", 1)                         = 1
read(8, "\r", 1)                        = 1
read(8, "\n", 1)                        = 1
# 成功握手后，发送命令 psync2，要求 master 进行数据同步工作。
# REPLCONF CAPA is used in order to notify masters that a slave is able to understand the new +CONTINUE reply.
write(8, "*5\r\n$8\r\nREPLCONF\r\n$4\r\ncapa\r\n$3\r\neof\r\n$4\r\ncapa\r\n$6\r\npsync2\r\n", 59) = 59
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 995) = 1
read(8, "+", 1)                         = 1
read(8, "O", 1)                         = 1
read(8, "K", 1)                         = 1
read(8, "\r", 1)                        = 1
read(8, "\n", 1)                        = 1
write(1, "19836:S 20 May 2020 06:53:08.514 * Trying a partial resynchronization (request 48f9e4f8d75856f90b65299ce0c6ae57a8a69814:1).\n", 124) = 124
# 成功握手后，发送命令 psync，（服务 id + 当前数据偏移量）要求 master 进行数据同步工作。
write(8, "*3\r\n$5\r\nPSYNC\r\n$40\r\n48f9e4f8d75856f90b65299ce0c6ae57a8a69814\r\n$1\r\n1\r\n", 69) = 69
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 993) = 1
# master 回复确认 '+FULLRESYNC'，进行全量同步。(+FULLRESYNC <replid> <offset>)
read(8, "+", 1)                         = 1
read(8, "F", 1)                         = 1
read(8, "U", 1)                         = 1
read(8, "L", 1)                         = 1
read(8, "L", 1)                         = 1
read(8, "R", 1)                         = 1
read(8, "E", 1)                         = 1
read(8, "S", 1)                         = 1
read(8, "Y", 1)                         = 1
read(8, "N", 1)                         = 1
read(8, "C", 1)                         = 1
read(8, " ", 1)                         = 1
read(8, "d", 1)                         = 1
read(8, "2", 1)                         = 1
read(8, "8", 1)                         = 1
read(8, "b", 1)                         = 1
read(8, "d", 1)                         = 1
read(8, "8", 1)                         = 1
read(8, "0", 1)                         = 1
read(8, "8", 1)                         = 1
read(8, "c", 1)                         = 1
read(8, "0", 1)                         = 1
read(8, "9", 1)                         = 1
read(8, "2", 1)                         = 1
read(8, "2", 1)                         = 1
read(8, "b", 1)                         = 1
read(8, "5", 1)                         = 1
read(8, "6", 1)                         = 1
read(8, "7", 1)                         = 1
read(8, "9", 1)                         = 1
read(8, "0", 1)                         = 1
read(8, "3", 1)                         = 1
read(8, "9", 1)                         = 1
read(8, "d", 1)                         = 1
read(8, "b", 1)                         = 1
read(8, "9", 1)                         = 1
read(8, "8", 1)                         = 1
read(8, "a", 1)                         = 1
read(8, "7", 1)                         = 1
read(8, "4", 1)                         = 1
read(8, "9", 1)                         = 1
read(8, "3", 1)                         = 1
read(8, "f", 1)                         = 1
read(8, "7", 1)                         = 1
read(8, "6", 1)                         = 1
read(8, "6", 1)                         = 1
read(8, "8", 1)                         = 1
read(8, "9", 1)                         = 1
read(8, "0", 1)                         = 1
read(8, "8", 1)                         = 1
read(8, "4", 1)                         = 1
read(8, "e", 1)                         = 1
read(8, " ", 1)                         = 1
read(8, "0", 1)                         = 1
read(8, "\r", 1)                        = 1
read(8, "\n", 1)                        = 1
# ？
epoll_ctl(5, EPOLL_CTL_DEL, 8, 0x7fff69ce0a74) = 0
write(1, "19836:S 20 May 2020 06:53:08.531 * Full resync from master: d28bd808c0922b5679039db98a7493f76689084e:0\n", 103) = 103
write(1, "19836:S 20 May 2020 06:53:08.532 * Discarding previously cached master state.\n", 78) = 78
# 创建临时文件接收数据。
open("temp-1589928788.19836.rdb", O_WRONLY|O_CREAT|O_EXCL, 0644) = 9
epoll_ctl(5, EPOLL_CTL_ADD, 8, {EPOLLIN, {u32=8, u64=8}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 976) = 1
# 接收数据长度。
read(8, "$", 1)                         = 1
read(8, "2", 1)                         = 1
read(8, "7", 1)                         = 1
read(8, "6", 1)                         = 1
read(8, "\r", 1)                        = 1
read(8, "\n", 1)                        = 1
write(1, "19836:S 20 May 2020 06:53:08.799 * MASTER <-> REPLICA sync: receiving 276 bytes from master to disk\n", 100) = 100
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 709) = 1
# 接收数据。
read(8, "REDIS0009\372\tredis-ver\0075.9.104\372\nredis-bits\300@\372\5ctime\302Tc\304^\372\10used-mem\302\2704\35\0\372\16repl-stream-db\300\0\372\7repl-id(d28bd808c0922b5679039db98a7493f76689084e\372\vrepl-offset\300\0\372\faof-preamble\300\0\376\0\373\6\0\0\7fsddf3a\tfddsffdsf\0\3fsf\4fdsf\0\4fsdf\4fdsf\0\5fsdf3\10fdsffdsf\0\6fsddf3\10fdsffdsf\0\tfsd44df3a\tfddsffdsf\377Q\211\240\211\306\270\r$", 276) = 276
# 保存在本地临时文件。
write(9, "REDIS0009\372\tredis-ver\0075.9.104\372\nredis-bits\300@\372\5ctime\302Tc\304^\372\10used-mem\302\2704\35\0\372\16repl-stream-db\300\0\372\7repl-id(d28bd808c0922b5679039db98a7493f76689084e\372\vrepl-offset\300\0\372\faof-preamble\300\0\376\0\373\6\0\0\7fsddf3a\tfddsffdsf\0\3fsf\4fdsf\0\4fsdf\4fdsf\0\5fsdf3\10fdsffdsf\0\6fsddf3\10fdsffdsf\0\tfsd44df3a\tfddsffdsf\377Q\211\240\211\306\270\r$", 276) = 276
write(1, "19836:S 20 May 2020 06:53:08.800 * MASTER <-> REPLICA sync: Flushing old data\n", 78) = 78
epoll_ctl(5, EPOLL_CTL_DEL, 8, 0x7fff69cdcb24) = 0
write(1, "19836:S 20 May 2020 06:53:08.800 * MASTER <-> REPLICA sync: Loading DB in memory\n", 81) = 81
open("dump.rdb", O_RDONLY|O_NONBLOCK)   = 10
# 新文件覆盖旧文件。
rename("temp-1589928788.19836.rdb", "dump.rdb") = 0
futex(0x7ac164, FUTEX_WAKE_OP_PRIVATE, 1, 1, 0x7ac160, {FUTEX_OP_SET, 0, FUTEX_OP_CMP_GT, 1}) = 1
futex(0x7ac200, FUTEX_WAKE_PRIVATE, 1)  = 1
open("dump.rdb", O_RDONLY)              = 10
fstat(10, {st_mode=S_IFREG|0644, st_size=276, ...}) = 0
fstat(10, {st_mode=S_IFREG|0644, st_size=276, ...}) = 0
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f80929da000
# 读数据加载进入内存。
read(10, "REDIS0009\372\tredis-ver\0075.9.104\372\nredis-bits\300@\372\5ctime\302Tc\304^\372\10used-mem\302\2704\35\0\372\16repl-stream-db\300\0\372\7repl-id(d28bd808c0922b5679039db98a7493f76689084e\372\vrepl-offset\300\0\372\faof-preamble\300\0\376\0\373\6\0\0\7fsddf3a\tfddsffdsf\0\3fsf\4fdsf\0\4fsdf\4fdsf\0\5fsdf3\10fdsffdsf\0\6fsddf3\10fdsffdsf\0\tfsd44df3a\tfddsffdsf\377Q\211\240\211\306\270\r$", 4096) = 276
write(1, "19836:S 20 May 2020 06:53:08.801 * Loading RDB produced by version 5.9.104\n", 75) = 75
write(1, "19836:S 20 May 2020 06:53:08.802 * RDB age 0 seconds\n", 53) = 53
write(1, "19836:S 20 May 2020 06:53:08.802 * RDB memory usage when created 1.83 Mb\n", 73) = 73
close(10)                               = 0
munmap(0x7f80929da000, 4096)            = 0
close(9)                                = 0
# 主从通信设置成 非阻塞。
fcntl(8, F_GETFL)                       = 0x802 (flags O_RDWR|O_NONBLOCK)
fcntl(8, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
setsockopt(8, SOL_TCP, TCP_NODELAY, [1], 4) = 0
setsockopt(8, SOL_SOCKET, SO_KEEPALIVE, [1], 4) = 0
setsockopt(8, SOL_TCP, TCP_KEEPIDLE, [300], 4) = 0
setsockopt(8, SOL_TCP, TCP_KEEPINTVL, [100], 4) = 0
setsockopt(8, SOL_TCP, TCP_KEEPCNT, [3], 4) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 8, {EPOLLIN, {u32=8, u64=8}}) = 0
write(1, "19836:S 20 May 2020 06:53:08.804 * MASTER <-> REPLICA sync: Finished with success\n", 82) = 82
epoll_wait(5, [], 10128, 703)           = 0
# 通知 master 数据更新完毕。
write(8, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$1\r\n0\r\n", 34) = 34
write(8, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$1\r\n0\r\n", 34) = 34
epoll_wait(5, [], 10128, 999)           = 0
write(8, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$1\r\n0\r\n", 34) = 34
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 999) = 1
# 双方链接通过心跳保活。
# master 发送 ‘PING’
read(8, "*1\r\n$4\r\nPING\r\n", 16384)  = 14
# 回复 'nACK'。
write(8, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$2\r\n14\r\n", 35) = 35
```

* master (127.0.0.1:16379)

```shell
strace -p 19831 -s 512 -o /tmp/connect.master
sed '/gettimeofday/d' /tmp/connect.master >  /tmp/connect.master.bak

```

```shell
...
# 监听 socket 接收到 slave 的链接。
epoll_wait(5, [{EPOLLIN, {u32=6, u64=6}}], 10128, 1000) = 1
accept(6, {sa_family=AF_INET, sin_port=htons(32795), sin_addr=inet_addr("127.0.0.1")}, [16]) = 7
fcntl(7, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(7, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
# 设置异步通信和保活。
setsockopt(7, SOL_TCP, TCP_NODELAY, [1], 4) = 0
setsockopt(7, SOL_SOCKET, SO_KEEPALIVE, [1], 4) = 0
setsockopt(7, SOL_TCP, TCP_KEEPIDLE, [300], 4) = 0
setsockopt(7, SOL_TCP, TCP_KEEPINTVL, [100], 4) = 0
setsockopt(7, SOL_TCP, TCP_KEEPCNT, [3], 4) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 7, {EPOLLIN, {u32=7, u64=7}}) = 0
accept(6, 0x7ffeac017080, 0x7ffeac01707c) = -1 EAGAIN (Resource temporarily unavailable)
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 284) = 1
# 接收到 slave 的 'PING'
read(7, "*1\r\n$4\r\nPING\r\n", 16384)  = 14
# 回复 'PONG'
write(7, "+PONG\r\n", 7)                = 7
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 283) = 1
# 接收 slave 的监听端口。
read(7, "*3\r\n$8\r\nREPLCONF\r\n$14\r\nlistening-port\r\n$4\r\n6379\r\n", 16384) = 49
# 回复。
write(7, "+OK\r\n", 5)                  = 5
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 281) = 1
# ？
read(7, "*5\r\n$8\r\nREPLCONF\r\n$4\r\ncapa\r\n$3\r\neof\r\n$4\r\ncapa\r\n$6\r\npsync2\r\n", 16384) = 59
write(7, "+OK\r\n", 5)                  = 5
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 280) = 1
# 接收 slave 的 'PSYNC' 命令。
read(7, "*3\r\n$5\r\nPSYNC\r\n$40\r\n48f9e4f8d75856f90b65299ce0c6ae57a8a69814\r\n$1\r\n1\r\n", 16384) = 69
getpeername(7, {sa_family=AF_INET, sin_port=htons(32795), sin_addr=inet_addr("127.0.0.1")}, [16]) = 0
write(1, "19831:M 20 May 2020 06:53:08.515 * Replica 127.0.0.1:6379 asks for synchronization\n", 83) = 83
write(1, "19831:M 20 May 2020 06:53:08.516 * Partial resynchronization not accepted: Replication ID mismatch (Replica asked for '48f9e4f8d75856f90b65299ce0c6ae57a8a69814', my replication IDs are '667662257ed2a295ae15f5a3b92c93fb535ece50' and '0000000000000000000000000000000000000000')\n", 276) = 276
mmap(NULL, 2621440, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = 0x7fe7db452000
write(1, "19831:M 20 May 2020 06:53:08.516 * Starting BGSAVE for SYNC with target: disk\n", 78) = 78
pipe([8, 9])                            = 0
fcntl(8, F_GETFL)                       = 0 (flags O_RDONLY)
fcntl(8, F_SETFL, O_RDONLY|O_NONBLOCK)  = 0
# fork 子进程进行异步存储 rdb 快照。
clone(child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7fe7e5346250) = 19934
write(1, "19831:M 20 May 2020 06:53:08.518 * Background saving started by pid 19934\n", 74) = 74
# 回复全量发送。
write(7, "+FULLRESYNC d28bd808c0922b5679039db98a7493f76689084e 0\r\n", 56) = 56
epoll_wait(5, 0x7fe7e4127d80, 10128, 274) = -1 EINTR (Interrupted system call)
--- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=19934, si_uid=0, si_status=0, si_utime=0, si_stime=0} ---
futex(0x7fe7e420738c, FUTEX_WAKE_OP_PRIVATE, 1, 1, 0x7fe7e4207388, {FUTEX_OP_SET, 0, FUTEX_OP_CMP_GT, 1}) = 1
futex(0x7fe7e42073f8, FUTEX_WAKE_PRIVATE, 1) = 1
# fork 进程存储 rdb 快照完成。关闭子进程。
wait4(-1, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], WNOHANG, NULL) = 19934
write(1, "19831:M 20 May 2020 06:53:08.795 * Background saving terminated with success\n", 77) = 77
# 打开 rdb 文件，读取数据。
open("dump.rdb", O_RDONLY)              = 10
# 读取文件大小为 276 byte。
fstat(10, {st_mode=S_IFREG|0644, st_size=276, ...}) = 0
epoll_ctl(5, EPOLL_CTL_MOD, 7, {EPOLLIN|EPOLLOUT, {u32=7, u64=7}}) = 0
read(8, "\0\0\0\0\0\0\0\0\0@\4\0\0\0\0\0xV4\22z\332}\301", 24) = 24
close(8)                                = 0
close(9)                                = 0
epoll_wait(5, [{EPOLLOUT, {u32=7, u64=7}}], 10128, 999) = 1
# 先发送文件长度，在发送数据。
write(7, "$276\r\n", 6)                 = 6
lseek(10, 0, SEEK_SET)                  = 0
# 从 rdb 文件中读数据进行发送。
read(10, "REDIS0009\372\tredis-ver\0075.9.104\372\nredis-bits\300@\372\5ctime\302Tc\304^\372\10used-mem\302\2704\35\0\372\16repl-stream-db\300\0\372\7repl-id(d28bd808c0922b5679039db98a7493f76689084e\372\vrepl-offset\300\0\372\faof-preamble\300\0\376\0\373\6\0\0\7fsddf3a\tfddsffdsf\0\3fsf\4fdsf\0\4fsdf\4fdsf\0\5fsdf3\10fdsffdsf\0\6fsddf3\10fdsffdsf\0\tfsd44df3a\tfddsffdsf\377Q\211\240\211\306\270\r$", 16384) = 276
# 发送数据给 slave。
write(7, "REDIS0009\372\tredis-ver\0075.9.104\372\nredis-bits\300@\372\5ctime\302Tc\304^\372\10used-mem\302\2704\35\0\372\16repl-stream-db\300\0\372\7repl-id(d28bd808c0922b5679039db98a7493f76689084e\372\vrepl-offset\300\0\372\faof-preamble\300\0\376\0\373\6\0\0\7fsddf3a\tfddsffdsf\0\3fsf\4fdsf\0\4fsdf\4fdsf\0\5fsdf3\10fdsffdsf\0\6fsddf3\10fdsffdsf\0\tfsd44df3a\tfddsffdsf\377Q\211\240\211\306\270\r$", 276) = 276
close(10)                               = 0
epoll_ctl(5, EPOLL_CTL_MOD, 7, {EPOLLIN, {u32=7, u64=7}}) = 0
epoll_ctl(5, EPOLL_CTL_MOD, 7, {EPOLLIN|EPOLLOUT, {u32=7, u64=7}}) = 0
getpeername(7, {sa_family=AF_INET, sin_port=htons(32795), sin_addr=inet_addr("127.0.0.1")}, [16]) = 0
write(1, "19831:M 20 May 2020 06:53:08.798 * Synchronization with replica 127.0.0.1:6379 succeeded\n", 89) = 89
epoll_wait(5, [{EPOLLOUT, {u32=7, u64=7}}], 10128, 998) = 1
epoll_ctl(5, EPOLL_CTL_MOD, 7, {EPOLLIN, {u32=7, u64=7}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 998) = 1
read(7, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$1\r\n0\r\n", 16384) = 34
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 1000) = 1
read(7, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$1\r\n0\r\n", 16384) = 34
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 1000) = 1
read(7, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$1\r\n0\r\n", 16384) = 34
write(7, "*1\r\n$4\r\nPING\r\n", 14)    = 14
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 1000) = 1
read(7, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$2\r\n14\r\n", 16384) = 35
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 999) = 1
read(7, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$2\r\n14\r\n", 16384) = 35
...
```

---

## 3. 数据结构

### 3.1. redisServer

```c
#define CONFIG_RUN_ID_SIZE 40

struct redisServer {
    ...
    list *slaves, *monitors;    /* List of slaves and MONITORs */
    ...
    /* Replication (master) */
    char replid[CONFIG_RUN_ID_SIZE+1];  /* My current replication ID. */
    char replid2[CONFIG_RUN_ID_SIZE+1]; /* replid inherited from master*/
    long long second_replid_offset; /* Accept offsets up to this for replid2. */
    int slaveseldb;                 /* Last SELECTed DB in replication output */
    time_t repl_no_slaves_since;    /* We have no slaves since that time.
    ...
    /* Replication (slave) */
    char *masterhost;               /* Hostname of master */
    int masterport;                 /* Port of master */
    int repl_state;          /* Replication status if the instance is a slave */
    int repl_transfer_fd;    /* Slave -> Master SYNC temp file descriptor */
    char *repl_transfer_tmpfile; /* Slave-> master SYNC temp file name */
    connection *repl_transfer_s;     /* Slave -> Master SYNC connection */
    client *master;     /* Client that is master for this slave */
    client *cached_master; /* Cached master to be reused for PSYNC. */
}
```

---

### 3.2. 通信状态

```c
/* Slave replication state. Used in server.repl_state for slaves to remember
 * what to do next. */
#define REPL_STATE_NONE 0 /* No active replication */
#define REPL_STATE_CONNECT 1 /* Must connect to master */
#define REPL_STATE_CONNECTING 2 /* Connecting to master */
/* --- Handshake states, must be ordered --- */
#define REPL_STATE_RECEIVE_PONG 3 /* Wait for PING reply */
#define REPL_STATE_SEND_AUTH 4 /* Send AUTH to master */
#define REPL_STATE_RECEIVE_AUTH 5 /* Wait for AUTH reply */
#define REPL_STATE_SEND_PORT 6 /* Send REPLCONF listening-port */
#define REPL_STATE_RECEIVE_PORT 7 /* Wait for REPLCONF reply */
#define REPL_STATE_SEND_IP 8 /* Send REPLCONF ip-address */
#define REPL_STATE_RECEIVE_IP 9 /* Wait for REPLCONF reply */
#define REPL_STATE_SEND_CAPA 10 /* Send REPLCONF capa */
#define REPL_STATE_RECEIVE_CAPA 11 /* Wait for REPLCONF reply */
#define REPL_STATE_SEND_PSYNC 12 /* Send PSYNC */
#define REPL_STATE_RECEIVE_PSYNC 13 /* Wait for PSYNC reply */
/* --- End of handshake states --- */
#define REPL_STATE_TRANSFER 14 /* Receiving .rdb from master */
#define REPL_STATE_CONNECTED 15 /* Connected to master */
```

---

## 4. 通信逻辑

```c
int serverCron(struct aeEventLoop *eventLoop, long long id, void *clientData) {
    ...
    /* Replication cron function -- used to reconnect to master,
     * detect transfer failures, start background RDB transfers and so forth. */
    run_with_period(1000) replicationCron();
    ...
}

/* Replication cron function, called 1 time per second. */
void replicationCron(void) {
    ...
    /* Check if we should connect to a MASTER */
    if (server.repl_state == REPL_STATE_CONNECT) {
        serverLog(LL_NOTICE,"Connecting to MASTER %s:%d",
            server.masterhost, server.masterport);
        if (connectWithMaster() == C_OK) {
            serverLog(LL_NOTICE,"MASTER <-> REPLICA sync started");
        }
    }
    ...
}

int connectWithMaster(void) {
    server.repl_transfer_s = server.tls_replication ? connCreateTLS() : connCreateSocket();
    if (connConnect(server.repl_transfer_s, server.masterhost, server.masterport,
                NET_FIRST_BIND_ADDR, syncWithMaster) == C_ERR) {
        serverLog(LL_WARNING,"Unable to connect to MASTER: %s",
                connGetLastError(server.repl_transfer_s));
        connClose(server.repl_transfer_s);
        server.repl_transfer_s = NULL;
        return C_ERR;
    }

    server.repl_transfer_lastio = server.unixtime;
    server.repl_state = REPL_STATE_CONNECTING;
    return C_OK;
}

static inline int connConnect(connection *conn, const char *addr, int port, const char *src_addr,
        ConnectionCallbackFunc connect_handler) {
    return conn->type->connect(conn, addr, port, src_addr, connect_handler);
}

// 链接的时候状态是 CONN_STATE_CONNECTING
static int connSocketConnect(connection *conn, const char *addr, int port, const char *src_addr,
        ConnectionCallbackFunc connect_handler) {
    int fd = anetTcpNonBlockBestEffortBindConnect(NULL,addr,port,src_addr);
    if (fd == -1) {
        conn->state = CONN_STATE_ERROR;
        conn->last_errno = errno;
        return C_ERR;
    }

    conn->fd = fd;
    conn->state = CONN_STATE_CONNECTING;

    conn->conn_handler = connect_handler;
    aeCreateFileEvent(server.el, conn->fd, AE_WRITABLE, conn->type->ae_handler, conn);

    return C_OK;
}

int aeCreateFileEvent(aeEventLoop *eventLoop, int fd, int mask,
        aeFileProc *proc, void *clientData) {
    if (fd >= eventLoop->setsize) {
        errno = ERANGE;
        return AE_ERR;
    }
    aeFileEvent *fe = &eventLoop->events[fd];

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

// 读写事件处理，如果这个事件是正在链接的，CONN_STATE_CONNECTING，那么这个链接不是错误，就是链接成功了。
static void connSocketEventHandler(struct aeEventLoop *el, int fd, void *clientData, int mask) {
    UNUSED(el);
    UNUSED(fd);
    connection *conn = clientData;

    if (conn->state == CONN_STATE_CONNECTING &&
            (mask & AE_WRITABLE) && conn->conn_handler) {

        if (connGetSocketError(conn)) {
            conn->last_errno = errno;
            conn->state = CONN_STATE_ERROR;
        } else {
            // 先设置链接成功的状态，再调用 conn_handler，也就是 syncWithMaster。
            conn->state = CONN_STATE_CONNECTED;
        }

        if (!conn->write_handler) aeDeleteFileEvent(server.el,conn->fd,AE_WRITABLE);

        if (!callHandler(conn, conn->conn_handler)) return;
        conn->conn_handler = NULL;
    }

    /* Normally we execute the readable event first, and the writable
     * event later. This is useful as sometimes we may be able
     * to serve the reply of a query immediately after processing the
     * query.
     *
     * However if WRITE_BARRIER is set in the mask, our application is
     * asking us to do the reverse: never fire the writable event
     * after the readable. In such a case, we invert the calls.
     * This is useful when, for instance, we want to do things
     * in the beforeSleep() hook, like fsync'ing a file to disk,
     * before replying to a client. */
    int invert = conn->flags & CONN_FLAG_WRITE_BARRIER;

    int call_write = (mask & AE_WRITABLE) && conn->write_handler;
    int call_read = (mask & AE_READABLE) && conn->read_handler;

    /* Handle normal I/O flows */
    if (!invert && call_read) {
        if (!callHandler(conn, conn->read_handler)) return;
    }
    /* Fire the writable event. */
    if (call_write) {
        if (!callHandler(conn, conn->write_handler)) return;
    }
    /* If we have to invert the call, fire the readable event now
     * after the writable one. */
    if (invert && call_read) {
        if (!callHandler(conn, conn->read_handler)) return;
    }
}

```

---

## 6. 总结

* 异步逻辑，与同步比较，逻辑不够直观，通过回调实现逻辑有点绕，复杂的逻辑往往把人绕晕。如果支持协程，用同步逻辑写异步那维护成本显然会降低很多，然而协程对于 c/c++ 也不是个简单的东西。不像 `golang`，源码级别上支持。如果要安装一大堆库去支持，那就得不偿失了！

---

## 7. 参考

* 《redis 设计与实现》

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
