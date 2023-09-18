---
layout: post
title:  "[redis 源码走读] sentinel 哨兵 - 选举投票"
categories: redis
tags: redis sentinel vote 
author: wenfh2020
---

投票原理："先到先得"，每个 sentinel 机会是对等的，都有投票权利。

当前 sentienl 节点，确认某个 master 客观下线后，它会主动开启故障转移的选举环节，进行拉票（选自己）和投票（选别人）。

经过票数统计，在最新一轮的选举过程中，超过法定数量（一般过半数）的 sentinel 投票给某个 sentinel 节点时，那么它就当选 leader，选举结束后，由它去执行其它剩余的故障转移步骤。





* content
{:toc}

---

## 1. 选举整体流程

下面是伪代码的执行流程。

<div align=center><img src="/images/2023/2023-09-15-16-42-11.png" data-action="zoom"/></div>

```shell
# 只有检查到 master 客观掉线了才会去询问，在确认客观下线了，马上进行多轮选举，直到选出 leader。
|-- main
    # 定时检测处理故障。
    |-- sentinelTimer
        |-- server.hz = CONFIG_DEFAULT_HZ + rand() % CONFIG_DEFAULT_HZ;
        |-- sentinelHandleDictOfRedisInstances(sentinel.masters);
            |-- sentinelHandleRedisInstance(ri);
                # 通过 PING/INFO/PUBLISH 协议定时给集群其它节点发送数据，使得集群紧密联系起来。
                |-- sentinelSendPeriodicCommands(ri);
                    # 往 __sentinel__:hello 频道发布数据。
                    |-- sentinelSendHello(ri)
                        # 定时更新 master 的选举纪元 current_epoch，使得整个集群保持选举纪元数据一致。
                        |-- <ip>,<port>,<runid>,<current_epoch>,<master_name>,<master_ip>,<master_port>,<master_config_epoch>
                # 检查节点是否已经主观下线（所有类型的节点 sentinel/master/slave）。
                |-- sentinelCheckSubjectivelyDown(ri);
                # 检测 master 节点是否客观下线。
                |-- sentinelCheckObjectivelyDown(ri);
                    |-- if (master->flags & SRI_S_DOWN)
                        # 统计已检测到该 master 节点下线的 sentinel 节点个数，如果总数大于法定人数，就确认某个 master 节点客观下线。
                        |-- if (quorum >= master->quorum) odown = 1;
                        # 确认客观下线后，设置标识。
                        |-- odown ? master->flags |= SRI_O_DOWN : master->flags &= ~SRI_O_DOWN;
                # 如果检测到 master 节点是客观下线，马上开启进入故障转移的选举投票环节。
                |-- if (sentinelStartFailoverIfNeeded(ri))
                        # 满足选举投票条件，进入新一轮的投票环节。
                        |-- if ((master->flags & SRI_O_DOWN) && !(master->flags & SRI_FAILOVER_IN_PROGRESS))
                                |-- sentinelStartFailover(master);
                                    # 进入投票环节。
                                    |-- master->failover_state = SENTINEL_FAILOVER_STATE_WAIT_START; 
                                    # 设置故障转移状态为开启状态（选举投票）。
                                    |-- master->flags |= SRI_FAILOVER_IN_PROGRESS; 
                                    # 设置当前投票纪元（标识当前 sentinel 发起的投票是第几轮投票）
                                    |-- master->failover_epoch = ++sentinel.current_epoch;
                        # 刚开启新一轮的选举，强制马上执行拉票动作。
                        |-- sentinelAskMasterStateToOtherSentinels(ri, SENTINEL_ASK_FORCED); 
                # 故障转移流程状态机。
                |-- sentinelFailoverStateMachine(ri);
                    # 投票环节。
                    |-- SENTINEL_FAILOVER_STATE_WAIT_START:
                        |-- sentinelFailoverWaitStart(ri);
                            # 定时统计选票。
                            |-- leader = sentinelGetLeader(ri, ri->failover_epoch); 
                                         # 先统计当前接收到的选票，暂时将获得票数最多的 sentinel 节点确定为 winner。
                                         |-- ...
                                         # 然后再统计自己的投票。
                                         |-- if (winner)
                                             # 在新一轮的选举中将自己的选票投给获得票数最多的 winnder。
                                             |-- myvote = sentinelVoteLeader(master, epoch, winner, &leader_epoch);
                                                          # 刷新最新选举纪元。
                                                          |-- if (req_epoch > sentinel.current_epoch)
                                                              |-- sentinel.current_epoch = req_epoch;
                                                          # 在新一轮选举中，将票投给对应的 sentinel 节点（req_runid）
                                                          |-- if (master->leader_epoch < req_epoch && sentinel.current_epoch <= req_epoch)
                                                              |-- master->leader = sdsnew(req_runid);
                                                              |-- master->leader_epoch = sentinel.current_epoch;
                                                              # 如果其它 sentinel 节点获得选票，那么当前 sentinel 节点需延后自己进入下一轮选举的时间。
                                                              |-- if (strcasecmp(master->leader, sentinel.myid))
                                                                  master->failover_start_time = mstime() + rand() % SENTINEL_MAX_DESYNC;
                                                          |-- return master->leader ? sdsnew(master->leader) : NULL;
                                         |-- else
                                             # 在新一轮选举中，如果当前 sentinel 节点暂时没发现别的 sentinel 节点获得选票，就将票投给自己。
                                             |-- myvote = sentinelVoteLeader(master, epoch, sentinel.myid, &leader_epoch);
                                         # 如果 winner 获得超过法定人数的选票，那么它就获选 leader。
                                         |-- voters_quorum = voters/2+1;
                                         |-- if (winner && (max_votes < voters_quorum || max_votes < master->quorum))
                                             |-- winner = NULL;
                                         |-- return winner;
                            |-- isleader = leader && strcasecmp(leader, sentinel.myid) == 0;
                            # 通过票数统计，选出 leader，如果这个 leader 是自己，那么马上进入下一个故障转移环节。
                            |-- if (isleader)
                                |-- ri->failover_state = SENTINEL_FAILOVER_STATE_SELECT_SLAVE;
                            |-- else
                                # 如果当前 sentinel 节点开启选举后，在预定的选举时间内，没有选出 leader，那准备进入下一轮投票。
                                |-- if (mstime() - ri->failover_start_time > election_timeout)
                                    |-- sentinelAbortFailover(ri);
                # 定时在当前一轮投票中，进行节点客观下线询问或者拉票。
                |-- sentinelAskMasterStateToOtherSentinels(ri, SENTINEL_NO_FLAGS);
    |-- ...
        # 网络端接收信息。
        |-- sentinelCommand(client *c)
            # 接收到其它 sentinel 节点客观下线询问或者拉票。
            |-- if (!strcasecmp(c->argv[1]->ptr,"is-master-down-by-addr"))
                |-- if (!sentinel.tilt && ri && (ri->flags & SRI_S_DOWN) && (ri->flags & SRI_MASTER))
                    |-- isdown = 1; # 检测到询问的 master 节点已下线。
                # 接收到其它 sentinel 节点的拉票，。
                |-- if (ri && ri->flags & SRI_MASTER && strcasecmp(c->argv[5]->ptr,"*"))
                    |-- leader = sentinelVoteLeader(ri,(uint64_t)req_epoch, c->argv[5]->ptr, &leader_epoch);
                |-- addReply(c, isdown ? shared.cone : shared.czero);
                |-- addReplyBulkCString(c, leader ? leader : "*");
        # 接收到其它 sentinel 的回复，设置客观下线，或者选举。
        |-- sentinelReceiveIsMasterDownReply
            # 根据别的 sentinel 节点的回复，设置它是否确认 master 已经下线。
            |-- if (r->element[0]->integer == 1)
                |-- ri->flags |= SRI_MASTER_DOWN;
            |-- else
                |-- ri->flags &= ~SRI_MASTER_DOWN;
            |-- if (strcmp(r->element[1]->str, "*"))
                # 接收到别的 sentinel 节点的拉票，将票投给拉票者。
                |-- ri->leader = sdsnew(r->element[1]->str);
                |-- ri->leader_epoch = r->element[2]->integer;
        # 接收其它节点的发布信息并处理。
        |-- sentinelProcessHelloMessage
            |-- sentinelProcessHelloMessage(r->element[2]->str, r->element[2]->len);
                # 刷新当前选举纪元，争取每次选举都在最新一轮的选举上进行。
                |-- if (current_epoch > sentinel.current_epoch)
                    # 更新当前的选举纪元。
                    |-- sentinel.current_epoch = current_epoch;
                    # 将当前选举纪元持久化到本地配置文件。
                    |-- sentinelFlushConfig();
```

