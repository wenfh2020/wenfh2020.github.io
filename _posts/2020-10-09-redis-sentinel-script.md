---
layout: post
title:  "[redis 源码走读] sentinel 哨兵 - 通知第三方"
categories: redis
tags: redis sentinel script notify
author: wenfh2020
---

sentinel 监控管理 redis 节点，那么我们如何感知 sentinel 的动作？sentinel 为我们提供了很多途径：

> 详细请参考官方文档 [《Redis Sentinel Documentation》](https://redis.io/topics/sentinel)

1. 日志。
2. 事件的发布订阅，用户向 sentinel 订阅感兴趣事件。
3. 脚本通知 `sentinel notification-script <master-name> <script-path>`。
4. 也提供了命令，提供 client 获取信息，例如 `SENTINEL get-master-addr-by-name <master name>`




* content
{:toc}

---

## 1. 日志

在配置中可以开启 sentinel 日志，通过日志查看 sentinel 的工作流程。

* logfile 日志配置。

```shell
# sentinel.conf

# Specify the log file name. Also the empty string can be used to force
# Sentinel to log on the standard output. Note that if you use standard
# output for logging but daemonize, logs will be sent to /dev/null
logfile "sentinel.log"
```

* 详细日志（sentinel leader 故障转移日志，详细参考[《[redis 源码走读] sentinel 哨兵 - 故障转移》](https://wenfh2020.com/2020/09/27/redis-sentinel-failover/)）。

```shell
# sentinel.log
...
# 发现 master 6379 主观下线。
32123:X 30 Sep 2020 15:07:51.408 # +sdown master mymaster 127.0.0.1 6379
# 确认 master 6379 客观下线。
32123:X 30 Sep 2020 15:07:51.474 # +odown master mymaster 127.0.0.1 6379 #quorum 3/2
# 开始进入选举环节，选举纪元(计数器) 29。（这个测试日志不是第一次，所以纪元有历史数据。）
32123:X 30 Sep 2020 15:07:51.474 # +new-epoch 29
# 尝试对 6379 开启故障转移流程，注意：这里还没正式开启，只有在选举中获胜的 sentinel 才会正式开启。
32123:X 30 Sep 2020 15:07:51.474 # +try-failover master mymaster 127.0.0.1 6379
# 当前 sentinel 没发现其它 sentinel 向它拉票，所以它把选票投给了自己。
32123:X 30 Sep 2020 15:07:51.494 # +vote-for-leader 0400c9170654ecbaeaf98fedb1630486e5f8f5b6 29
...
# 重新连接，发现 6379 没上线，标识它为主观下线，因为它不是 master 了，不需要走确认客观下线流程。
32123:X 30 Sep 2020 15:08:23.392 # +sdown slave 127.0.0.1:6379 127.0.0.1 6379 @ mymaster 127.0.0.1 6377
# 当前 sentinel 发现旧 master 6379 重新上线，去掉它主观下线标识。
32123:X 30 Sep 2020 15:10:22.709 # -sdown slave 127.0.0.1:6379 127.0.0.1 6379 @ mymaster 127.0.0.1 6377
# 旧 master 角色还是 master，被 sentinel 降级为 slave。
32123:X 30 Sep 2020 15:10:42.730 * +convert-to-slave slave 127.0.0.1:6379 127.0.0.1 6379 @ mymaster 127.0.0.1 6377
```

---

![第三方通知流程](/images/2020-10-10-11-41-26.png){:data-action="zoom"}

## 2. 命令

sentinel 也是 redis 程序，支持 redis-client 通过命令读写访问。

例如，第三方程序，需要知道 redis 集群的 master 信息，可以通过命令 `SENTINEL get-master-addr-by-name <master name>` 进行访问。

> 其它命令详细参考官网文档 [《Redis Sentinel Documentation》](https://redis.io/topics/sentinel)

```shell
# Sentinel commands
...
SENTINEL masters Show a list of monitored masters and their state.
SENTINEL master <master name> Show the state and info of the specified master.
SENTINEL replicas <master name> Show a list of replicas for this master, and their state.
SENTINEL sentinels <master name> Show a list of sentinel instances for this master, and their state.
SENTINEL get-master-addr-by-name <master name> Return the ip and port number of the master with that name. If a failover is in progress or terminated successfully for this master it returns the address and port of the promoted replica.
...
```

---

## 3. 事件通知

事件通知函数 `sentinelEvent` 主要做了三件事：

1. 记录日志。
2. 将事件文本信息发布到对应的事件频道上，例如：
   > "+slave" 发现 slave 节点。
   >
   > "+sdown" 发现 master 主观下线。
   >
   > "+odown" 发现 master 客观下线。
   >
   > "-odown" 解除 master 客观下线。
   >
   > ...
3. 执行配置文件的脚本。

```c
/* 事件通知。 */
void sentinelEvent(int level, char *type, sentinelRedisInstance *ri, const char *fmt, ...) {
    va_list ap;
    char msg[LOG_MAX_LEN];
    robj *channel, *payload;

    /* Handle %@ */
    if (fmt[0] == '%' && fmt[1] == '@') {
        sentinelRedisInstance *master = (ri->flags & SRI_MASTER) ? NULL : ri->master;

        if (master) {
            snprintf(msg, sizeof(msg), "%s %s %s %d @ %s %s %d",
                     sentinelRedisInstanceTypeStr(ri),
                     ri->name, ri->addr->ip, ri->addr->port,
                     master->name, master->addr->ip, master->addr->port);
        } else {
            snprintf(msg, sizeof(msg), "%s %s %s %d",
                     sentinelRedisInstanceTypeStr(ri),
                     ri->name, ri->addr->ip, ri->addr->port);
        }
        fmt += 2;
    } else {
        msg[0] = '\0';
    }

    /* Use vsprintf for the rest of the formatting if any. */
    if (fmt[0] != '\0') {
        va_start(ap, fmt);
        vsnprintf(msg + strlen(msg), sizeof(msg) - strlen(msg), fmt, ap);
        va_end(ap);
    }

    /* 打印适当级别的日志。*/
    if (level >= server.verbosity)
        serverLog(level, "%s %s", type, msg);

    /* 将事件发布到指定的 "type" 频道上。 */
    if (level != LL_DEBUG) {
        channel = createStringObject(type, strlen(type));
        payload = createStringObject(msg, strlen(msg));
        pubsubPublishMessage(channel, payload);
        decrRefCount(channel);
        decrRefCount(payload);
    }

    /* 指定等级的日志，调用脚本进行输出。 */
    if (level == LL_WARNING && ri != NULL) {
        sentinelRedisInstance *master = (ri->flags & SRI_MASTER) ? ri : ri->master;
        if (master && master->notification_script) {
            /* 给脚本填充参数，时钟将会调用指定脚本。 */
            sentinelScheduleScriptExecution(master->notification_script, type, msg, NULL);
        }
    }
}
```

---

### 3.1. 脚本通知

脚本通知，原理很简单，sentinel 只做了两件事：

1. 调用指定路径的脚本文件。
2. 给调用的脚本进程传递参数。

* sentinel.conf 配置。

```shell
# sentinel.conf
sentinel notification-script mymaster /var/redis/notify.sh
```

* notify.sh，这个脚本是自定义的，根据需要编写对应的脚本功能。这里为了测试，脚本输出参数内容到本地日志：nofify.log。

```shell
#!/bin/sh
echo $* >> /tmp/nofify.log
```

* nofify.log 日志内容，sentinel 根据对应业务事件传递对应文本参数，我们可以处理感兴趣的参数，例如："+sdown"，“+switch-master” 等。现实中，每个 sentinel 都应该配置脚本，所以有些事件每个 sentinel 都会触发，有些事件只有 leader 角色才会触发，例如故障转移 “+switch-master” ，只有一个 sentinel 触发。

![故障转移测试环节](/images/2020-09-30-16-47-51.png){:data-action="zoom"}

```shell
# /tmp/nofify.log
# 三个 sentinel 每个都发现 6379 节点主观下线。
+sdown master mymaster 127.0.0.1 6379
+sdown master mymaster 127.0.0.1 6379
+sdown master mymaster 127.0.0.1 6379
# 三个 sentinel 开启选举，进行拉票投票。
+new-epoch 37
+vote-for-leader 989f0e00789a0b41cff738704ce8b04bad306714 37
+try-failover master mymaster 127.0.0.1 6379
+odown master mymaster 127.0.0.1 6379 #quorum 2/2
+vote-for-leader 989f0e00789a0b41cff738704ce8b04bad306714 37
+odown master mymaster 127.0.0.1 6379 #quorum 3/2
+new-epoch 37
+new-epoch 37
+vote-for-leader 989f0e00789a0b41cff738704ce8b04bad306714 37
# 一个 989f0e00789a0b41cff738704ce8b04bad306714 被选举为 leader 进行故障转移。
+failover-state-select-slave master mymaster 127.0.0.1 6379
+elected-leader master mymaster 127.0.0.1 6379
+selected-slave slave 127.0.0.1:6377 127.0.0.1 6377 @ mymaster 127.0.0.1 6379
+promoted-slave slave 127.0.0.1:6377 127.0.0.1 6377 @ mymaster 127.0.0.1 6379
+failover-state-reconf-slaves master mymaster 127.0.0.1 6379
+switch-master mymaster 127.0.0.1 6379 127.0.0.1 6377
+config-update-from sentinel 989f0e00789a0b41cff738704ce8b04bad306714 127.0.0.1 26378 @ mymaster 127.0.0.1 6379
+switch-master mymaster 127.0.0.1 6379 127.0.0.1 6377
+config-update-from sentinel 989f0e00789a0b41cff738704ce8b04bad306714 127.0.0.1 26378 @ mymaster 127.0.0.1 6379
-odown master mymaster 127.0.0.1 6379
+switch-master mymaster 127.0.0.1 6379 127.0.0.1 6377
# 故障转移结束。
+failover-end master mymaster 127.0.0.1 6379
# 旧 master 被 leader 设置为新 master 的 slave，但是它处在下线状态。三个sentinel 都同步了数据，发现它主观下线。
+sdown slave 127.0.0.1:6379 127.0.0.1 6379 @ mymaster 127.0.0.1 6377
+sdown slave 127.0.0.1:6379 127.0.0.1 6379 @ mymaster 127.0.0.1 6377
+sdown slave 127.0.0.1:6379 127.0.0.1 6379 @ mymaster 127.0.0.1 6377
# 三个 sentinel 发现旧 master 重新上线，去掉主观下线标识。
-sdown slave 127.0.0.1:6379 127.0.0.1 6379 @ mymaster 127.0.0.1 6377
-sdown slave 127.0.0.1:6379 127.0.0.1 6379 @ mymaster 127.0.0.1 6377
-sdown slave 127.0.0.1:6379 127.0.0.1 6379 @ mymaster 127.0.0.1 6377
```

* 脚本调用流程。

```c
/* 定时处理脚本。 */
void sentinelTimer(void) {
    ...
    /* fork 子进程执行等待启动的脚本。 */
    sentinelRunPendingScripts();
    /* 检查脚本是否运行完成，回收数据。 */
    sentinelCollectTerminatedScripts();
    /* 关闭超时脚本。*/
    sentinelKillTimedoutScripts();
    ...
}

/* 通过 fork 子进程，执行脚本。*/
void sentinelRunPendingScripts(void) {
    ...
    while (sentinel.running_scripts < SENTINEL_SCRIPT_MAX_RUNNING &&
           (ln = listNext(&li)) != NULL) {
        ...
        pid = fork();

        if (pid == -1) {
            ...
        } else if (pid == 0) {
            /* 执行脚本。 */
            execve(sj->argv[0], sj->argv, environ);
            /* If we are here an error occurred. */
            _exit(2); /* Don't retry execution. */
        } else {
            ...
        }
    }
}
```

---

## 4. 参考

* [Redis Sentinel for monitoring purposes? Notification script fires off too many times](https://stackoverflow.com/questions/34645391/redis-sentinel-for-monitoring-purposes-notification-script-fires-off-too-many-t)

---

> 🔥 文章来源：[《[redis 源码走读] sentinel 哨兵 - 故障转移》](https://wenfh2020.com/2020/09/27/redis-sentinel-failover/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
