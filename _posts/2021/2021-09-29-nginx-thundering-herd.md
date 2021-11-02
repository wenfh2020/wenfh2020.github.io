---
layout: post
title:  "探索惊群 ③ - nginx 惊群现象"
categories: nginx kernel
tags: linux nginx thundering herd
author: wenfh2020
---

本文将深入 Linux (5.0.1) 内核源码，剖析基于 TCP 协议的 nginx (1.20.1) ，它产生惊群现象的原因。





* content
{:toc}

---

## 1. nginx 惊群现象

在不配置 nginx 处理惊群特性的情况下，通过 `strace` 命令观察 nginx 的系统调用日志。

由测试现象可见，等待资源的两个进程同时被唤醒，进程 1 获得资源，进程 2 获取资源失败，惊群现象发生了！

> 先不配置 accept_mutex，reuseport 等特性，后面会详细剖析。

<div align=center><img src="/images/2021-10-06-23-02-19.png" data-action="zoom"/></div>

* nginx 启动后进程情况。

```shell
# strace -f -s 512 -o /tmp/nginx.log /usr/local/nginx/sbin/nginx
root      79980      1  0 22:28 ?        00:00:00 nginx: master process /usr/local/nginx/sbin/nginx
nobody    79981  79980  0 22:28 ?        00:00:00 nginx: worker process      
nobody    79982  79980  0 22:28 ?        00:00:00 nginx: worker process
```

* telnet 测试。

```shell
telnet 127.0.0.1 80
```

* nginx 系统调用。

```shell
# 1. pid   2. syscall

# 主进程。
# 79979 进程启动加载 nginx。nginx 主进程 socket -> bind -> listen。
79979 socket(PF_INET, SOCK_STREAM, IPPROTO_IP) = 6
79979 bind(6, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("0.0.0.0")}, 16) = 0
79979 listen(6, 511)                    = 0
# (79979)进程 clone 子进程(79980) 作为 nginx 的主进程。
79979 clone(child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f9e6f67fa10) = 79980
# nginx 主进程 fork 两个子进程作为工作进程：79981，79982。
79980 clone(child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f9e6f67fa10) = 79981
79980 clone( <unfinished ...>
79980 <... clone resumed> child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f9e6f67fa10) = 79982

# 子进程 79981
79980 clone(child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f9e6f67fa10) = 79981
79981 epoll_create(512 <unfinished ...>
79981 <... epoll_create resumed> )      = 8
# 子进程 epoll 监控共享的 listen socket ---> 6。
79981 epoll_ctl(8, EPOLL_CTL_ADD, 6, {EPOLLIN|EPOLLRDHUP, {u32=1868849168, u64=140318450409488}} <unfinished ...>
# 子进程 79981 被唤醒。
79981 epoll_wait(8, {{EPOLLIN, {u32=1868849392, u64=140318450409712}}}, 512, -1) = 1
79981 epoll_wait(8,  <unfinished ...>
79981 accept4(6,  <unfinished ...>
# accept4 成功获取一个链接资源。
79981 <... accept4 resumed> {sa_family=AF_INET, sin_port=htons(58960), sin_addr=inet_addr("127.0.0.1")}, [16], SOCK_NONBLOCK) = 10
79981 epoll_ctl(8, EPOLL_CTL_ADD, 10, {EPOLLIN|EPOLLRDHUP|EPOLLET, {u32=1868849616, u64=140318450409936}}) = 0
79981 epoll_wait(8, {{EPOLLIN|EPOLLRDHUP, {u32=1868849616, u64=140318450409936}}}, 512, 60000) = 1
79981 recvfrom(10, "", 1024, 0, NULL, NULL) = 0
79981 close(10)                         = 0

# 子进程 79982
79980 <... clone resumed> child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f9e6f67fa10) = 79982
79982 epoll_create(512 <unfinished ...>
79982 <... epoll_create resumed> )      = 10
79982 epoll_wait(10,  <unfinished ...>
# 子进程 epoll 监控共享的 listen socket ---> 6。
79982 epoll_ctl(10, EPOLL_CTL_ADD, 6, {EPOLLIN|EPOLLRDHUP, {u32=1868849168, u64=140318450409488}}) = 0
79982 epoll_wait(10,  <unfinished ...>
# 子进程被唤醒后，accept4 获取链接资源失败，返回 EAGAIN。
79982 accept4(6,  <unfinished ...>
79982 <... accept4 resumed> 0x7ffe70c17e40, [112], SOCK_NONBLOCK) = -1 EAGAIN (Resource temporarily unavailable)
79982 epoll_wait(10,  <unfinished ...>
```

