---
layout: post
title:  "[kimserver] libev + hiredis redis 异步连接池"
categories: kimserver redis hiredis
tags: redis hiredis pool
author: wenfh2020
---

[kimserver](https://github.com/wenfh2020/kimserver) 网络库基于 `libev`，redis 异步链接池主要封装了 `hiredis`，它足够高效：

1. 单进程（单线程）的异步服务，轻松并发 10w+，。
2. 一个 `redis - ip:port` 对应一个链接基本可以满足正常的读写。
3. 其它简单封装了一些接口，方便对多个 redis 节点进行操作。




* content
{:toc}

---

## 1. hiredis 异步接口

redis 链接池实现， 参考 hiredis 的 libev 异步测试[例子](https://github.com/redis/hiredis/blob/master/examples/example-libev.c)。

> hiredis 详细异步原理可以参考文章：《[[hiredis 源码走读] 异步回调机制剖析](https://wenfh2020.com/2020/08/04/hiredis-callback/)》

hiredis 异步接口：

```c
static int redisLibevAttach(EV_P_ redisAsyncContext *ac);
int redisAsyncSetConnectCallback(redisAsyncContext *ac, redisConnectCallback *fn);
int redisAsyncSetDisconnectCallback(redisAsyncContext *ac, redisDisconnectCallback *fn);
int redisAsyncCommandArgv(redisAsyncContext *ac, redisCallbackFn *fn, void *privdata, int argc, const char **argv, const size_t *argvlen);
```

---

## 2. 链接池

### 2.1. 配置

redis 连接池通过 (node) 节点管理链接的 ip 和 port 信息。下面 json 配置文件里 "redis" 单元的 "test" 节点。

```json
{
    "redis": {
        "test": {
            "host": "127.0.0.1",
            "port": 6379
        }
    },
}
```

---

### 2.2. 接口

链接池主要两个接口，初始化 redis 的链接信息 (ip/port)，以及发送命令接口。

```c++
class RedisMgr {
    ...
    /*
     * 初始化 redis 配置节点信息(ip/port)
     * config: json 配置信息结构。
     */
    bool init(CJsonObject& config);
    /*
     * 发送 redis 命令。
     * node: 链接节点信息。
     * argv: redis 命令参数。
     * fn: 命令回调函数指针。
     * privdata: 回调的自定义信息。
     */
    bool send_to(const char* node, const std::vector<std::string>& argv, redisCallbackFn* fn, void* privdata);
    ...
};
```

---

### 2.3. 测试实现

详细源码在 ([github](https://github.com/wenfh2020/kimserver/blob/master/src/test/test_redis/test_redis.cpp))。

```c++
/* redis 异步连接池对象指针。 */
kim::RedisMgr* g_mgr = nullptr;

/* redis 命令回调函数。 */
void on_redis_callback(redisAsyncContext* c, void* reply, void* privdata) {...}

int main(int args, char** argv) {
    ...
    struct ev_loop* loop = EV_DEFAULT;
    g_mgr = new kim::RedisMgr(m_logger, loop);
    /* 初始化连接池，从 json 配置文件读入 redis 相关连接信息。 */
    if (!g_mgr->init(config["redis"])) {
        LOG_ERROR("init redis g_mgr failed!");
        return 1;
    }
    ...
    /* redis 读写命令。 */
    std::vector<std::string> read_cmds{"get", "key"};
    std::vector<std::string> write_cmds{"set", "key", "hello world!"};
    for (int i = 0; i < g_test_cnt; i++) {
        user_data_t* d = new user_data_t(++g_send_cnt);
        /* 发送 redis 命令到 redis test（参考配置）节点。 */
        g_mgr->send_to("test", g_is_write ? write_cmds : read_cmds, on_redis_callback, (void*)d);
    }
    /* 运行 libev 异步服务。 */
    ev_run(loop, 0);
    ...
}
```

---

### 2.4. 性能

本地测试写数据：测试 1,000,000 个包，并发 37,6732 / s，可能机器配置比较好，所以感觉并发数据好到有点夸张。

虽然测试命令比较简单，但是也反映了异步读写 redis 确实高效。

```shell
# make clean; make && ./test_redis write 1000000
spend time: 2.65439
avg:        376732
callback cnt:     1000000
err callback cnt: 0
```

---

## 3. 参考

* [[hiredis 源码走读] 异步回调机制剖析](https://wenfh2020.com/2020/08/04/hiredis-callback/)
