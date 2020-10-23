---
layout: post
title:  "[kimserver] 父子进程传输文件描述符"
categories: kimserver
tags: kimserver socketpair socket transfer
author: wenfh2020
---

多进程服务架构，涉及到进程管理，例如，服务端为了负载均衡，希望负载比较低的子进程处理新的用户请求，这就需要主进程进行调度。就像包工头负责接活，然后将活分配给没那么忙处理能力比较强的马仔处理。

这个（文件描述符传输）调度的实现，通过管道通信，实现 socket 的传输。




* content
{:toc}

---

## 1. 流程

### 1.1. C/S 接入流程

1. 父子进程通过 `socketpair` 创建的相互通信的管道。
2. 客户端接入到主进程。
3. 主进程 accept 到客户端的 fd1。
4. 主进程将客户端的 fd1 通过管道 `sendmsg` 传输给子进程。
5. 子进程通过 `recvmsg` 接收到主进程发送的 fd1。注意，这时候经过发送后的文件描述符已经发生改变，变成 fd2 了。
6. 文件描述符传输完毕，客户端与子进程成功建立连接 fd2。
7. 主进程可以关闭旧的 fd1。

![接入流程](/images/2020-10-23-17-41-28.png){:data-action="zoom"}

---

### 1.2. 优缺点

* 优点：多进程方便调度，无锁，减少 accept 竞争。
* 缺点：单进程单线程接入，能力被削弱。（尽管接入操作不是很耗费资源。）

---

## 2. 源码分析

### 2.1. 原理

详细原理请参考 [linux网络编程之socket（十六）：通过UNIX域套接字传递描述符和 sendmsg/recvmsg 函数](https://blog.csdn.net/jnu_simba/article/details/9079627)。

---

### 2.2. nginx

sendmsg 和 recvmsg 发送和接收文件描述符。具体功能实现可以参考 nginx 源码：[ngx_channel](https://github.com/nginx/nginx/blob/master/src/os/unix/ngx_channel.c)。

```c
/* 读数据。 */
ngx_int_t ngx_read_channel(ngx_socket_t s, ngx_channel_t *ch, size_t size, ngx_log_t *log);
/* 传数据。 */
ngx_int_t ngx_write_channel(ngx_socket_t s, ngx_channel_t *ch, size_t size, ngx_log_t *log);
```

---

## 3. 源码实现

详细源码调用实现在 [kimserver](https://github.com/wenfh2020/kimserver)

```c++
/* 传输数据结构。 */
typedef struct channel_s {
    int fd;
    int family;
    int codec;
} channel_t;

/* 文件描述符发送和接收函数 */
int write_channel(int fd, channel_t* ch, size_t size, Log* logger = nullptr);
int read_channel(int fd, channel_t* ch, size_t size, Log* logger = nullptr);

/* manager.cpp 父子进程创建管道进行通信。 */
bool Manager::create_worker(int worker_index) {
    int pid, data_fds[2];
    ...
    /* 创建父子进程通信管道。 */
    if (socketpair(PF_UNIX, SOCK_STREAM, 0, data_fds) < 0) {
       ...
    }

    if ((pid = fork()) == 0) {
        /* 将管道描述符 data_fds[1] 传给子进程。 */
    } else if (pid > 0) {
        /* 将管道描述符 data_fds[0] 传给父进程。 */
    }
    ...
}

/* 发送文件描述符，主进程 accpet 客户端接入的 fd，然后传输给子进程。 */
void Network::accept_and_transfer_fd(int fd) {
    int cport, cfd, family;
    char cip[NET_IP_STR_LEN] = {0};

    /* 主进程 accpet 客户端的接入文件描述符。*/
    cfd = anet_tcp_accept(m_errstr, fd, cip, sizeof(cip), &cport, &family);
    ...
    /* 父进程发送客户端的 cfd 到子进程。 */
    int chanel_fd = m_woker_data_mgr->get_next_worker_data_fd();
    if (chanel_fd > 0) {
        LOG_DEBUG("send client fd: %d to worker through chanel fd %d", cfd, chanel_fd);
        /* 发送的结构体数据。 */
        channel_t ch = {cfd, family, static_cast<int>(m_gate_codec)};
        int err = write_channel(chanel_fd, &ch, sizeof(channel_t), m_logger);
        ...
    } 
    ...
}

/* 子进程接收文件描述符 */
void Network::read_transfer_fd(int fd) {
    channel_t ch;
    ...
    while (max--) {
        /* 子进程接收父进程发送的客户端的文件描述符。*/
        err = read_channel(fd, &ch, sizeof(channel_t), m_logger);
        ...
    }
...
}
```

---

## 4. 参考

* [linux网络编程之socket（十六）：通过UNIX域套接字传递描述符和 sendmsg/recvmsg 函数](https://blog.csdn.net/jnu_simba/article/details/9079627)
* [通过UNIX域套接字传递文件描述符](view-source:https://www.bwar.tech/2018/07/17/fd-transfer.html)

---

> 🔥 文章来源：[《[kimserver] 父子进程文件描述符传输》](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