---

## 2. 原因

惊群现象出现，子进程 2 被唤醒但是并没有 accept 到链接资源。原因：

两个子进程通过 epoll_ctl 添加关注了主进程创建的 socket，当该 listen socket 没有资源时，子进程都通过 epoll_wait 进入了阻塞睡眠状态。也就是子进程分别往 socket.wq 等待队列添加了各自的等待事件，因为添加的方式是 `add_wait_queue`，而不是 add_wait_queue_exclusive。

但是 add_wait_queue 并没有设置 `WQ_FLAG_EXCLUSIVE` 排它唤醒标识，所以当 listen socket 的资源到来时，内核通过 `__wake_up_common` 去唤醒两个子进程去 accept 获取资源。
  
如果只有一个链接资源，那么 nginx 的两个子进程被唤醒，当然只有一个子进程能成功，另外一个则无功而返。

* socket 结构。

```c
/* include/linux/net.h*/
struct socket {
    ...
    struct socket_wq *wq; /* socket 等待队列。 */
    ...
};
```

* 进程在 epoll_ctl 关注 listen socket 时，添加了当前进程的等待事件到 socket.wq 等待队列，进程的 epoll 唤醒回调函数 ep_poll_callback 与 socket 关联起来了。

```c
/* fs/eventpoll.c */
static void ep_ptable_queue_proc(struct file *file, wait_queue_head_t *whead, poll_table *pt) {
    struct epitem *epi = ep_item_from_epqueue(pt);
    struct eppoll_entry *pwq;

    if (epi->nwait >= 0 && (pwq = kmem_cache_alloc(pwq_cache, GFP_KERNEL)) {
        init_waitqueue_func_entry(&pwq->wait, ep_poll_callback);
        pwq->whead = whead;
        pwq->base = epi;
        if (epi->event.events & EPOLLEXCLUSIVE)
            add_wait_queue_exclusive(whead, &pwq->wait);
        else
            /* 因为 nginx 默认情况下是没有开启 EPOLLEXCLUSIVE 特性的，
             * 所以调用的是没有设置排它性属性的函数 add_wait_queue。  */
            add_wait_queue(whead, &pwq->wait);
        ...
    }
    ...
}
```

* 当 listen socket 的资源到来，唤醒等待的进程。因为 add_wait_queue 没有添加 WQ_FLAG_EXCLUSIVE 标识，所以两个子进程被唤醒。

```c
/* kernel/sched/wait.c
 * This is the callback that is passed to the wait queue wakeup
 * mechanism. It is called by the stored file descriptors when they
 * have events to report. */
static int __wake_up_common(struct wait_queue_head *wq_head, unsigned int mode,
            int nr_exclusive, int wake_flags, void *key,
            wait_queue_entry_t *bookmark) {
    wait_queue_entry_t *curr, *next;
    int cnt = 0;
    ...
    /* 遍历等待队列，调用唤醒函数去唤醒进程。 */
    list_for_each_entry_safe_from(curr, next, &wq_head->head, entry) {
        unsigned flags = curr->flags;
        int ret;
        ...
        /* 调用进程唤醒回调函数：ep_poll_callback。*/
        ret = curr->func(curr, mode, wake_flags, key);
        if (ret < 0)
            break;
        /* 检测 WQ_FLAG_EXCLUSIVE 属性，是否只唤醒一个进。*/
        if (ret && (flags & WQ_FLAG_EXCLUSIVE) && !--nr_exclusive)
            break;
        ...
    }
    ...
}
```

---

## 3. 原理

### 3.1. 基本原理

先捋一捋这个通知唤醒的工作流程：tcp 产生链接资源后唤醒阻塞等待的子进程去 accept 获取。

