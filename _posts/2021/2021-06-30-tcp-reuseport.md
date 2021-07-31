---
layout: post
title:  "剖析 TCP - SO_REUSEPORT"
categories: kernel nginx
tags: reuseport nginx
author: wenfh2020
---

在 TCP 应用中，SO_REUSEPORT 是 TCP 的一个选项设置，它能开启内核功能：网络连接分配负载均衡。

该功能允许多个进程/线程 bind/listen 相同的 IP/PORT，提升了新连接的分配性能。

nginx 开启 reuseport 功能后，性能有立竿见影的提升，我们也会分析一下 nginx 是如何支持 reuseport 功能的。



* content
{:toc}




---

## 1. 概述

### 1.1. what

从下面这段英文提取一些关键信息：

SO_REUSEPORT 是网络的一个选项设置，它允许多个进程/线程 bind/listen 相同的 IP/PORT，在 TCP 的应用中，它是一个新连接分发的负载均衡功能，它提升了新连接的分配性能（针对 accept ）。

```shell
Socket options
    The socket options listed below can be set by using setsockopt(2)
    and read with getsockopt(2) with the socket level set to
    SOL_SOCKET for all sockets.  Unless otherwise noted, optval is a
    pointer to an int.
...
    SO_REUSEPORT (since Linux 3.9)
                Permits multiple AF_INET or AF_INET6 sockets to be bound
                to an identical socket address.  This option must be set
                on each socket (including the first socket) prior to
                calling bind(2) on the socket.  To prevent port hijacking,
                all of the processes binding to the same address must have
                the same effective UID.  This option can be employed with
                both TCP and UDP sockets.

                For TCP sockets, this option allows accept(2) load
                distribution in a multi-threaded server to be improved by
                using a distinct listener socket for each thread.  This
                provides improved load distribution as compared to
                traditional techniques such using a single accept(2)ing
                thread that distributes connections, or having multiple
                threads that compete to accept(2) from the same socket.

                For UDP sockets, the use of this option can provide better
                distribution of incoming datagrams to multiple processes
                (or threads) as compared to the traditional technique of
                having multiple processes compete to receive datagrams on
                the same socket.
```

