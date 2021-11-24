---
layout: post
title:  "[hiredis 源码走读] redis pipeline"
categories: redis hiredis
tags: redis hiredis pipeline
author: wenfh2020
---

redis 是 c/s 模式 tcp 通信服务。它支持批量命令处理（发送/接收），这就是 pipeline 技术。

> 详细请参考：[Using pipelining to speedup Redis queries](https://redis.io/topics/pipelining)




* content
{:toc}

---

## 1. 优缺点

### 1.1. 优点

1. 避免频繁发包/接包，避免时间（RTT (Round Trip Time））都浪费在通信路上。
2. 避免性能损耗，发包/接包，write() / read() 调用内核接口非常耗资源，所以每次将多个命令打包发送，每次接收多个回复包（回复集合）将减少资源损耗。——避免大巴车每次只载几个人...

---

### 1.2. 缺点

redis 集群，数据根据各种形式分片到不同实例，所以客户端如果将各个节点的数据读写命令，打包发往一个 redis 节点，往往无法达到预期，所以在使用前要做好方案调研，避免掉坑里。

---

## 2. 使用

我们参考 hiredis 测试源码：[test.c](https://github.com/redis/hiredis/blob/master/test.c)。

* 同步单命令通信。

```c
num = 1000;
replies = hi_malloc_safe(sizeof(redisReply*)*num);
for (i = 0; i < num; i++) {
    /* 同步发送命令，接收回复。 */
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
    /* 将多个命令缓存到发送缓冲区。 */
    redisAppendCommand(c,"PING");
for (i = 0; i < num; i++) {
    /* 将发送缓冲区命令打包发送，读取回复集合，逐个返回。 */
    assert(redisGetReply(c, (void*)&replies[i]) == REDIS_OK);
    assert(replies[i] != NULL && replies[i]->type == REDIS_REPLY_STATUS);
}
for (i = 0; i < num; i++) freeReplyObject(replies[i]);
hi_free(replies);
```

---

## 3. 性能

用 hiredis 压测 100w 条命令，测试源码 [github](https://github.com/wenfh2020/c_test/blob/master/redis/test_pipeline.cpp)。

### 3.1. 耗时

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

### 3.2. 性能

redis-server 火焰图：上图是单命令，下图是 pipeline。对比之下，单命令要耗费更多内核读写资源。

> **gettimeofday** 这个接口也不是省油的灯。

<div align=center><img src="/images/2021-03-15-14-52-33.png" data-action="zoom"/></div>

> 火焰图参考：[如何生成火焰图🔥](https://wenfh2020.com/2020/07/30/flame-diagram/)

---

## 4. hiredis 客户端源码剖析

详细请参考：[hiredis github 源码](https://github.com/redis/hiredis/blob/master/hiredis.c)。

### 4.1. 单命令接口

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

### 4.2. pipeline 多命令

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

## 5. 参考

* [Using pipelining to speedup Redis queries](https://redis.io/topics/pipelining)