* tcp 协议的链接是通过三次握手实现的，而完整的链接资源是服务端在第三次握手中产生的，服务端会将新的链接资源存储在 listen socket 的完全队列中。

* nginx 作为高性能服务程序，在 Linux 系统，它处理网络事件时，一般会采用 epoll 事件驱动。它通过 `epoll_wait` 等待事件，当通过 epoll_ctl 关注的 tcp listen socket 产生事件时，阻塞等待的 epoll_wait 被唤醒去 accept 链接资源。

---

### 3.2. 等待唤醒流程

1. 进程通过 epoll_ctl 监控 listen socket 的 EPOLLIN 事件。
2. 进程通过 epoll_wait 阻塞等待监控的 listen socket 事件触发，然后返回。
3. tcp 第三次握手，服务端产生新的链接资源。
4. 内核将链接资源保存到 listen socket 的完全队列中。
5. 内核唤醒步骤2的进程去 accept 获取 listen socket 完全队列中的链接资源。

<div align=center><img src="/images/2021-10-14-11-21-46.png" data-action="zoom"/></div>

---

### 3.3. 内核原理

通过下图，了解一下服务端 tcp 的第三次握手和 epoll 内核的等待唤醒工作流程。

<div align=center><img src="/images/2021-10-13-23-39-31.png" data-action="zoom"/></div>

1. 进程通过 epoll_create 创建 eventpoll 对象。
2. 进程通过 epoll_ctl 添加关注 listen socket 的 EPOLLIN 可读事件。
3. 接步骤 2，epoll_ctl 还将 epoll 的 socket 唤醒等待事件（唤醒函数：ep_poll_callback）通过 add_wait_queue 函数添加到 socket.wq 等待队列。
   > 当 listen socket 有链接资源时，内核通过 __wake_up_common 调用 epoll 的 ep_poll_callback 唤醒函数，唤醒进程。
4. 进程通过 epoll_wait 等待就绪事件，往 eventpoll.wq 等待队列中添加当前进程的等待事件，当 epoll_ctl 监控的 socket 产生对应的事件时，被唤醒返回。
5. 客户端通过 tcp connect 链接服务端，三次握手成功，第三次握手在服务端进程产生新的链接资源。
6. 服务端进程根据 socket.wq 等待队列，唤醒正在等待资源的进程处理。例如 nginx 的惊群现象，__wake_up_common 唤醒等待队列上的两个等待进程，调用 ep_poll_callback 去唤醒 epoll_wait 阻塞等待的进程。
7. ep_poll_callback 唤醒回调会检查 listen socket 的完全队列是否为空，如果不为空，那么就将 epoll_ctl 监控的 listen socket 的节点 epi 添加到 `就绪队列`：eventpoll.rdllist，然后唤醒 eventpoll.wq 里通过 epoll_wait 等待的进程，处理 eventpoll.rdllist 上的事件数据。
8. 睡眠在内核的 epoll_wait 被唤醒后，内核通过 ep_send_events 将就绪事件数据，从内核空间拷贝到用户空间，然后进程从内核空间返回到用户空间。
9. epoll_wait 被唤醒，返回用户空间，读取 listen socket 返回的 EPOLLIN 事件，然后 accept listen socket 完全队列上的链接资源。

---

`【注意】` 有了 socket.wq 为啥还要有 eventpoll.wq 啊？因为 listen socket 能被多个进程共享，epoll 实例也能被多个进程共享！

* 添加等待事件流程：
  
  epoll_ctl -> listen socket -> add_wait_queue <+ep_poll_callback+> -> socket.wq ==> epoll_wait -> eventpoll.wq

* 唤醒流程：
  
  tcp_v4_rcv -> socket.wq -> __wake_up_common -> ep_poll_callback -> eventpoll.wq -> wake_up_locked -> epoll_wait -> accept

---

## 4. 内核源码分析

### 4.1. TCP 三次握手

客户端主动链接服务端，TCP 三次握手成功后，服务端产生新的 tcp 链接资源，内核将唤醒 socket.wq 上的等待进程，通过 accept 从 listen socket 上的 `全链接队列` 中获取 TCP 链接资源。

<div align=center><img src="/images/2021-08-18-13-26-18.png" data-action="zoom"/></div>

