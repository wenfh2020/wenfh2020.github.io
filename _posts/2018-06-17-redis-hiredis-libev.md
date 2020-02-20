---
layout: post
title:  "hiredis + libev 异步测试"
categories: redis
tags: redis hiredis libev
author: wenfh2020
---

用 `hiredis` 测试写命令 `set key value`，几个字节的 value，轻松 10 万+ 并发；1024 个字节的 value，10w 请求需要耗时 1.5 秒左右。所以 `hiredis` 的异步使用性能非常给力的，而且程序的性能损耗也不高。只是异步使用有点反人类，业务都要在 callback 里面处理，没有同步调用那么直观。`libev` 是一个不错的事件驱动库，在这里就不展开了。

![本地性能](/images/2020-02-20-16-56-08.png)



* content
{:toc}

---

## 测试

`hiredis` 代码提供了 `libev` 的 I/O 回调。只要绑定相关 libev 的相关回调，即可使用，代码也相对比较精简。([测试源码](https://github.com/wenfh2020/mytest/blob/master/c%2B%2B/hiredis_test/async/main.cpp))

```c
void RdsCbConnect(const redisAsyncContext* pRdsContext, int iStatus);
void RdsCbDisConnect(const redisAsyncContext* pRdsContext, int iStatus);
void RdsCbCmd(redisAsyncContext* pRdsContext, void* pReply, void* pData);

void RdsCbCmd(redisAsyncContext* pRdsContext, void* pReply, void* pData) {
    if (NULL == pReply) {
        printf("call back repplay null!\n");
        return;
    }

    redisReply* pRdsReply = (redisReply*)pReply;
    if (REDIS_REPLY_NIL == pRdsReply->type) {
        printf("reply nil\n");
        return;
    }

    //printf("%d, redis reply info: type = %d, string = %s\n", ++g_iCmdCallback, pRdsReply->type, pRdsReply->str);

    if (++g_iCmdCallback >= TEST_CMD_COUNT) {
        unsigned long long ullEndTime = GetMicrosecond();
        printf("test end time: %s, %llu, interval: %llu\n",
               GetCurrentTime().c_str(), ullEndTime, ullEndTime - g_ullBeginTime);
        redisAsyncDisconnect((redisAsyncContext*)pRdsContext);
    }
}

int main() {
    redisAsyncContext* pRdsContext = redisAsyncConnect(IP, PORT);
    if (pRdsContext->err != REDIS_OK) {
        printf("async redis connect failed! err code = %d, err msg = %s\n", pRdsContext->err, pRdsContext->errstr);
        return 1;
    }

    struct ev_loop* pLoop = EV_DEFAULT;
    redisLibevAttach(pLoop, pRdsContext);
    redisAsyncSetConnectCallback(pRdsContext, RdsCbConnect);
    redisAsyncSetDisconnectCallback(pRdsContext, RdsCbDisConnect);
    ev_run(pLoop, 0);
    return 0;
}
```

测试结果(interval 是微妙为单位的时间差)

```shell
connect call back, status = 0
test write cmd count = 100000
test begin time: 2018-06-17 08:17:43, 1529194663712890
test end time: 2018-06-17 08:17:44, 1529194664952655, interval: 1239765  
disconnect call back, status = 0
```
