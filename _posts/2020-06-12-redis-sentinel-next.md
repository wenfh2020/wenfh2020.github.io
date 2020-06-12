---
layout: post
title:  "[redis 源码走读] 高可用集群 - sentinel 哨兵（下）"
categories: redis
tags: redis sentinel
author: wenfh2020
---

承接上一章 《[[redis 源码走读] 高可用集群 - sentinel 哨兵（上）](wenfh2020.com)》，本章主要通过 gdb 调试，去落实 sentinel 源码运行流程。



* content
{:toc}

---

## 1. 启动

以下是 sentinel 启动命令，参考 《[用 gdb 调试 redis](https://wenfh2020.com/2020/01/05/redis-gdb/)》 启动 gdb 调试。

```shell
redis-sentinel /path/to/your/sentinel.conf
redis-server /path/to/your/sentinel.conf --sentinel
```

![启动调试](/images/2020-06-12-14-31-49.png){:data-action="zoom"}

---

## 2. 初始化

集群 sentinel / master / slave 三个角色都用数据结构 `sentinelRedisInstance` 进行管理。

* sentinel 从配置 sentinel.conf 读取 master 信息，链接 master。

```shell
# sentinel.conf
sentinel monitor mymaster 127.0.0.1 6379 2
```

* 初始化配置运行堆栈。

```shell
# 创建 sentinel 管理实例。
createSentinelRedisInstance(char* name, int flags, char* hostname, int port, int quorum, sentinelRedisInstance* master) (/Users/wenfh2020/src/redis/src/sentinel.c:1192)
sentinelHandleConfiguration(char** argv, int argc) (/Users/wenfh2020/src/redis/src/sentinel.c:1636)
loadServerConfigFromString(char* config) (/Users/wenfh2020/src/redis/src/config.c:504)
# 加载配置。
loadServerConfig(char* filename, char* options) (/Users/wenfh2020/src/redis/src/config.c:566)
main(int argc, char** argv) (/Users/wenfh2020/src/redis/src/server.c:5101)
```

---

* 创建 master / slave 监控实例。

```c
// 加载处理配置信息。
char *sentinelHandleConfiguration(char **argv, int argc) {
   ...
   if (!strcasecmp(argv[0],"monitor") && argc == 5) {
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
        // sentinel 运行过程中，会把信息存储在 sentinel.conf 配置文件中。
        // 这里存储了 master 对应的 slave 信息。
        sentinelRedisInstance *slave;

        /* known-replica <name> <ip> <port> */
        ri = sentinelGetMasterByName(argv[1]);
        if (!ri) return "No such master with specified name.";
        if ((slave = createSentinelRedisInstance(NULL,SRI_SLAVE,argv[2],
                    atoi(argv[3]), ri->quorum, ri)) == NULL) {
            return "Wrong hostname or port for replica.";
        }
    } else if (!strcasecmp(argv[0],"known-sentinel") && (argc == 4 || argc == 5)) {
        // sentinel 运行过程中，会把信息存储在 sentinel.conf 配置文件中。
        // 存储的其它 sentinel 节点信息。
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
    // 检查避免重复添加。
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

## 3. 数据结构

redis 集群 sentinel / master / slave 角色关系。

![redis 集群角色关系](/images/2020-06-12-19-14-50.png){:data-action="zoom"}

```c
typedef struct sentinelRedisInstance {
    int flags;      /* See SRI_... defines */
    char *name;     /* Master name from the point of view of this sentinel. */
    char *runid;    /* Run ID of this instance, or unique ID if is a Sentinel.*/
    uint64_t config_epoch;  /* Configuration epoch. */
    sentinelAddr *addr; /* Master host. */
    instanceLink *link; /* Link to the instance, may be shared for Sentinels. */
    mstime_t last_pub_time;   /* Last time we sent hello via Pub/Sub. */
    mstime_t last_hello_time; /* Only used if SRI_SENTINEL is set. Last time
                                 we received a hello from this Sentinel
                                 via Pub/Sub. */
    mstime_t last_master_down_reply_time; /* Time of last reply to
                                             SENTINEL is-master-down command. */
    mstime_t s_down_since_time; /* Subjectively down since time. */
    mstime_t o_down_since_time; /* Objectively down since time. */
    mstime_t down_after_period; /* Consider it down after that period. */
    mstime_t info_refresh;  /* Time at which we received INFO output from it. */
    dict *renamed_commands;     /* Commands renamed in this instance:
                                   Sentinel will use the alternative commands
                                   mapped on this table to send things like
                                   SLAVEOF, CONFING, INFO, ... */

    /* Role and the first time we observed it.
     * This is useful in order to delay replacing what the instance reports
     * with our own configuration. We need to always wait some time in order
     * to give a chance to the leader to report the new configuration before
     * we do silly things. */
    int role_reported;
    mstime_t role_reported_time;
    mstime_t slave_conf_change_time; /* Last time slave master addr changed. */

    /* Master specific. */
    dict *sentinels;    /* Other sentinels monitoring the same master. */
    dict *slaves;       /* Slaves for this master instance. */
    unsigned int quorum;/* Number of sentinels that need to agree on failure. */
    int parallel_syncs; /* How many slaves to reconfigure at same time. */
    char *auth_pass;    /* Password to use for AUTH against master & replica. */
    char *auth_user;    /* Username for ACLs AUTH against master & replica. */

    /* Slave specific. */
    mstime_t master_link_down_time; /* Slave replication link down time. */
    int slave_priority; /* Slave priority according to its INFO output. */
    mstime_t slave_reconf_sent_time; /* Time at which we sent SLAVE OF <new> */
    struct sentinelRedisInstance *master; /* Master instance if it's slave. */
    char *slave_master_host;    /* Master host as reported by INFO */
    int slave_master_port;      /* Master port as reported by INFO */
    int slave_master_link_status; /* Master link status as reported by INFO */
    unsigned long long slave_repl_offset; /* Slave replication offset. */
    /* Failover */
    char *leader;       /* If this is a master instance, this is the runid of
                           the Sentinel that should perform the failover. If
                           this is a Sentinel, this is the runid of the Sentinel
                           that this Sentinel voted as leader. */
    uint64_t leader_epoch; /* Epoch of the 'leader' field. */
    uint64_t failover_epoch; /* Epoch of the currently started failover. */
    int failover_state; /* See SENTINEL_FAILOVER_STATE_* defines. */
    mstime_t failover_state_change_time;
    mstime_t failover_start_time;   /* Last failover attempt start time. */
    mstime_t failover_timeout;      /* Max time to refresh failover state. */
    mstime_t failover_delay_logged; /* For what failover_start_time value we
                                       logged the failover delay. */
    struct sentinelRedisInstance *promoted_slave; /* Promoted slave instance. */
    /* Scripts executed to notify admin or reconfigure clients: when they
     * are set to NULL no script is executed. */
    char *notification_script;
    char *client_reconfig_script;
    sds info; /* cached INFO output */
} sentinelRedisInstance;

/* Main state. */
struct sentinelState {
    char myid[CONFIG_RUN_ID_SIZE+1]; /* This sentinel ID. */
    uint64_t current_epoch;         /* Current epoch. */
    dict *masters;      /* Dictionary of master sentinelRedisInstances.
                           Key is the instance name, value is the
                           sentinelRedisInstance structure pointer. */
    int tilt;           /* Are we in TILT mode? */
    int running_scripts;    /* Number of scripts in execution right now. */
    mstime_t tilt_start_time;       /* When TITL started. */
    mstime_t previous_time;         /* Last time we ran the time handler. */
    list *scripts_queue;            /* Queue of user scripts to execute. */
    char *announce_ip;  /* IP addr that is gossiped to other sentinels if
                           not NULL. */
    int announce_port;  /* Port that is gossiped to other sentinels if
                           non zero. */
    unsigned long simfailure_flags; /* Failures simulation. */
    int deny_scripts_reconfig; /* Allow SENTINEL SET ... to change script
                                  paths at runtime? */
} sentinel;

// sentinel 实例，sentinel / master / slave 三个角色都会使用这个数据结构。
typedef struct sentinelRedisInstance {
   ...
}
```

---

## 4. 问题

1. 读配置流程。
2. sentinel 数据结构。
3. 三个角色建立通信流程。
4. 检查故障，发现故障，故障转移流程。
5. sentinel 的数据结构。
6. 复制数据偏移量为啥不一样。
7. info 命令看看 sub-slave 问题。是不是所有 slave 都传到 master。
8. master 和 slave 故障区别。

---

## 5. 流程

1. 启动 master 和 slave。
2. 启动 sentinel 监控三个节点的情况。

```c
int serverCron(struct aeEventLoop *eventLoop, long long id, void *clientData) {
    ...
    /* Run the Sentinel timer if we are in sentinel mode. */
    if (server.sentinel_mode) sentinelTimer();
    ...
}

void sentinelTimer(void) {
    sentinelCheckTiltCondition();
    sentinelHandleDictOfRedisInstances(sentinel.masters);
    sentinelRunPendingScripts();
    sentinelCollectTerminatedScripts();
    sentinelKillTimedoutScripts();

    /* We continuously change the frequency of the Redis "timer interrupt"
     * in order to desynchronize every Sentinel from every other.
     * This non-determinism avoids that Sentinels started at the same time
     * exactly continue to stay synchronized asking to be voted at the
     * same time again and again (resulting in nobody likely winning the
     * election because of split brain voting). */
    server.hz = CONFIG_DEFAULT_HZ + rand() % CONFIG_DEFAULT_HZ;
}
```

---

## 6. 参考

* [Redis Sentinel Documentation](https://redis.io/topics/sentinel)
* [[redis 源码走读] 主从数据复制（上）](https://wenfh2020.com/2020/05/17/redis-replication/)
* [[redis 源码走读] 主从数据复制（下）](https://wenfh2020.com/2020/05/31/redis-replication-next/)
* 《redis 实现与设计》
* [分布式算法之选举算法Raft](https://blog.csdn.net/cainaioaaa/article/details/79881296)
* [10分钟弄懂Raft算法](http://blog.itpub.net/31556438/viewspace-2637112/)
* [Redis开发与运维之第九章哨兵(四)--配置优化](https://blog.csdn.net/cuiwjava/article/details/99405508)
* [用 gdb 调试 redis](https://wenfh2020.com/2020/01/05/redis-gdb/)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
