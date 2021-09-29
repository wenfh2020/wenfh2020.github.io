---
layout: post
title:  "惊群效应"
categories: network
tags: thundering herd
author: wenfh2020
---

多个 进程/线程 等待资源，当资源到来时，多个 进程/线程 同时争抢，而只有少数 进程/线程 获得资源，这就是传说中的 `“惊群效应”`。

那么怎样才能避免 “惊群效应” 呢？答案是当一个资源到来时，只分配给一个 进程/线程 处理，这样就避免出现资源争抢的现象。

> 这与抢红包的道理是一样的，当你往群组里发一个红包，大家拼命争抢，结果是有人欢喜有人忧。当你不再往群组里发包了，私下发包，这样就不存在争抢的问题了。

---

本文将会简述 “惊群效应” 的影响、原理和解决方案。因为多进程和多线程模型在解析惊群问题，原理差不多，而且多进程模型有比较经典的案例，所以本文将会通过多进程模型剖析惊群问题。



* content
{:toc}

---

* 剖析经典的多线程和多进程处理方案。
* epoll 惊群。
* 剖析 nginx 原来是怎么做的。
* 剖析 nginx reuseport 是怎么处理的。
* 惊群会产生什么问题。

---

## 1. accept 惊群

### 1.1. 三次握手

通过 TCP 服务端和客户端的链接流程，了解 accept 从 listener 的 `全连接队列` 获取新链接资源的工作原理。（参考下图TCP 三次握手流程。）

<div align=center><img src="/images/2021-08-18-13-26-18.png" data-action="zoom"/></div>

---

### 1.2. 工作逻辑

正常的同步服务程序，会启动多个进程/线程（worker #1 / worker #2）进行 accept 新的链接，然后多个 进程/线程（worker #3 / worker #4） 处理新链接的逻辑。

<div align=center><img src="/images/2021-09-27-10-44-09.png" data-action="zoom"/></div>

这样的架构有个问题：多个 进程/线程 同时等待资源，那么内核应该将新来的资源分配给谁呢？是分配给其中一个 进程/线程 呢？还是将这些等待 accept 的 进程/线程 全部唤醒处理呢？答案是只将一个资源分配给一个 进程/线程，接下来看看内核是如何处理的。

---

### 1.3. accept 内核源码

进程/线程 accept 阻塞等待资源场景下，内核调用 `inet_csk_wait_for_connect` 等待资源。

通过源码了解它当资源到来时，怎么只唤醒一个进程处理的，关键在于 `WQ_FLAG_EXCLUSIVE` 排它性等待标识，当资源到来时，`__wake_up_common` 根据标识，只唤醒一个正在等待的 进程/线程。（参考 Linux 源码：5.0.1）

