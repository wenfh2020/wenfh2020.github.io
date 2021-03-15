---
layout: post
title:  "[hiredis 源码走读] redis pipeline"
categories: redis
tags: redis hiredis pipeline
author: wenfh2020
---

pipeline 官方文档：[Using pipelining to speedup Redis queries](https://redis.io/topics/pipelining)。

---

redis 是 c/s 模式 tcp 通信服务。它支持客户端单命令发送给服务处理，也支持客户端将多个命令一次性发送。后者就是 pipeline 技术。

pipeline 好处：

1. 避免频繁发包/接包，避免时间（RTT (Round Trip Time））都浪费在通信路上。
2. 避免性能损耗，要知道，每次发送和接收数据，send() / write() 调用内核接口非常耗资源。——避免大巴车每次只载几个人...




* content
{:toc}

---

## 1. 使用

我们参考 hiredis 测试源码：[test.c](https://github.com/redis/hiredis/blob/master/test.c)。

* 同步单命令通信。

```c
num = 1000;
replies = hi_malloc_safe(sizeof(redisReply*)*num);
for (i = 0; i < num; i++) {
    replies[i] = redisCommand(c,"PING");
    assert(replies[i] != NULL && replies[i]->type == REDIS_REPLY_STATUS);
}
for (i = 0; i < num; i++) freeReplyObject(replies[i]);
hi_free(replies);
```

* 同步 pipeline 通信。

```c
num = 10000;
replies = hi_malloc_safe(sizeof(redisReply*)*num);
for (i = 0; i < num; i++) 
    redisAppendCommand(c,"PING");
for (i = 0; i < num; i++) {
    assert(redisGetReply(c, (void*)&replies[i]) == REDIS_OK);
    assert(replies[i] != NULL && replies[i]->type == REDIS_REPLY_STATUS);
}
for (i = 0; i < num; i++) freeReplyObject(replies[i]);
hi_free(replies);
```

---

## 2. 性能

压测 100w 条命令，测试源码 [github](https://github.com/wenfh2020/c_test/blob/master/redis/test_pipeline.cpp)。

### 2.1. 耗时

单命令耗费时间是 pipeline 的 10 倍。

* 单命令。

```shell
# gcc test_pipeline.cpp -o tp -lhiredis && ./tp 0 1000000
test pipeline: 0, cmd cnt: 1000000
normal test, cmd cnt: 1000000, spend time: 27626593 us.
```

* pipeline

```shell
# pipeline
# gcc test_pipeline.cpp -o tp -lhiredis && ./tp 1 1000000
test pipeline: 1, cmd cnt: 1000000
pipeline test, cmd cnt: 1000000, spend time: 2240152 us.
```

---

### 2.2. 性能

redis-server 火焰图：上图是单命令，下图是 pipeline。对比之下，单命令要耗费更多内核读写资源。

> **gettimeofday** 这个接口也不是省油的灯。

<div align=center><img src="/images/2021-03-15-14-52-33.png" data-action="zoom"/></div>

---

## 3. hiredis 客户端源码剖析

详细请参考：[hiredis github 源码](https://github.com/redis/hiredis/blob/master/hiredis.c)。

### 3.1. 单命令接口

redisCommand，发送完命令，马上阻塞等待 redis-server 回包。

```c
void *redisCommand(redisContext *c, const char *format, ...) {
    va_list ap;
    va_start(ap,format);
    void *reply = redisvCommand(c,format,ap);
    va_end(ap);
    return reply;
}

void *redisvCommand(redisContext *c, const char *format, va_list ap) {
    if (redisvAppendCommand(c,format,ap) != REDIS_OK)
        return NULL;
    return __redisBlockForReply(c);
}
```

---

### 3.2. pipeline 多命令

* 命令追加到发送缓冲区。

```c
int redisAppendCommand(redisContext *c, const char *format, ...) {
    va_list ap;
    int ret;

    va_start(ap,format);
    ret = redisvAppendCommand(c,format,ap);
    va_end(ap);
    return ret;
}

int redisvAppendCommand(redisContext *c, const char *format, va_list ap) {
    char *cmd;
    int len;

    /* 格式化接口命令。 */
    len = redisvFormatCommand(&cmd,format,ap);
    if (len == -1) {
        __redisSetError(c,REDIS_ERR_OOM,"Out of memory");
        return REDIS_ERR;
    } else if (len == -2) {
        __redisSetError(c,REDIS_ERR_OTHER,"Invalid format string");
        return REDIS_ERR;
    }

    /* 追加命令到发送缓冲区。 */
    if (__redisAppendCommand(c,cmd,len) != REDIS_OK) {
        hi_free(cmd);
        return REDIS_ERR;
    }

    hi_free(cmd);
    return REDIS_OK;
}
```

* 将发送缓冲区所有命令发送出去，然后读取 redis-server 回复集合。

```c
int redisGetReply(redisContext *c, void **reply) {
    int wdone = 0;
    void *aux = NULL;

    /* 如果读缓冲区还有回复没处理完，继续处理。 */
    if (redisGetReplyFromReader(c,&aux) == REDIS_ERR)
        return REDIS_ERR;

    /* For the blocking context, flush output buffer and read reply */
    if (aux == NULL && c->flags & REDIS_BLOCK) {
        /* 将发送缓冲区的命令集合发出去。*/
        do {
            if (redisBufferWrite(c,&wdone) == REDIS_ERR)
                return REDIS_ERR;
        } while (!wdone);

        /* Read until there is a reply */
        do {
            /* 等待服务端回复数据。 */
            if (redisBufferRead(c) == REDIS_ERR)
                return REDIS_ERR;

            /* We loop here in case the user has specified a RESP3
             * PUSH handler (e.g. for client tracking). */
            do {
                /* 读到数据，从读缓冲区里取回复。 */
                if (redisGetReplyFromReader(c,&aux) == REDIS_ERR)
                    return REDIS_ERR;
            } while (redisHandledPushReply(c, aux));
        } while (aux == NULL);
    }

    /* Set reply or free it if we were passed NULL */
    if (reply != NULL) {
        *reply = aux;
    } else {
        freeReplyObject(aux);
    }

    return REDIS_OK;
}

```

---

## 4. 参考

* [Using pipelining to speedup Redis queries](https://redis.io/topics/pipelining)
