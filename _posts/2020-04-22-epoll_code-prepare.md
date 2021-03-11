---
layout: post
title:  "[epoll 源码走读] epoll 源码实现-预备知识"
categories: network
tags: epoll Linux
author: wenfh2020
---

epoll 源码涉及到很多知识点：（socket）网络通信，进程调度，等待队列，socket 信号处理，VFS（虚拟文件系统），红黑树算法等等知识点。有些接口的实现，藏得很深，参考了不少网上的帖子，在此整理一下。

> 本文主要为 《[[epoll 源码走读] epoll 实现原理](https://wenfh2020.com/2020/04/23/epoll-code/)》，提供预备知识。



* content
{:toc}

---

## 1. 网络数据传输流程

网络数据是如何从网卡传到内核，内核如何将数据传到用户层的。

> 参考 [Linux网络包收发总体过程](https://www.cnblogs.com/zhjh256/p/12227883.html)
>
> 参考 [epoll源码分析](https://www.cnblogs.com/diegodu/p/9377535.html)

---

## 2. 内核进程调度

网络通信过程中，进程什么时候睡眠，什么时候唤醒，一个 cpu 为何能跑多个进程，进程是如何调度的。

> 参考 [彻底理解epoll](https://blog.csdn.net/qq_31967569/article/details/102953756)

```c
/* Used in tsk->state: */

// sched.h
#define TASK_RUNNING            0x0000
#define TASK_INTERRUPTIBLE      0x0001
#define TASK_UNINTERRUPTIBLE    0x0002
```

| 进程状态             | 描述                               |
| :------------------- | :--------------------------------- |
| TASK_RUNNING         | 正在运行                           |
| TASK_INTERRUPTIBLE   | 等待状态。等待状态可被信号解除。   |
| TASK_UNINTERRUPTIBLE | 等待状态。等待状态不可被信号解除。 |

---

## 3. 等待队列

什么是等待队列，进程阻塞睡眠后，内核如何通过等待队列唤醒进程工作。

> 参考 [linux等待队列 wait_queue 的使用](https://blog.csdn.net/u012218309/article/details/81148083)。

---

## 4. 文件描述符

fd 文件描述符是什么，socket 是什么，Linux 一切皆文件，它通过 vfs 虚拟文件系统进行管理。

> 参考 [Linux 进程、线程、文件描述符的底层原理](https://www.solves.com.cn/news/hlw/2020-03-15/13907.html)

---

### 4.1. 创建 socket

```c
// socket.c
int __sys_socket(int family, int type, int protocol) {
    ...
    // 创建 socket。
    retval = sock_create(family, type, protocol, &sock);
    if (retval < 0)
        return retval;

    return sock_map_fd(sock, flags & (O_CLOEXEC | O_NONBLOCK));
}
```

---

### 4.2. accept

accept 分配 socket 资源。

```c
// socket.c
int __sys_accept4_file(struct file *file, unsigned file_flags,
               struct sockaddr __user *upeer_sockaddr,
               int __user *upeer_addrlen, int flags) {
    ...
    newfile = sock_alloc_file(newsock, flags, sock->sk->sk_prot_creator->name);
    if (IS_ERR(newfile)) {
        err = PTR_ERR(newfile);
        put_unused_fd(newfd);
        goto out;
    }
    ...
}
```

---

### 4.3. socket 关联 fd/file

```c
// socket.c
static int sock_map_fd(struct socket *sock, int flags) {
    struct file *newfile;
    // 分配一个空闲的 fd 文件描述符。
    int fd = get_unused_fd_flags(flags);
    if (unlikely(fd < 0)) {
        sock_release(sock);
        return fd;
    }

    // socket 与文件建立联系。
    newfile = sock_alloc_file(sock, flags, NULL);
    if (!IS_ERR(newfile)) {
        // fd 文件描述符绑定 file 文件对象。
        fd_install(fd, newfile);
        return fd;
    }
    ...
}

// socket.c
struct file *sock_alloc_file(struct socket *sock, int flags, const char *dname) {
    struct file *file;

    if (!dname)
        dname = sock->sk ? sock->sk->sk_prot_creator->name : "";

    file = alloc_file_pseudo(SOCK_INODE(sock), sock_mnt, dname,
                O_RDWR | (flags & O_NONBLOCK),
                &socket_file_ops);
    if (IS_ERR(file)) {
        sock_release(sock);
        return file;
    }

    // socket 与文件建立联系。
    sock->file = file;
    file->private_data = sock;
    stream_open(SOCK_INODE(sock), file);
    return file;
}
```

---

### 4.4. socket 关联 sock

`sock_init_data` 将 socket 关联 sock。sock 等待队列指向 socket 等待队列。

```c
// socket.c
int __sys_socket(int family, int type, int protocol) {
    ...
    // 创建 socket。
    retval = sock_create(family, type, protocol, &sock);
    ...
}

// socket.c
int sock_create(int family, int type, int protocol, struct socket **res) {
    return __sock_create(current->nsproxy->net_ns, family, type, protocol, res, 0);
}

int __sock_create(struct net *net, int family, int type, int protocol,
            struct socket **res, int kern) {
    struct socket *sock;
    ...
    sock = sock_alloc(); // 创建传输层 socket。
    ...
    pf = rcu_dereference(net_families[family]);
    ...
    err = pf->create(net, sock, protocol, kern); // inet_create
    ...
}

// socket.c
static const struct net_proto_family __rcu *net_families[NPROTO] __read_mostly;

// af_inet.c
static const struct net_proto_family inet_family_ops = {
    .family = PF_INET,
    .create = inet_create,
    .owner    = THIS_MODULE,
};

// af_inet.c
static int inet_create(struct net *net, struct socket *sock, int protocol, int kern) {
    ...
    sk = sk_alloc(net, PF_INET, GFP_KERNEL, answer_prot, kern);
    ...
    sock_init_data(sock, sk);
    ...
}

// socket.c
void sock_init_data(struct socket *sock, struct sock *sk) {
    ...
    if (sock) {
        sk->sk_type    =    sock->type;
        RCU_INIT_POINTER(sk->sk_wq, &sock->wq); // sock 的等待队列指向 socket 的等待队列。
        sock->sk    =    sk; // sock 与 socket 建立联系。
        sk->sk_uid    =    SOCK_INODE(sock)->i_uid;
    } else {
        RCU_INIT_POINTER(sk->sk_wq, NULL);
        sk->sk_uid    =    make_kuid(sock_net(sk)->user_ns, 0);
    }
    ...
}

```

---

## 5. fd 就绪事件回调处理

fd 与回调 `ep_poll_callback` 建立联系，当网络事件到来，触发回调来筛选出用户关注的事件进行处理。

![驱动粘合设备和内核](/images/2020-05-12-16-53-50.png){:data-action="zoom"}

---

### 5.1. poll 接口

就绪事件处理操作 poll 接口。

```c
struct file_operations {
    ...
    __poll_t (*poll) (struct file *, struct poll_table_struct *);
    ...
} __randomize_layout;

// socket.c
static const struct file_operations socket_file_ops = {
    ...
    .poll = sock_poll, // socket 的就绪事件处理函数。
    ...
};
```

---

### 5.2. file_operations

file_operations 与文件建立联系。

```c
// socket.c
struct file *sock_alloc_file(struct socket *sock, int flags, const char *dname) {
    ...
    // 创建文件，绑定文件操作接口：poll().
    file = alloc_file_pseudo(SOCK_INODE(sock), sock_mnt, dname,
                O_RDWR | (flags & O_NONBLOCK),
                &socket_file_ops);
    ...
    return file;
}

// file_table.c
struct file *alloc_file_pseudo(struct inode *inode, struct vfsmount *mnt,
                const char *name, int flags,
                const struct file_operations *fops) {
    ...
    file = alloc_file(&path, flags, fops);
    ...
    return file;
}

// file_table.c
static struct file *alloc_file(const struct path *path, int flags,
        const struct file_operations *fop) {
    struct file *file;

    file = alloc_empty_file(flags, current_cred());
    ...
    // 操作对象与文件建立关系。
    file->f_op = fop;
    ...
    return file;
}
```

---

### 5.3. tcp_poll

socket 就绪事件处理 tcp_poll。

```c
// 就绪事件处理结构。
typedef struct poll_table_struct {
    poll_queue_proc _qproc; // 处理函数（eventpoll.c 的 ep_ptable_queue_proc）。
    __poll_t _key;          // 事件组合。
} poll_table;

// poll.h
static inline __poll_t vfs_poll(struct file *file, struct poll_table_struct *pt) {
    if (unlikely(!file->f_op->poll))
        return DEFAULT_POLLMASK;
    // sock_poll
    return file->f_op->poll(file, pt);
}

static __poll_t sock_poll(struct file *file, poll_table *wait) {
    struct socket *sock = file->private_data;
    ...
    return sock->ops->poll(file, sock, wait) | flag;
}

// net.h
struct socket {
    ...
    const struct proto_ops *ops; // 协议操作指针。
    struct socket_wq wq;  // socket 等待队列节点。
};

// net.h
struct socket_wq {
    wait_queue_head_t wait;
    ...
} ____cacheline_aligned_in_smp;

// 初始化 socket.ops，指向 &inet_stream_ops
static struct inet_protosw inetsw_array[] = {
    {
        .type =       SOCK_STREAM,
        .protocol =   IPPROTO_TCP,
        .prot =       &tcp_prot,
        .ops =        &inet_stream_ops, // tcp 数据流操作。
        .flags =      INET_PROTOSW_PERMANENT | INET_PROTOSW_ICSK,
    },
    ...
}

// af_inet.c
const struct proto_ops inet_stream_ops = {
    ...
    .poll          = tcp_poll, // 就绪事件处理函数。
    ...
};

// tcp.c
__poll_t tcp_poll(struct file *file, struct socket *sock, poll_table *wait) {
    __poll_t mask;
    struct sock *sk = sock->sk;
    const struct tcp_sock *tp = tcp_sk(sk);
    int state;

    sock_poll_wait(file, sock, wait);

    // 检查 socket 读写事件。
    state = inet_sk_state_load(sk);
    if (state == TCP_LISTEN)
        return inet_csk_listen_poll(sk);
    ...
}

// sock.h
static inline void sock_poll_wait(struct file *filp, struct socket *sock, poll_table *p) {
    if (!poll_does_not_wait(p)) {
        poll_wait(filp, &sock->wq.wait, p);
        ...
    }
}

// poll.h
static inline void poll_wait(struct file * filp, wait_queue_head_t * wait_address, poll_table *p) {
    if (p && p->_qproc && wait_address)
        // ep_ptable_queue_proc 增加等待队列并将 socket 与 ep_poll_callback 回调建立联系。
        p->_qproc(filp, wait_address, p);
}
```

---

### 5.4. ep_poll_callback

网卡读写数据，驱动通知内核，内核触发 ep_poll_callback。

```c
// net.h
struct socket {
    struct sock *sk;
    struct socket_wq wq;
};

struct sock {
    ...
    union {
        struct socket_wq __rcu  *sk_wq; // 指针指向 socket 的等待队列。
        ...
    };
    ...
}

// 驱动中断回调，唤醒等待队列处理：ep_poll_callback
// sock.c
static void sock_def_wakeup(struct sock *sk) {
    struct socket_wq *wq;

    rcu_read_lock();
    wq = rcu_dereference(sk->sk_wq);
    if (skwq_has_sleeper(wq))
        // 唤醒等待队列。
        wake_up_interruptible_all(&wq->wait);
    rcu_read_unlock();
}

// wait.h
#define wake_up(x)      __wake_up(x, TASK_NORMAL, 1, NULL)
#define wake_up_interruptible_all(x)    __wake_up(x, TASK_INTERRUPTIBLE, 0, NULL)

// wait.c
void __wake_up(struct wait_queue_head *wq_head, unsigned int mode, int nr_exclusive, void *key) {
    __wake_up_common_lock(wq_head, mode, nr_exclusive, 0, key);
}

// wait.c
static void __wake_up_common_lock(struct wait_queue_head *wq_head, unsigned int mode,
            int nr_exclusive, int wake_flags, void *key) {
    ...
    do {
        ...
        nr_exclusive = __wake_up_common(wq_head, mode, nr_exclusive,
                        wake_flags, key, &bookmark);
        ...
    } while (bookmark.flags & WQ_FLAG_BOOKMARK);
}

// wait.c
static int __wake_up_common(struct wait_queue_head *wq_head, unsigned int mode,
            int nr_exclusive, int wake_flags, void *key,
            wait_queue_entry_t *bookmark) {
    wait_queue_entry_t *curr, *next;
    ...
    // 循环处理等待队列结点，回调 ep_poll_callback
    list_for_each_entry_safe_from(curr, next, &wq_head->head, entry) {
        ...
        // ep_poll_callback
        ret = curr->func(curr, mode, wake_flags, key);
        ...
    }
    ...
}
```

---

## 6. 参考

* [socket信号处理](https://vcpu.me/socket%E4%BF%A1%E5%8F%B7%E5%A4%84%E7%90%86/)
