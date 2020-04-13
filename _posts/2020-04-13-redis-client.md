---
layout: post
title:  "[redis 源码走读] 客户端 client"
categories: redis
tags: reids client
author: wenfh2020
---

走 redis client 的工作流程



* content
{:toc}

---

* 链接 - 事件触发
* 选择 db
* 发包
* 事件触发 - epoll
* 处理函数
* 断开链接。- timer

---

## 结构

```c
typedef struct client {
    uint64_t id;            /* Client incremental unique ID. */
    connection *conn;
    ...
    redisDb *db;            /* Pointer to currently SELECTed DB. */
    robj *name;             /* As set by CLIENT SETNAME. */
    sds querybuf;           /* Buffer we use to accumulate client queries. */
    size_t qb_pos;          /* The position we have read in querybuf. */
    sds pending_querybuf;   /* If this client is flagged as master, this buffer
                               represents the yet not applied portion of the
                               replication stream that we are receiving from
                               the master. */
    int argc;               /* Num of arguments of current command. */
    robj **argv;            /* Arguments of current command. */
    struct redisCommand *cmd, *lastcmd;  /* Last command executed. */
    list *reply;            /* List of reply objects to send to the client. */
    unsigned long long reply_bytes; /* Tot bytes of objects in reply list. */
    size_t sentlen;         /* Amount of bytes already sent in the current
                               buffer or object being sent. */
    /* Response buffer */
    int bufpos;
    char buf[PROTO_REPLY_CHUNK_BYTES];
    ...
}

struct redisServer {
    ...
    list *clients;              /* List of active clients */
    list *clients_to_close;     /* Clients to close asynchronously */
    list *clients_pending_write; /* There is to write or install handler. */
    list *clients_pending_read;  /* Client has pending read socket buffers. */
    client *current_client;     /* Current client executing the command. */
}
```

## 参考

* [为什么tcp 连接断开只有3个包？](https://www.zhihu.com/question/55890292)
* [TCP_Relative_Sequence_Numbers](https://wiki.wireshark.org/TCP_Relative_Sequence_Numbers)
* 《TCP/IP 详解卷 1：协议》

---

* 更精彩内容，可以关注我的博客：[wenfh2020.com](https://wenfh2020.com/)