> 参考：[《[内核源码] 网络协议栈 - tcp 三次握手状态》](https://wenfh2020.com/2021/08/17/kernel-tcp-handshakes/) [《[内核源码] 网络协议栈 - listen (tcp)》](https://wenfh2020.com/2021/07/21/kernel-sys-listen/)

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

/* 三次握手，服务端第二次握手。 */
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

/* parent 参数是 listen socket 的网络对象指针。 */
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
        /* 将睡眠的进程唤醒: ep_poll_callback。 */
        ret = curr->func(curr, mode, wake_flags, key);
        if (ret < 0)
            break;
        if (ret && (flags & WQ_FLAG_EXCLUSIVE) && !--nr_exclusive)
            break;
        ...
    }

    return nr_exclusive;
}
```

---

### 4.2. epoll

#### 4.2.1. epoll_wait 逻辑

epoll_wait 它的核心实现逻辑并不复杂，先添加进程的等待事件，然后检查就绪队列是否有就绪事件，如果没有就绪事件就睡眠等待，如果有事件就唤醒，将就绪事件从内核空间拷贝到用户空间，然后删除进程的等待事件。

```shell
#------------------- *用户空间* ---------------------------
epoll_wait
#------------------- *内核空间* ---------------------------
|-- do_epoll_wait
    |-- ep_poll
```

```c
/* fs/eventpoll.c */
static int ep_poll(struct eventpoll *ep, struct epoll_event __user *events,
           int maxevents, long timeout) {
    ...
fetch_events:
    ...
    /* 检查 epoll 是否有就绪事件。 */
    eavail = ep_events_available(ep);
    if (eavail)
        /* 如果有就绪事件，直接将事件从内核空间拷贝到用户空间，不需要睡眠等待。 */
        goto send_events;
    ...
    /* 如果没有就绪事件，进程将进入睡眠等待状态，添加等待事件到等待队列。
     * 当 epoll 关注的文件有对应的事件发生，会触发 ep_poll_callback 函数（epoll_ctl 里绑定的），
     * 唤醒等待队列里的对应进程。 */
    if (!waiter) {
        waiter = true;
        init_waitqueue_entry(&wait, current);
        spin_lock_irq(&ep->wq.lock);
        /* epoll 往等待队列中，添加当前进程的等待事件，等待唤醒。 */
        __add_wait_queue_exclusive(&ep->wq, &wait);
        spin_unlock_irq(&ep->wq.lock);
    }

    for (;;) {
        /* 将进程设置为可被中断唤醒的睡眠状态。 */
        set_current_state(TASK_INTERRUPTIBLE);
        ...
        /* 再检查是否有就绪事件发生，如果有就不睡了。 */
        eavail = ep_events_available(ep);
        if (eavail)
            break;
        ...
        /* 进入超时等待睡眠状态。 */
        if (!schedule_hrtimeout_range(to, slack, HRTIMER_MODE_ABS)) {
            timed_out = 1;
            break;
        }
    }

    /* 上面循环退出，进程恢复运行状态。 */
    __set_current_state(TASK_RUNNING);

send_events:
    /* 如果检测到有就绪事件发生，内核空间向用户空间拷贝就绪事件。 */
    if (!res && eavail &&
        !(res = ep_send_events(ep, events, maxevents)) && !timed_out)
        goto fetch_events;

    if (waiter) {
        spin_lock_irq(&ep->wq.lock);
        /* epoll 从等待队列中，删除当前进程的等待事件。 */
        __remove_wait_queue(&ep->wq, &wait);
        spin_unlock_irq(&ep->wq.lock);
    }
}
```

---

#### 4.2.2. epoll_wait 睡眠等待逻辑

epoll_wait 通过 __add_wait_queue_exclusive 函数添加 `WQ_FLAG_EXCLUSIVE` 排它性唤醒属性的等待事件到等待队列，表明当 ep_poll_callback 回调函数被调用时（<font color=gray>请看下面 ep_poll 源码的英文注释</font>），拥有 epoll fd 的进程只能有一个被唤醒处理资源（有可能有多个进程共享 epoll，而 nginx 每个子进程都有自己独立的 epoll 实例，不共享）。通过__remove_wait_queue 函数删除对应的等待事件。

```c
/* include/linux/wait.h */
static inline void
__add_wait_queue_exclusive(struct wait_queue_head *wq_head, struct wait_queue_entry *wq_entry) {
    /* 唤醒事件，增加了 WQ_FLAG_EXCLUSIVE 排它性唤醒属性。*/
    wq_entry->flags |= WQ_FLAG_EXCLUSIVE;
    __add_wait_queue(wq_head, wq_entry);
}

