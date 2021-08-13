---
layout: post
title:  "[内核源码] 网络协议栈 connect (tcp)"
categories: kernel
tags: linux kernel connect
author: wenfh2020
---

走读网络协议栈 accept (tcp) 的（Linux - 5.0.1 [下载](https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.0.1.tar.xz)）内核源码。

connect....。




* content
{:toc}

---

## 1. 概述

tcp 通信，客户端与服务端通过 connect 建立连接。

```c
/* sockfd: socket 函数返回的套接字描述符。
 * servaddr: 要连接的目标服务地址（IP/PORT）。
 * addrlen: 地址长度。
 * return: 正确返回 0，否则返回 -1。
 */
#include <sys/socket.h>
int connect(int sockfd, const struct sockaddr *servaddr, socklen_t addrlen);
```

> 参考：《UNIX 网络编程_卷_1》- 4.3 connect 函数。

---

## 2. 三次握手

连接需要通过三次握手，握手🤝流程详见下图。

<div align=center><img src="/images/2021-08-08-12-30-55.png" data-action="zoom"/></div>

> 参考：《UNIX 网络编程_卷_1》- 2.6.1 三路握手。

---

## 3. 内核

### 3.1. 调试堆栈

```shell
tcp_v4_connect(struct sock * sk, struct sockaddr * uaddr, int addr_len) (/root/linux-5.0.1/net/ipv4/tcp_ipv4.c:203)
__inet_stream_connect(struct socket * sock, struct sockaddr * uaddr, int addr_len, int flags, int is_sendmsg) (/root/linux-5.0.1/net/ipv4/af_inet.c:655)
inet_stream_connect(struct socket * sock, struct sockaddr * uaddr, int addr_len, int flags) (/root/linux-5.0.1/net/ipv4/af_inet.c:719)
__sys_connect(int fd, struct sockaddr * uservaddr, int addrlen) (/root/linux-5.0.1/net/socket.c:1663)
__do_sys_connect() (/root/linux-5.0.1/net/socket.c:1674)
__se_sys_connect() (/root/linux-5.0.1/net/socket.c:1671)
__x64_sys_connect(const struct pt_regs * regs) (/root/linux-5.0.1/net/socket.c:1671)
do_syscall_64(unsigned long nr, struct pt_regs * regs) (/root/linux-5.0.1/arch/x86/entry/common.c:290)
entry_SYSCALL_64() (/root/linux-5.0.1/arch/x86/entry/entry_64.S:175)
```

