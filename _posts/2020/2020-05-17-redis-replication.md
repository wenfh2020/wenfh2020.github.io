---
layout: post
title:  "[redis 源码走读] 主从数据复制 ①"
categories: redis
tags: redis replication
author: wenfh2020
---

redis 主从模式作用：多节点协调工作保证服务高可用；读写分离，提高系统负载能力；多节点保存数据副本，确保数据安全性。

主从模式，需要实现数据同步，master 节点将数据（全量/增量）复制到链接它的 slave 节点。redis 为了保证节点高性能，采用了异步的数据复制方式，高效地实现了数据的最终一致，并非强一致。

那么接下来，将分两个章节来探索 redis 数据复制的核心工作流程。

> 详细源码分析，请参考 [下一章](https://wenfh2020.com/2020/05/31/redis-replication-next/)




* content
{:toc}

---

## 1. 复制架构

```shell
# Master-Replica replication. Use replicaof to make a Redis instance a copy of
# another Redis server. A few things to understand ASAP about Redis replication.
#
#   +------------------+      +---------------+
#   |      Master      | ---> |    Replica    |
#   | (receive writes) |      |  (exact copy) |
#   +------------------+      +---------------+
```

主从复制，数据是由 master 发送到 slave。一般有两种架构：一主多从，链式主从。这两种复制架构各有优缺点：

* A 图，主从节点间数据复制实时性较好，但是如果 slave 节点数量多了，master 复制数据量就会增大，特别是全量复制场景，对 master 性能影响比较大。
* B 图，D，E `sub-slave` 节点数据复制实时性相对差一点，但是能降低 master 数据复制给多个从节点的压力，整个系统能支撑更大的负载。

<div align=center><img src="/images/2023/2023-09-20-15-33-50.png" data-action="zoom"/></div>

---

## 2. 配置

redis.conf 对应 `REPLICATION` 部分主要配置项内容。

```shell
# 服务建立主从关系命令，设置该服务为其它服务的 slave。
replicaof <masterip> <masterport>

# slave是否支持写命令操作。
replica-read-only yes

# 积压缓冲区大小。缓冲区在 master，slave 断线重连后，
# 如果是增量复制，master 就从缓冲区里取出数据复制给 slave。
repl-backlog-size 1mb

# 防止脑裂设置，对 slave 的链接数量和 slave 复制（保活）时间限制。
min-replicas-to-write 3
min-replicas-max-lag 10
```

---

## 3. 客户端命令

### 3.1. replicaof

客户端命令：`replicaof` / `slaveof`，可以使两个 redis 实例实现主从复制关系。

```shell
# 建立主从关系。
replicaof <masterip> <masterport>

# 取消主从关系。
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

### 3.2. info

[info](https://redis.io/commands/info) 命令可以查询主从副本的相关属性信息。

```shell
into replication
```

---

## 4. 复制

### 4.1. 复制方式

<style> table th:first-of-type { width: 120px; } </style>

|模式|描述|
|:--:|:--|
|全量数据复制|当 slave 第一次与 master 链接或 slave 与 master 断开链接很久，重新链接后，主从数据严重不一致了，需要全部数据进行复制。|
|增量数据复制|slave 因为网络抖动或其它原因，与 master 断开一段时间，重新链接，发现主从数据差异不大，master 只需要复制增加部分数据即可。|
|正常链接数据复制|主从节点链接正常，工作过程中，master 数据有变动（增删改），这些变化的数据被 master 异步复制到 slave。|

---

### 4.2. 请求复制参数

重点看看 `PSYNC` 主从数据复制流程，slave 数据复制要解决两个问题：

* 向谁要数据，\<repild> 副本 id，master 通过副本 id 标识自己。
* 要多少数据，\<offset> 数据偏移量，slave 保存的偏移量和 master 保存的偏移量之间的数据差，就是需要复制的增量数据。

所以 slave 保存了一份 master 数据：master 的 \<master_repild> 和 数据偏移量 \<master_offset>。主从数据复制是异步操作，主从数据并非严格一致，有一定延时。当主从断开链接，slave 重新链接 master，需要通过协议，传递 \<replid>  和 \<offset> 给 master。

```shell
PSYNC <master_replid> <master_offset>
```

第一次链接，slave 还没有 master 的数据。

```shell
PSYNC ? -1
```

---

## 5. 主从数据复制流程

Linux 平台可以通过 `strace` 抓包，观察主从数据复制工作流程。

客户端 client 将 redis-server1 设置成 redis-server2 的副本。

* (**slave**) redis-server1: 端口 6379
* (**master**) redis-server2: 端口 16379
* client

```shell
# 链接 6379 端口服务。
./src/redis-cli -h 127.0.0.1 -p 6379

# 设置主从关系。
replicaof 127.0.0.1 16379
```

<div align=center><img src="/images/2023/2023-09-20-15-03-54.png" data-action="zoom"/></div>

---

### 5.1. slave (127.0.0.1:6379)

* strace 查看底层通信流程。

```shell
# strace 抓取底层通信接口的调用。
strace -p 19836 -s 512 -o /tmp/connect.slave

# 太多时间接口调用了。可以通过 sed 过滤这些数据。
sed '/gettimeofday/d' /tmp/connect.slave >  /tmp/connect.slave.bak
```

* 查看系统调用日志。

```shell
...
# slave 接收到 client 发送的 replicaof 命令。
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 1000) = 1
read(7, "*3\r\n$9\r\nreplicaof\r\n$9\r\n127.0.0.1\r\n$5\r\n16379\r\n", 16384) = 45
write(1, "19836:S 20 May 2020 06:53:07.745 * Before turning into a replica, using my own master parameters to synthesize a cached master: I may be able to synchronize with the new master with just a partial transfer.\n", 207) = 207
getpeername(7, {sa_family=AF_INET, sin_port=htons(13832), sin_addr=inet_addr("127.0.0.1")}, [16]) = 0
# 给客户端返回 ack，服务开始与 master 进行通信连接。
write(7, "+OK\r\n", 5)                  = 5
# -------------------------------------------
epoll_wait(5, [], 10128, 757)           = 0
write(1, "19836:S 20 May 2020 06:53:08.507 * Connecting to MASTER 127.0.0.1:16379\n", 72) = 72
# 创建非阻塞 socket。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 8
setsockopt(8, SOL_SOCKET, SO_REUSEADDR, [1], 4) = 0
fcntl(8, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(8, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
bind(8, {sa_family=AF_INET, sin_port=htons(0), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
# 连接 master。
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
# REPLCONF CAPA is used in order to notify masters that a slave is able to understand the new +CONTINUE reply.
write(8, "*5\r\n$8\r\nREPLCONF\r\n$4\r\ncapa\r\n$3\r\neof\r\n$4\r\ncapa\r\n$6\r\npsync2\r\n", 59) = 59
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 995) = 1
read(8, "+", 1)                         = 1
read(8, "O", 1)                         = 1
read(8, "K", 1)                         = 1
read(8, "\r", 1)                        = 1
read(8, "\n", 1)                        = 1
write(1, "19836:S 20 May 2020 06:53:08.514 * Trying a partial resynchronization (request 48f9e4f8d75856f90b65299ce0c6ae57a8a69814:1).\n", 124) = 124
# 成功握手后，发送命令 psync，（服务 id + 当前数据偏移量）要求 master 进行数据复制工作。
# slaveTryPartialResynchronization(conn,0)
write(8, "*3\r\n$5\r\nPSYNC\r\n$40\r\n48f9e4f8d75856f90b65299ce0c6ae57a8a69814\r\n$1\r\n1\r\n", 69) = 69
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 993) = 1
# master 回复确认 '+FULLRESYNC'，进行全量数据复制。(+FULLRESYNC <replid> <offset>)
# reply = sendSynchronousCommand(SYNC_CMD_READ,conn,NULL);
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
# connSetReadHandler(conn, NULL);
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
# slave 接收 master 发送的数据。
read(8, "REDIS0009\372\tredis-ver\0075.9.104\372\nredis-bits\300@\372\5ctime\302Tc\304^\372\10used-mem\302\2704\35\0\372\16repl-stream-db\300\0\372\7repl-id(d28bd808c0922b5679039db98a7493f76689084e\372\vrepl-offset\300\0\372\faof-preamble\300\0\376\0\373\6\0\0\7fsddf3a\tfddsffdsf\0\3fsf\4fdsf\0\4fsdf\4fdsf\0\5fsdf3\10fdsffdsf\0\6fsddf3\10fdsffdsf\0\tfsd44df3a\tfddsffdsf\377Q\211\240\211\306\270\r$", 276) = 276
# 保存在本地临时 rdb 文件。
write(9, "REDIS0009\372\tredis-ver\0075.9.104\372\nredis-bits\300@\372\5ctime\302Tc\304^\372\10used-mem\302\2704\35\0\372\16repl-stream-db\300\0\372\7repl-id(d28bd808c0922b5679039db98a7493f76689084e\372\vrepl-offset\300\0\372\faof-preamble\300\0\376\0\373\6\0\0\7fsddf3a\tfddsffdsf\0\3fsf\4fdsf\0\4fsdf\4fdsf\0\5fsdf3\10fdsffdsf\0\6fsddf3\10fdsffdsf\0\tfsd44df3a\tfddsffdsf\377Q\211\240\211\306\270\r$", 276) = 276
write(1, "19836:S 20 May 2020 06:53:08.800 * MASTER <-> REPLICA sync: Flushing old data\n", 78) = 78
# 在导入数据前，先删除 fd 读事件，避免事件触发异步回调，导致递归重复处理逻辑。
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
# rdb 文件加载进内存完成，slave 创建 master 的链接对象。 replicationCreateMasterClient
fcntl(8, F_GETFL)                       = 0x802 (flags O_RDWR|O_NONBLOCK)
fcntl(8, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
setsockopt(8, SOL_TCP, TCP_NODELAY, [1], 4) = 0
setsockopt(8, SOL_SOCKET, SO_KEEPALIVE, [1], 4) = 0
setsockopt(8, SOL_TCP, TCP_KEEPIDLE, [300], 4) = 0
setsockopt(8, SOL_TCP, TCP_KEEPINTVL, [100], 4) = 0
setsockopt(8, SOL_TCP, TCP_KEEPCNT, [3], 4) = 0
# connSetReadHandler(server.master->conn, readQueryFromClient);
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
# 回复 'ACK'。
write(8, "*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$2\r\n14\r\n", 35) = 35
```

---

### 5.2. master (127.0.0.1:16379)

* strace 查看底层通信流程。

```shell
strace -p 19831 -s 512 -o /tmp/connect.master
sed '/gettimeofday/d' /tmp/connect.master >  /tmp/connect.master.bak
```

* 查看系统调用日志。

```shell
...
# 监听 socket 接收到 slave 的 connect。
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
# replconfCommand。
read(7, "*3\r\n$8\r\nREPLCONF\r\n$14\r\nlistening-port\r\n$4\r\n6379\r\n", 16384) = 49
# 回复。
write(7, "+OK\r\n", 5)                  = 5
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 281) = 1
# slave 回复，支持新协议。(REPLCONF CAPA is used in order to notify masters that a slave is able to understand the new +CONTINUE reply.)
# replconfCommand
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
# master 接收 slave 的心跳。
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