> 参考：《[[内核源码] 网络协议栈 - accept (tcp)](https://wenfh2020.com/2021/07/28/kernel-accept/)》

---

#### 1.3.1. 睡眠等待资源

进程/线程 添加等待排它性唤醒标识 WQ_FLAG_EXCLUSIVE，`prepare_to_wait_exclusive` 将 进程/线程 添加到等待队列，然后睡眠等待唤醒；

```shell
accept
|-- inet_accept
    |-- inet_csk_accept
        |-- inet_csk_wait_for_connect # 如果当前没有资源，进程/线程 睡眠等待资源，被唤醒。
            |-- prepare_to_wait_exclusive # 将当前 进程/线程 添加到等待队列。
                |-- __add_wait_queue_entry_tail # 添加到等待队列。
```

```c
/* net/ipv4/af_inet.c */
int inet_accept(struct socket *sock, struct socket *newsock, int flags,
        bool kern) {
    struct sock *sk1 = sock->sk;
    int err = -EINVAL;
    struct sock *sk2 = sk1->sk_prot->accept(sk1, flags, &err, kern);
    ...
}

/* net/ipv4/inet_connection_sock.c 
 * 从 listener socket 的全连接队列里取出一个新的已完成链接。*/
struct sock *inet_csk_accept(struct sock *sk, int flags, int *err, bool kern) {
    struct inet_connection_sock *icsk = inet_csk(sk);
    /* icsk_accept_queue 全连接队列。 */
    struct request_sock_queue *queue = &icsk->icsk_accept_queue;
    struct request_sock *req;
    struct sock *newsk;
    int error;
    ...
    /* 如果 listen socket 的全连接队列是空的，进入超时等待状态。 */
    if (reqsk_queue_empty(queue)) {
        long timeo = sock_rcvtimeo(sk, flags & O_NONBLOCK);

        /* 如果是非阻塞场景，返回 EAGAIN。 */
        error = -EAGAIN;
        if (!timeo)
            goto out_err;

        /* 阻塞场景下等超时等待链接资源。 */
        error = inet_csk_wait_for_connect(sk, timeo);
        if (error)
            goto out_err;
    }
    /* 从 listen socket 全连接队列删除获取一个 request_sock 连接处理。 */
    req = reqsk_queue_remove(queue, sk);
    newsk = req->sk;
    ...
}

/* 请仔细观察源码的英文注释~~ */
static int inet_csk_wait_for_connect(struct sock *sk, long timeo) {
    struct inet_connection_sock *icsk = inet_csk(sk);
    DEFINE_WAIT(wait);
    int err;

    /*
     * True wake-one mechanism for incoming connections: only
     * one process gets woken up, not the 'whole herd'.
     * Since we do not 'race & poll' for established sockets
     * anymore, the common case will execute the loop only once.
     *
     * Subtle issue: "add_wait_queue_exclusive()" will be added
     * after any current non-exclusive waiters, and we know that
     * it will always _stay_ after any new non-exclusive waiters
     * because all non-exclusive waiters are added at the
     * beginning of the wait-queue. As such, it's ok to "drop"
     * our exclusiveness temporarily when we get woken up without
     * having to remove and re-insert us on the wait queue.
     */
    for (;;) {
        /* 将当前进程添加到等待唤醒队列，然后睡眠，直到等待资源到来时候被唤醒或者满足其它条件被唤醒。 */
        prepare_to_wait_exclusive(sk_sleep(sk), &wait,
                      TASK_INTERRUPTIBLE);
        release_sock(sk);
        if (reqsk_queue_empty(&icsk->icsk_accept_queue))
            timeo = schedule_timeout(timeo);
        sched_annotate_sleep();
        lock_sock(sk);
        err = 0;
        if (!reqsk_queue_empty(&icsk->icsk_accept_queue))
            break;
        ...
    }
    finish_wait(sk_sleep(sk), &wait);
    return err;
}

/* kernel/sched/wait.c
 * 添加等待唤醒队列，等待唤醒 */
void prepare_to_wait_exclusive(struct wait_queue_head *wq_head, struct wait_queue_entry *wq_entry, int state) {
    unsigned long flags;

    /* 添加排它唤醒标识 WQ_FLAG_EXCLUSIVE，也就是当资源到来时，内核只唤醒一个进程/线程。 */
    wq_entry->flags |= WQ_FLAG_EXCLUSIVE;
    spin_lock_irqsave(&wq_head->lock, flags);
    if (list_empty(&wq_entry->entry))
        __add_wait_queue_entry_tail(wq_head, wq_entry);
    /* 设置进程的状态为 TASK_INTERRUPTIBLE，睡眠，但是可被中断唤醒。*/
    set_current_state(state);
    spin_unlock_irqrestore(&wq_head->lock, flags);
}
```

---

#### 1.3.2. 唤醒

资源到来，`__wake_up_common` 函数唤醒等待进程/线程。tcp 完全链接，是通过客户端与服务端进行 `三次握手` 完成的，所以当三次握手成功时，内核会将链接添加到 listener 的完全连接队列，看看最后一次握手，服务端唤醒 listener 的等待队列中的等待的 进程/线程。

```shell
tcp_v4_rcv
|-- tcp_child_process
    |-- sk_data_ready # sock_def_wakeup
        |-- wake_up_interruptible_all # __wake_up_sync_key((x), TASK_INTERRUPTIBLE, 1, poll_to_key(m))
            |-- __wake_up_common_lock
                |-- __wake_up_common
                    |-- autoremove_wake_function # 唤醒。
```

* 第三次握手成功时，__wake_up_common 函数调用堆栈。

```shell
__wake_up_common(struct wait_queue_head * wq_head, unsigned int mode, int nr_exclusive, int wake_flags, void * key, wait_queue_entry_t * bookmark) (/root/linux-5.0.1/kernel/sched/wait.c:92)
__wake_up_common_lock(struct wait_queue_head * wq_head, unsigned int mode, int nr_exclusive, int wake_flags, void * key) (/root/linux-5.0.1/kernel/sched/wait.c:121)
__wake_up_sync_key(struct wait_queue_head * wq_head, unsigned int mode, int nr_exclusive, void * key) (/root/linux-5.0.1/kernel/sched/wait.c:199)
sock_def_readable(struct sock * sk) (/root/linux-5.0.1/net/core/sock.c:2643)
tcp_child_process(struct sock * parent, struct sock * child, struct sk_buff * skb) (/root/linux-5.0.1/net/ipv4/tcp_minisocks.c:848)
tcp_v4_rcv(struct sk_buff * skb) (/root/linux-5.0.1/net/ipv4/tcp_ipv4.c:1875)
ip_protocol_deliver_rcu(struct net * net, struct sk_buff * skb, int protocol) (/root/linux-5.0.1/net/ipv4/ip_input.c:208)
ip_local_deliver_finish(struct net * net, struct sock * sk, struct sk_buff * skb) (/root/linux-5.0.1/net/ipv4/ip_input.c:234)
NF_HOOK() (/root/linux-5.0.1/include/linux/netfilter.h:289)
ip_local_deliver(struct sk_buff * skb) (/root/linux-5.0.1/net/ipv4/ip_input.c:255)
NF_HOOK() (/root/linux-5.0.1/include/linux/netfilter.h:289)
ip_rcv(struct sk_buff * skb, struct net_device * dev, struct packet_type * pt, struct net_device * orig_dev) (/root/linux-5.0.1/net/ipv4/ip_input.c:524)
__netif_receive_skb_one_core(struct sk_buff * skb, bool pfmemalloc) (/root/linux-5.0.1/net/core/dev.c:4973)
process_backlog(struct napi_struct * napi, int quota) (/root/linux-5.0.1/net/core/dev.c:5923)
napi_poll() (/root/linux-5.0.1/net/core/dev.c:6346)
net_rx_action(struct softirq_action * h) (/root/linux-5.0.1/net/core/dev.c:6412)
__do_softirq() (/root/linux-5.0.1/kernel/softirq.c:292)
run_ksoftirqd(unsigned int cpu) (/root/linux-5.0.1/kernel/softirq.c:654)
smpboot_thread_fn(void * data) (/root/linux-5.0.1/kernel/smpboot.c:164)
kthread(void * _create) (/root/linux-5.0.1/kernel/kthread.c:246)
```

> 参考：[vscode + gdb 远程调试 linux (EPOLL) 内核源码](https://www.bilibili.com/video/bv1yo4y1k7QJ)

* listen 的 socket 在创建时就注册了 sk_data_ready 唤醒函数。

```c
/* include/net/sock.h */
struct sock {
    ...
    void (*sk_data_ready)(struct sock *sk);
    ...
}

static int inet_create(struct net *net, struct socket *sock, int protocol, int kern) {
    struct sock *sk;
    ...
    sock_init_data(sock, sk);
    ...
}

/* net/core/sock.c */
void sock_init_data(struct socket *sock, struct sock *sk) {
    sk_init_common(sk);
    ...
    sk->sk_data_ready = sock_def_readable;
    ...
}
```

* tcp 第三次握手成功，`__wake_up_common` 唤醒进程/线程。

```c
int tcp_v4_rcv(struct sk_buff *skb) {
process:
    ...
    if (sk->sk_state == TCP_NEW_SYN_RECV) {
        ...
        else if (tcp_child_process(sk, nsk, skb)) {
            ...
        }
        ...
    }
}

int tcp_child_process(struct sock *parent, struct sock *child,
              struct sk_buff *skb) {
    int ret = 0;
    int state = child->sk_state;
    ...
    tcp_segs_in(tcp_sk(child), skb);
    if (!sock_owned_by_user(child)) {
        ret = tcp_rcv_state_process(child, skb);
        /* Wakeup parent, send SIGIO */
        if (state == TCP_SYN_RECV && child->sk_state != state)
            /* 唤醒 */
            parent->sk_data_ready(parent);
    }
    ...
}

/* sk_data_ready */
static void sock_def_wakeup(struct sock *sk) {
    struct socket_wq *wq;

    rcu_read_lock();
    wq = rcu_dereference(sk->sk_wq);
    if (skwq_has_sleeper(wq))
        wake_up_interruptible_all(&wq->wait);
    rcu_read_unlock();
}

/* 调用 __wake_up_sync_key 函数，将 nr_exclusive 唤醒进程/线程的个数设置为 1. */
#define wake_up_interruptible_sync_poll(x, m)                    \
    __wake_up_sync_key((x), TASK_INTERRUPTIBLE, 1, poll_to_key(m))

void __wake_up_sync_key(struct wait_queue_head *wq_head, unsigned int mode,
            int nr_exclusive, void *key) {
    __wake_up_common_lock(wq_head, mode, nr_exclusive, wake_flags, key);
}

static void __wake_up_common_lock(struct wait_queue_head *wq_head, unsigned int mode,
            int nr_exclusive, int wake_flags, void *key) {
    ...
    nr_exclusive = __wake_up_common(wq_head, mode, nr_exclusive, wake_flags, key, &bookmark);
    ...
}

static int __wake_up_common(struct wait_queue_head *wq_head, unsigned int mode,
            int nr_exclusive, int wake_flags, void *key,
            wait_queue_entry_t *bookmark) {
    wait_queue_entry_t *curr, *next;
    int cnt = 0;
    ...
    /* 遍历唤醒等待队列。 */
    list_for_each_entry_safe_from(curr, next, &wq_head->head, entry) {
        unsigned flags = curr->flags;
        int ret;
        ...
        /* 将睡眠的进程唤醒。
         * curr->func ---> autoremove_wake_function */
        ret = curr->func(curr, mode, wake_flags, key);
        if (ret < 0)
            break;
        /* 如果设置了 WQ_FLAG_EXCLUSIVE 标签的话，执行一次唤醒（nr_exclusive == 1），就退出循环。 */
        if (ret && (flags & WQ_FLAG_EXCLUSIVE) && !--nr_exclusive)
            break;
        ...
    }

    return nr_exclusive;
}
```

---

### 1.4. 测试

通过多进程架构进行测试，主进程 listen，fork 两个子进程分别进行 accept。验证了阻塞的 accept 不会产生惊群问题。

> Linux 线程与进程工作原理几乎一样，大家可以测测多线程。

```shell
# 主进程 listen，fork 两个子进程（child pid: 69312,69313）进行 accept。
[s][69311][2021-09-27 19:08:56.070][server.c][init_server:12] init server.....
[s][69311][2021-09-27 19:08:56.070][server.c][init_server:24] create listen socket, fd: 4.
[s][69311][2021-09-27 19:08:56.070][server.c][init_server:48] server start now, ip: 127.0.0.1, port: 5001.
[c][69311][2021-09-27 19:08:56.070][main.c][workers:79] child pid: 69312
[c][69311][2021-09-27 19:08:56.071][main.c][workers:79] child pid: 69313
[s][69312][2021-09-27 19:08:56.071][server.c][run_server:53] run server.....
[s][69313][2021-09-27 19:08:56.071][server.c][run_server:53] run server.....

# 新连接到来，只有一个进程（pid: 69312） accept 到资源。
[s][69312][2021-09-27 19:09:00.795][server.c][run_server:76] accept new client, pid: 69312, fd: 5, ip: 127.0.0.1, port: 40502

# 新连接到来，只有一个进程（pid: 69313） accept 到资源。
[s][69313][2021-09-27 19:09:02.266][server.c][run_server:76] accept new client, pid: 69313, fd: 5, ip: 127.0.0.1, port: 40504
```

---

## 2. epoll 惊群

经过对阻塞的 accept 服务模型进行分析，我们应该可以理解惊群的避免解决方法了，这个问题内核早已解决，不需要用户处理了。

现在 Linux 高性能服务一般都使用一些异步的 IO 模型：`select/poll/epoll`，不再是通过 accept 阻塞去获取资源，例如 🌰：redis / nginx。

> redis 为啥那么快，通过 epoll 事件驱动处理事件就是快的其中一个原因。

如果我们使用 epoll 多路复用 IO 模型，那么它就会通过 `epoll_wait` 去超时阻塞等待资源，直到获取到就绪事件（暂不考虑超时，信号，异常等原因），才会唤醒进程处理事件。

所以接下来，要分析 epoll 模型，它是否也会产生惊群问题。

---

### 2.1. 单进程

使用 epoll 非常高效，单进程/线程也能实现高性能服务。所以只要使用单进程去 `epoll_wait` 等待资源，就不会存在什么 “惊群” 问题。例如：redis。

---

#### 2.1.1. redis

Linux 系统，redis 默认使用 epoll 异步事件驱动，可以高效地处理网络事件。

redis 的网络逻辑是在主进程（主线程）中实现的，一个进程（主线程）何来 “惊群”？！所以 redis 不存在 “惊群” 问题。

> 参考：《[[redis 源码走读] 异步通信流程-单线程](http://wenfh2020.com/2020/04/30/redis-async-communication/)》

<div align=center><img src="/images/2021-09-28-12-41-03.png" data-action="zoom"/></div>

---

#### 2.1.2. 文件描述符透传

redis 是数据服务，业务逻辑相对简单，单进程也能很好地完成任务，然而一般的高性能服务业务逻辑比较复杂，单进程显然无法很好地完成业务逻辑，需要利用多核资源，创建多个进程去处理业务逻辑。

那么多进程怎么避免 “惊群” 呢？

有一个比较典型的服务模型，就是一个进程去 accept listener 的资源，然后通过 socket pair 管道进行文件描述符传输给子进程。

如下图，master 主进程负责 listener 资源的 accept，当主进程获得资源，按照一定的策略，分派给相应的子进程。相当于 master 是管理者，子进程是一线员工。

虽然文件描述符透传这个是多进程模型，但因为只有一个 master 进程在等待 listener 的资源，所以也不存在多个进程争抢资源的 “惊群” 问题。

> 参考：《[[kimserver] 父子进程传输文件描述符](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)》

<div align=center><img src="/images/2021-09-28-14-10-47.png" data-action="zoom"/></div>

---

### 2.2. 多进程

#### 2.2.1. nginx

nginx 是典型的多进程网络模型，为了利用多核的资源，主进程 fork 了多个子进程，处理网络事件。

---

## 3. 结果

线程或进程切换，内核需要保存上下文以及寄存器等资源，频繁切换会导致系统资源损耗。

---

## 4. 测试

[源码](https://github.com/wenfh2020/c_test/blob/master/network/thundering_herd/main.cpp) server 是 epoll 事件模型，client 用 telnet 即可。

---

## 5. 参考

* [一个epoll惊群导致的性能问题](https://www.ichenfu.com/2017/05/03/proxy-epoll-thundering-herd/)
* [Linux惊群效应详解](https://blog.csdn.net/lyztyycode/article/details/78648798)
* [Linux 最新SO_REUSEPORT特性](https://www.cnblogs.com/Anker/p/7076537.html)
* [[kimserver] 父子进程传输文件描述符](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)
