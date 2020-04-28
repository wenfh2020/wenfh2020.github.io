---
layout: post
title:  "epoll 多路复用 I/O工作流程"
categories: 网络
tags: epoll 事件 多路复用
author: wenfh2020
---

从业务逻辑上，了解一下 `epoll` 多路复用 I/O 的工作流程。



* content
{:toc}

---

## 1. epoll

`epoll` 是一个 `Linux` 系统的一个事件驱动。简单点来说，是一个针对系统文件的事件管理器，可以高效管理大量网络链接下的数据并发。研发人员根据业务需要，通过事件管理器，监控对应文件描述符的读写事件。

> 详细的解析可以参考 [百度百科](https://baike.baidu.com/item/epoll/10738144?fr=aladdin)

---

### 1.1. 事件结构

```c
// epoll.h
typedef union epoll_data {
  void *ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
} epoll_data_t;

struct epoll_event {
  uint32_t events;   // epoll 事件
  epoll_data_t data; // 用户数据
} __EPOLL_PACKED;
```

---

| epoll 事件 | 描述                   |
| :--------- | :--------------------- |
| EPOLLIN    | 可读。                 |
| EPOLLOUT   | 可写。                 |
| EPOLLERR   | 该文件描述符发生错误。 |
| EPOLLHUP   | 该文件描述符被挂断。   |

---

### 1.2. 操作接口

* 创建 epoll 文件描述符。

```c
int epoll_create(int size);
```

* epoll 事件注册函数。

```c
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);
```

| op 操作事件   | 描述                         |
| :------------ | :--------------------------- |
| EPOLL_CTL_ADD | 注册新的 fd 到 epfd          |
| EPOLL_CTL_MOD | 修改已经注册的 fd 的监听事件 |
| EPOLL_CTL_DEL | 从 epfd 中删除一个 fd        |

* 等待事件发生。

```c
int epoll_wait(int epfd, struct epoll_event* events, int maxevents. int timeout);
```

---

## 2. 工作流程

`epoll` 是一个事件驱动，主要对文件描述符 fd 以及对应的事件进行管理，服务进程通过 `epoll_wait` 往内核获取就绪可读可写事件进行逻辑处理。

* 服务器创建非阻塞 socket（server_fd）。
* `epoll_create` 创建 epoll 事件驱动 (epoll_fd)。
* `epoll_ctl` 监控 server_fd 的可读事件 `EPOLLIN`。
* 服务进程通过 `epoll_wait` 获取内核就绪事件处理。
* 如果就绪事件是新连接，`accept` 为客户端新连接分配新的文件描述符 client_fd，设置非阻塞，然后 `epoll_ctl` 监控 client_fd 的可读事件 `EPOLLIN`。
* 如果就绪事件不是新连接，`read` 读取客户端发送数据进行逻辑处理。
* 处理逻辑过程中需要 `write` 回复客户端，`write` 内容很大，超出了内核缓冲区，没能实时发送完成所有数据，需要下次继续发送；那么 `epoll_ctl` 监控 client_fd 的 `EPOLLOUT` 可写事件，下次触发事件进行发送。下次触发可写事件发送完毕后， `epoll_ctl` 删除 `EPOLLOUT` 事件。
* 客户端关闭链接，服务端监控客户端 fd，如果 `read == 0`，`close` 关闭对应 fd 从而完成四次挥手。

![epoll 事件逻辑](/images/2020-04-17-10-09-45.png){: data-action="zoom"}

---

## 3. 参考

* [http://man7.org/linux/man-pages/dir_all_by_section.html](http://man7.org/linux/man-pages/dir_all_by_section.html)
* [http://man7.org/linux/man-pages/man2/write.2.html](http://man7.org/linux/man-pages/man2/write.2.html)
* [http://man7.org/linux/man-pages/man2/read.2.html](http://man7.org/linux/man-pages/man2/read.2.html)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
