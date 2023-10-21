---
layout: post
title:  "抓包分析 tcp 握手和挥手"
categories: network
tags: tcp handshakes waves
author: wenfh2020
---

Linux 环境下，用 `tcpdump` 抓包分析 tcp 三次握手和四次挥手/三次挥手。



* content
{:toc}

---

## 1. 工具

* tcpdump
* wireshark
* telnet

---

## 2. 抓包分析

* 服务端口 `12456`。

```shell
tcpdump -i lo -vvn port 8080 -w /tmp/tcpdump.cap
```

* 客户端 `telnet`：

```shell
telnet 127.0.0.1 8080
```

* tcp 包结构。

<div align=center><img src="/images/2023/2023-10-21-16-48-04.png" data-action="zoom"></div>

> 图片来源：《图解 TCP_IP》 – 6.7 TCP 首部格式

* 链接，三次握手抓包内容：

<div align=center><img src="/images/2023/2023-10-21-16-17-06.png" data-action="zoom"></div>

* 断开链接，四次挥手抓包内容：

<div align=center><img src="/images/2023/2023-10-21-16-18-27.png" data-action="zoom"></div>

* 流程。从上面抓包数据看，我们可以描述一下 tcp 握手挥手工作流程。

<div align=center><img src="/images/2023/2023-10-21-16-33-39.png" data-action="zoom"></div>

* 四次挥手，如果双方同时关闭链接。

<div align=center><img src="/images/2023/2023-10-21-16-29-00.png" data-action="zoom"></div>

---

## 3. tcp 状态变迁
  
  > 图片来源：《TCP/IP 详解卷 1：协议》 -- 18.6 tcp 的状态变迁图

![tcp 状态变迁](/images/2020/2020-04-13-13-14-49.png){: data-action="zoom"}

```c
// tcp_states.h
enum {
    TCP_ESTABLISHED = 1,
    TCP_SYN_SENT,
    TCP_SYN_RECV,
    TCP_FIN_WAIT1,
    TCP_FIN_WAIT2,
    TCP_TIME_WAIT,
    TCP_CLOSE,
    TCP_CLOSE_WAIT,
    TCP_LAST_ACK,
    TCP_LISTEN,
    TCP_CLOSING,    /* Now a valid state */
    TCP_NEW_SYN_RECV,

    TCP_MAX_STATES    /* Leave at the end! */
};
```

---

## 4. 其它

* 客户端主动 connect 服务端，三次握手是在服务端 accept 前完成的。
  
  > 因为 accept 是去内核的全链接队列捞取链接数据。而链接在三次握手后，才会从半链接队列，转存于全链接队列，然后内核唤醒进程去获取链接数据。
* 为什么链接是三次，挥手是四次？
  > 因为 TCP 协议是全双工的，全双工实际是用两条单工信道。TCP 建立链接握手时，对端 ACK + SYN 两个包并在一起发，所以链接是三次握手。
* TIME_WAIT 和 SYN 问题处理，修改 sysctl.conf 文件。
  
  > 配置引用自：[解决 Linux TIME_WAIT 过多造成的问题](https://blog.csdn.net/zhangjunli/article/details/89321202)

```shell
#/etc/sysctl.conf

# 表示开启SYN Cookies。当出现SYN等待队列溢出时，启用cookies来处理，可防范少量SYN攻击，默认为0，表示关闭；
net.ipv4.tcp_syncookies=1

# 表示开启重用。允许将 TIME_WAIT sockets 重新用于新的TCP连接，默认为0，表示关闭；
net.ipv4.tcp_tw_reuse=1

# 表示开启TCP连接中 TIME_WAIT sockets的快速回收，默认为0，表示关闭。
net.ipv4.tcp_tw_recycle=1

# 修改系默认的 TIMEOUT 时间。
net.ipv4.tcp_fin_timeout=30

# --------

# 表示当keepalive起用的时候，TCP发送keepalive消息的频度。缺省是2小时，改为20分钟。
net.ipv4.tcp_keepalive_time = 1200 

# 表示用于向外连接的端口范围。缺省情况下很小：32768到61000，改为1024到65000。
net.ipv4.ip_local_port_range = 1024 65000 

# 表示SYN队列的长度，默认为1024，加大队列长度为8192，可以容纳更多等待连接的网络连接数。
net.ipv4.tcp_max_syn_backlog = 8192 

# 表示系统同时保持TIME_WAIT套接字的最大数量，如果超过这个数字，TIME_WAIT套接字将立刻被清除并打印警告信息。
net.ipv4.tcp_max_tw_buckets = 5000

# /sbin/sysctl -p
```

---

## 5. 参考

* [从linux源码看socket的close](https://my.oschina.net/alchemystar/blog/1821680)
* [TCP三次握手源码分析](https://www.cnblogs.com/seanloveslife/p/12103830.html)
* [为什么tcp 连接断开只有3个包？](https://www.zhihu.com/question/55890292)
* [TCP_Relative_Sequence_Numbers](https://wiki.wireshark.org/TCP_Relative_Sequence_Numbers)
* 《TCP/IP 详解卷 1：协议》
* [Linux SIGPIPE信号产生原因与解决方法](https://blog.csdn.net/u010821666/article/details/81841755)
* [解决 Linux TIME_WAIT 过多造成的问题](https://blog.csdn.net/zhangjunli/article/details/89321202)