> 注释文字来源 (连接需要翻墙）：[socket(7) — Linux manual page](https://man7.org/linux/man-pages/man7/socket.7.html)

---

### 1.2. how

SO_REUSEPORT 功能使用，可以通过网络选项进行设置，在 bind 前面设置即可，使用比较简单。

```c
int fd, reuse = 1;
fd = socket(PF_INET, SOCK_STREAM, IPPROTO_IP);
setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, (const void *)&reuse, sizeof(int));
```

---

### 1.3. why

SO_REUSEPORT 功能解决了什么问题？我们先看看 2013 年提交的这个 Linux 内核功能 [补丁](https://github.com/torvalds/linux/commit/da5e36308d9f7151845018369148201a5d28b46d?branch=da5e36308d9f7151845018369148201a5d28b46d&diff=split) 的注释。

```shell
soreuseport: TCP/IPv4 implementation
Allow multiple listener sockets to bind to the same port.

Motivation for soresuseport would be something like a web server
binding to port 80 running with multiple threads, where each thread
might have it's own listener socket.  This could be done as an
alternative to other models: 1) have one listener thread which
dispatches completed connections to workers. 2) accept on a single
listener socket from multiple threads.  In case #1 the listener thread
can easily become the bottleneck with high connection turn-over rate.
In case #2, the proportion of connections accepted per thread tends
to be uneven under high connection load (assuming simple event loop:
while (1) { accept(); process() }, wakeup does not promote fairness
among the sockets.  We have seen the  disproportion to be as high
as 3:1 ratio between thread accepting most connections and the one
accepting the fewest.  With so_reusport the distribution is
uniform.

Signed-off-by: Tom Herbert <therbert@google.com>
Signed-off-by: David S. Miller <davem@davemloft.net>
 master
 v5.13 
…
 v3.9-rc1
@davem330
Tom Herbert authored and davem330 committed on 24 Jan 2013
1 parent 055dc21 commit da5e36308d9f7151845018369148201a5d28b46d
```

soreuseport 主要解决了两个问题：

1. （A 图）单个 listen socket 遇到的性能瓶颈。
2. （B 图）单个 listen socket 多个线程同时 accept，但是多个线程资源分配不均。

<div align=center><img src="/images/2021-07-30-17-49-30.png" data-action="zoom"/></div>

---

其实它还解决了一个很重要的问题：

在 tcp 多线程场景中，（B 图）服务端如果所有新连只保存在一个 listen socket 的全连接队列中，那么多个线程去这个队里获取（accept）新的连接，势必会出现多个线程对一个公共资源的争抢，争抢过程中，大量资源的损耗。

---

（C 图）有多个 listener 共同 bind/listen 相同的 IP/PORT，也就是说每个进程/线程有一个独立的 listener，相当于每个进程/线程独享一个 listener 的全连接队列，不需要多个进程/线程竞争某个公共资源，能充分利用多核，减少竞争的资源消耗，效率自然提高了。

---

## 2. 原理

TCP 客户端连接服务端，第一次握手，服务端被动收到第一次握手 SYN 包，内核就通过哈希算法，将客户端的连接分派到内核半连接队列，三次握手成功后，再将这个连接从半连接队列移动到某个 listener 的全连接队列中，提供 accept 获取。

* 三次握手流程。

<div align=center><img src="/images/2021-07-30-22-45-14.png" data-action="zoom"/></div>

* 服务端被动第一次握手，查找合适的 listener，详看源码（Linux 5.0.1）。

<div align=center><img src="/images/2021-07-31-13-57-48.png" data-action="zoom"/></div>

```c
static inline struct sock *__inet_lookup(struct net *net,
                     struct inet_hashinfo *hashinfo,
                     struct sk_buff *skb, int doff,
                     const __be32 saddr, const __be16 sport,
                     const __be32 daddr, const __be16 dport,
                     const int dif, const int sdif,
                     bool *refcounted)
{
    u16 hnum = ntohs(dport);
    struct sock *sk;

    /* skb 包，从 established 哈希表中查找是否已有 established 的包。*/
    sk = __inet_lookup_established(net, hashinfo, saddr, sport,
                       daddr, hnum, dif, sdif);
    *refcounted = true;
    if (sk)
        return sk;
    *refcounted = false;

    /* 上面没找到，那么就找一个合适的 listener，去走三次握手的流程。 */
    return __inet_lookup_listener(net, hashinfo, skb, doff, saddr,
                      sport, daddr, hnum, dif, sdif);
}

struct sock *__inet_lookup_listener(struct net *net,
                    struct inet_hashinfo *hashinfo,
                    struct sk_buff *skb, int doff,
                    const __be32 saddr, __be16 sport,
                    const __be32 daddr, const unsigned short hnum,
                    const int dif, const int sdif) {
    struct inet_listen_hashbucket *ilb2;
    struct sock *result = NULL;
    unsigned int hash2;

    /* 通过目标 ip/port 哈希值从 hashinfo.lhash2 查找对应的 slot。*/
    hash2 = ipv4_portaddr_hash(net, daddr, hnum);
    ilb2 = inet_lhash2_bucket(hashinfo, hash2);

    /* 再从对应的 slot 上，搜索哈希链上的数据。 */
    result = inet_lhash2_lookup(net, ilb2, skb, doff,
                    saddr, sport, daddr, hnum,
                    dif, sdif);
    ...
    return result;
}

/* called with rcu_read_lock() : No refcount taken on the socket */
static struct sock *inet_lhash2_lookup(struct net *net,
                struct inet_listen_hashbucket *ilb2,
                struct sk_buff *skb, int doff,
                const __be32 saddr, __be16 sport,
                const __be32 daddr, const unsigned short hnum,
                const int dif, const int sdif) {
    bool exact_dif = inet_exact_dif_match(net, skb);
    struct inet_connection_sock *icsk;
    struct sock *sk, *result = NULL;
    int score, hiscore = 0;
    u32 phash = 0;

    /* 遍历哈希链，获取合适的 listener。 */
    inet_lhash2_for_each_icsk_rcu(icsk, &ilb2->head) {
        sk = (struct sock *)icsk;

        score = compute_score(sk, net, hnum, daddr, dif, sdif, exact_dif);
        /* 统计分数，获取最大匹配分数的 socket。*/
        if (score > hiscore) {
            if (sk->sk_reuseport) {
                /* 算出哈希值。 */
                phash = inet_ehashfn(net, daddr, hnum, saddr, sport);
                /* 在数组里，通过哈希获得 sk。 */
                result = reuseport_select_sock(sk, phash, skb, doff);
                if (result)
                    return result;
            }
            result = sk;
            hiscore = score;
        }
    }

    return result;
}
```

> 参考：[[内核源码走读] 网络协议栈 listen (tcp)](https://wenfh2020.com/2021/07/21/kernel-sys-listen/#33-%E6%9F%A5%E6%89%BE-listen-socket)

---

## 3. nginx

nginx 是多进程架构模型，在内核还没有添加 reuseport 功能前，nginx 为了解决单个 listener 暴露出来的问题，花了不少心思。

2013 年 Linux 内核添加了 reuseport 功能后，nginx 在 2015 年，1.9.1 版本也增加对应功能的支持，nginx 开启 reuseport 功能后，性能是原来的 2-3 倍，效果可谓立竿见影！

> 详细请参考 nginx 官方文档：[Socket Sharding in NGINX Release 1.9.1](https://www.nginx.com/blog/socket-sharding-nginx-release-1-9-1/)

接下来我们看看 nginx 是如何支持 reuseport 的。

---

### 3.1. 开启 SO_REUSEPORT

修改 nginx 配置，在 nginx.conf 里，listen 关键字后面添加 'reuseport'。

```shell
# nginx.conf
# vim /usr/local/nginx/conf/nginx.conf

# 启动 4 个子进程。
worker_processes  4;

http {
    ...
    server {
        listen 80 reuseport;
        server_name localhost;
        ...
    }
    ...
}
```

---

### 3.2. 工作流程

启动测试 nginx，1 master / 4 workers，监听 80 端口。

---

#### 3.2.1. 进程

* 父子进程。

```shell
# ps -ef | grep nginx
root      88994   1770  0 14:57 ?        00:00:00 nginx: master process /usr/local/nginx/sbin/nginx
nobody    88995  88994  0 14:57 ?        00:00:00 nginx: worker process      
nobody    88996  88994  0 14:57 ?        00:00:00 nginx: worker process      
nobody    88997  88994  0 14:57 ?        00:00:00 nginx: worker process      
nobody    88998  88994  0 14:57 ?        00:00:00 nginx: worker process      
```

* 父子进程 LISTEN 80 端口情况。

  因为配置文件设置了 `worker_processes 4` 需要启动 4 个子进程，
  nginx 进程发现配置文件关键字 listen 后添加了 reuseport 关键字，那么主进程先创建 4 个 socket 并设置 SO_REUSEPORT 选项，然后进行 bind 和 listen。

  当 fork 子进程时，子进程拷贝了父进程的这 4 个 socket，所以你看到每个子进程都有相同 LISTEN 的 socket fd（6，7，8，9）。

```shell
# lsof -i:80 | grep nginx 
nginx   88994   root    6u  IPv4 909209      0t0  TCP *:http (LISTEN)
nginx   88994   root    7u  IPv4 909210      0t0  TCP *:http (LISTEN)
nginx   88994   root    8u  IPv4 909211      0t0  TCP *:http (LISTEN)
nginx   88994   root    9u  IPv4 909212      0t0  TCP *:http (LISTEN)
nginx   88995 nobody    6u  IPv4 909209      0t0  TCP *:http (LISTEN)
nginx   88995 nobody    7u  IPv4 909210      0t0  TCP *:http (LISTEN)
nginx   88995 nobody    8u  IPv4 909211      0t0  TCP *:http (LISTEN)
nginx   88995 nobody    9u  IPv4 909212      0t0  TCP *:http (LISTEN)
nginx   88996 nobody    6u  IPv4 909209      0t0  TCP *:http (LISTEN)
nginx   88996 nobody    7u  IPv4 909210      0t0  TCP *:http (LISTEN)
nginx   88996 nobody    8u  IPv4 909211      0t0  TCP *:http (LISTEN)
nginx   88996 nobody    9u  IPv4 909212      0t0  TCP *:http (LISTEN)
nginx   88997 nobody    6u  IPv4 909209      0t0  TCP *:http (LISTEN)
nginx   88997 nobody    7u  IPv4 909210      0t0  TCP *:http (LISTEN)
nginx   88997 nobody    8u  IPv4 909211      0t0  TCP *:http (LISTEN)
nginx   88997 nobody    9u  IPv4 909212      0t0  TCP *:http (LISTEN)
nginx   88998 nobody    6u  IPv4 909209      0t0  TCP *:http (LISTEN)
nginx   88998 nobody    7u  IPv4 909210      0t0  TCP *:http (LISTEN)
nginx   88998 nobody    8u  IPv4 909211      0t0  TCP *:http (LISTEN)
nginx   88998 nobody    9u  IPv4 909212      0t0  TCP *:http (LISTEN)
```

---

#### 3.2.2. 网络初始流程

nginx 是多进程模型，Linux 环境下一般使用 epoll 事件驱动。

<div align=center><img src="/images/2021-07-31-14-18-17.png" data-action="zoom"/></div>

* strace 监控 nginx 进程的系统调用流程。

```shell
# strace -f -s 512 -o /tmp/nginx.log /usr/local/nginx/sbin/nginx
# grep -n -E 'socket\(PF_INET|SO_REUSEPORT|listen|bind|clone|epoll' /tmp/nginx.log

# master
208:88993 socket(PF_INET, SOCK_STREAM, IPPROTO_IP) = 6
210:88993 setsockopt(6, SOL_SOCKET, SO_REUSEPORT, [1], 4) = 0
212:88993 bind(6, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("0.0.0.0")}, 16) = 0
213:88993 listen(6, 511)                    = 0
214:88993 socket(PF_INET, SOCK_STREAM, IPPROTO_IP) = 7
216:88993 setsockopt(7, SOL_SOCKET, SO_REUSEPORT, [1], 4) = 0
218:88993 bind(7, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("0.0.0.0")}, 16) = 0
219:88993 listen(7, 511)                    = 0
220:88993 socket(PF_INET, SOCK_STREAM, IPPROTO_IP) = 8
222:88993 setsockopt(8, SOL_SOCKET, SO_REUSEPORT, [1], 4) = 0
224:88993 bind(8, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("0.0.0.0")}, 16) = 0
225:88993 listen(8, 511)                    = 0
226:88993 socket(PF_INET, SOCK_STREAM, IPPROTO_IP) = 9
228:88993 setsockopt(9, SOL_SOCKET, SO_REUSEPORT, [1], 4) = 0
230:88993 bind(9, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("0.0.0.0")}, 16) = 0
231:88993 listen(9, 511)                    = 0

# master --> fork
250:88993 clone(child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f0d875dfa10) = 88994
274:88994 clone(child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f0d875dfa10) = 88995
305:88994 clone( <unfinished ...>
308:88994 <... clone resumed> child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f0d875dfa10) = 88996
349:88995 epoll_create(512 <unfinished ...>
351:88995 <... epoll_create resumed> )      = 11
413:88995 epoll_ctl(11, EPOLL_CTL_ADD, 6, {EPOLLIN|EPOLLRDHUP, {u32=2270846992, u64=139696082149392}} <unfinished ...>
443:88996 <... epoll_create resumed> )      = 13
445:88994 <... clone resumed> child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f0d875dfa10) = 88998
524:88997 epoll_create(512 <unfinished ...>
526:88997 <... epoll_create resumed> )      = 15
543:88998 epoll_create(512 <unfinished ...>
545:88998 <... epoll_create resumed> )      = 17
564:88997 epoll_ctl(15, EPOLL_CTL_ADD, 8, {EPOLLIN|EPOLLRDHUP, {u32=2270846992, u64=139696082149392}} <unfinished ...>
565:88996 epoll_ctl(13, EPOLL_CTL_ADD, 7, {EPOLLIN|EPOLLRDHUP, {u32=2270846992, u64=139696082149392}} <unfinished ...>
606:88998 epoll_ctl(17, EPOLL_CTL_ADD, 9, {EPOLLIN|EPOLLRDHUP, {u32=2270846992, u64=139696082149392}}) = 0
```

---

* 分析总结一下 strace 采集的系统调用日志。

```shell
# 如果有 N 个子进程就创建 N 个 socket 并对其设置，绑定地址和监听端口。
N * (socket --> setsockopt SO_REUSEPORT --> bind --> listen) --> 
# fork 子进程
fork -->
# 每个子进程创建 epoll_create 实例进行网络读写工作。
# 注意，listen fd 是父进程创建的，父进程在 fork 子进程时，为每个子进程打上编号了，
# 每个编号的子进程会处理一个 listen fd.
epoll_create --> epoll_ctl EPOLL_CTL_ADD listen fd --> 
epoll_wait --> accept/accept4/read/write
```

* 源码函数调用层次。

```shell
# 函数调用层次关系。
# ------------------------ master ------------------------
main
|-- ngx_init_cycle
    |-- ngx_open_listening_sockets
        |-- socket # 如果有 N 个子进程，那么创建 N 个 socket.
        |-- setsockopt SO_REUSEPORT
        |-- bind
        |-- listen
|-- ngx_master_process_cycle
    |-- ngx_start_worker_processes
        |-- ngx_spawn_process # 每个 fork 出来的子进程，主进程都会传递一个顺序的数字编号进行标识，保存到 ngx_worker
            |-- fork
# ------------------------ worker ------------------------
            |-- ngx_worker_process_cycle
                |-- ngx_worker_process_init
                    |-- ngx_event_process_init
                        |-- ngx_epoll_init
                            |-- epoll_create
                        |-- ngx_epoll_add_event # ngx_add_event
                            |-- epoll_ctl # EPOLL_CTRL_ADD - 对应子进程编号的 listen fd.
                |-- ngx_process_events_and_timers
                    |-- ngx_epoll_process_events # ngx_process_events
                        |-- epoll_wait
                        |-- ngx_event_accept
                            |-- accept/accept4
```

---

## 4. 参考

* 《Linux 内核源代码情景分析》
* [多个进程绑定相同端口的实现分析[Google Patch]](http://m.blog.chinaunix.net/uid-10167808-id-3807060.html)
* [【优化】nginx启用reuseport](https://wfhu.gitbooks.io/life/content/chapter7/nginx-enable-reuseport.html)
* [Linux TCP SO_REUSEPORT — Usage and implementation](https://tech.flipkart.com/linux-tcp-so-reuseport-usage-and-implementation-6bfbf642885a)
* [再谈Linux epoll惊群问题的原因和解决方案](https://blog.csdn.net/dog250/article/details/80837278)
* [[epoll 源码走读] epoll 实现原理](http://127.0.0.1:4000/2020/04/23/epoll-code/)
* [socket(7) — Linux manual page](https://man7.org/linux/man-pages/man7/socket.7.html)
* [Socket Sharding in NGINX Release 1.9.1](https://www.nginx.com/blog/socket-sharding-nginx-release-1-9-1/)
* [Linux 网络层收发包流程及 Netfilter 框架浅析](https://zhuanlan.zhihu.com/p/93630586?from_voters_page=true)
* [Why does one NGINX worker take all the load?](https://blog.cloudflare.com/the-sad-state-of-linux-socket-balancing/)
* [深入浅出 Linux 惊群：现象、原因和解决方案](https://blog.csdn.net/Tencent_TEG/article/details/118501694?utm_medium=distribute.pc_feed.none-task-blog-short_term_tag-4.nonecase&depth_1-utm_source=distribute.pc_feed.none-task-blog-short_term_tag-4.nonecase)
* [Linux 4.6内核对TCP REUSEPORT的优化](https://blog.csdn.net/dog250/article/details/51510823)
* [[内核源码走读] 网络协议栈 listen (tcp)](https://wenfh2020.com/2021/07/21/kernel-sys-listen/)
