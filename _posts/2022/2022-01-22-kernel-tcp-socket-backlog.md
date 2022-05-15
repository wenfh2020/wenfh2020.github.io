---
layout: post
title:  "[内核源码] tcp 连接队列"
categories: kernel
tags: kernel tcp backlog
author: wenfh2020
---

服务端与客户端是一对多的关系，tcp 服务，当大量用户通过三次握手涌入服务端时，连接优化处理就非常重要。

服务端优化的方向有几个：全连接长度，半连接长度，syncookies 配置。

本文通过走读 Linux(5.0.1) 内核源码，了解对应的知识点。

> `待续` .....


* content
{:toc}

---

## 1. 概述

tcp 通过三次握手，客户端与服务端建立完整连接。

从下图可以比较直观地看到：内核半连接队列和全连接队列的作用。

<style> table th:first-of-type { width: 70px; } </style>

| 关键       | 描述                                                                                                                                                                                                                                                                   |
| :--------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 半连接队列 | 客户端第一次握手，发送 syn 包给服务端，服务端内核收到 syn 包后，将产生一个轻量级的连接信息，保存于半连接队列，半连接队列相当于全连接队列的缓冲区。> 半连接队列的连接信息，其实保存于哈希表，为了方便描述，这里把它称为半连接队列。                                     |
| 全连接队列 | 当客户端触发第三次握手时，服务端收到客户端发送的 ack 包，将半连接队列对应的连接信息，转移到全连接队列，（唤醒）等待用户调用 accept 接口从全连接队列取出新的链接。                                                                                                      |
| syncookies | 半连接队列是全连接队列的缓冲区，但是某些场景，缓冲区可能溢出，而全连接队列还能填充新的数据，这时候需要修改内核配置：sysctl_tcp_syncookies，支持 syncookies 功能，三次握手，通讯包通过特殊的校验，使得 syn 包绕过半连接队列缓冲区，完成三次握手，连接进入到全连接队列。 |

* 三次握手流程。

<div align=center><img src="/images/2021-08-18-13-26-18.png" data-action="zoom"/></div>

