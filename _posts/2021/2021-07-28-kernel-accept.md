---
layout: post
title:  "[内核源码] 网络协议栈 - accept (tcp)"
categories: kernel
tags: kernel accept
author: wenfh2020
---

走读网络协议栈 accept (tcp) 的（Linux - 5.0.1 [下载](https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.0.1.tar.xz)）内核源码。

accept 函数由 tcp 服务器调用，用于从已完成连接队列头返回一个已完成连接。如果已连接队列为空，阻塞情况下：那么进程将睡眠等待，非阻塞将马上返回 -1，错误码为 EAGAIN。



* content
{:toc}

---

## 1. 概述

```c
/* sockfd：listen socket's fd。
 * cliaddr：已连接的客户端的协议地址。
 * addrlen：cliaddr 地址长度。
 * return：返回新的文件描述符，或者非阻塞马上返回 -1，错误码为 EAGAIN。
 */
#include <sys/socket.h>
int accept(int sockfd, struct sockaddr *cliaddr, socklen_t *addrlen);
```

> 参考：《UNIX 网络编程-卷 1》

---

## 2. 内核

<div align=center><img src="/images/2021/2021-07-28-14-07-24.png" data-action="zoom"/></div>

> 图片来源：[linux 内核 listen (tcp/IPv4) 结构关系](https://processon.com/view/60fa6dfe7d9c083494e37a9a)

---

### 2.1. 调试堆栈

```shell
__sys_accept4(int fd, struct sockaddr * upeer_sockaddr, int * upeer_addrlen, int flags) (/root/linux-5.0.1/net/socket.c:1589)
__do_sys_accept() (/root/linux-5.0.1/net/socket.c:1630)
__se_sys_accept() (/root/linux-5.0.1/net/socket.c:1627)
__x64_sys_accept(const struct pt_regs * regs) (/root/linux-5.0.1/net/socket.c:1627)
do_syscall_64(unsigned long nr, struct pt_regs * regs) (/root/linux-5.0.1/arch/x86/entry/common.c:290)
entry_SYSCALL_64() (/root/linux-5.0.1/arch/x86/entry/entry_64.S:175)
```

> 参考：[vscode + gdb 远程调试 linux (EPOLL) 内核源码](https://www.bilibili.com/video/bv1yo4y1k7QJ)

---

### 2.2. 函数调用层次关系

```shell
#------------------- *用户态* ---------------------------
accept
#------------------- *内核态* ---------------------------
__sys_accept4 # net/socket.c - 内核系统调用。
|-- sockfd_lookup_light # 根据 fd 查找 listen socket 的 socket 指针。
|-- sock_alloc # 创建一个新的 socket 对象，因为要从 listen socket 的全连接队列里获取一个就绪的连接。
|-- get_unused_fd_flags # 从进程中获取一个空闲的文件 fd。
|-- sock_alloc_file # 从进程中创建一个新的文件，因为文件要与 socket 关联。
|-- inet_accept # 从 listen socket 的全连接队列里获取一个就绪的 sock 连接，与前面新创建的 socket 关联。
    |-- inet_csk_accept 
        |-- reqsk_queue_empty # 如果 listen socket 的全连接队列是空的，那么阻塞或者非阻塞返回 EAGAIN。
        |-- sock_rcvtimeo
        |-- inet_csk_wait_for_connect # 阻塞场景下的等待。
        # 如果 listen socket 的全连接队列非空，那么从全连接队列取一个连接处理。
        |-- reqsk_queue_remove # 从 listen socket 全连接队列删除获取一个 request_sock 连接处理。
    |-- sock_graft # socket 与 sock 建立联系。
|-- inet_getname
|-- move_addr_to_user # 拷贝 accept 的连接的 ip/port 到用户层。
|-- fd_install # 文件和进程进行关联。__fd_install(current->files, fd, file);
```

---

## 3. 参考

* [socket API 实现（四）—— accept 函数](http://blog.guorongfei.com/2014/10/29/socket-accept/)
* [[内核源码] 网络协议栈 socket (tcp)](https://wenfh2020.com/2021/07/13/kernel-sys-socket/)
* [[内核源码] 网络协议栈 bind (tcp)](https://wenfh2020.com/2021/07/17/kernel-bind/)
* [[内核源码] 网络协议栈 listen (tcp)](https://wenfh2020.com/2021/07/21/kernel-sys-listen/)
