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
tcpdump -i lo -vvn port 12456 -w /tmp/tcpdump.cap
```

* 客户端 `telnet`：

```shell
telnet 127.0.0.1 12456
```

* 三次握手，四次挥手抓包内容：

```c
# tcpdump -r /tmp/tcpdump.cap
--- handshakes
02:24:03.518594 IP localhost.27749 > localhost.12456: Flags [S], seq 1527358664, win 43690, options [mss 65495,sackOK,TS val 102124122 ecr 0,nop,wscale 11], length 0
22:49:27.762588 IP localhost.12456 > localhost.27749: Flags [S.], seq 2031984515, ack 1527358665, win 43690, options [mss 65495,sackOK,TS val 102124122 ecr 102124122,nop,wscale 11], length 0
02:24:03.518636 IP localhost.27749 > localhost.12456: Flags [.], ack 1, win 22, options [nop,nop,TS val 102124122 ecr 102124122], length 0
--- send msg
02:24:05.472290 IP localhost.27749 > localhost.12456: Flags [P.], seq 1:4, ack 1, win 22, options [nop,nop,TS val 102126076 ecr 102124122], length 3
02:24:05.472304 IP localhost.12456 > localhost.27749: Flags [.], ack 4, win 22, options [nop,nop,TS val 102126076 ecr 102126076], length 0
--- waves
02:24:15.614921 IP localhost.27749 > localhost.12456: Flags [F.], seq 4, ack 1, win 22, options [nop,nop,TS val 102136219 ecr 102126076], length 0
02:24:15.654843 IP localhost.12456 > localhost.27749: Flags [.], ack 5, win 22, options [nop,nop,TS val 102136259 ecr 102136219], length 0
02:24:25.615242 IP localhost.12456 > localhost.27749: Flags [F.], seq 1, ack 5, win 22, options [nop,nop,TS val 102146219 ecr 102136219], length 0
02:24:25.615276 IP localhost.27749 > localhost.12456: Flags [.], ack 2, win 22, options [nop,nop,TS val 102146219 ecr 102146219], length 0
```

* 用神器 `wireshark` 打开 `*.cap` 文件。

![wireshark](/images/2020-04-13-09-46-38.png){: data-action="zoom"}

* 流程

从上面抓包数据看，我们可以描述一下 tcp 握手挥手工作流程。

![握手挥手流程](/images/2020-04-13-13-20-03.png){: data-action="zoom"}

* 三次握手，三次挥手。
  
  在本地进行简单测试，抓到的挥手包，多数只有三个，而不是四个。那为什么会出现三个挥手包呢？当客户端主动 close 关闭链接，服务端收到 FIN 后，发现已经没有新的数据要发送给客户端了，那么 ACK 和 FIN 会合成一个包下发，这样就节省了一次挥手，否则还是四次挥手。
  > 当服务端发现客户端断开后 (read () == 0)，sleep 一下，再调用 close，那么将会抓到 4 个挥手包。

```c
# tcpdump -r /tmp/tcpdump.cap
--- handshakes
13:15:40.439590 IP localhost.25541 > localhost.12456: Flags [S], seq 2751955316, win 43690, options [mss 65495,sackOK,TS val 54821043 ecr 0,nop,wscale 11], length 0
12:03:10.399044 IP localhost.12456 > localhost.25541: Flags [S.], seq 2140744854, ack 2751955317, win 43690, options [mss 65495,sackOK,TS val 54821043 ecr 54821043,nop,wscale 11], length 0
13:15:40.439616 IP localhost.25541 > localhost.12456: Flags [.], ack 1, win 22, options [nop,nop,TS val 54821043 ecr 54821043], length 0
--- waves
13:15:57.601816 IP localhost.12456 > localhost.25541: Flags [F.], seq 1, ack 1, win 22, options [nop,nop,TS val 54838205 ecr 54821043], length 0
13:15:57.602406 IP localhost.25541 > localhost.12456: Flags [F.], seq 1, ack 2, win 22, options [nop,nop,TS val 54838206 ecr 54838205], length 0
13:15:57.602425 IP localhost.12456 > localhost.25541: Flags [.], ack 2, win 22, options [nop,nop,TS val 54838206 ecr 54838206], length 0
```

---

## 3. tcp 状态变迁
  
  > 图片来源：《TCP/IP 详解卷 1：协议》 -- 18.6 tcp 的状态变迁图

![tcp 状态变迁](/images/2020-04-13-13-14-49.png){: data-action="zoom"}

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

* 客户端主动 connect 服务端，三次握手是在服务端 accept 前完成的。服务端 accept 前面添加 sleep 再抓下包看看。
* 为什么链接是三次，挥手是四次？因为 TCP 协议是全双工的，全双工实际是用两条单工信道。TCP 建立链接握手时，对端 ACK + SYN 两个包并在一起发，所以链接是三次握手。
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

* [为什么tcp 连接断开只有3个包？](https://www.zhihu.com/question/55890292)
* [TCP_Relative_Sequence_Numbers](https://wiki.wireshark.org/TCP_Relative_Sequence_Numbers)
* 《TCP/IP 详解卷 1：协议》
* [Linux SIGPIPE信号产生原因与解决方法](https://blog.csdn.net/u010821666/article/details/81841755)
* [解决 Linux TIME_WAIT 过多造成的问题](https://blog.csdn.net/zhangjunli/article/details/89321202)
