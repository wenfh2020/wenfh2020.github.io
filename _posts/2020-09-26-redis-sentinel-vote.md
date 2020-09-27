---
layout: post
title:  "[redis 源码走读] sentinel 哨兵 - 选举投票"
categories: redis
tags: redis sentinel vote 
author: wenfh2020
---

在 sentinel 故障转移的流程上，当 sentinel 确认 master 客观下线（[《[redis 源码走读] sentinel 哨兵 - 主客观下线》](https://wenfh2020.com/2020/06/15/redis-sentinel-master-down/)）后，那么它要进入 `选举投票` 环节。

多个 sentinel 有可能在同一个时间段内一起发现某个 master 客观下线，如果多个 sentinel 同时执行故障转移，有可能会乱套，也可能出现“脑裂”现象（[《[redis 源码走读] sentinel 哨兵 - 脑裂处理方案》](https://wenfh2020.com/2019/12/27/redis-split-brain/)），所以在一个集群里，多个 sentinel 需要通过投票选出一个代表，由代表去执行故障转移。




* content
{:toc}

---

## 1. 原理

投票原理："先到先得"，每个 sentinel 机会是对等的，都有投票权利。

每个 sentinel 当确认 master 客观下线，它需要向其它 sentinel 拉票，让它们投票给自己。当然 sentinel 除了拉票，它自己也能主动投，投别人，或者投自己。

多数服从少数，当集群里超过半数的 sentinel 选某个 sentinel 为代表，那么它就是 leader，这样选举结束。

![选举投票](/images/2020-09-27-12-46-37.png){:data-action="zoom"}

---

## 2. 拉票

### 2.1. 发送拉票命令

投票通过命令 `SENTINEL IS-MASTER-DOWN-BY-ADDR`：

```shell
# is-master-down-by-addr 命令格式。
SENTINEL is-master-down-by-addr <masterip> <masterport> <sentinel.current_epoch> <sentinel_runid>
```

1. \<masterip\>， \<masterport\> 参数传输 master 的 ip 和 端口（注意：不是传 mastername，因为每个 sentinel 上配置的 name 有可能不一样）。
2. \<sentinel.current_epoch\> 选举纪元，可以理解为选举计数器，每次 sentinel 之间选举，不一定成功，有可能会进行多次，所以每次选举计数器会加 1，表示第几轮选举。
3. \<sentinel_runid\> 当前 sentinel 的 runid，因为选举投票原理是“先到先得”。当其它 sentinel 在一轮选举中，先接收到拉票信息的，会先投给它。
   > 例如 sentinel A，B，C 三个实例，当 A 向 B，C 进行拉票。B 先接收到 A 的拉票信息，那么 B 就选 A 为 leader，但是 C 在接收到 A 的拉票信息前，它已经接到 B 的拉票信息，它已经将票投给了 B，不能再投给 A 了，所以 B 会返回它选的 C 的信息。

---

```c
void sentinelAskMasterStateToOtherSentinels(sentinelRedisInstance *master, int flags) {
    dictIterator *di;
    dictEntry *de;

    di = dictGetIterator(master->sentinels);
    while ((de = dictNext(di)) != NULL) {
        sentinelRedisInstance *ri = dictGetVal(de);
        ...
        /* Only ask if master is down to other sentinels if:
         *
         * 1) We believe it is down, or there is a failover in progress.
         * 2) Sentinel is connected.
         * 3) We did not receive the info within SENTINEL_ASK_PERIOD ms. */
        if ((master->flags & SRI_S_DOWN) == 0) continue;
        if (ri->link->disconnected) continue;
        if (!(flags & SENTINEL_ASK_FORCED) &&
            mstime() - ri->last_master_down_reply_time < SENTINEL_ASK_PERIOD)
            continue;

        /* 当 sentinel 检测到 master 主观下线，那么参数发送 "*"，等待确认客观下线，
         * 当确认客观下线后，再进入选举环节。sentinel 再向其它 sentinel 发送自己的 runid，去拉票。*/
        ll2string(port, sizeof(port), master->addr->port);
        retval = redisAsyncCommand(ri->link->cc,
                                   sentinelReceiveIsMasterDownReply, ri,
                                   "%s is-master-down-by-addr %s %s %llu %s",
                                   sentinelInstanceMapCommand(ri, "SENTINEL"),
                                   master->addr->ip, port,
                                   sentinel.current_epoch,
                                   (master->failover_state > SENTINEL_FAILOVER_STATE_NONE) ? sentinel.myid : "*");
        if (retval == C_OK) ri->link->pending_commands++;
    }
    dictReleaseIterator(di);
}
```

---

### 2.2. 接收拉票

其它 sentinel 节点，接收到拉票信息，进行投票 `sentinelVoteLeader`。

```c
void sentinelCommand(client *c) {
    ...
    else if (!strcasecmp(c->argv[1]->ptr, "is-master-down-by-addr")) {
        ...
        /* 其它 sentinel 接收到询问命令，根据 ip 和 端口查找对应的 master。 */
        ri = getSentinelRedisInstanceByAddrAndRunID(
            sentinel.masters, c->argv[2]->ptr, port, NULL);

        /* 当前 sentinel 如果没有处于异常保护状态，而且也检测到询问的 master 已经主观下线了。 */
        if (!sentinel.tilt && ri && (ri->flags & SRI_S_DOWN) && (ri->flags & SRI_MASTER))
            isdown = 1;

        /* 询问 master 主观下线命令参数是 *，选举投票参数是请求的 sentinel 的 runid。*/
        if (ri && ri->flags & SRI_MASTER && strcasecmp(c->argv[5]->ptr, "*")) {
            /* 投票 */
            leader = sentinelVoteLeader(ri, (uint64_t)req_epoch, c->argv[5]->ptr, &leader_epoch);
        }

        /* 投票选举业务确定回复的内容参数。 */
        addReplyArrayLen(c, 3);
        addReply(c, isdown ? shared.cone : shared.czero);
        addReplyBulkCString(c, leader ? leader : "*");
        addReplyLongLong(c, (long long)leader_epoch);
        if (leader) sdsfree(leader);
    }
    ...
}
```

---

### 2.3. 拉票回复

根据回复结果，更新对应 sentinel 选举的 leader 结果。

```c
/* Receive the SENTINEL is-master-down-by-addr reply, see the
 * sentinelAskMasterStateToOtherSentinels() function for more information. */
void sentinelReceiveIsMasterDownReply(redisAsyncContext *c, void *reply, void *privdata) {
    ...
    if (r->type == REDIS_REPLY_ARRAY && r->elements == 3 &&
        r->element[0]->type == REDIS_REPLY_INTEGER &&
        r->element[1]->type == REDIS_REPLY_STRING &&
        r->element[2]->type == REDIS_REPLY_INTEGER) {
        ri->last_master_down_reply_time = mstime();
        if (r->element[0]->integer == 1) {
            /* ri sentinel 回复：它也检测到该 master 节点已经主观下线。 */
            ri->flags |= SRI_MASTER_DOWN;
        } else {
            ri->flags &= ~SRI_MASTER_DOWN;
        }
        if (strcmp(r->element[1]->str, "*")) {
            /* 当前 sentinel 向 ri 拉选票，ri 回复：它所投票的 sentinel（runid）。*/
            sdsfree(ri->leader);
            if ((long long)ri->leader_epoch != r->element[2]->integer)
                serverLog(LL_WARNING,
                          "%s voted for %s %llu", ri->name,
                          r->element[1]->str,
                          (unsigned long long)r->element[2]->integer);
            ri->leader = sdsnew(r->element[1]->str);
            ri->leader_epoch = r->element[2]->integer;
        }
    }
}
```

---

## 3. 投票

* 投票方式

sentinel 的投票有两种方式：

1. 被动：接收到别人的投票请求（上述的别人拉票 `SENTINEL IS-MASTER-DOWN-BY-ADDR`）。
2. 主动：“我”主动投票（`sentinelVoteLeader`）给别人/自己。

投票是“先到先得”，可以投给别人也可以投给自己，如果实在没人拉票，就投给自己。“先到先得” 是通过 `epoch` 去标识，它是一个计数器，表示第几轮投票。所有 sentinel 节点第一轮投票从 epoch == 1 开始，区别是有些 sentinel 投得快，有的投得慢，因为每个 sentinel 时钟定时执行的频率有可能不一样。

```c
char *sentinelVoteLeader(sentinelRedisInstance *master, uint64_t req_epoch, char *req_runid, uint64_t *leader_epoch) {
    /* 同步 epoch，保证多个 sentinel 数据一致性。 */
    if (req_epoch > sentinel.current_epoch) {
        sentinel.current_epoch = req_epoch;
        sentinelFlushConfig();
        sentinelEvent(LL_WARNING, "+new-epoch", master, "%llu",
                      (unsigned long long)sentinel.current_epoch);
    }

    /* 有可能出现多次选举，投票给最大一轮选举的 sentinel。*/
    if (master->leader_epoch < req_epoch && sentinel.current_epoch <= req_epoch) {
        sdsfree(master->leader);
        master->leader = sdsnew(req_runid);
        master->leader_epoch = sentinel.current_epoch;
        sentinelFlushConfig();
        sentinelEvent(LL_WARNING, "+vote-for-leader", master, "%s %llu",
                      master->leader, (unsigned long long)master->leader_epoch);
        /* 如果别人是 leader，那么先设置故障转移开始时间，使得在一个时间段内，
         * 别人在故障转移的时候，自己不能开启故障转移。 */
        if (strcasecmp(master->leader, sentinel.myid))
            master->failover_start_time = mstime() + rand() % SENTINEL_MAX_DESYNC;
    }

    *leader_epoch = master->leader_epoch;
    return master->leader ? sdsnew(master->leader) : NULL;
}
```

* 主动投票。

故障转移有很多环节，sentinel 要选举中赢得选举，成为 leader，才能完成故障转移所有环节。

当 sentinel 检测到 master 客观下线，它进入了“选举”环节，已经开启了故障转移，并统计投票选举结果。在统计票数过程中，它会根据统计结果进行主动投票：如果没人来拉票，我也没有投过票，那么可以投自己，否则自己投票数多的人。

```c
void sentinelFailoverWaitStart(sentinelRedisInstance *ri) {
    ...
    /* 统计选举结果。 */
    leader = sentinelGetLeader(ri, ri->failover_epoch);
    ...
}

/* 统计选票结果。*/
char *sentinelGetLeader(sentinelRedisInstance *master, uint64_t epoch) {
    ...
    /* 如果没人来拉票，我也没有投过票，那么可以投自己，否则自己投票数多的人。 */
    if (winner)
        myvote = sentinelVoteLeader(master, epoch, winner, &leader_epoch);
    else
        myvote = sentinelVoteLeader(master, epoch, sentinel.myid, &leader_epoch);
    ...
    return winner;
}
```

---

## 4. 统计票数

定时检查已经连接的 sentinel，统计选举情况，选出票数最多的 sentinel 为 leader。

```c
char *sentinelGetLeader(sentinelRedisInstance *master, uint64_t epoch) {
    ...
    counters = dictCreate(&leaderVotesDictType, NULL);
    voters = dictSize(master->sentinels) + 1; /* All the other sentinels and me.*/

    /* 统计别人的 sentinel 投票结果。 */
    di = dictGetIterator(master->sentinels);
    while ((de = dictNext(di)) != NULL) {
        sentinelRedisInstance *ri = dictGetVal(de);
        if (ri->leader != NULL && ri->leader_epoch == sentinel.current_epoch)
            sentinelLeaderIncr(counters, ri->leader);
    }
    dictReleaseIterator(di);

    /* Check what's the winner. For the winner to win, it needs two conditions:
     * 1) Absolute majority between voters (50% + 1).
     * 2) And anyway at least master->quorum votes. */
    di = dictGetIterator(counters);
    while ((de = dictNext(di)) != NULL) {
        uint64_t votes = dictGetUnsignedIntegerVal(de);
        if (votes > max_votes) {
            max_votes = votes;
            winner = dictGetKey(de);
        }
    }
    dictReleaseIterator(di);

    /* 前面是统计其它人的投票，现在轮到我投票，如果其它人已经投票了，那么就将自己的票投给 winner，
     * 否则自己的票就投给自己。 */
    if (winner)
        myvote = sentinelVoteLeader(master, epoch, winner, &leader_epoch);
    else
        myvote = sentinelVoteLeader(master, epoch, sentinel.myid, &leader_epoch);

    /* 统计自己的投票结果。 */
    if (myvote && leader_epoch == epoch) {
        uint64_t votes = sentinelLeaderIncr(counters, myvote);
        if (votes > max_votes) {
            max_votes = votes;
            winner = myvote;
        }
    }

    /* 选出的 winner 最少要 >= 已知 sentinel 个数的 (50% + 1)，
     * 而且 winner 票数也不能少于法定投票数量。 */
    voters_quorum = voters / 2 + 1;
    if (winner && (max_votes < voters_quorum || max_votes < master->quorum))
        winner = NULL;

    winner = winner ? sdsnew(winner) : NULL;
    sdsfree(myvote);
    dictRelease(counters);
    return winner;
}
```

---

## 5. 差异化

### 5.1. 随机时间

实际使用中，redis 集群基本都部署在局域网，当一个 master 下线，各个 sentinel 会很快感知 master 客观下线。因为 sentinel 都是通过时钟定时工作，为了让 sentinel 差异化，时钟的频率会引入随机数，这样使得各个 sentinel 差异化更接近现实。

```c
int serverCron(struct aeEventLoop *eventLoop, long long id, void *clientData) {
    ...
    /* Run the Sentinel timer if we are in sentinel mode. */
    if (server.sentinel_mode) sentinelTimer();
    ...
}

void sentinelTimer(void) {
    ...
    /* 定时器刷新频率添加随机数，添加投票的差异化。 */
    server.hz = CONFIG_DEFAULT_HZ + rand() % CONFIG_DEFAULT_HZ;
}
```

```c
/* 故障转移开始时间也会添加一个随机时间因子。*/
master->failover_start_time = mstime() + rand() % SENTINEL_MAX_DESYNC;
```

---

### 5.2. 先到先得

投票的原理是“先到先得”，如何操作才能保证 “先到先得”？如何保证在同一个时间段内，只有一个 sentinel 在进行故障转移？我们看看这个变量的巧妙利用 `master->failover_start_time`。

* 主动。

```c
/* 是否满足故障转移条件，开启故障转移。 */
int sentinelStartFailoverIfNeeded(sentinelRedisInstance *master) {
    /* master 客观下线。 */
    if (!(master->flags & SRI_O_DOWN)) return 0;

    /* 当前 master 没有处在故障转移过程中。 */
    if (master->flags & SRI_FAILOVER_IN_PROGRESS) return 0;

    /* 两次故障转移，需要有一定的时间间隔。如果别人已经开始了，
     * 那么你也需要等待一段时间，让别人在这个时间段内先跑完流程。否则自己可以开启故障转移流程。 */
    if (mstime() - master->failover_start_time < master->failover_timeout * 2) {
        ...
        return 0;
    }

    /* 满足故障转移条件，开启故障转移。 */
    sentinelStartFailover(master);
    return 1;
}

void sentinelStartFailover(sentinelRedisInstance *master) {
    ...
    /* 开启故障转移，设置故障转移时间。 */
    master->failover_start_time = mstime() + rand() % SENTINEL_MAX_DESYNC;
    ...
}
```

* 被动。当别人向你拉票的时候，说明故障转移已经开始，结合上面分析，那么当你要开启故障转移的时候，你必须等待一段时间。

```c
char *sentinelVoteLeader(sentinelRedisInstance *master, uint64_t req_epoch, char *req_runid, uint64_t *leader_epoch) {
    ...
    /* 有可能出现多次选举，投票给最大一轮选举的 sentinel。*/
    if (master->leader_epoch < req_epoch && sentinel.current_epoch <= req_epoch) {
        ...
        /* 如果投票的人不是自己，那么开启故障转移。 */
        if (strcasecmp(master->leader, sentinel.myid))
            master->failover_start_time = mstime() + rand() % SENTINEL_MAX_DESYNC;
    }
    ...
}

```

---

## 6. 参考

* [Redis源码解析：22sentinel(三)客观下线以及故障转移之选举领导节点](https://www.cnblogs.com/gqtcgq/archive/2004/01/13/7247047.html)

---

> 🔥 文章来源：[《[redis 源码走读] sentinel 哨兵 - 选举投票》](https://wenfh2020.com/2020/09/26/redis-sentinel-vote/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
