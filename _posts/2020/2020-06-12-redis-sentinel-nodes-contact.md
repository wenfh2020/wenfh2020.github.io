---
layout: post
title:  "[redis 源码走读] sentinel 哨兵 - 节点链接流程"
categories: redis
tags: redis sentinel contact
author: wenfh2020
---

上一章讲述了哨兵的[工作原理](https://wenfh2020.com/2020/06/06/redis-sentinel/)。

本章通过 `strace` 命令抓取 sentinel 的系统调用日志，熟悉节点通信流程，阅读相关源码。




* content
{:toc}

---

## 1. 工作流程

### 1.1. 命令

* 下面两个命令都可以启动 sentinel 进程。

```shell
redis-sentinel /path/to/your/sentinel.conf
redis-server /path/to/your/sentinel.conf --sentinel
```

* 通信命令。

```c
struct redisCommand sentinelcmds[] = {
    {"ping",pingCommand,1,"",0,NULL,0,0,0,0,0},
    {"sentinel",sentinelCommand,-2,"",0,NULL,0,0,0,0,0},
    {"subscribe",subscribeCommand,-2,"",0,NULL,0,0,0,0,0},
    {"unsubscribe",unsubscribeCommand,-1,"",0,NULL,0,0,0,0,0},
    {"psubscribe",psubscribeCommand,-2,"",0,NULL,0,0,0,0,0},
    {"punsubscribe",punsubscribeCommand,-1,"",0,NULL,0,0,0,0,0},
    {"publish",sentinelPublishCommand,3,"",0,NULL,0,0,0,0,0},
    {"info",sentinelInfoCommand,-1,"",0,NULL,0,0,0,0,0},
    ...
};
```

---

### 1.2. 节点关系

<style> table th:first-of-type { width: 150px; } </style>

| node       | port  |
| :--------- | :---- |
| master     | 6379  |
| slave      | 6378  |
| sentinel A | 26379 |
| sentinel B | 26377 |
| sentinel C | 26378 |

![角色关系](/images/2020/2020-09-17-16-00-08.png){:data-action="zoom"}

---

### 1.3. 连接关系

节点之间通过 TCP 建立联系，下图展示了 sentinel A 节点与其它节点的关系。

> 箭头代表节点 connect 的方向，箭头上面的数字是 fd，可以根据 strace 日志，对号入座。fd 从小到大，展示了创建链接的时序。

![抓包工作流程](/images/2020/2020-09-17-15-29-12.png){:data-action="zoom"}

---

#### 1.3.1. 配置

* 链接 master。

```shell
# sentinel monitor <master-name> <ip> <redis-port> <quorum>
sentinel monitor mymaster 127.0.0.1 6379 2
```

* 保存已建立链接的节点信息。
  
  当 sentinel 启动后，它与集群中其它节点建立了联系，它会将这些节点信息保存在配置文件里。

```shell
# sentinel.conf

# slave 信息。
sentinel known-replica mymaster 127.0.0.1 6378
# sentinel B 信息。
sentinel known-sentinel mymaster 127.0.0.1 26377 de0ffb0d63f77605db3fccb959f67b65b8fdb529
# sentinel C 信息。
sentinel known-sentinel mymaster 127.0.0.1 26378 989f0e00789a0b41cff738704ce8b04bad306714
```

---

#### 1.3.2. 工作日志

```shell
16259:X 17 Sep 2020 14:17:51.097 # oO0OoO0OoO0Oo Redis is starting oO0OoO0OoO0Oo
16259:X 17 Sep 2020 14:17:51.097 # Redis version=5.9.104, bits=64, commit=00000000, modified=0, pid=16259, just started
16259:X 17 Sep 2020 14:17:51.098 # Configuration loaded
16259:X 17 Sep 2020 14:17:51.104 * Running mode=sentinel, port=26379.
16259:X 17 Sep 2020 14:17:51.106 # Sentinel ID is 0400c9170654ecbaeaf98fedb1630486e5f8f5b6
16259:X 17 Sep 2020 14:17:51.107 # +monitor master mymaster 127.0.0.1 6379 quorum 2
16259:X 17 Sep 2020 14:17:51.113 * +slave slave 127.0.0.1:6378 127.0.0.1 6378 @ mymaster 127.0.0.1 6379
16259:X 17 Sep 2020 14:17:52.168 * +sentinel sentinel de0ffb0d63f77605db3fccb959f67b65b8fdb529 127.0.0.1 26377 @ mymaster 127.0.0.1 6379
16259:X 17 Sep 2020 14:17:52.370 * +sentinel sentinel 989f0e00789a0b41cff738704ce8b04bad306714 127.0.0.1 26378 @ mymaster 127.0.0.1 6379
```

---

### 1.4. 通信流程

通过 `strace` 命令查看 socket 的发送和接收数据日志内容，我们基本可以掌握 sentinel/master/slave 这三个角色是怎么联系起来的。

1. sentinel 通过配置文件 master 的链接信息，链接 master，发送 PING。
2. sentinel 向 master 发送 `INFO` 命令，获取 master 上的 slave 名单。
3. sentinel 向 master/slave 订阅了 `__sentinel__:hello` 频道，当其它节点定时向 master/slave 发布消息时，订阅者也能被通知，所以当前 sentinel 也能收到其它 sentinel 的信息，并进行链接。

这样 sentinel 只需要配置 `master` 的信息，通过 `INFO` 命令和订阅频道 `__sentinel__:hello` 就能将集群中所有角色的节点紧密联系在一起。

---

|        命令         | 描述                                                                                                                                                                        |
| :-----------------: | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|        PING         | 三个角色之间通过发送 PING 作为心跳，确认对方是否在线。                                                                                                                      |
|        INFO         | sentinel 向 master/slave 发送该命令，获取 slave 节点的详细信息。                                                                                                            |
| PUBLISH / SUBSCRIBE | sentinel 向 master / slave 订阅（SUBSCRIBE） `__sentinel__:hello` 了频道，但是会向三个角色都发布（PUBLISH）消息，推送相关信息给其它 sentinel 节点，从而与其它节点建立联系。 |

---

### 1.5. 具体日志流程

根据 `strace` 日志参考上述对应连接关系图。

> 从日志中看，有几个命令是一起 `sendto` 发送出去的，因为 sentinel 通过 `hiredis` 作为连接的 client，绑定了 redis 的多路复用异步通信。通过接口写入的命令是异步操作，会先写入发送缓冲区，当触发写事件，才会将发送缓冲区数据发送出去。所以你看到很多命令不是一条一条发出去的，同理，`recvfrom` 收到的回复包，hiredis 触发读事件后，才去读数据，所以很多时候接收的命令也是几条一起读出来。
>
> 这是 pipeline 批量处理，详细原理请参考 《[[hiredis 源码走读] 异步回调机制剖析](https://wenfh2020.com/2020/08/04/hiredis-callback/)》。

```shell
# strace -s 512 -o /tmp/sentinel.log ./redis-sentinel sentinel.conf

# sentinel A 启动绑定 26379 端口。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 7
setsockopt(7, SOL_SOCKET, SO_REUSEADDR, [1], 4) = 0
bind(7, {sa_family=AF_INET, sin_port=htons(26379), sin_addr=inet_addr("0.0.0.0")}, 16) = 0
listen(7, 511)                          = 0

# sentinel A 与 master 通信。两条链接，一条是命令链接，一条是发布订阅链接。
connect(8, {sa_family=AF_INET, sin_port=htons(6379), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
sendto(8, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-0400c917-cmd\r\n*1\r\n$4\r\nPING\r\n*1\r\n$4\r\nINFO\r\n", 85, 0, NULL, 0) = 85
connect(9, {sa_family=AF_INET, sin_port=htons(6379), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
sendto(9, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$24\r\nsentinel-0400c917-pubsub\r\n*2\r\n$9\r\nSUBSCRIBE\r\n$18\r\n__sentinel__:hello\r\n", 104, 0, NULL, 0) = 104
# sentinl A 从 master 获取 slave 节点信息。
recvfrom(8, "+OK\r\n+PONG\r\n$3757\r\n# Server\r\nredis_version:5.9.104\r\nredis_git_sha1:00000000\r\nredis_git_dirty:0\r\nredis_build_id:995c39fc3a59d30e\r\nredis_mode:standalone\r\nos:Linux 3.10.0-693.2.2.el7.x86_64 x86_64\r\narch_bits:64\r\nmultiplexing_api:epoll\r\natomicvar_api:atomic-builtin\r\ngcc_version:8.3.1\r\nprocess_id:7676\r\nrun_id:93843ea6e3ddb2a0c0bc0688a62470b578ef9489\r\ntcp_port:6379\r\nuptime_in_seconds:8271174\r\nuptime_in_days:95\r\nhz:1000\r\nconfigured_hz:1000\r\nlru_clock:6487951\r\nexecutable:/home/other/redis-test/maser/./redis-server\r"..., 16384, 0, NULL, NULL) = 3778
recvfrom(9, "+OK\r\n*3\r\n$9\r\nsubscribe\r\n$18\r\n__sentinel__:hello\r\n:1\r\n", 16384, 0, NULL, NULL) = 53

# sentinel A 与 slave 通信。两条链接，一条是命令链接，一条是发布订阅链接。
connect(10, {sa_family=AF_INET, sin_port=htons(6378), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
sendto(10, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-0400c917-cmd\r\n*1\r\n$4\r\nPING\r\n*1\r\n$4\r\nINFO\r\n", 85, 0, NULL, 0) = 85
connect(11, {sa_family=AF_INET, sin_port=htons(6378), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
sendto(11, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$24\r\nsentinel-0400c917-pubsub\r\n*2\r\n$9\r\nSUBSCRIBE\r\n$18\r\n__sentinel__:hello\r\n", 104, 0, NULL, 0) = 104
recvfrom(10, "+OK\r\n+PONG\r\n$3828\r\n# Server\r\nredis_version:5.9.104\r\nredis_git_sha1:00000000\r\nredis_git_dirty:0\r\nredis_build_id:995c39fc3a59d30e\r\nredis_mode:standalone\r\nos:Linux 3.10.0-693.2.2.el7.x86_64 x86_64\r\narch_bits:64\r\nmultiplexing_api:epoll\r\natomicvar_api:atomic-builtin\r\ngcc_version:8.3.1\r\nprocess_id:15605\r\nrun_id:c945db01b8ff34ffaa529dcfb8f24c7f3a600573\r\ntcp_port:6378\r\nuptime_in_seconds:408\r\nuptime_in_days:0\r\nhz:1000\r\nconfigured_hz:1000\r\nlru_clock:6487951\r\nexecutable:/home/other/redis-test/slave/./redis-server\r\ncon"..., 16384, 0, NULL, NULL) = 3849
recvfrom(11, "+OK\r\n*3\r\n$9\r\nsubscribe\r\n$18\r\n__sentinel__:hello\r\n:1\r\n", 16384, 0, NULL, NULL) = 53

# sentinel A 与 sentinel B 通信。sentinel A 从 master 获得 sentinel B 发布的链接信息。
recvfrom(9, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26377,de0ffb0d63f77605db3fccb959f67b65b8fdb529,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
connect(12, {sa_family=AF_INET, sin_port=htons(26377), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
sendto(12, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-0400c917-cmd\r\n*1\r\n$4\r\nPING\r\n", 71, 0, NULL, 0) = 71
recvfrom(8, "+PONG\r\n", 16384, 0, NULL, NULL) = 7
recvfrom(10, "+PONG\r\n", 16384, 0, NULL, NULL) = 7
recvfrom(12, "+OK\r\n+PONG\r\n", 16384, 0, NULL, NULL) = 12

# sentinel A 与 sentinel C 通信。sentinel A 从 slave 获得 sentinel C 的链接信息。
recvfrom(11, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,989f0e00789a0b41cff738704ce8b04bad306714,0,mymaster,127.0.0.1,6379,0\r\n*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,989f0e00789a0b41cff738704ce8b04bad306714,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 266
recvfrom(9, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,989f0e00789a0b41cff738704ce8b04bad306714,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
connect(13, {sa_family=AF_INET, sin_port=htons(26378), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
sendto(13, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-0400c917-cmd\r\n*1\r\n$4\r\nPING\r\n", 71, 0, NULL, 0) = 71
recvfrom(13, "+OK\r\n+PONG\r\n", 16384, 0, NULL, NULL) = 12

# sentinel A 向 master / slave 发布自己的链接信息和对应的 master 信息。
sendto(8, "*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26379,0400c9170654ecbaeaf98fedb1630486e5f8f5b6,0,mymaster,127.0.0.1,6379,0\r\n", 133, 0, NULL, 0) = 133
sendto(10, "*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26379,0400c9170654ecbaeaf98fedb1630486e5f8f5b6,0,mymaster,127.0.0.1,6379,0\r\n", 133, 0, NULL, 0) = 133
recvfrom(8, ":3\r\n", 16384, 0, NULL, NULL) = 4
recvfrom(10, ":3\r\n", 16384, 0, NULL, NULL) = 4

# sentinel C 链接 sentinel A。
accept(7, {sa_family=AF_INET, sin_port=htons(62448), sin_addr=inet_addr("127.0.0.1")}, [16]) = 14
read(14, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-989f0e00-cmd\r\n*1\r\n$4\r\nPING\r\n", 16384) = 71
write(14, "+OK\r\n+PONG\r\n", 12)       = 12

# sentinle B 链接 sentinel A。
accept(7, {sa_family=AF_INET, sin_port=htons(62450), sin_addr=inet_addr("127.0.0.1")}, [16]) = 15
read(15, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-de0ffb0d-cmd\r\n*1\r\n$4\r\nPING\r\n", 16384) = 71
```

---

## 2. 源码理解

通过上述分析，我们基本了解了节点之间的通信流程时序，下面来分析一下源码。

---

### 2.1. 结构

sentinel 进程对 sentinel / master / slave 三个角色用数据结构 `sentinelRedisInstance` 进行管理。

![sentinelRedisInstance 节点保存关系](/images/2020/2020-09-17-16-23-59.png){:data-action="zoom"}

<div align=center><img src="/images/2023/2023-09-18-20-15-12.png" data-action="zoom"></div>

```c
// 角色数据结构。
typedef struct sentinelRedisInstance {
    int flags;      /* See SRI_... defines */
    char *name;     /* Master name from the point of view of this sentinel. */
    char *runid;    /* Run ID of this instance, or unique ID if is a Sentinel.*/
    uint64_t config_epoch;  /* Configuration epoch. */
    sentinelAddr *addr; /* Master host. */
    instanceLink *link; /* Link to the instance, may be shared for Sentinels. */
    ...
    /* Master specific. */
    dict *sentinels;    /* Other sentinels monitoring the same master. */
    dict *slaves;       /* Slaves for this master instance. */
    unsigned int quorum;/* Number of sentinels that need to agree on failure. */
    ...
} sentinelRedisInstance;

// sentinel 数据结构。
struct sentinelState {
    char myid[CONFIG_RUN_ID_SIZE+1]; /* This sentinel ID. */
    uint64_t current_epoch;         /* Current epoch. */
    dict *masters;      /* Dictionary of master sentinelRedisInstances. */
    ...
} sentinel;
```

---

### 2.2. 初始化

sentinel 进程启动，加载配置，创建对应节点的管理实例 `sentinelRedisInstance`。

> sentinel 运行过程中，会把新发现的 sentinel / master / slave 节点信息保存 sentinel.conf 文件里。

```shell
# 创建 sentinel 管理实例。
createSentinelRedisInstance(char* name, int flags, char* hostname, int port, int quorum, sentinelRedisInstance* master) (/Users/wenfh2020/src/redis/src/sentinel.c:1192)
sentinelHandleConfiguration(char** argv, int argc) (/Users/wenfh2020/src/redis/src/sentinel.c:1636)
loadServerConfigFromString(char* config) (/Users/wenfh2020/src/redis/src/config.c:504)
# 加载配置。
loadServerConfig(char* filename, char* options) (/Users/wenfh2020/src/redis/src/config.c:566)
main(int argc, char** argv) (/Users/wenfh2020/src/redis/src/server.c:5101)
```

```c
// 加载处理配置信息。
char *sentinelHandleConfiguration(char **argv, int argc) {
   ...
   if (!strcasecmp(argv[0],"monitor") && argc == 5) {
        // 加载 master 信息。
        /* monitor <name> <host> <port> <quorum> */
        int quorum = atoi(argv[4]);

        if (quorum <= 0) return "Quorum must be 1 or greater.";
        // 创建 master 的监控实例。
        if (createSentinelRedisInstance(
           argv[1], SRI_MASTER, argv[2], atoi(argv[3]), quorum, NULL) == NULL) {
            switch(errno) {
            case EBUSY: return "Duplicated master name.";
            case ENOENT: return "Can't resolve master instance hostname.";
            case EINVAL: return "Invalid port number";
            }
        }
    } else if ((!strcasecmp(argv[0],"known-slave") ||
                !strcasecmp(argv[0],"known-replica")) && argc == 4) {
        // 加载 slave 信息。
        sentinelRedisInstance *slave;

        /* known-replica <name> <ip> <port> */
        ri = sentinelGetMasterByName(argv[1]);
        if (!ri) return "No such master with specified name.";
        if ((slave = createSentinelRedisInstance(NULL,SRI_SLAVE,argv[2],
                    atoi(argv[3]), ri->quorum, ri)) == NULL) {
            return "Wrong hostname or port for replica.";
        }
    } else if (!strcasecmp(argv[0],"known-sentinel") && (argc == 4 || argc == 5)) {
        // 加载其它 sentinel 节点信息。
        sentinelRedisInstance *si;
        if (argc == 5) { /* Ignore the old form without runid. */
            /* known-sentinel <name> <ip> <port> [runid] */
            ri = sentinelGetMasterByName(argv[1]);
            if (!ri) return "No such master with specified name.";
            if ((si = createSentinelRedisInstance(argv[4],SRI_SENTINEL,argv[2],
                        atoi(argv[3]), ri->quorum, ri)) == NULL) {
                return "Wrong hostname or port for sentinel.";
            }
            si->runid = sdsnew(argv[4]);
            sentinelTryConnectionSharing(si);
        }
    }
   ...
}

// 创建角色实例对象。角色间关系，通过哈希表进行管理。
sentinelRedisInstance *createSentinelRedisInstance(char *name, int flags, char *hostname, int port, int quorum, sentinelRedisInstance *master) {
    sentinelRedisInstance *ri;
    sentinelAddr *addr;
    dict *table = NULL;
    char slavename[NET_PEER_ID_LEN], *sdsname;

    serverAssert(flags & (SRI_MASTER|SRI_SLAVE|SRI_SENTINEL));
    serverAssert((flags & SRI_MASTER) || master != NULL);

    // 域名解析
    addr = createSentinelAddr(hostname,port);
    if (addr == NULL) return NULL;

    /* 一般以 master 为核心管理。只有 master 才配置名称。slave 通过 ip:port 组合成名称进行管理。*/
    if (flags & SRI_SLAVE) {
        anetFormatAddr(slavename, sizeof(slavename), hostname, port);
        name = slavename;
    }

    // 创建不同角色的哈希表。
    if (flags & SRI_MASTER) table = sentinel.masters;
    else if (flags & SRI_SLAVE) table = master->slaves;
    else if (flags & SRI_SENTINEL) table = master->sentinels;
    sdsname = sdsnew(name);
    // 去重。
    if (dictFind(table,sdsname)) {
        releaseSentinelAddr(addr);
        sdsfree(sdsname);
        errno = EBUSY;
        return NULL;
    }

    // 创建 sentinelRedisInstance 实例对象。
    ri = zmalloc(sizeof(*ri));
    ri->flags = flags;
    ri->name = sdsname;
    ri->runid = NULL;
    ri->config_epoch = 0;
    ri->addr = addr;
    ...
    ri->sentinels = dictCreate(&instancesDictType,NULL);
    ri->quorum = quorum;
    ri->parallel_syncs = SENTINEL_DEFAULT_PARALLEL_SYNCS;
    ri->master = master;
    ri->slaves = dictCreate(&instancesDictType,NULL);
    ...
    // 将新实例关联到对应的哈希表进行管理。
    dictAdd(table, ri->name, ri);
    return ri;
}
```

---

### 2.3. 链接

定时器定期对其它节点进行监控管理。sentinel 利用 [hiredis](https://github.com/redis/hiredis/blob/master/README.md) 作为 redis client，链接其它节点进行相互通信。

---

#### 2.3.1. 数据结构

```c
// 链接结构，两条 hiredis 封装的链接，一条用来发布/订阅。一条用来处理命令。
typedef struct instanceLink {
    int refcount;          /* Number of sentinelRedisInstance owners. */
    int disconnected;      /* Non-zero if we need to reconnect cc or pc. */
    int pending_commands;  /* Number of commands sent waiting for a reply. */
    redisAsyncContext *cc; /* Hiredis context for commands. */
    redisAsyncContext *pc; /* Hiredis context for Pub / Sub. */
    ...
} instanceLink;
```

| params           | desc                                                                                       |
| :--------------- | :----------------------------------------------------------------------------------------- |
| disconnected     | tcp 链接状态。                                                                             |
| pending_commands | 等待回复命令个数，因为异步通信，命令并非实时回复，通过统计等待命令回复个数，实现一些策略。 |
| cc               | 发送的 hiredis 链接。                                                                      |
| pc               | 对 master/slave 发布订阅的 hiredis 链接。                                                  |

---

#### 2.3.2. 定时管理节点

```c
// 定时器。
int serverCron(struct aeEventLoop *eventLoop, long long id, void *clientData) {
    ...
    if (server.sentinel_mode) sentinelTimer();
    ...
}

void sentinelTimer(void) {
    ...
    // 管理节点。
    sentinelHandleDictOfRedisInstances(sentinel.masters);
    ...
}

void sentinelHandleDictOfRedisInstances(dict *instances) {
    ...
    /* There are a number of things we need to perform against every master. */
    /* 遍历 master 哈希表下的拓扑数据结构，管理对应节点。*/
    di = dictGetIterator(instances);
    while((de = dictNext(di)) != NULL) {
        sentinelRedisInstance *ri = dictGetVal(de);
        // 节点管理。
        sentinelHandleRedisInstance(ri);
        ...
    }
    ...
}

void sentinelHandleRedisInstance(sentinelRedisInstance *ri) {
    ...
    /* 异步链接，链接节点 ri。*/
    sentinelReconnectInstance(ri);
    /* 监控节点 ri，定时向其它节点发送信息。
     * 定期给所有类型节点 ri 发送命令 PING/PUBLISH，给 master/slave ri 发送 INFO。*/
    sentinelSendPeriodicCommands(ri);
    ...
}
```

---

#### 2.3.3. 异步链接

sentinel 异步重连其它节点。

1. 每秒检查一次命令链接和发布订阅链接是否正常。
2. 链接断开需要重新链接。
3. 命令链接重连成功，发送 PING 命令。
4. 发布订阅重连成功，SUBSCRIBE 订阅 hello 频道。

```c
void sentinelReconnectInstance(sentinelRedisInstance *ri) {
    if (ri->link->disconnected == 0) return;
    if (ri->addr->port == 0) return; /* port == 0 means invalid address. */
    instanceLink *link = ri->link;
    mstime_t now = mstime();

    /* 每秒检查一次。*/
    if (now - ri->link->last_reconn_time < SENTINEL_PING_PERIOD) {
        return;
    }
    ri->link->last_reconn_time = now;

    /* 链接命令通道。*/
    if (link->cc == NULL) {
        link->cc = redisAsyncConnectBind(ri->addr->ip,ri->addr->port,NET_FIRST_BIND_ADDR);
        ...
        /* 链接成功后，发送 PING 命令。*/
        sentinelSendPing(ri);
        ...
    }

    /* 链接发布订阅通道。*/
    if ((ri->flags & (SRI_MASTER|SRI_SLAVE)) && link->pc == NULL) {
        /* 创建异步非阻塞链接。*/
        link->pc = redisAsyncConnectBind(ri->addr->ip,ri->addr->port,NET_FIRST_BIND_ADDR);
        ...
        /* 链接成功后订阅 hello 频道。*/
        retval = redisAsyncCommand(link->pc,
            sentinelReceiveHelloMessages, ri, "%s %s",
            sentinelInstanceMapCommand(ri,"SUBSCRIBE"),
            SENTINEL_HELLO_CHANNEL);
        ...
    }
    ...
}
```

---

#### 2.3.4. 定时发送消息

sentinel 定期发送命令：PING / INFO / PUBLISH。每种命令发送的时间间隔不一样；不同场景下，同一个命令发送时间间隔可能会改变。

---

**命令发送对象**：

| 命令    | 发送节点类型              |
| :------ | :------------------------ |
| PING    | master / slave / sentinel |
| PUBLISH | master / slave / sentinel |
| INFO    | master / slave            |

```c
void sentinelSendPeriodicCommands(sentinelRedisInstance *ri) {
    mstime_t now = mstime();
    mstime_t info_period, ping_period;
    int retval;

    if (ri->link->disconnected) return;

    /* 因为是异步通信，如果发出去的命令还没有收到回复，当到达一定的量，暂停发送定时命令。*/
    if (ri->link->pending_commands >=
        SENTINEL_MAX_PENDING_COMMANDS * ri->link->refcount) return;

    /* 如果当前节点是 slave，它对应的 master 已经客观下线，并且进入了故障转移状态。
     * 那么提高发命令（INFO）频率，因为故障转移过程中，sentinel 需要通过 "info" 命令
     * 获得节点的信息来完成故障转移环节，例如：slave 的 role 角色信息，
     * 还有当 slave 是否已经成功连接新的 master（"master_link_status"），等等。*/
    if ((ri->flags & SRI_SLAVE) &&
        ((ri->master->flags & (SRI_O_DOWN|SRI_FAILOVER_IN_PROGRESS)) ||
         (ri->master_link_down_time != 0))) {
        info_period = 1000;
    } else {
        info_period = SENTINEL_INFO_PERIOD;
    }

    /* 监控 master，掉线时长可以通过 'down-after-milliseconds' 配置。
     * 但 PING 命令发送间隔不能长于 master 掉线时间，否则不能保活。*/
    ping_period = ri->down_after_period;
    if (ping_period > SENTINEL_PING_PERIOD) {
        ping_period = SENTINEL_PING_PERIOD;
    }

    /* 给 master / slave 发送 INFO。*/
    if ((ri->flags & SRI_SENTINEL) == 0 &&
        (ri->info_refresh == 0 || (now - ri->info_refresh) > info_period)) {
        retval = redisAsyncCommand(ri->link->cc,
            sentinelInfoReplyCallback, ri, "%s",
            sentinelInstanceMapCommand(ri,"INFO"));
        if (retval == C_OK) ri->link->pending_commands++;
    }

    /* 发送 PING。*/
    if ((now - ri->link->last_pong_time) > ping_period &&
        (now - ri->link->last_ping_time) > ping_period/2) {
        sentinelSendPing(ri);
    }

    /* 发布 sentinel 链接信息到 hello 频道。 */
    if ((now - ri->last_pub_time) > SENTINEL_PUBLISH_PERIOD) {
        sentinelSendHello(ri);
    }
}
```

---

#### 2.3.5. INFO 回复

sentinel 通过 master / slave 的 INFO 回复，主要下面几件事：

> 故障转移下一节详细介绍。

1. 发现节点信息变更，同步新的节点属性信息。
2. 如果在 master 的回复文本中发现新的 slave，进行链接建立联系。
3. 节点角色改变，进行故障转移或其它相关的逻辑。

* master

```shell
# Server
run_id:93843ea6e3ddb2a0c0bc0688a62470b578ef9489
...

# Replication
role:master
slave0:ip=127.0.0.1,port=6378,state=online,offset=1554692663,lag=1
...
```

* slave

```shell
# Server
run_id:c945db01b8ff34ffaa529dcfb8f24c7f3a600573

# Replication
role:slave
master_host:127.0.0.1
master_port:6379
master_link_status:up
slave_priority:100
slave_repl_offset:1563634631
```

* 根据 INFO 回复信息，更新当前监控节点属性信息。

```c
void sentinelInfoReplyCallback(redisAsyncContext *c, void *reply, void *privdata) {
    ...
    sentinelRefreshInstanceInfo(ri,r->str);
}

// 分析 INFO 回复的文本信息。
void sentinelRefreshInstanceInfo(sentinelRedisInstance *ri, const char *info) {
    sds *lines;
    int numlines, j;
    int role = 0;

    /* cache full INFO output for instance */
    sdsfree(ri->info);
    ri->info = sdsnew(info);

    ri->master_link_down_time = 0;

    /* info 命令回复内容是多行文本，分析每行文本内容。*/
    lines = sdssplitlen(info,strlen(info),"\r\n",2,&numlines);
    for (j = 0; j < numlines; j++) {
        sentinelRedisInstance *slave;
        sds l = lines[j];
        ...
        /* old versions: slave0:<ip>,<port>,<state>
         * new versions: slave0:ip=127.0.0.1,port=9999,... */
        if ((ri->flags & SRI_MASTER) &&
            sdslen(l) >= 7 && !memcmp(l,"slave",5) && isdigit(l[5])) {
            char *ip, *port, *end;
            ...
            if (sentinelRedisInstanceLookupSlave(ri,ip,atoi(port)) == NULL) {
                /* 如果从 master 回复的 INFO 信息中发现新的 slave 就添加监控实例。 */
                if ((slave = createSentinelRedisInstance(
                    NULL,SRI_SLAVE,ip, atoi(port), ri->quorum, ri)) != NULL) {
                    sentinelEvent(LL_NOTICE,"+slave",slave,"%@");
                    sentinelFlushConfig();
                }
            }
        }

        /* role:<role> */
        if (!memcmp(l,"role:master",11)) role = SRI_MASTER;
        else if (!memcmp(l,"role:slave",10)) role = SRI_SLAVE;

        /* 更新 slave 对应的属性信息。 */
        if (role == SRI_SLAVE) {
            /* master_host:<host> */
            ...
            /* master_port:<port> */
            ...
            /* master_link_status:<status> */
            ...
            /* slave_priority:<priority> */
            ...
            /* slave_repl_offset:<offset> */
            ...
        }
    }

    /* 如果 sentinel 正处在异常状态，不参与故障转移。 */
    if (sentinel.tilt) return;

    /* 故障转移 */
    ...
}
```

---

#### 2.3.6. 发布订阅 hello 频道

![抓包工作流程](/images/2020/2020-09-17-15-29-12.png){:data-action="zoom"}

* sentinel 发布的文本内容。

```shell
<ip>,<port>,<runid>,<current_epoch>,<master_name>,<master_ip>,<master_port>,<master_config_epoch>
```

* sentinel 向 `__sentinel__:hello` 频道发布订阅的 `strace` 日志。

```shell
# sentinel A 向 master 订阅 hello 频道。
sendto(9, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$24\r\nsentinel-0400c917-pubsub\r\n*2\r\n$9\r\nSUBSCRIBE\r\n$18\r\n__sentinel__:hello\r\n", 104, 0, NULL, 0) = 104
recvfrom(9, "+OK\r\n*3\r\n$9\r\nsubscribe\r\n$18\r\n__sentinel__:hello\r\n:1\r\n", 16384, 0, NULL, NULL) = 53

# sentinel A 向 slave 订阅 hello 频道。
sendto(11, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$24\r\nsentinel-0400c917-pubsub\r\n*2\r\n$9\r\nSUBSCRIBE\r\n$18\r\n__sentinel__:hello\r\n", 104, 0, NULL, 0) = 104
recvfrom(11, "+OK\r\n*3\r\n$9\r\nsubscribe\r\n$18\r\n__sentinel__:hello\r\n:1\r\n", 16384, 0, NULL, NULL) = 53

# sentinel A 从 master / slave 收到 sentinel C 发布的信息。
recvfrom(11, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,989f0e00789a0b41cff738704ce8b04bad306714,0,mymaster,127.0.0.1,6379,0\r\n*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,989f0e00789a0b41cff738704ce8b04bad306714,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 266
recvfrom(9, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,989f0e00789a0b41cff738704ce8b04bad306714,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133

# sentinel A 从 master / slave 收到 sentinel B 发布的信息。
recvfrom(9, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26377,de0ffb0d63f77605db3fccb959f67b65b8fdb529,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
recvfrom(11, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26377,de0ffb0d63f77605db3fccb959f67b65b8fdb529,0,mymaster,127.0.0.1,6379,0\r\n*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26377,de0ffb0d63f77605db3fccb959f67b65b8fdb529,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 266

# sentinel A 向 master / slave 发布自己的链接信息和对应的 master 信息。
# __sentinel__:hello
# <ip>,<port>,<runid>,<current_epoch>,<master_name>,<master_ip>,<master_port>,<master_config_epoch>
sendto(8, "*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26379,0400c9170654ecbaeaf98fedb1630486e5f8f5b6,0,mymaster,127.0.0.1,6379,0\r\n", 133, 0, NULL, 0) = 133
sendto(10, "*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26379,0400c9170654ecbaeaf98fedb1630486e5f8f5b6,0,mymaster,127.0.0.1,6379,0\r\n", 133, 0, NULL, 0) = 133
recvfrom(8, ":3\r\n", 16384, 0, NULL, NULL) = 4
recvfrom(10, ":3\r\n", 16384, 0, NULL, NULL) = 4
```

* 发布。

```c
int sentinelSendHello(sentinelRedisInstance *ri) {
    ...
    sentinelRedisInstance *master = (ri->flags & SRI_MASTER) ? ri : ri->master;
    sentinelAddr *master_addr = sentinelGetCurrentMasterAddress(master);
    ...
    /* Format and send the Hello message. */
    snprintf(payload, sizeof(payload),
             "%s,%d,%s,%llu," /* Info about this sentinel. */
             "%s,%s,%d,%llu", /* Info about current master. */
             announce_ip, announce_port, sentinel.myid,
             (unsigned long long)sentinel.current_epoch,
             /* --- */
             master->name, master_addr->ip, master_addr->port,
             (unsigned long long)master->config_epoch);
    retval = redisAsyncCommand(ri->link->cc,
                               sentinelPublishReplyCallback, ri, "%s %s %s",
                               sentinelInstanceMapCommand(ri, "PUBLISH"),
                               SENTINEL_HELLO_CHANNEL, payload);
    ...
}
```

* 订阅。
  sentinel 向 master / slave 订阅 hello 频道，通过异步函数 `sentinelReceiveHelloMessages` 接收其它 sentinel 发布的信息。

```c
void sentinelReconnectInstance(sentinelRedisInstance *ri) {
    ...
    if ((ri->flags & (SRI_MASTER|SRI_SLAVE)) && link->pc == NULL) {
        ...
        // 接收广播消息。
        retval = redisAsyncCommand(link->pc,
                sentinelReceiveHelloMessages, ri, "%s %s",
                sentinelInstanceMapCommand(ri,"SUBSCRIBE"),
                SENTINEL_HELLO_CHANNEL);
        ...
    }
    ...
}
```

* 接收文本回复 sentinelReceiveHelloMessages。

```c
/* to discover other sentinels attached at the same master. */
void sentinelReceiveHelloMessages(redisAsyncContext *c, void *reply, void *privdata) {
    ...
    sentinelProcessHelloMessage(r->element[2]->str, r->element[2]->len);
}

void sentinelProcessHelloMessage(char *hello, int hello_len) {
    /* Format is composed of 8 tokens:
     * 0=ip,1=port,2=runid,3=current_epoch,4=master_name,
     * 5=master_ip,6=master_port,7=master_config_epoch. */
    ...

    if (numtokens == 8) {
        ...
        si = getSentinelRedisInstanceByAddrAndRunID(
            master->sentinels, token[0], port, token[2]);
        ...
        if (!si) {
            ...
            /* Add the new sentinel. */
            si = createSentinelRedisInstance(
                token[2], SRI_SENTINEL, token[0], port, master->quorum, master);
            ...
        }
        ...
        /* 如果 master 链接信息改变，那么修改 master 的属性信息，以及重置 master 对应的 slave 信息。 */
        if (si && master->config_epoch < master_config_epoch) {
            master->config_epoch = master_config_epoch;
            if (master_port != master->addr->port || strcmp(master->addr->ip, token[5])) {
                ...
                sentinelResetMasterAndChangeAddress(master, token[5], master_port);
                ...
            }
        }
        ...
    }
    ...
}
```

---

## 3. 参考

* [Redis Sentinel Documentation](https://redis.io/topics/sentinel)
* 《redis 设计与实现》