/* fs/eventpoll.c */
static int ep_poll(struct eventpoll *ep, struct epoll_event __user *events,
           int maxevents, long timeout) {
    ...
    /*
     * We don't have any available event to return to the caller.  We need
     * to sleep here, and we will be woken by ep_poll_callback() when events
     * become available.
     */
    if (!waiter) {
        waiter = true;
        init_waitqueue_entry(&wait, current);

        spin_lock_irq(&ep->wq.lock);
        /* 添加排它性唤醒标识，将等待事件添加到 epoll 的等待队列。 */
        __add_wait_queue_exclusive(&ep->wq, &wait);
        spin_unlock_irq(&ep->wq.lock);
    }
    ...
}
```

---

#### 4.2.3. epoll_wait 唤醒流程

##### 4.2.3.1. socket 注册唤醒函数

epoll_ctl -> listen socket -> add_wait_queue <+ep_poll_callback+> -> socket.wq

* 函数调用堆栈。
  
  通过函数堆栈，可以发现：epoll 里的进程睡眠唤醒函数 ep_poll_callback，与 tcp socket 关联起来了，睡眠事件添加到 socket 的睡眠队列里，当 socket 有对应的就绪事件，就会触发对应的函数，在这里就会触发 ep_poll_callback。

```shell
init_waitqueue_func_entry() (/root/linux-5.0.1/include/linux/wait.h:89)
ep_ptable_queue_proc(struct file * file, wait_queue_head_t * whead, poll_table * pt) (/root/linux-5.0.1/fs/eventpoll.c:1245)
poll_wait() (/root/linux-5.0.1/include/linux/poll.h:47)
sock_poll_wait() (/root/linux-5.0.1/include/net/sock.h:2091)
tcp_poll(struct file * file, struct socket * sock, poll_table * wait) (/root/linux-5.0.1/net/ipv4/tcp.c:510)
sock_poll(struct file * file, poll_table * wait) (/root/linux-5.0.1/net/socket.c:1128)
vfs_poll() (/root/linux-5.0.1/include/linux/poll.h:86)
ep_item_poll(poll_table * pt, int depth) (/root/linux-5.0.1/fs/eventpoll.c:892)
ep_insert(struct eventpoll * ep, const struct epoll_event * event, struct file * tfile, int fd, int full_check) (/root/linux-5.0.1/fs/eventpoll.c:1463)
__do_sys_epoll_ctl() (/root/linux-5.0.1/fs/eventpoll.c:2139)
__se_sys_epoll_ctl() (/root/linux-5.0.1/fs/eventpoll.c:2025)
__x64_sys_epoll_ctl(const struct pt_regs * regs) (/root/linux-5.0.1/fs/eventpoll.c:2025)
do_syscall_64(unsigned long nr, struct pt_regs * regs) (/root/linux-5.0.1/arch/x86/entry/common.c:290)
entry_SYSCALL_64() (/root/linux-5.0.1/arch/x86/entry/entry_64.S:175)
[Unknown/Just-In-Time compiled code] (Unknown Source:0)
```

> 参考：[vscode + gdb 远程调试 linux (EPOLL) 内核源码](https://www.bilibili.com/video/bv1yo4y1k7QJ)

* 内核源码。

```c
/* epoll 结构对象。*/
struct eventpoll {
    ...
    /* 使用当前 epoll 的进程等待队列。 */
    wait_queue_head_t wq;
    ...
    /* 就绪队列。关注事件已发生，将对应的 fd 节点 epi 添加到就绪队列。 */
    struct list_head rdllist;
    ...
};

/* socket 结构。 */
struct socket {
    ...
    struct socket_wq *wq; /* socket 等待队列。 */
    struct file      *file;
    struct sock      *sk;
    ...
};

