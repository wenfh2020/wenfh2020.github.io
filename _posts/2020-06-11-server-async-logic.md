---
layout: post
title:  "高性能服务异步通信逻辑"
categories: 网络
tags: async
author: wenfh2020
---

最近整理了一下服务程序异步通信逻辑思路。异步逻辑与同步逻辑处理差别比较大，异步逻辑可能涉及多次回调才能完成一个完整的请求处理，逻辑被碎片化，切分成串行的步骤。习惯了写同步逻辑的朋友，有可能思维上转不过来。



* content
{:toc}

---

## 1. 逻辑

* 高性能异步非阻塞服务，底层一般用多路复用 I/O 模型对事件进行管理，Linux 平台用 epoll。
* epoll 支持异步事件逻辑。epoll_wait 会将就绪事件从内核中取出进行处理。
* 服务处理事件，每个 fd 对应一个事件处理器 callback 处理取出的 events。
* callback 逻辑被分散为逻辑步骤 `step`，这些步骤一般是异步串行处理，时序跟同步差不多，只是异步逻辑可能需要回调多次才能处理完一个完整的逻辑。

![高性能异步框架通信流程](/images/2020-06-11-21-28-24.png){:data-action="zoom"}

> 设计图来源：《[异步服务框架通信流程](https://www.processon.com/view/5ee1d7de7d9c084420107b53)》

---

## 2. redis 源码逻辑

正常逻辑一般有 N 个步骤，异步逻辑不同之处，通过 callback 逻辑实现，与同步比较确实有点反人类。callback 回调回来还能定位到原来执行体，关键点在于 `privdata`。

我们看看 redis 的 callback 逻辑。（[github 源码](https://github.com/redis/redis/blob/unstable/src/sentinel.c)）

* 事件结构。

```c
typedef struct redisAeEvents {
    redisAsyncContext *context;
    aeEventLoop *loop;
    int fd;
    int reading, writing;
} redisAeEvents;
```

* 添加读事件，将 privdata (`redisAeEvents`) 与对应事件，对应回调函数绑定。

```c
static void redisAeAddRead(void *privdata) {
    redisAeEvents *e = (redisAeEvents*)privdata;
    aeEventLoop *loop = e->loop;
    if (!e->reading) {
        e->reading = 1;
        aeCreateFileEvent(loop,e->fd,AE_READABLE,redisAeReadEvent,e);
    }
}
```

* 回调。

```c
static void redisAeReadEvent(aeEventLoop *el, int fd, void *privdata, int mask) {
    ((void)el); ((void)fd); ((void)mask);

    redisAeEvents *e = (redisAeEvents*)privdata;
    redisAsyncHandleRead(e->context);
}
```

---

## 3. 状态机

用状态机实现异步逻辑是常用做法，异步逻辑本来已经很复杂了，状态机如果设计复杂，那将会增加项目的复杂度。所以状态机用 `switch` 实现，简简单单就足够了。

下面的测试代码写得比较粗糙，只实现了简单的几个操作，就有几十行代码了。用 (python/golang) 协程，源码可控制在 20 行以内，而且也能一定程度上兼顾性能。

> 在一些致力于敏捷研发的团队，用 callback 写异步逻辑不是一个明智的做法，非性能瓶颈，不建议使用异步逻辑去写业务。毕竟快速交付项目，推进业务，才是目标。而且很多时候，增加几台机器的成本，远远低于增加一个员工。

[github 测试源码](https://github.com/wenfh2020/kimserver/blob/master/src/module/cmd_test_redis.h)

```c++
namespace kim {

enum E_STEP {
    E_STEP_PARSE_REQUEST = 0,
    E_STEP_REDIS_SET,
    E_STEP_REDIS_SET_CALLBACK,
    E_STEP_REDIS_GET,
    E_STEP_REDIS_GET_CALLBACK,
};

Cmd::STATUS CmdTestRedis::execute_steps(int err, void* data) {
    int port = 6379;
    std::string host("127.0.0.1");

    switch (get_exec_step()) {
        case E_STEP_PARSE_REQUEST: {
            const HttpMsg* msg = m_req->get_http_msg();
            if (msg == nullptr) {
                return Cmd::STATUS::ERROR;
            }

            LOG_DEBUG("cmd test redis, http path: %s, data: %s",
                      msg->path().c_str(), msg->body().c_str());

            CJsonObject req_data(msg->body());
            if (!req_data.Get("key", m_key) ||
                !req_data.Get("value", m_value)) {
                LOG_ERROR("invalid request data! pls check!");
                return response_http(ERR_FAILED, "invalid request data");
            }
            return execute_next_step(err, data);
        }
        case E_STEP_REDIS_SET: {
            LOG_DEBUG("step redis set, key: %s, value: %s", m_key.c_str(), m_value.c_str());
            std::vector<std::string> rds_cmds{"set", m_key, m_value};
            Cmd::STATUS status = redis_send_to(host, port, rds_cmds);
            if (status == Cmd::STATUS::ERROR) {
                return response_http(ERR_FAILED, "redis failed!");
            }
            return status;
        }
        case E_STEP_REDIS_SET_CALLBACK: {
            redisReply* reply = (redisReply*)data;
            if (err != ERR_OK || reply == nullptr ||
                reply->type != REDIS_REPLY_STATUS || strncmp(reply->str, "OK", 2) != 0) {
                LOG_ERROR("redis set data callback failed!");
                return response_http(ERR_FAILED, "redis set data callback failed!");
            }
            LOG_DEBUG("redis set callback result: %s", reply->str);
            return execute_next_step(err, data);
        }
        case E_STEP_REDIS_GET: {
            std::vector<std::string> rds_cmds{"get", m_key};
            Cmd::STATUS status = redis_send_to(host, port, rds_cmds);
            if (status == Cmd::STATUS::ERROR) {
                return response_http(ERR_FAILED, "redis failed!");
            }
            return status;
        }
        case E_STEP_REDIS_GET_CALLBACK: {
            redisReply* reply = (redisReply*)data;
            if (err != ERR_OK || reply == nullptr || reply->type != REDIS_REPLY_STRING) {
                LOG_ERROR("redis get data callback failed!");
                return response_http(ERR_FAILED, "redis set data failed!");
            }
            LOG_DEBUG("redis get callback result: %s, type: %d", reply->str, reply->type);
            CJsonObject rsp_data;
            rsp_data.Add("key", m_key);
            rsp_data.Add("value", m_value);
            return response_http(ERR_OK, "success", rsp_data);
        }
        default: {
            LOG_ERROR("invalid step");
            return response_http(ERR_FAILED, "invalid step!");
        }
    }
}

}  // namespace kim
```

---

## 4. 性能

用 siege 对异步 http 服务进行压力测试。服务单进程单线程支持：长连接 1.5w qps，短连接 1w qps。多进程整体的并发能力将会更大。

> 数据是通过 Mac 本子本地压测获得的，不同机器，得出的数据可能不一样，进程并发能力与物理机器配置也有直接关系。

* 长连接。

```shell
# ./http_pressure.sh
{       "transactions":                        50000,
        "availability":                       100.00,
        "elapsed_time":                         3.38,
        "data_transferred":                     3.43,
        "response_time":                        0.01,
        "transaction_rate":                 14792.90,
        "throughput":                           1.02,
        "concurrency":                         99.66,
        "successful_transactions":             50000,
        "failed_transactions":                     0,
        "longest_transaction":                  0.02,
        "shortest_transaction":                 0.00
}
```

* 短连接。

```shell
# ./http_pressure.sh
{       "transactions":                        10000,
        "availability":                       100.00,
        "elapsed_time":                         0.99,
        "data_transferred":                     0.69,
        "response_time":                        0.01,
        "transaction_rate":                 10101.01,
        "throughput":                           0.69,
        "concurrency":                         97.59,
        "successful_transactions":             10000,
        "failed_transactions":                     0,
        "longest_transaction":                  0.08,
        "shortest_transaction":                 0.00
}
```

---

## 5. 参考

* [[redis 源码走读] 事件 - 文件事件](https://wenfh2020.com/2020/04/09/redis-ae-file/)

---

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/2020/06/11/server-async-logic/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
