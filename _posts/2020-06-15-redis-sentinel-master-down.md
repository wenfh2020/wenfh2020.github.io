---
layout: post
title:  "[redis 源码走读] sentinel 哨兵 - 主客观下线"
categories: redis
tags: redis sentinel SubjectivelyDown ObjectivelyDown 
author: wenfh2020
---

redis 哨兵集群有 3 个角色：sentinel/master/slave，每个角色都可能出现故障，故障转移主要针对 <font color='red'>master</font>，而且故障转移是个复杂的工作流程。在分布式系统中，多个节点要保证数据一致性，需要相互通信协调，要经历几个环节：

> master 主观下线 --> master 客观下线 --> 投票选举 leader --> leader 执行故障转移。

本章重点走读 redis 源码，理解 sentinel 检测 master 节点的主客观下线流程。




* content
{:toc}

---

## 1. 故障转移流程

1. sentinel 时钟定时检查监控的各个 redis 实例角色，是否通信异常。
2. 发现 master 主观下线。
3. 向其它 sentinel 节点询问它们是否也检测到该 master 主观下线。
4. sentinel 通过询问，确认 master 客观下线。
5. 进入选举环节，sentinel 向其它 sentinel 节点拉票，希望它们选自己为代表进行故障转移。
6. 少数服从多数，当超过法定 sentinel 个数选择某个 sentinel 为代表。
7. sentinel 代表执行故障转移。

```c
void sentinelHandleRedisInstance(sentinelRedisInstance *ri) {
    ...
    /* 检查 sentinel 是否处在异常状态，例如本地时间忽然改变，因为心跳通信等，依赖时间。*/
    if (sentinel.tilt) {
        if (mstime() - sentinel.tilt_start_time < SENTINEL_TILT_PERIOD) return;
        sentinel.tilt = 0;
        sentinelEvent(LL_WARNING, "-tilt", NULL, "#tilt mode exited");
    }

    /* 检查所有节点类型 sentinel/master/slave，是否主观下线。*/
    sentinelCheckSubjectivelyDown(ri);
    ...
    if (ri->flags & SRI_MASTER) {
        /* 检查 master 是否客观下线。 */
        sentinelCheckObjectivelyDown(ri);
        /* 是否满足故障转移条件，开启故障转移。 */
        if (sentinelStartFailoverIfNeeded(ri))
            /* 满足条件，进入故障转移环节，马上向其它 sentinel 节点选举拉票。 */
            sentinelAskMasterStateToOtherSentinels(ri, SENTINEL_ASK_FORCED);
        /* 通过状态机，处理故障转移对应各个环节。 */
        sentinelFailoverStateMachine(ri);
        /* 定时向其它 sentinel 节点询问 master 主观下线状况或选举拉票。 */
        sentinelAskMasterStateToOtherSentinels(ri, SENTINEL_NO_FLAGS);
    }
}
```

---

## 2. 故障发现

### 2.1. 主观下线

主要检查节点间的 <font color=red>心跳</font> 通信是否正常。

* 检测异步链接是否超时，超时则关闭链接。
* 检测心跳是否超时，超时则标识主观下线，否则恢复正常。
* master 角色误报，超时标识主观下线。

```c
void sentinelCheckSubjectivelyDown(sentinelRedisInstance *ri) {
    mstime_t elapsed = 0;

    /* 通过心跳通信间隔判断掉线逻辑。 */
    if (ri->link->act_ping_time)
        elapsed = mstime() - ri->link->act_ping_time;
    else if (ri->link->disconnected)
        elapsed = mstime() - ri->link->last_avail_time;

    /* tcp 异步链接通信超时关闭对应链接。 */
    ...

    /* 主观下线
     * 1. 心跳通信超时。
     * 2. 主服务节点却上报从服务角色，异常情况超时。 */
    if (elapsed > ri->down_after_period ||
        (ri->flags & SRI_MASTER &&
         ri->role_reported == SRI_SLAVE &&
         mstime() - ri->role_reported_time >
             (ri->down_after_period + SENTINEL_INFO_PERIOD * 2))) {
        /* Is subjectively down */
        if ((ri->flags & SRI_S_DOWN) == 0) {
            sentinelEvent(LL_WARNING, "+sdown", ri, "%@");
            ri->s_down_since_time = mstime();
            ri->flags |= SRI_S_DOWN;
        }
    } else {
        /* 被标识为主观下线的节点，恢复正常，去掉主观下线标识。*/
        if (ri->flags & SRI_S_DOWN) {
            sentinelEvent(LL_WARNING, "-sdown", ri, "%@");
            ri->flags &= ~(SRI_S_DOWN | SRI_SCRIPT_KILL_SENT);
        }
    }
}
```

---

### 2.2. 客观下线