> 参考：[vscode + gdb 远程调试 linux (EPOLL) 内核源码](https://www.bilibili.com/video/bv1yo4y1k7QJ)

---

### 3.2. TCP 协议相关数据结构

connect 是 tcp 协议的一个重要接口，要对 tcp 协议的相关结构有一定的了解。

> 详细参考：[[内核源码] 网络协议栈 socket (tcp)](https://wenfh2020.com/2021/07/13/kernel-sys-socket/)

```c
/* ./include/linux/net.h */
struct socket {
    socket_state       state;
    short              type;
    ...
    struct sock        *sk;
    const struct proto_ops  *ops;
};

/* ./include/net/sock.h */
struct proto {
    ...
    int (*connect)(struct sock *sk, struct sockaddr *uaddr, int addr_len);
    ...
} __randomize_layout;

/* net/ipv4/tcp_ipv4.c */
struct proto tcp_prot = {
    ...
    .connect = tcp_v4_connect,
    ...
};

/* ./net/ipv4/af_inet.c */
const struct proto_ops inet_stream_ops = {
    .family  = PF_INET,
    ...
    .connect = inet_stream_connect,
    ...
};

/* af_inet.c */
static struct inet_protosw inetsw_array[] = {
    {
        .type =       SOCK_STREAM,
        .protocol =   IPPROTO_TCP,
        .prot =       &tcp_prot,
        .ops =        &inet_stream_ops,
        .flags =      INET_PROTOSW_PERMANENT | INET_PROTOSW_ICSK,
    },
    ...
};
```

---

### 3.3. 源码逻辑

```shell
#------------------- *用户态* ---------------------------
connect
#------------------- *内核态* ---------------------------
__sys_connect # net/socket.c - 内核系统调用。
|-- sockfd_lookup_light # 根据 fd 查找 listen socket 的 socket 指针。
|-- sock_alloc # 创建一个新的 socket 对象，因为要从 listen socket 的全连接队列里获取一个就绪的连接。
```

```c
SYSCALL_DEFINE3(connect, int, fd, struct sockaddr __user *, uservaddr,
        int, addrlen) {
    return __sys_connect(fd, uservaddr, addrlen);
}

int __sys_connect(int fd, struct sockaddr __user *uservaddr, int addrlen) {
    struct socket *sock;
    ...
    /* inet_stream_connect */
    err = sock->ops->connect(sock, (struct sockaddr *)&address, addrlen,
                 sock->file->f_flags);
    ...
}

int inet_stream_connect(struct socket *sock, struct sockaddr *uaddr,
            int addr_len, int flags) {
    ...
    err = __inet_stream_connect(sock, uaddr, addr_len, flags, 0);
    ...
}

int __inet_stream_connect(struct socket *sock, struct sockaddr *uaddr,
              int addr_len, int flags, int is_sendmsg) {
    struct sock *sk = sock->sk;
    int err;
    long timeo;
    ...
    switch (sock->state) {
        ...
    case SS_UNCONNECTED:
        ...
        /* 连接逻辑：sock >> tcp_prot >> tcp_v4_connect。 */
        err = sk->sk_prot->connect(sk, uaddr, addr_len);
        ...
    }

    timeo = sock_sndtimeo(sk, flags & O_NONBLOCK);

    if ((1 << sk->sk_state) & (TCPF_SYN_SENT | TCPF_SYN_RECV)) {
        ...
        /* 异步返回，同步等待处理。 */
        if (!timeo || !inet_wait_for_connect(sk, timeo, writebias))
            goto out;
        ...
    }
    ...
    sock->state = SS_CONNECTED;
    ...
}
```

---

## 4. 连接逻辑

连接的核心逻辑在函数 <font color=red> tcp_v4_connect </font>。

* 相关数据结构。

```c
struct inet_hashinfo;

struct inet_timewait_death_row {
    atomic_t tw_count;

    struct inet_hashinfo *hashinfo ____cacheline_aligned_in_smp;
    int sysctl_max_tw_buckets;
};

/* include/net/netns/ipv4.h */
struct netns_ipv4 {
    ...
    struct inet_timewait_death_row tcp_death_row;
    ...
}
```

* 逻辑。

```c
/* This will initiate an outgoing connection. */
int tcp_v4_connect(struct sock *sk, struct sockaddr *uaddr, int addr_len) {
    struct sockaddr_in *usin = (struct sockaddr_in *)uaddr;
    struct inet_sock *inet = inet_sk(sk);
    struct tcp_sock *tp = tcp_sk(sk);
    __be16 orig_sport, orig_dport;
    __be32 daddr, nexthop;
    struct flowi4 *fl4;
    struct rtable *rt;
    int err;
    struct ip_options_rcu *inet_opt;
    struct inet_timewait_death_row *tcp_death_row = &sock_net(sk)->ipv4.tcp_death_row;
    ...
    nexthop = daddr = usin->sin_addr.s_addr;
    inet_opt = rcu_dereference_protected(inet->inet_opt, lockdep_sock_is_held(sk));
    if (inet_opt && inet_opt->opt.srr) {
        if (!daddr)
            return -EINVAL;
        nexthop = inet_opt->opt.faddr;
    }

    orig_sport = inet->inet_sport;
    orig_dport = usin->sin_port;
    fl4 = &inet->cork.fl.u.ip4;

    /* 查找路由。 */
    rt = ip_route_connect(fl4, nexthop, inet->inet_saddr,
                  RT_CONN_FLAGS(sk), sk->sk_bound_dev_if,
                  IPPROTO_TCP,
                  orig_sport, orig_dport, sk);
    ...
    /* 更新临时目标地址，有可能与用户传入的目标地址不同。 */
    if (!inet_opt || !inet_opt->opt.srr)
        daddr = fl4->daddr;

    /* 如果 socket 在 connect 前没有指定源地址，那么设置路由选择的源地址。 */
    if (!inet->inet_saddr)
        inet->inet_saddr = fl4->saddr;
    sk_rcv_saddr_set(sk, inet->inet_saddr);
    ...
    /* 更新目标地址和端口。 */
    inet->inet_dport = usin->sin_port;
    sk_daddr_set(sk, daddr);

    /* 设置 ip 选项长度。 */
    inet_csk(sk)->icsk_ext_hdr_len = 0;
    if (inet_opt)
        inet_csk(sk)->icsk_ext_hdr_len = inet_opt->opt.optlen;

    /* 设置 maximum segment size。 */
    tp->rx_opt.mss_clamp = TCP_MSS_DEFAULT;

    /* 设置连接状态为 SYN 发送状态。 */
    tcp_set_state(sk, TCP_SYN_SENT);

    /* 如果连接还没指定源端口，那么内核将会分配一个源端口。
     * 为其绑定地址和端口。 
     * 保存 sk 连接到哈希表。*/
    err = inet_hash_connect(tcp_death_row, sk);
    ...
    /* 更新路由缓存表信息。 */
    rt = ip_route_newports(fl4, rt, orig_sport, orig_dport,
                   inet->inet_sport, inet->inet_dport, sk);
    ...
    /* 更新路由缓存项目。*/
    sk->sk_gso_type = SKB_GSO_TCPV4;
    sk_setup_caps(sk, &rt->dst);
    rt = NULL;

    /* 计算第一个报文的序列号。*/
    if (likely(!tp->repair)) {
        if (!tp->write_seq)
            tp->write_seq = secure_tcp_seq(inet->inet_saddr,
                               inet->inet_daddr,
                               inet->inet_sport,
                               usin->sin_port);
        /* 哈希计算时间偏移值。 */
        tp->tsoffset = secure_tcp_ts_off(sock_net(sk),
                         inet->inet_saddr,
                         inet->inet_daddr);
    }

    /* 计算 IP 报文 id。 */
    inet->inet_id = tp->write_seq ^ jiffies;
    ...

    /* 发送 SYN 报文。 */
    err = tcp_connect(sk);
    ...
}
```

---

## 5. 参考

* 《UNIX 网络编程_卷_1》
* [重温网络基础](https://wenfh2020.com/2021/05/08/network-base/)
* [[内核源码] 网络协议栈 socket (tcp)](https://wenfh2020.com/2021/07/13/kernel-sys-socket/)
* [connect及bind、listen、accept背后的三次握手](https://www.cnblogs.com/yxzh-ustc/p/12101658.html)
* [Linux TCP/IP 协议栈之 Socket的实现分析(Connect客户端发起连接请求)](https://www.cnblogs.com/my_life/articles/6085588.html)
* [TCP/IP协议栈在Linux内核中的运行时序分析](https://www.cnblogs.com/xingruizhi/p/14331785.html)