---

## 2. 拉票

### 2.1. 发送拉票命令

拉票命令：`SENTINEL IS-MASTER-DOWN-BY-ADDR`

```shell
# is-master-down-by-addr 命令格式。
SENTINEL is-master-down-by-addr <masterip> <masterport> <sentinel.current_epoch> <sentinel_runid>
```

1. \<masterip\>， \<masterport\> 参数传输 master 的 ip 和 端口（注意：不是传 mastername，因为每个 sentinel 上配置的 name 有可能不一样）。
2. \<sentinel.current_epoch\> 选举纪元，可以理解为选举计数器，每次 sentinel 之间选举，不一定成功，有可能会进行多次，所以每次选举计数器会加 1，表示第几轮选举。
3. \<sentinel_runid\> 当前 sentinel 的 runid，因为选举投票原理是 “先到先得”。当其它 sentinel 在一轮选举中，先接收到拉票信息的，会先投给它。
   > 例如：sentinel A，B，C 三个实例，当 A 向 B，C 进行拉票。如果 B 先接收到 A 的拉票信息，那么 B 就选 A 为 leader。如果 B 在接收到 A 的拉票信息前，已接收到 C 的拉票，那么 B 已将票投给了 C，B 将会回复 "已投票给 C" 给 A。

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
                                   (master->failover_state > SENTINEL_FAILOVER_STATE_NONE) 
                                   ? sentinel.myid : "*");
        if (retval == C_OK) {
            ri->link->pending_commands++;
        }
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
            leader = sentinelVoteLeader(
                     ri, (uint64_t)req_epoch, c->argv[5]->ptr, &leader_epoch);
        }

        /* 投票选举业务确定回复的内容参数。 */
        addReplyArrayLen(c, 3);
        addReply(c, isdown ? shared.cone : shared.czero);
        addReplyBulkCString(c, leader ? leader : "*");
        addReplyLongLong(c, (long long)leader_epoch);
        if (leader) {
            sdsfree(leader);
        }
    }
    ...
}
```

---

### 2.3. 拉票回复

根据拉票回复，更新对方 sentinel 节点的投票结果。

```c
/* Receive the SENTINEL is-master-down-by-addr reply, see the
 * sentinelAskMasterStateToOtherSentinels() function for more information. */