* 询问主观下线。

当 sentinel 检测到 master 主观下线，它会询问其它 sentinel（发送 IS-MASTER-DOWN-BY-ADDR 请求）：是否也检测到该 master 已经主观下线了。

---

`SENTINEL IS-MASTER-DOWN-BY-ADDR` 命令有两个作用：

1. 询问其它 sentinel 节点，该 master 是否已经主观下线。命令最后一个参数为 <*>。
2. 确认 master 客观下线，当前 sentinel 向其它 sentinel 拉选票，让其它 sentinel 选自己为 “代表”。命令最后一个参数为 <sentinel_runid>，sentinel 自己的 runid。

这里是 sentinel 发现了 master 主观下线，所以先进入询问环节，再进行选举拉票。

---

```shell
# is-master-down-by-addr 命令格式。
SENTINEL is-master-down-by-addr <masterip> <masterport> <sentinel.current_epoch> <*>
```

```c
/* If we think the master is down, we start sending
 * SENTINEL IS-MASTER-DOWN-BY-ADDR requests to other sentinels
 * in order to get the replies that allow to reach the quorum
 * needed to mark the master in ODOWN state and trigger a failover. */
#define SENTINEL_ASK_FORCED (1 << 0)

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

* 其它 sentinel 接收命令。

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
            leader = sentinelVoteLeader(ri, (uint64_t)req_epoch, c->argv[5]->ptr, &leader_epoch);
        }

        /* 根据询问主观下线或投票选举业务确定回复的内容参数。 */
        addReplyArrayLen(c, 3);
        addReply(c, isdown ? shared.cone : shared.czero);
        addReplyBulkCString(c, leader ? leader : "*");
        addReplyLongLong(c, (long long)leader_epoch);
        if (leader) sdsfree(leader);
    }
    ...
}
```

* 当前 sentinel 接收命令回复。

当前 sentinel 接收到询问的回复，如果确认该 master 已经主观下线，那么将其标识为 `SRI_MASTER_DOWN`。

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
            /* ri sentinel 回复，也检测到该 master 节点已经主观下线。 */
            ri->flags |= SRI_MASTER_DOWN;
        } else {
            ri->flags &= ~SRI_MASTER_DOWN;
        }
        if (strcmp(r->element[1]->str, "*")) {
            /* 当前 sentinel 向 ri 拉选票，ri 回复它选举的情况。 */
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

#### 2.2.1. 确认客观下线

当 >= 法定个数（quorum）的 sentinel 节点确认该 master 主观下线，那么标识当前主观下线的 master 被标识为客观下线。

```c
void sentinelCheckObjectivelyDown(sentinelRedisInstance *master) {
    dictIterator *di;
    dictEntry *de;
    unsigned int quorum = 0, odown = 0;

    if (master->flags & SRI_S_DOWN) {
        /* Is down for enough sentinels? */
        quorum = 1; /* the current sentinel. *
        /* Count all the other sentinels. */
        di = dictGetIterator(master->sentinels);
        while ((de = dictNext(di)) != NULL) {
            sentinelRedisInstance *ri = dictGetVal(de);
            /* 该 ri 检测到 master 主观掉线。 */
            if (ri->flags & SRI_MASTER_DOWN) {
                quorum++;
            }
        }
        dictReleaseIterator(di);
        /* 是否满足当前 sentinel 配置的法定个数：quorum。 */
        if (quorum >= master->quorum) odown = 1;
    }

    /* Set the flag accordingly to the outcome. */
    if (odown) {
        if ((master->flags & SRI_O_DOWN) == 0) {
            sentinelEvent(LL_WARNING, "+odown", master, "%@ #quorum %d/%d",
                          quorum, master->quorum);
            master->flags |= SRI_O_DOWN;
            master->o_down_since_time = mstime();
        }
    } else {
        if (master->flags & SRI_O_DOWN) {
            sentinelEvent(LL_WARNING, "-odown", master, "%@");
            master->flags &= ~SRI_O_DOWN;
        }
    }
}
```

---

## 3. 参考

* [raft 论文翻译](https://github.com/maemual/raft-zh_cn/blob/master/raft-zh_cn.md)
* [raft 算法官网](https://raft.github.io)
* [raft 算法原理](http://thesecretlivesofdata.com/raft/)
* [Redis Sentinel 高可用原理](https://521-wf.com/archives/356.html)
* [Redis源码解析：21sentinel(二)定期发送消息、检测主观下线](https://www.cnblogs.com/gqtcgq/p/7247048.html)
* [Redis源码解析：22sentinel(三)客观下线以及故障转移之选举领导节点](https://www.cnblogs.com/gqtcgq/archive/2004/01/13/7247047.html)

---

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/2019/12/27/redis-split-brain/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
