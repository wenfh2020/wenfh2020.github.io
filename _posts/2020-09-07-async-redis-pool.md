---
layout: post
title:  "[kimserver] redis 异步连接池"
categories: kimserver redis
tags: redis hiredis pool
author: wenfh2020
---

链接池主要封装了 `hiredis`，因为这个 redis client 已经足够高效：异步功能，轻松并发 10w+，单进程的异步服务，一个链接基本可以满足正常的读写。其它就是简单封装了一些接口，方便使用操作。


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
kim::RedisMgr* g_mgr = nullptr;

void on_redis_callback(redisAsyncContext* c, void* reply, void* privdata) {...}

int main(int args, char** argv) {
    ...
    struct ev_loop* loop = EV_DEFAULT;
    g_mgr = new kim::RedisMgr(m_logger, loop);
    if (!g_mgr->init(config["redis"])) {
        LOG_ERROR("init redis g_mgr failed!");
        return 1;
    }
    ...
    std::vector<std::string> read_cmds{"get", "key"};
    std::vector<std::string> write_cmds{"set", "key", "hello world!"};
    for (int i = 0; i < g_test_cnt; i++) {
        user_data_t* d = new user_data_t(++g_send_cnt);
        g_mgr->send_to("test", g_is_write ? write_cmds : read_cmds, on_redis_callback, (void*)d);
    }
    ev_run(loop, 0);
    ...
}
```

---

### 2.4. 性能

本地测试写数据：测试 1,000,000 个包，并发 37,6732 / s，可能机器配置比较好，所以感觉并发数据好到有点夸张。

虽然测试命令比较简单，但是也反映了这个异步读写 redis 确实高效。

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

---

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/2020/08/30/kimserver-async-mysql/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>