> 图片来源：[TCP 三次握手（内核）](https://www.processon.com/view/610f1bbb1efad41a37e200c7)

* 三次握手源码流程。

<div align=center><img src="/images/2021-08-18-15-42-54.png" data-action="zoom"/></div>

> 图片来源：[TCP 三次握手（内核）](https://www.processon.com/view/610f1bbb1efad41a37e200c7)

---

## 2. 数据结构

listen socket 的 struct sock 数据结构 inet_connection_sock。

* 全连接队列和半连接队列最大长度：
  inet_connection_sock.icsk_inet.sock.sk_max_ack_backlog

* 全连接队列：
  inet_connection_sock.icsk_accept_queue.rskq_accept_head

* 当前全连接队列长度：
  inet_connection_sock.icsk_inet.sock.sk_ack_backlog

* 半连接队列（哈希表）：
  inet_hashinfo.inet_ehash_bucket

* 当前半连接队列长度：
  inet_connection_sock.icsk_accept_queue.qlen

<div align=center><img src="/images/2021-07-28-10-01-09.png" data-action="zoom"/></div>

> 图片来源：[linux 内核 listen (tcp/IPv4) 结构关系](https://processon.com/view/60fa6dfe7d9c083494e37a9a)

```c
/* include/net/inet_connection_sock.h */
struct inet_connection_sock {
    /* inet_sock has to be the first member! */
    struct inet_sock icsk_inet;
    struct request_sock_queue icsk_accept_queue; /* 半连接和全连接数据记录。 */
    ...
};

/* include/net/inet_sock.h */
struct inet_sock {
    /* sk and pinet6 has to be the first two members of inet_sock */
    struct sock sk;
    ...
}

/* include/net/sock.h */
struct sock {
    ...
    u32 sk_ack_backlog; /* 当前全连接队列已有数据个数。 */
    u32 sk_max_ack_backlog; /* 队列最大长度，用于限制半连接和全连接队列的长度。 */
    ...
}

/* include/net/request_sock.h */
struct request_sock_queue {
    ...
    atomic_t qlen;  /* 半连接队列 sk 个数。 */
    ...
    /* 全连接队列，队列头，队列尾。*/
    struct request_sock *rskq_accept_head; /* 队列头。*/
    struct request_sock *rskq_accept_tail; /* 队列尾。*/
    ...
};

// 半连接数据保存在哈希表中 inet_hashinfo.inet_ehash_bucket

/* net/ipv4/tcp_ipv4.c */
struct inet_hashinfo tcp_hashinfo;

/* include/net/inet_hashtables.h */
struct inet_hashinfo {
    /* 保存了 TCP_ESTABLISHED <= sk->sk_state < TCP_CLOSE 状态的连接。 */
    struct inet_ehash_bucket *ehash;
    spinlock_t               *ehash_locks;
    unsigned int             ehash_mask;
    unsigned int             ehash_locks_mask;
    ...
};
```

---

## 3. 全连接队列

从上文数据结构可知，全连接相关结构：

1. 全连接队列和半连接队列最大长度：
   inet_connection_sock.icsk_inet.sock.sk_max_ack_backlog

2. 全连接队列：
   inet_connection_sock.icsk_accept_queue.rskq_accept_head

3. 当前全连接队列长度：
   inet_connection_sock.icsk_inet.sock.sk_ack_backlog

---

它的最大长度是由用户层接口：`listen` 的 backlog 参数控制的，同时也与内核配置 net.core.somaxconn 有关：sk_max_ack_backlog = min(backlog, somaxconn)

* listen 源码逻辑。

```c
/* net/socket.c */
int __sys_listen(int fd, int backlog) {
    struct socket *sock;
    int err, fput_needed;
    int somaxconn;

    /* 通过 fd 查找 socket. */
    sock = sockfd_lookup_light(fd, &err, &fput_needed);
    if (sock) {
        /* backlog 配置默认最大值。 */
        somaxconn = sock_net(sock->sk)->core.sysctl_somaxconn;
        /* 如果 backlog 超过了配置值，就采用配置的值。 */
        if ((unsigned int)backlog > somaxconn)
            backlog = somaxconn;
        ...
        if (!err)
            /* inet_listen */
            err = sock->ops->listen(sock, backlog);
        ...
    }
    ...
}

/* net/ipv4/af_inet.c */
int inet_listen(struct socket *sock, int backlog) {
    struct sock *sk = sock->sk;
    ...
    sk->sk_max_ack_backlog = backlog;
    ...
}
```

* somaxconn 内核配置。

```shell
# /etc/sysctl.conf
net.core.somaxconn = 1024
# /sbin/sysctl -p
```

* 检查全连接队列是否已满。

```c
static inline bool sk_acceptq_is_full(const struct sock *sk) {
    return sk->sk_ack_backlog > sk->sk_max_ack_backlog;
}
```

---

## 4. 半连接队列

linux 5.0.1 半连接的最大长度，也是通过 sk_max_ack_backlog 进行限制的，跟全连接的最大长度一样。

1. 全连接队列和半连接队列最大长度：
   inet_connection_sock.icsk_inet.sock.sk_max_ack_backlog

2. 半连接队列（哈希表）：
   inet_hashinfo.inet_ehash_bucket

3. 当前半连接队列长度：
   inet_connection_sock.icsk_accept_queue.qlen

---

* 检查半连接队列是否已满。

```c
/* include/net/inet_connection_sock.h */
static inline int inet_csk_reqsk_queue_is_full(const struct sock *sk) {
    return inet_csk_reqsk_queue_len(sk) >= sk->sk_max_ack_backlog;
}

static inline int inet_csk_reqsk_queue_len(const struct sock *sk) {
    return reqsk_queue_len(&inet_csk(sk)->icsk_accept_queue);
}

static inline int reqsk_queue_len(const struct request_sock_queue *queue) {
    return atomic_read(&queue->qlen);
}
```

---

## 5. syncookies

当出现 syn 等待队列溢出时，可以开启 syn cookies 处理。

> 详细请参考：[深入浅出TCP中的SYN-Cookies](https://segmentfault.com/a/1190000019292140)

```shell
#/etc/sysctl.conf
net.ipv4.tcp_syncookies=1
# /sbin/sysctl -p
```

---

## 6. 逻辑

从上述分析，无论是半连接队列或者全连接队列，资源都是有限制的，当队列满了以后内核就会采用相应的策略拒绝新的连接，接下来看看第一次握手 `服务端` 处理 syn 包的场景。

1. 只要全连接队列满了，丢弃 syn 包，等待客户端重发处理。
2. 开启了 syncookies > 0，全连接队列没满，一般不丢弃 syn 包。
3. 半连接队列满了，并且没打开 syncookies 配置，丢弃 syn 包。
4. syncookies == 2 并且 全连接队列没满，不丢弃。
5. 半链接队列满了，全链接队列没满，syncookies > 0，不丢弃。

> 因为客户端有重发机制，所以服务端接收到数据包，发现超负荷了，丢掉数据包后，客户端发现发出的数据包长时间得不到回应，会触发重传机制，经过重传的时间差，服务端可能已经降低了荷载，能重新处理客户端重传的 syn 包了。

* tcp_max_syn_backlog
  
  这个配置，有点鸡肋，感觉完全是为了兼容以前版本的逻辑，因为半连接队列的最大长度跟全连接的最大长度一样了。

```shell
# /etc/sysctl.conf
net.ipv4.tcp_max_syn_backlog = 2048
# /sbin/sysctl -p
```

* 逻辑。

```c
int tcp_conn_request(struct request_sock_ops *rsk_ops,
             const struct tcp_request_sock_ops *af_ops,
             struct sock *sk, struct sk_buff *skb)
{
    struct tcp_fastopen_cookie foc = { .len = -1 };
    __u32 isn = TCP_SKB_CB(skb)->tcp_tw_isn;
    struct tcp_options_received tmp_opt;
    struct tcp_sock *tp = tcp_sk(sk);
    struct net *net = sock_net(sk);
    struct sock *fastopen_sk = NULL;
    struct request_sock *req;
    bool want_cookie = false;
    struct dst_entry *dst;
    struct flowi fl;

    /* 半连接队列满了并且没有开启 syncookies，丢弃包。 */
    if ((net->ipv4.sysctl_tcp_syncookies == 2 ||
         inet_csk_reqsk_queue_is_full(sk)) && !isn) {
        want_cookie = tcp_syn_flood_action(sk, skb, rsk_ops->slab_name);
        if (!want_cookie)
            goto drop;
    }

    /* 如果全连接队列满了，丢弃包。 */
    if (sk_acceptq_is_full(sk)) {
        NET_INC_STATS(sock_net(sk), LINUX_MIB_LISTENOVERFLOWS);
        goto drop;
    }
    ...
    /*  */
    if (!want_cookie && !isn) {
        /* 如果没开启 syncookies 配置，并且
         * 当前半连接队列长度，不超过 sysctl_max_syn_backlog 的 3/4 不丢弃。 */
        if (!net->ipv4.sysctl_tcp_syncookies &&
            (net->ipv4.sysctl_max_syn_backlog - inet_csk_reqsk_queue_len(sk) <
             (net->ipv4.sysctl_max_syn_backlog >> 2)) &&
            !tcp_peer_is_proven(req, dst)) {
            ...
            pr_drop_req(req, ntohs(tcp_hdr(skb)->source),
                    rsk_ops->family);
            goto drop_and_release;
        }
        ...
    }
}

static bool tcp_syn_flood_action(const struct sock *sk,
                 const struct sk_buff *skb,
                 const char *proto)
{
    ...
#ifdef CONFIG_SYN_COOKIES
    if (net->ipv4.sysctl_tcp_syncookies) {
        msg = "Sending cookies";
        want_cookie = true;
        __NET_INC_STATS(sock_net(sk), LINUX_MIB_TCPREQQFULLDOCOOKIES);
    }
#endif
    ...
    return want_cookie;
}
```

---

## 7. 待续
