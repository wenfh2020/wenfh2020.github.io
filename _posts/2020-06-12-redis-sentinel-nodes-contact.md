---
layout: post
title:  "[redis 源码走读] sentinel 哨兵 - 集群节点链接流程"
categories: redis
tags: redis sentinel
author: wenfh2020
---

承接上一章 《[[redis 源码走读] sentinel 哨兵 - 原理](https://wenfh2020.com/2020/06/06/redis-sentinel/)》，本章通过 `strace` 命令从底层抓取 sentinel 工作流程日志。通过对日志的分析，走通 sentinel 通信逻辑，为源码走读做准备。



* content
{:toc}

---

## 1. 测试

先启动两个 sentinel 进程，端口分别为 26377，26378。然后启动第三个 sentinel A 进程，端口为 26379，观察它的工作流程。

测试过程中，用 `strace` 工具抓取 sentinel 工作日志。测试集群节点情况：3 个 sentinel，1 个 master，1 个 slave。

![角色关系](/images/2020-06-15-09-59-12.png){:data-action="zoom"}

---

### 1.1. 启动 sentinel 测试



> 节点之间通过 TCP 建立联系，下图展示了 sentinel A 节点与其它节点的关系。
>
> 箭头代表节点 connect 的方向，箭头上面的数字是 fd，可以根据 strace 日志，对号入座。fd 从小到大，展示了创建链接的时序。

![抓包流程](/images/2020-06-15-09-54-30.png){:data-action="zoom"}

---

### 1.2. 简单通信流程

查看 socket 的发送和接收数据，了解节点间的通信内容。

> 详细 strace 日志，请参考  <u> strace 详细日志 </u>  章节。

```shell
# 向 master 发送命令 CLIENT SETNAME / PING / INFO。
sendto(8, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-270e0528-cmd\r\n*1\r\n$4\r\nPING\r\n*1\r\n$4\r\nINFO\r\n", 85, 0, NULL, 0) = 85
# 向 master 发送命令 CLIENT SETNAME，并订阅 master 的 __sentinel__:hello 频道。
sendto(9, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$24\r\nsentinel-270e0528-pubsub\r\n*2\r\n$9\r\nSUBSCRIBE\r\n$18\r\n__sentinel__:hello\r\n", 104, 0, NULL, 0) = 104
# master 回复链接 1 发送的请求。
recvfrom(8, "+OK\r\n+PONG\r\n$3705\r\n# Server\r\nredis_version:5.9.104\r\nredis_git_sha1:00000000\r\nredis_git_dirty:0\r\nredis_build_id:995c39fc3a59d30e\r\nredis_mode:standalone\r\nos:Linux 3.10.0-693.2.2.el7.x86_64 x86_64\r\narch_bits:64\r\nmultiplexing_api:epoll\r\natomicvar_api:atomic-builtin\r\ngcc_version:8.3.1\r\nprocess_id:26660\r\nrun_id:95e58cbfd24f896b11147da117b799383ddf3f96\r\ntcp_port:6379\r\nuptime_in_seconds:410048\r\nuptime_in_days:4\r\nhz:1000\r\nconfigured_hz:1000\r\nlru_clock:14972439\r\nexecutable:/home/other/redis-test/maser/./redis-server\r"..., 16384, 0, NULL, NULL) = 3726
# 链接 2 收到 master 的回复。
recvfrom(9, "+OK\r\n*3\r\n$9\r\nsubscribe\r\n$18\r\n__sentinel__:hello\r\n:1\r\n", 16384, 0, NULL, NULL) = 53
# 向 slave 发送 CLIENT SETNAME / PING / INFO 命令。
sendto(10, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-270e0528-cmd\r\n*1\r\n$4\r\nPING\r\n*1\r\n$4\r\nINFO\r\n", 85, 0, NULL, 0) = 85
# 向 slave 发送命令 CLIENT SETNAME，并订阅 master 的 __sentinel__:hello 频道。
sendto(11, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$24\r\nsentinel-270e0528-pubsub\r\n*2\r\n$9\r\nSUBSCRIBE\r\n$18\r\n__sentinel__:hello\r\n", 104, 0, NULL, 0) = 104
# 收到 slave 的回复。
recvfrom(10, "+OK\r\n+PONG\r\n$3812\r\n# Server\r\nredis_version:5.9.104\r\nredis_git_sha1:00000000\r\nredis_git_dirty:0\r\nredis_build_id:995c39fc3a59d30e\r\nredis_mode:standalone\r\nos:Linux 3.10.0-693.2.2.el7.x86_64 x86_64\r\narch_bits:64\r\nmultiplexing_api:epoll\r\natomicvar_api:atomic-builtin\r\ngcc_version:8.3.1\r\nprocess_id:31519\r\nrun_id:81bd16693346a6a9641df9a3852ff21f2d396c3d\r\ntcp_port:6378\r\nuptime_in_seconds:331563\r\nuptime_in_days:3\r\nhz:1000\r\nconfigured_hz:1000\r\nlru_clock:14972439\r\nexecutable:/home/other/redis-test/slave/./redis-server\r"..., 16384, 0, NULL, NULL) = 3833
# 收到 slave 的回复。
recvfrom(11, "+OK\r\n*3\r\n$9\r\nsubscribe\r\n$18\r\n__sentinel__:hello\r\n:1\r\n", 16384, 0, NULL, NULL) = 53
# 收到 sentinel 节点的请求。获得该节点的 ip / port 等信息。
read(12, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-260e0528-cmd\r\n*1\r\n$4\r\nPING\r\n*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,260e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384) = 204
# 回复请求处理。
write(12, "+OK\r\n+PONG\r\n:1\r\n", 16) = 16
# 向 sentinel 发送命令。
sendto(13, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-270e0528-cmd\r\n*1\r\n$4\r\nPING\r\n", 71, 0, NULL, 0) = 71
# 收到 sentinel 的回复。
recvfrom(13, "+OK\r\n+PONG\r\n", 16384, 0, NULL, NULL) = 12
# 读取 sentinel 发送的消息。
read(14, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-210e0528-cmd\r\n*1\r\n$4\r\nPING\r\n*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26377,210e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384) = 204
write(14, "+OK\r\n+PONG\r\n:1\r\n", 16) = 16
sendto(15, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-270e0528-cmd\r\n*1\r\n$4\r\nPING\r\n", 71, 0, NULL, 0) = 71
recvfrom(15, "+OK\r\n+PONG\r\n", 16384, 0, NULL, NULL) = 12
# 接收 sentinel B 发布给 slave 的信息。
recvfrom(9, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,260e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
```

---

## 2. 源码理解

通过 `strace` 日志内容分析，我们基本了解了节点之间的通信流程，下面来看源码。

---

### 2.1. 结构

sentinel 进程对 sentinel / master / slave 三个角色用数据结构 `sentinelRedisInstance` 进行管理。

![sentinelRedisInstance 节点保存关系](/images/2020-06-15-11-52-21.png){:data-action="zoom"}

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
    dict *masters;      /* Dictionary of master sentinelRedisInstances.
    ...
} sentinel;
```

---

### 2.2. 初始化

* sentinel 从配置 sentinel.conf 读取 master 信息，链接 master。

```shell
# sentinel.conf
sentinel monitor mymaster 127.0.0.1 6379 2
```

* 加载配置，创建角色监控实例运行堆栈。

```shell
# 创建 sentinel 管理实例。
createSentinelRedisInstance(char* name, int flags, char* hostname, int port, int quorum, sentinelRedisInstance* master) (/Users/wenfh2020/src/redis/src/sentinel.c:1192)
sentinelHandleConfiguration(char** argv, int argc) (/Users/wenfh2020/src/redis/src/sentinel.c:1636)
loadServerConfigFromString(char* config) (/Users/wenfh2020/src/redis/src/config.c:504)
# 加载配置。
loadServerConfig(char* filename, char* options) (/Users/wenfh2020/src/redis/src/config.c:566)
main(int argc, char** argv) (/Users/wenfh2020/src/redis/src/server.c:5101)
```

* sentinel 进程启动，载入 sentinel.conf 配置，创建对应节点的管理实例 `sentinelRedisInstance`，读出对应节点 ip / port，准备建立连接。

> sentinel 运行过程中，会把新发现的 sentinel / master / slave 节点信息保存回 sentinel.conf 文件里。

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

    // 解析域名地址。
    addr = createSentinelAddr(hostname,port);
    if (addr == NULL) return NULL;

    /* 一般以 master 为核心管理。只有 master 才配置名称。
     * slave 通过 ip:port 组合成名称进行管理。*/
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

定时器定期对其它节点进行监控链接。sentinel 利用 [hiredis](https://github.com/redis/hiredis/blob/master/README.md) 作为 redis 链接通信 client，链接其它节点进行相互通信。

* 数据结构。

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

* 定时器定时管理节点。

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

/* Perform scheduled operations for all the instances in the dictionary.
 * Recursively call the function against dictionaries of slaves. */
void sentinelHandleDictOfRedisInstances(dict *instances) {
    dictIterator *di;
    dictEntry *de;
    sentinelRedisInstance *switch_to_promoted = NULL;

    /* There are a number of things we need to perform against every master. */
    // 遍历 master 哈希表下的拓扑数据结构，对节点进行处理。
    di = dictGetIterator(instances);
    while((de = dictNext(di)) != NULL) {
        sentinelRedisInstance *ri = dictGetVal(de);

        // 节点管理。
        sentinelHandleRedisInstance(ri);
        if (ri->flags & SRI_MASTER) {
            sentinelHandleDictOfRedisInstances(ri->slaves);
            sentinelHandleDictOfRedisInstances(ri->sentinels);
            if (ri->failover_state == SENTINEL_FAILOVER_STATE_UPDATE_CONFIG) {
                switch_to_promoted = ri;
            }
        }
    }
    if (switch_to_promoted)
        sentinelFailoverSwitchToPromotedSlave(switch_to_promoted);
    dictReleaseIterator(di);
}

void sentinelHandleRedisInstance(sentinelRedisInstance *ri) {
    ...
    // 链接其它节点。
    sentinelReconnectInstance(ri);
    // 监控节点，定时向其它节点发送信息。
    sentinelSendPeriodicCommands(ri);
    ...
}
```

* 异步链接节点逻辑。

```c
/* Create the async connections for the instance link if the link
 * is disconnected. Note that link->disconnected is true even if just
 * one of the two links (commands and pub/sub) is missing. */
void sentinelReconnectInstance(sentinelRedisInstance *ri) {
    if (ri->link->disconnected == 0) return;
    if (ri->addr->port == 0) return; /* port == 0 means invalid address. */
    instanceLink *link = ri->link;
    mstime_t now = mstime();

    if (now - ri->link->last_reconn_time < SENTINEL_PING_PERIOD) return;
    ri->link->last_reconn_time = now;

    // 命令链接。
    if (link->cc == NULL) {
        // 绑定异步链接上下文，回调函数。
        link->cc = redisAsyncConnectBind(ri->addr->ip,ri->addr->port,NET_FIRST_BIND_ADDR);
        if (!link->cc->err && server.tls_replication &&
                (instanceLinkNegotiateTLS(link->cc) == C_ERR)) {
            sentinelEvent(LL_DEBUG,"-cmd-link-reconnection",ri,"%@ #Failed to initialize TLS");
            instanceLinkCloseConnection(link,link->cc);
        } else if (link->cc->err) {
            sentinelEvent(LL_DEBUG,"-cmd-link-reconnection",ri,"%@ #%s",
                link->cc->errstr);
            instanceLinkCloseConnection(link,link->cc);
        } else {
            // 绑定异步上下文，回调函数。
            link->pending_commands = 0;
            link->cc_conn_time = mstime();
            link->cc->data = link;
            redisAeAttach(server.el,link->cc);
            redisAsyncSetConnectCallback(link->cc,
                    sentinelLinkEstablishedCallback);
            redisAsyncSetDisconnectCallback(link->cc,
                    sentinelDisconnectCallback);
            sentinelSendAuthIfNeeded(ri,link->cc);
            sentinelSetClientName(ri,link->cc,"cmd");

            /* Send a PING ASAP when reconnecting. */
            sentinelSendPing(ri);
        }
    }

    // 发布 / 订阅链接。只限 master / slave 角色。
    if ((ri->flags & (SRI_MASTER|SRI_SLAVE)) && link->pc == NULL) {
        // 创建异步非阻塞链接。
        link->pc = redisAsyncConnectBind(ri->addr->ip,ri->addr->port,NET_FIRST_BIND_ADDR);
        if (!link->pc->err && server.tls_replication &&
                (instanceLinkNegotiateTLS(link->pc) == C_ERR)) {
            sentinelEvent(LL_DEBUG,"-pubsub-link-reconnection",ri,"%@ #Failed to initialize TLS");
        } else if (link->pc->err) {
            sentinelEvent(LL_DEBUG,"-pubsub-link-reconnection",ri,"%@ #%s",
                link->pc->errstr);
            instanceLinkCloseConnection(link,link->pc);
        } else {
            int retval;

            // 绑定异步链接上下文，回调函数。
            link->pc_conn_time = mstime();
            link->pc->data = link;
            redisAeAttach(server.el,link->pc);
            redisAsyncSetConnectCallback(link->pc,
                    sentinelLinkEstablishedCallback);
            redisAsyncSetDisconnectCallback(link->pc,
                    sentinelDisconnectCallback);
            sentinelSendAuthIfNeeded(ri,link->pc);
            sentinelSetClientName(ri,link->pc,"pubsub");
            // 订阅 hello 频道后，sentinelReceiveHelloMessages 接收广播消息。
            retval = redisAsyncCommand(link->pc,
                sentinelReceiveHelloMessages, ri, "%s %s",
                sentinelInstanceMapCommand(ri,"SUBSCRIBE"),
                SENTINEL_HELLO_CHANNEL);
            if (retval != C_OK) {
                /* If we can't subscribe, the Pub/Sub connection is useless
                 * and we can simply disconnect it and try again. */
                instanceLinkCloseConnection(link,link->pc);
                return;
            }
        }
    }

    // 标识链接成功。
    if (link->cc && (ri->flags & SRI_SENTINEL || link->pc))
        link->disconnected = 0;
}
```

---

### 2.4. 监控节点

* sentinel 定期发送命令：PING / INFO / PUBLISH。
  
  sentinel 与其它角色链接成功后，定时发送信息给其它节点，监控这些节点的健康状况。

  > `INFO` 命令只发给 master / slave，不会发给其它 sentinel。

```c
/* Send periodic PING, INFO, and PUBLISH to the Hello channel to
 * the specified master or slave instance. */
void sentinelSendPeriodicCommands(sentinelRedisInstance *ri) {
    mstime_t now = mstime();
    mstime_t info_period, ping_period;
    int retval;

    /* Return ASAP if we have already a PING or INFO already pending, or
     * in the case the instance is not properly connected. */
    if (ri->link->disconnected) return;

    // 因为是异步通信，如果链接积压待发送命令超过了一定范围，暂停发送定时命令。
    if (ri->link->pending_commands >=
        SENTINEL_MAX_PENDING_COMMANDS * ri->link->refcount) return;

    // 如果监控的节点出现异常，提高发命令频率。
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
    if (ping_period > SENTINEL_PING_PERIOD) ping_period = SENTINEL_PING_PERIOD;

    // 对 master / slave 角色实例发送 INFO 信息。
    if ((ri->flags & SRI_SENTINEL) == 0 &&
        (ri->info_refresh == 0 ||
        (now - ri->info_refresh) > info_period)) {
        retval = redisAsyncCommand(ri->link->cc,
            sentinelInfoReplyCallback, ri, "%s",
            sentinelInstanceMapCommand(ri,"INFO"));
        if (retval == C_OK) ri->link->pending_commands++;
    }

    // 对所有链接角色实例，发送 PING 信息。
    if ((now - ri->link->last_pong_time) > ping_period &&
        (now - ri->link->last_ping_time) > ping_period/2) {
        sentinelSendPing(ri);
    }

    // 对所有链接角色实例，发布信息。
    if ((now - ri->last_pub_time) > SENTINEL_PUBLISH_PERIOD) {
        sentinelSendHello(ri);
    }
}
```

---

#### 2.4.1. INFO 回复

sentinel 通过 master 回复，获得 master / slave 详细信息。如果有发现新的 slave，可以创建链接。如果 master 发生改变，再进行故障转移。

* master INFO 命令。

```shell
# Replication
role:master
connected_slaves:1
slave0:ip=127.0.0.1,port=6378,state=online,offset=46927618,lag=0
master_replid:902964531b691a75fab13a55fe060e328d91d922
master_replid2:0000000000000000000000000000000000000000
master_repl_offset:46927751
master_repl_meaningful_offset:46927751
second_repl_offset:-1
repl_backlog_active:1
repl_backlog_size:1048576
repl_backlog_first_byte_offset:45879176
repl_backlog_histlen:1048576
```

* slave INFO 命令。

```shell
# Replication
role:slave
master_host:127.0.0.1
master_port:6379
master_link_status:up
master_last_io_seconds_ago:1
master_sync_in_progress:0
slave_repl_offset:30011452
slave_priority:100
slave_read_only:1
connected_slaves:0
master_replid:902964531b691a75fab13a55fe060e328d91d922
master_replid2:0000000000000000000000000000000000000000
master_repl_offset:30011452
master_repl_meaningful_offset:30011452
second_repl_offset:-1
repl_backlog_active:1
repl_backlog_size:1048576
repl_backlog_first_byte_offset:28962877
repl_backlog_histlen:1048576
```

* strace 日志。

```shell
# sentinel 向 master 发送命令 CLIENT SETNAME / PING / INFO。
sendto(8, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-270e0528-cmd\r\n*1\r\n$4\r\nPING\r\n*1\r\n$4\r\nINFO\r\n", 85, 0, NULL, 0) = 85
# master 回复。
recvfrom(8, "+OK\r\n+PONG\r\n$3705\r\n# Server\r\nredis_version:5.9.104\r\nredis_git_sha1:00000000\r\nredis_git_dirty:0\r\nredis_build_id:995c39fc3a59d30e\r\nredis_mode:standalone\r\nos:Linux 3.10.0-693.2.2.el7.x86_64 x86_64\r\narch_bits:64\r\nmultiplexing_api:epoll\r\natomicvar_api:atomic-builtin\r\ngcc_version:8.3.1\r\nprocess_id:26660\r\nrun_id:95e58cbfd24f896b11147da117b799383ddf3f96\r\ntcp_port:6379\r\nuptime_in_seconds:410048\r\nuptime_in_days:4\r\nhz:1000\r\nconfigured_hz:1000\r\nlru_clock:14972439\r\nexecutable:/home/other/redis-test/maser/./redis-server\r"..., 16384, 0, NULL, NULL) = 3726
# 分析 INFO 命令回复，将 slave 信息写入日志。
open("sentinel.log", O_WRONLY|O_CREAT|O_APPEND, 0666) = 10
lseek(10, 0, SEEK_END)                  = 8418
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
write(10, "28574:X 13 Jun 2020 14:45:43.832 * +slave slave 127.0.0.1:6378 127.0.0.1 6378 @ mymaster 127.0.0.1 6379\n", 104) = 104
close(10)                               = 0
...
# 将 INFO 接收到新的信息回写 sentinel.conf 配置文件。
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDWR|O_CREAT, 0644) = 10
write(10, "..."..., 10931) = 10931
close(10)                               = 0
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDONLY) = 10
# 将 sentinel.conf 文件内容刷新到磁盘。
fsync(10)                               = 0
close(10)                               = 0
```

* 根据 INFO 回复信息，更新当前集群监控情况。

```c
void sentinelInfoReplyCallback(redisAsyncContext *c, void *reply, void *privdata) {
    sentinelRedisInstance *ri = privdata;
    instanceLink *link = c->data;
    redisReply *r;

    if (!reply || !link) return;
    link->pending_commands--;
    r = reply;

    if (r->type == REDIS_REPLY_STRING)
        // 监控集群监控情况。
        sentinelRefreshInstanceInfo(ri,r->str);
}

// 行分析 INFO 回复的文本信息。
void sentinelRefreshInstanceInfo(sentinelRedisInstance *ri, const char *info) {
    sds *lines;
    int numlines, j;
    int role = 0;

    /* cache full INFO output for instance */
    sdsfree(ri->info);
    ri->info = sdsnew(info);

    ri->master_link_down_time = 0;

    /* Process line by line. */
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
                // 如果有新的 slave 就增加。
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

        // 更新 slave 对应的属性信息。
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

    // 如果是保护模式，不进行故障转移。
    if (sentinel.tilt) return;

    // 故障转移。

    /* Handle slave -> master role switch. */
    // 如果是 slave 角色转移为 master。
    if ((ri->flags & SRI_SLAVE) && role == SRI_MASTER) {
        ...
    }
    ...
    /* Handle slaves replicating to a different master address. */
    // 提升 slave 为 master。
    if ((ri->flags & SRI_SLAVE) && role == SRI_SLAVE &&
        (ri->slave_master_port != ri->master->addr->port ||
         strcasecmp(ri->slave_master_host,ri->master->addr->ip))) {
        ...
    }
    ...
}
```

---

#### 2.4.2. 接收 hello 频道广播消息

* sentinel 与 master / slave 节点建立连接的时候，异步通信已经绑定了频道订阅的回复处理 `sentinelReceiveHelloMessages`。

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

* 回复处理。
  
  回复的内容是 sentinel 和 master 接入信息。

```shell
# 接收 sentinel B 发布给 slave 的信息。
recvfrom(9, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,260e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
```

```c
/* to discover other sentinels attached at the same master. */
void sentinelReceiveHelloMessages(redisAsyncContext *c, void *reply, void *privdata) {
    ...
    sentinelProcessHelloMessage(r->element[2]->str, r->element[2]->len);
}

// 如果发现新节点就增加新节点，如果 master 发生改变就进行故障转移。
void sentinelProcessHelloMessage(char *hello, int hello_len) {
    /* Format is composed of 8 tokens:
     * 0=ip,1=port,2=runid,3=current_epoch,4=master_name,
     * 5=master_ip,6=master_port,7=master_config_epoch. */
    ...
}

```

---

## 3. strace 详细日志

```shell
# 命令启动进程
execve("./redis-sentinel", ["./redis-sentinel", "sentinel.conf"], [/* 34 vars */]) = 0
...
# 读取配置。
open("sentinel.conf", O_RDONLY)         = 5
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
read(5, "..."..., 4096) = 4096
read(5, "..."..., 4096) = 4096
read(5, "..."..., 4096) = 2617
read(5, "", 4096)                       = 0
close(5)                                = 0
...
# 获取设置进程文件限制。
getrlimit(RLIMIT_NOFILE, {rlim_cur=65535, rlim_max=65535}) = 0
# 创建 epoll 事件处理。
epoll_create(1024)                      = 5
# 创建 IPV6 监听 socket，监听端口 26379。
socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP) = 6
setsockopt(6, SOL_IPV6, IPV6_V6ONLY, [1], 4) = 0
setsockopt(6, SOL_SOCKET, SO_REUSEADDR, [1], 4) = 0
bind(6, {sa_family=AF_INET6, sin6_port=htons(26379), inet_pton(AF_INET6, "::", &sin6_addr), sin6_flowinfo=0, sin6_scope_id=0}, 28) = 0
listen(6, 511)                          = 0
# 设置非阻塞。
fcntl(6, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(6, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
# 创建 IPV4 监听 socket，监听端口 26379。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 7
setsockopt(7, SOL_SOCKET, SO_REUSEADDR, [1], 4) = 0
bind(7, {sa_family=AF_INET, sin_port=htons(26379), sin_addr=inet_addr("0.0.0.0")}, 16) = 0
listen(7, 511)                          = 0
# 设置非阻塞。
fcntl(7, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(7, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
# epoll 监控监听的 socket。
epoll_ctl(5, EPOLL_CTL_ADD, 6, {EPOLLIN, {u32=6, u64=6}}) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 7, {EPOLLIN, {u32=7, u64=7}}) = 0
...
# 将进程 id 写入 pid 文件。
open("/var/run/redis-sentinel.pid", O_WRONLY|O_CREAT|O_TRUNC, 0666) = 8
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
write(8, "28574\n", 6)                  = 6
close(8)                                = 0
...
# 检查 tcp_backlog。
open("/proc/sys/net/core/somaxconn", O_RDONLY) = 8
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
read(8, "4096\n", 1024)                 = 5
close(8)                                = 0
...
# 创建 TCP 链接，链接 master。（配置里有 master 的 ip / port）
# 链接 master 需要创建两条 tcp 链接，一条用来发命令，一条用来订阅 master 频道，方便 master 广播信息。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 8
fcntl(8, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(8, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
# 链接 master 端口 6379，因为 socket 是非阻塞的，connect 所以返回 -1。
connect(8, {sa_family=AF_INET, sin_port=htons(6379), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
setsockopt(8, SOL_TCP, TCP_NODELAY, [1], 4) = 0
# 链接 master 的 socket 通过 epoll 监控。等待 connect 事件通知。
epoll_ctl(5, EPOLL_CTL_ADD, 8, {EPOLLOUT, {u32=8, u64=8}}) = 0
# 创建 TCP 链接 2，链接 master。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 9
fcntl(9, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(9, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
connect(9, {sa_family=AF_INET, sin_port=htons(6379), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
setsockopt(9, SOL_TCP, TCP_NODELAY, [1], 4) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 9, {EPOLLOUT, {u32=9, u64=9}}) = 0
epoll_wait(5, [{EPOLLOUT, {u32=8, u64=8}}, {EPOLLOUT, {u32=9, u64=9}}], 10128, 83) = 2
# 链接 1 链接成功。
connect(8, {sa_family=AF_INET, sin_port=htons(6379), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
# 向 master 发送命令 CLIENT SETNAME / PING / INFO。
sendto(8, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-270e0528-cmd\r\n*1\r\n$4\r\nPING\r\n*1\r\n$4\r\nINFO\r\n", 85, 0, NULL, 0) = 85
epoll_ctl(5, EPOLL_CTL_DEL, 8, 0x7ffe0681e224) = 0
# 向 epoll 注册，关注链接1的事件。
epoll_ctl(5, EPOLL_CTL_ADD, 8, {EPOLLIN, {u32=8, u64=8}}) = 0
# 链接 2 链接成功。
connect(9, {sa_family=AF_INET, sin_port=htons(6379), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
# 向 master 发送命令 CLIENT SETNAME，并订阅 master 的 __sentinel__:hello 频道。
sendto(9, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$24\r\nsentinel-270e0528-pubsub\r\n*2\r\n$9\r\nSUBSCRIBE\r\n$18\r\n__sentinel__:hello\r\n", 104, 0, NULL, 0) = 104
epoll_ctl(5, EPOLL_CTL_DEL, 9, 0x7ffe0681e224) = 0
# 向 epoll 注册，关注链接2的事件。
epoll_ctl(5, EPOLL_CTL_ADD, 9, {EPOLLIN, {u32=9, u64=9}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}, {EPOLLIN, {u32=9, u64=9}}], 10128, 82) = 2
# master 回复链接 1 发送的请求。
recvfrom(8, "+OK\r\n+PONG\r\n$3705\r\n# Server\r\nredis_version:5.9.104\r\nredis_git_sha1:00000000\r\nredis_git_dirty:0\r\nredis_build_id:995c39fc3a59d30e\r\nredis_mode:standalone\r\nos:Linux 3.10.0-693.2.2.el7.x86_64 x86_64\r\narch_bits:64\r\nmultiplexing_api:epoll\r\natomicvar_api:atomic-builtin\r\ngcc_version:8.3.1\r\nprocess_id:26660\r\nrun_id:95e58cbfd24f896b11147da117b799383ddf3f96\r\ntcp_port:6379\r\nuptime_in_seconds:410048\r\nuptime_in_days:4\r\nhz:1000\r\nconfigured_hz:1000\r\nlru_clock:14972439\r\nexecutable:/home/other/redis-test/maser/./redis-server\r"..., 16384, 0, NULL, NULL) = 3726
# 分析回包，记录 master 回复的 slave 信息。
open("sentinel.log", O_WRONLY|O_CREAT|O_APPEND, 0666) = 10
lseek(10, 0, SEEK_END)                  = 8418
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
write(10, "28574:X 13 Jun 2020 14:45:43.832 * +slave slave 127.0.0.1:6378 127.0.0.1 6378 @ mymaster 127.0.0.1 6379\n", 104) = 104
close(10)                               = 0
munmap(0x7fe6be30f000, 4096)            = 0
# 将 slave 信息写入 sentinel.conf 文件中。
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDONLY) = 10
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
read(10, "..."..., 4096) = 4096
read(10, "..."..., 4096) = 4096
read(10, "..."..., 4096) = 2617
read(10, "", 4096)                      = 0
close(10)                               = 0
munmap(0x7fe6be30f000, 4096)            = 0
getcwd("/home/other/redis-test/sentinel", 1024) = 32
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDWR|O_CREAT, 0644) = 10
write(10, "..."..., 10931) = 10931
close(10)                               = 0
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDONLY) = 10
# 将文件内容刷新到磁盘。
fsync(10)                               = 0
close(10)                               = 0
# 链接 2 收到 master 的回复。
recvfrom(9, "+OK\r\n*3\r\n$9\r\nsubscribe\r\n$18\r\n__sentinel__:hello\r\n:1\r\n", 16384, 0, NULL, NULL) = 53
...
# 创建 socket 1 链接 slave。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 10
fcntl(10, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(10, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
connect(10, {sa_family=AF_INET, sin_port=htons(6378), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
setsockopt(10, SOL_TCP, TCP_NODELAY, [1], 4) = 0
# 向 epoll 注册链接。
epoll_ctl(5, EPOLL_CTL_ADD, 10, {EPOLLOUT, {u32=10, u64=10}}) = 0
# 创建 socket 2 链接 slave。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 11
fcntl(11, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(11, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
connect(11, {sa_family=AF_INET, sin_port=htons(6378), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
setsockopt(11, SOL_TCP, TCP_NODELAY, [1], 4) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 11, {EPOLLOUT, {u32=11, u64=11}}) = 0
epoll_wait(5, [{EPOLLOUT, {u32=10, u64=10}}, {EPOLLOUT, {u32=11, u64=11}}], 10128, 62) = 2
connect(10, {sa_family=AF_INET, sin_port=htons(6378), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
# 向 slave 发送 CLIENT SETNAME / PING / INFO 命令。
sendto(10, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-270e0528-cmd\r\n*1\r\n$4\r\nPING\r\n*1\r\n$4\r\nINFO\r\n", 85, 0, NULL, 0) = 85
epoll_ctl(5, EPOLL_CTL_DEL, 10, 0x7ffe0681e224) = 0
# 向 epoll 注册 slave 链接 1。
epoll_ctl(5, EPOLL_CTL_ADD, 10, {EPOLLIN, {u32=10, u64=10}}) = 0
connect(11, {sa_family=AF_INET, sin_port=htons(6378), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
# 向 slave 发送命令 CLIENT SETNAME，并订阅 master 的 __sentinel__:hello 频道。
sendto(11, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$24\r\nsentinel-270e0528-pubsub\r\n*2\r\n$9\r\nSUBSCRIBE\r\n$18\r\n__sentinel__:hello\r\n", 104, 0, NULL, 0) = 104
epoll_ctl(5, EPOLL_CTL_DEL, 11, 0x7ffe0681e224) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 11, {EPOLLIN, {u32=11, u64=11}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=10, u64=10}}, {EPOLLIN, {u32=11, u64=11}}], 10128, 62) = 2
# 收到 slave 的回复。
recvfrom(10, "+OK\r\n+PONG\r\n$3812\r\n# Server\r\nredis_version:5.9.104\r\nredis_git_sha1:00000000\r\nredis_git_dirty:0\r\nredis_build_id:995c39fc3a59d30e\r\nredis_mode:standalone\r\nos:Linux 3.10.0-693.2.2.el7.x86_64 x86_64\r\narch_bits:64\r\nmultiplexing_api:epoll\r\natomicvar_api:atomic-builtin\r\ngcc_version:8.3.1\r\nprocess_id:31519\r\nrun_id:81bd16693346a6a9641df9a3852ff21f2d396c3d\r\ntcp_port:6378\r\nuptime_in_seconds:331563\r\nuptime_in_days:3\r\nhz:1000\r\nconfigured_hz:1000\r\nlru_clock:14972439\r\nexecutable:/home/other/redis-test/slave/./redis-server\r"..., 16384, 0, NULL, NULL) = 3833
# 收到 slave 的回复。
recvfrom(11, "+OK\r\n*3\r\n$9\r\nsubscribe\r\n$18\r\n__sentinel__:hello\r\n:1\r\n", 16384, 0, NULL, NULL) = 53
# 收到其它 sentinel 节点的链接。
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 61) = 1
accept(7, {sa_family=AF_INET, sin_port=htons(62879), sin_addr=inet_addr("127.0.0.1")}, [16]) = 12
fcntl(12, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(12, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
setsockopt(12, SOL_TCP, TCP_NODELAY, [1], 4) = 0
setsockopt(12, SOL_SOCKET, SO_KEEPALIVE, [1], 4) = 0
setsockopt(12, SOL_TCP, TCP_KEEPIDLE, [300], 4) = 0
setsockopt(12, SOL_TCP, TCP_KEEPINTVL, [100], 4) = 0
setsockopt(12, SOL_TCP, TCP_KEEPCNT, [3], 4) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 12, {EPOLLIN, {u32=12, u64=12}}) = 0
accept(7, 0x7ffe0681e1a0, 0x7ffe0681e19c) = -1 EAGAIN (Resource temporarily unavailable)
epoll_wait(5, [{EPOLLIN, {u32=12, u64=12}}], 10128, 10) = 1
# 收到 sentinel 节点的请求。获得该节点的 ip / port 等信息。
read(12, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-260e0528-cmd\r\n*1\r\n$4\r\nPING\r\n*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,260e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384) = 204
open("sentinel.log", O_WRONLY|O_CREAT|O_APPEND, 0666) = 13
lseek(13, 0, SEEK_END)                  = 8522
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
write(13, "28574:X 13 Jun 2020 14:45:43.969 * +sentinel sentinel 260e052832c9352926f4bbfb48a7c1d7033264fb 127.0.0.1 26378 @ mymaster 127.0.0.1 6379\n", 137) = 137
close(13)                               = 0
munmap(0x7fe6be30f000, 4096)            = 0
# 将其它 sentinel 节点信息存储在 sentinel.conf 配置文件。
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDONLY) = 13
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
read(13, "..."..., 4096) = 4096
read(13, "..."..., 4096) = 4096
read(13, "..."..., 4096) = 2739
read(13, "", 4096)                      = 0
close(13)                               = 0
munmap(0x7fe6be30f000, 4096)            = 0
getcwd("/home/other/redis-test/sentinel", 1024) = 32
futex(0x7fe6bd00738c, FUTEX_WAKE_OP_PRIVATE, 1, 1, 0x7fe6bd007388, {FUTEX_OP_SET, 0, FUTEX_OP_CMP_GT, 1}) = 1
futex(0x7fe6bd0073f8, FUTEX_WAKE_PRIVATE, 1) = 1
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDWR|O_CREAT, 0644) = 13
# 先读后写。
write(13, "..."..., 11021) = 11021
close(13)                               = 0
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDONLY) = 13
fsync(13)                               = 0
close(13)                               = 0
# 回复请求处理。
write(12, "+OK\r\n+PONG\r\n:1\r\n", 16) = 16
...
# 链接端口为 26378 的 sentinel。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 13
fcntl(13, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(13, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
connect(13, {sa_family=AF_INET, sin_port=htons(26378), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
setsockopt(13, SOL_TCP, TCP_NODELAY, [1], 4) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 13, {EPOLLOUT, {u32=13, u64=13}}) = 0
epoll_wait(5, [{EPOLLOUT, {u32=13, u64=13}}], 10128, 58) = 1
connect(13, {sa_family=AF_INET, sin_port=htons(26378), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
# 向 sentinel 发送命令。
sendto(13, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-270e0528-cmd\r\n*1\r\n$4\r\nPING\r\n", 71, 0, NULL, 0) = 71
epoll_ctl(5, EPOLL_CTL_DEL, 13, 0x7ffe0681e224) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 13, {EPOLLIN, {u32=13, u64=13}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=13, u64=13}}], 10128, 57) = 1
# 收到 sentinel 的回复。
recvfrom(13, "+OK\r\n+PONG\r\n", 16384, 0, NULL, NULL) = 12
...
# 收到端口为 26377 的 sentinel 链接。
epoll_wait(5, [{EPOLLIN, {u32=7, u64=7}}], 10128, 62) = 1
accept(7, {sa_family=AF_INET, sin_port=htons(62883), sin_addr=inet_addr("127.0.0.1")}, [16]) = 14
fcntl(14, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(14, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
setsockopt(14, SOL_TCP, TCP_NODELAY, [1], 4) = 0
setsockopt(14, SOL_SOCKET, SO_KEEPALIVE, [1], 4) = 0
setsockopt(14, SOL_TCP, TCP_KEEPIDLE, [300], 4) = 0
setsockopt(14, SOL_TCP, TCP_KEEPINTVL, [100], 4) = 0
setsockopt(14, SOL_TCP, TCP_KEEPCNT, [3], 4) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 14, {EPOLLIN, {u32=14, u64=14}}) = 0
accept(7, 0x7ffe0681e1a0, 0x7ffe0681e19c) = -1 EAGAIN (Resource temporarily unavailable)
epoll_wait(5, [{EPOLLIN, {u32=14, u64=14}}], 10128, 13) = 1
# 读取 sentinel 发送的消息。
read(14, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-210e0528-cmd\r\n*1\r\n$4\r\nPING\r\n*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26377,210e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384) = 204
open("sentinel.log", O_WRONLY|O_CREAT|O_APPEND, 0666) = 15
lseek(15, 0, SEEK_END)                  = 8659
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
write(15, "28574:X 13 Jun 2020 14:45:44.608 * +sentinel sentinel 210e052832c9352926f4bbfb48a7c1d7033264fb 127.0.0.1 26377 @ mymaster 127.0.0.1 6379\n", 137) = 137
close(15)                               = 0
munmap(0x7fe6be30f000, 4096)            = 0
# 记录 sentinel 的信息。
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDONLY) = 15
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe6be30f000
read(15, "..."..., 4096) = 4096
read(15, "..."..., 4096) = 4096
read(15, "..."..., 4096) = 2829
read(15, "", 4096)                      = 0
close(15)                               = 0
munmap(0x7fe6be30f000, 4096)            = 0
getcwd("/home/other/redis-test/sentinel", 1024) = 32
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDWR|O_CREAT, 0644) = 15
write(15, "..."..., 11111) = 11111
close(15)                               = 0
open("/home/other/redis-test/sentinel/sentinel.conf", O_RDONLY) = 15
fsync(15)                               = 0
close(15)                               = 0
getpeername(14, {sa_family=AF_INET, sin_port=htons(62883), sin_addr=inet_addr("127.0.0.1")}, [16]) = 0
# 创建链接，链接 sentinel。
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 15
fcntl(15, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(15, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
connect(15, {sa_family=AF_INET, sin_port=htons(26377), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
setsockopt(15, SOL_TCP, TCP_NODELAY, [1], 4) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 15, {EPOLLOUT, {u32=15, u64=15}}) = 0
write(14, "+OK\r\n+PONG\r\n:1\r\n", 16) = 16
epoll_wait(5, [{EPOLLOUT, {u32=15, u64=15}}], 10128, 61) = 1
connect(15, {sa_family=AF_INET, sin_port=htons(26377), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
sendto(15, "*3\r\n$6\r\nCLIENT\r\n$7\r\nSETNAME\r\n$21\r\nsentinel-270e0528-cmd\r\n*1\r\n$4\r\nPING\r\n", 71, 0, NULL, 0) = 71
epoll_ctl(5, EPOLL_CTL_DEL, 15, 0x7ffe0681e224) = 0
epoll_ctl(5, EPOLL_CTL_ADD, 15, {EPOLLIN, {u32=15, u64=15}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=15, u64=15}}], 10128, 60) = 1
recvfrom(15, "+OK\r\n+PONG\r\n", 16384, 0, NULL, NULL) = 12
...
# 定期通过心跳保活，sentinel 发布信息和收到订阅信息。
epoll_ctl(5, EPOLL_CTL_MOD, 8, {EPOLLIN|EPOLLOUT, {u32=8, u64=8}}) = 0
epoll_wait(5, [{EPOLLOUT, {u32=8, u64=8}}], 10128, 66) = 1
sendto(8, "*1\r\n$4\r\nPING\r\n", 14, 0, NULL, 0) = 14
epoll_ctl(5, EPOLL_CTL_MOD, 8, {EPOLLIN, {u32=8, u64=8}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}], 10128, 65) = 1
recvfrom(8, "+PONG\r\n", 16384, 0, NULL, NULL) = 7
epoll_ctl(5, EPOLL_CTL_MOD, 10, {EPOLLIN|EPOLLOUT, {u32=10, u64=10}}) = 0
epoll_ctl(5, EPOLL_CTL_MOD, 13, {EPOLLIN|EPOLLOUT, {u32=13, u64=13}}) = 0
epoll_wait(5, [{EPOLLOUT, {u32=10, u64=10}}, {EPOLLOUT, {u32=13, u64=13}}], 10128, 52) = 2
sendto(10, "*1\r\n$4\r\nPING\r\n", 14, 0, NULL, 0) = 14
epoll_ctl(5, EPOLL_CTL_MOD, 10, {EPOLLIN, {u32=10, u64=10}}) = 0
sendto(13, "*1\r\n$4\r\nPING\r\n", 14, 0, NULL, 0) = 14
epoll_ctl(5, EPOLL_CTL_MOD, 13, {EPOLLIN, {u32=13, u64=13}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=10, u64=10}}], 10128, 52) = 1
recvfrom(10, "+PONG\r\n", 16384, 0, NULL, NULL) = 7
epoll_wait(5, [{EPOLLIN, {u32=13, u64=13}}], 10128, 52) = 1
recvfrom(13, "+PONG\r\n", 16384, 0, NULL, NULL) = 7
epoll_wait(5, [{EPOLLIN, {u32=12, u64=12}}], 10128, 51) = 1
read(12, "*1\r\n$4\r\nPING\r\n", 16384) = 14
write(12, "+PONG\r\n", 7)               = 7
epoll_wait(5, [{EPOLLIN, {u32=9, u64=9}}, {EPOLLIN, {u32=11, u64=11}}], 10128, 71) = 2
recvfrom(9, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26377,210e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
recvfrom(11, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26377,210e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26377,210e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 266
epoll_ctl(5, EPOLL_CTL_MOD, 15, {EPOLLIN|EPOLLOUT, {u32=15, u64=15}}) = 0
epoll_wait(5, [{EPOLLOUT, {u32=15, u64=15}}], 10128, 66) = 1
sendto(15, "*1\r\n$4\r\nPING\r\n", 14, 0, NULL, 0) = 14
epoll_ctl(5, EPOLL_CTL_MOD, 15, {EPOLLIN, {u32=15, u64=15}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=15, u64=15}}], 10128, 65) = 1
recvfrom(15, "+PONG\r\n", 16384, 0, NULL, NULL) = 7
epoll_wait(5, [{EPOLLIN, {u32=11, u64=11}}, {EPOLLIN, {u32=9, u64=9}}], 10128, 83) = 2
recvfrom(11, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,260e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,260e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 266
recvfrom(9, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,260e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
getsockname(8, {sa_family=AF_INET, sin_port=htons(19612), sin_addr=inet_addr("127.0.0.1")}, [16]) = 0
epoll_ctl(5, EPOLL_CTL_MOD, 8, {EPOLLIN|EPOLLOUT, {u32=8, u64=8}}) = 0
epoll_wait(5, [{EPOLLOUT, {u32=8, u64=8}}], 10128, 66) = 1
sendto(8, "*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26379,270e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 133, 0, NULL, 0) = 133
epoll_ctl(5, EPOLL_CTL_MOD, 8, {EPOLLIN, {u32=8, u64=8}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}, {EPOLLIN, {u32=9, u64=9}}, {EPOLLIN, {u32=11, u64=11}}], 10128, 65) = 3
recvfrom(8, ":3\r\n", 16384, 0, NULL, NULL) = 4
recvfrom(9, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26379,270e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
recvfrom(11, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26379,270e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
epoll_ctl(5, EPOLL_CTL_MOD, 8, {EPOLLIN|EPOLLOUT, {u32=8, u64=8}}) = 0
getsockname(10, {sa_family=AF_INET, sin_port=htons(51906), sin_addr=inet_addr("127.0.0.1")}, [16]) = 0
epoll_ctl(5, EPOLL_CTL_MOD, 10, {EPOLLIN|EPOLLOUT, {u32=10, u64=10}}) = 0
epoll_wait(5, [{EPOLLOUT, {u32=8, u64=8}}, {EPOLLOUT, {u32=10, u64=10}}], 10128, 51) = 2
sendto(8, "*1\r\n$4\r\nPING\r\n", 14, 0, NULL, 0) = 14
epoll_ctl(5, EPOLL_CTL_MOD, 8, {EPOLLIN, {u32=8, u64=8}}) = 0
sendto(10, "*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26379,270e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 133, 0, NULL, 0) = 133
epoll_ctl(5, EPOLL_CTL_MOD, 10, {EPOLLIN, {u32=10, u64=10}}) = 0
epoll_wait(5, [{EPOLLIN, {u32=8, u64=8}}, {EPOLLIN, {u32=10, u64=10}}, {EPOLLIN, {u32=11, u64=11}}], 10128, 51) = 3
recvfrom(8, "+PONG\r\n", 16384, 0, NULL, NULL) = 7
recvfrom(10, ":3\r\n", 16384, 0, NULL, NULL) = 4
recvfrom(11, "*3\r\n$7\r\nmessage\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26379,270e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384, 0, NULL, NULL) = 133
epoll_wait(5, [{EPOLLIN, {u32=12, u64=12}}], 10128, 90) = 1
read(12, "*1\r\n$4\r\nPING\r\n*3\r\n$7\r\nPUBLISH\r\n$18\r\n__sentinel__:hello\r\n$84\r\n127.0.0.1,26378,260e052832c9352926f4bbfb48a7c1d7033264fb,0,mymaster,127.0.0.1,6379,0\r\n", 16384) = 147
write(12, "+PONG\r\n:1\r\n", 11)        = 11
...
```

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/2020/06/12/redis-sentinel-nodes-contact/)