void sentinelReceiveIsMasterDownReply(
    redisAsyncContext *c, void *reply, void *privdata) {
    ...
    if (r->type == REDIS_REPLY_ARRAY && r->elements == 3 &&
        r->element[0]->type == REDIS_REPLY_INTEGER &&
        r->element[1]->type == REDIS_REPLY_STRING &&
        r->element[2]->type == REDIS_REPLY_INTEGER) {
        ri->last_master_down_reply_time = mstime();
        if (r->element[0]->integer == 1) {
            /* ri sentinel 回复：它也检测到该 master 节点已经下线。 */
            ri->flags |= SRI_MASTER_DOWN;
        } else {
            ri->flags &= ~SRI_MASTER_DOWN;
        }
        if (strcmp(r->element[1]->str, "*")) {
            /* 当前 sentinel 向 ri 拉选票，ri 回复：它已将票投给某个 sentinel（runid）。*/
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

sentinel 的投票（`sentinelVoteLeader`）有两种方式：

1. 被动：接收到别人的拉票请求，给对方进行投票。
2. 主动：在最新一轮的选举过程中，经过票数统计，主动给票数最多的 winner 投票，因为它当选几率最大，如果其它 sentinel 节点还没获得选票，那么就把票投给自己。

* 投票。

```c
char *sentinelVoteLeader(sentinelRedisInstance *master, 
    uint64_t req_epoch, char *req_runid, uint64_t *leader_epoch) {
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

* 被动投票。

```c
void sentinelCommand(client *c) {
    ...
    else if (!strcasecmp(c->argv[1]->ptr,"is-master-down-by-addr")) {
        ...
        if (ri && ri->flags & SRI_MASTER && strcasecmp(c->argv[5]->ptr,"*")) {
            leader = sentinelVoteLeader(ri,(uint64_t)req_epoch,
                                            c->argv[5]->ptr,
                                            &leader_epoch);
        }
        ...
        addReplyBulkCString(c, leader ? leader : "*");
        addReplyLongLong(c, (long long)leader_epoch);
        ...
    }
    ...
}
```

* 主动投票。

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

服务端的网络一般比较流畅，当一个 master 下线，各个 sentinel 节点会很快就会感知到。

因为 sentinel 都是通过时钟定时工作，为了提高选举的成功率，需要对 sentinel 开启选举进行差异化，因此对时钟频率会引入随机数。

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

投票的原理是 “先到先得”，如何操作才能保证 “先到先得”？如何保证在同一个时间段内，只有一个 sentinel 在进行故障转移？我们看看这个变量的巧妙利用 `master->failover_start_time`。

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
    /* 设定故障转移的选举纪元，标识第几轮选举。*/
    master->failover_epoch = ++sentinel.current_epoch;
    ...
    /* 延缓下一轮选举时间。*/
    master->failover_start_time = mstime() + rand() % SENTINEL_MAX_DESYNC;
    ...
}
```

* 被动。当别人向你拉票的时候，说明故障转移已经开始，结合上面分析，那么当你要开启故障转移的时候，你必须等待一段时间。

```c
char *sentinelVoteLeader(sentinelRedisInstance *master,
    uint64_t req_epoch, char *req_runid, uint64_t *leader_epoch) {
    ...
    /* 有可能出现多次选举，投票给最大一轮选举的 sentinel。*/
    if (master->leader_epoch < req_epoch && sentinel.current_epoch <= req_epoch) {
        ...
        if (strcasecmp(master->leader, sentinel.myid))
            /* 如果别人已获选，那么它在该轮选举中当选 leader 的几率非常高，
             * 那么自己要延缓开启下一轮选举的时间，不要与它发生冲突。*/
            master->failover_start_time = mstime() + rand() % SENTINEL_MAX_DESYNC;
    }
    ...
}
```

---

## 6. 参考

* [Redis源码解析：22sentinel(三)客观下线以及故障转移之选举领导节点](https://www.cnblogs.com/gqtcgq/archive/2004/01/13/7247047.html)