/* fs/eventpoll.c */
SYSCALL_DEFINE4(epoll_ctl, int, epfd, int, op, int, fd,
        struct epoll_event __user *, event) {
    ...
    struct epitem *epi;
    ...
    epi = ep_find(ep, tf.file, fd);
    error = -EINVAL;
    switch (op) {
    case EPOLL_CTL_ADD:
        if (!epi) {
            epds.events |= EPOLLERR | EPOLLHUP;
            error = ep_insert(ep, &epds, tf.file, fd, full_check);
        }
        ...
    }
    ...
}

/* fs/eventpoll.c */
static int ep_insert(struct eventpoll *ep, const struct epoll_event *event,
             struct file *tfile, int fd, int full_check) {
    ...
    struct epitem *epi;
    struct ep_pqueue epq;
    ...
    if (!(epi = kmem_cache_alloc(epi_cache, GFP_KERNEL)))
        return -ENOMEM;
    ...
    /* Initialize the poll table using the queue callback */
    epq.epi = epi;
    init_poll_funcptr(&epq.pt, ep_ptable_queue_proc);
    ...
    /* ep_item_poll 通过 ep_ptable_queue_proc 函数的调用，
     * 将 ep_poll_callback 回调函数与对应的 socket 进行绑定。
     * 同时检查并返回对应的 socket 已发生的就绪事件。 */
    revents = ep_item_poll(epi, &epq.pt, 1);
    ...
}

/* include/linux/poll.h */
static inline void init_poll_funcptr(poll_table *pt, poll_queue_proc qproc) {
    pt->_qproc = qproc;
    pt->_key   = ~(__poll_t)0; /* all events enabled */
}

/* fs/eventpoll.c */
static __poll_t ep_item_poll(const struct epitem *epi, poll_table *pt, int depth) {
    struct eventpoll *ep;
    bool locked;

    pt->_key = epi->event.events;
    if (!is_file_epoll(epi->ffd.file))
        return vfs_poll(epi->ffd.file, pt) & epi->event.events;
    ...
}

/* include/linux/poll.h */
static inline __poll_t vfs_poll(struct file *file, struct poll_table_struct *pt) {
    ...
    return file->f_op->poll(file, pt);
}

/* net/socket.c */
static __poll_t sock_poll(struct file *file, poll_table *wait) {
    struct socket *sock = file->private_data;
    ...
    return sock->ops->poll(file, sock, wait) | flag;
}

/* net/ipv4/tcp.c */
__poll_t tcp_poll(struct file *file, struct socket *sock, poll_table *wait) {
    __poll_t mask;
    struct sock *sk = sock->sk;
    const struct tcp_sock *tp = tcp_sk(sk);
    int state;

    sock_poll_wait(file, sock, wait);

    state = inet_sk_state_load(sk);
    if (state == TCP_LISTEN)
        /* 要检查完全队列是否有准备就绪的链接提供 accept。 */
        return inet_csk_listen_poll(sk);
    ...
}

/* include/net/inet_connection_sock.h */
static inline __poll_t inet_csk_listen_poll(const struct sock *sk) {
    /* 根据 listen socket 的完全队列是否为空返回对应的事件。 */
    return !reqsk_queue_empty(&inet_csk(sk)->icsk_accept_queue) ?
            (EPOLLIN | EPOLLRDNORM) : 0;
}

/* include/net/sock.h */
static inline void sock_poll_wait(struct file *filp, struct socket *sock, poll_table *p) {
    if (!poll_does_not_wait(p)) {
        poll_wait(filp, &sock->wq->wait, p);
        ...
    }
}

/* include/linux/poll.h */
static inline void poll_wait(struct file * filp, wait_queue_head_t * wait_address, poll_table *p) {
    if (p && p->_qproc && wait_address)
        /* ep_ptable_queue_proc */
        p->_qproc(filp, wait_address, p);
}

/* 进程添加等待事件到 socket.wq 等待队列，
 * 进程的 epoll 唤醒函数 ep_poll_callback 与 socket 关联起来了。*/
static void ep_ptable_queue_proc(struct file *file, wait_queue_head_t *whead, poll_table *pt) {
    struct epitem *epi = ep_item_from_epqueue(pt);
    struct eppoll_entry *pwq;

    if (epi->nwait >= 0 && (pwq = kmem_cache_alloc(pwq_cache, GFP_KERNEL)) {
        init_waitqueue_func_entry(&pwq->wait, ep_poll_callback);
        pwq->whead = whead;
        pwq->base = epi;
        if (epi->event.events & EPOLLEXCLUSIVE)
            add_wait_queue_exclusive(whead, &pwq->wait);
        else
            /* 因为 nginx 默认情况下是没有开启 EPOLLEXCLUSIVE 特性的，
             * 所以调用的是没有设置排它性属性的函数 add_wait_queue。  */
            add_wait_queue(whead, &pwq->wait);
        ...
    }
    ...
}
```

---

##### 4.2.3.2. epoll_wait 唤醒

tcp_v4_rcv -> socket.wq -> __wake_up_common -> ep_poll_callback -> eventpoll.wq -> wake_up_locked -> epoll_wait

```c
/*
 * This is the callback that is passed to the wait queue wakeup
 * mechanism. It is called by the stored file descriptors when they
 * have events to report.
 */
static int ep_poll_callback(wait_queue_entry_t *wait, unsigned mode, int sync, void *key) {
    int pwake = 0;
    unsigned long flags;
    struct epitem *epi = ep_item_from_wait(wait);
    struct eventpoll *ep = epi->ep;
    __poll_t pollflags = key_to_poll(key);
    int ewake = 0;
    ...
    /* 检查已经发生的就绪事件 pollflags，是否是用户关注（epoll_ctl）的就绪事件，
     * 如果不是就返回。*/
    if (pollflags && !(pollflags & epi->event.events))
        goto out_unlock;
    ...
    /* 如果发生的事件是用户关注的事件，而且就绪列表上还没有添加这个 fd 节点 epi，
     * 那么将 epi 添加到就绪队列尾部。 */
    if (!ep_is_linked(epi)) {
        list_add_tail(&epi->rdllink, &ep->rdllist);
        ep_pm_stay_awake_rcu(epi);
    }

    /*
     * Wake up ( if active ) both the eventpoll wait list and the ->poll()
     * wait list.
     */
    if (waitqueue_active(&ep->wq)) {
        ...
        /* 唤醒通过 epoll_wait 睡眠的进程。 */
        wake_up_locked(&ep->wq);
    }
    ...
}

/* include/linux/wait.h */
#define wake_up_locked(x) __wake_up_locked((x), TASK_NORMAL, 1)

/* kernel/sched/wait.c */
void __wake_up_locked(struct wait_queue_head *wq_head, unsigned int mode, int nr) {
    __wake_up_common(wq_head, mode, nr, 0, NULL, NULL);
}

/* kernel/sched/wait.c */
static int __wake_up_common(struct wait_queue_head *wq_head, unsigned int mode,
            int nr_exclusive, int wake_flags, void *key,
            wait_queue_entry_t *bookmark) {
    wait_queue_entry_t *curr, *next;
    int cnt = 0;
    ...
    list_for_each_entry_safe_from(curr, next, &wq_head->head, entry) {
        unsigned flags = curr->flags;
        int ret;

        if (flags & WQ_FLAG_BOOKMARK)
            continue;

        /* 唤醒进程。 */
        ret = curr->func(curr, mode, wake_flags, key);
        if (ret < 0)
            break;
        /* 排它性唤醒属性，而且 nr_exclusive == 1，所以循环只执行一次就退出，
         * 也就是只唤醒了一个进程。 */
        if (ret && (flags & WQ_FLAG_EXCLUSIVE) && !--nr_exclusive)
            break;
        ...
    }
    ...
}
```

---

## 5. 参考

* [Nginx的accept_mutex配置](https://blog.csdn.net/adams_wu/article/details/51669203)
* [Nginx 是如何解决 epoll 惊群的](https://ld246.com/article/1588731832846)
* [关于ngx_trylock_accept_mutex的一些解释](https://blog.csdn.net/brainkick/article/details/9081017)
* [linux性能诊断-perf](https://juejin.cn/post/6844903793348313102)
* [牛逼的Linux性能剖析—perf](https://juejin.cn/post/6844903793348313102)
