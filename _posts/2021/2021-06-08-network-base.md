---
layout: post
title:  "重温网络基础"
categories: network
tags: book
author: wenfh2020
---

最近看了这两本书 《网络是怎样连接的》 和 《图解 TCP_IP》，书本图文结合，通俗易懂。重温和扫盲了不少网络知识点，深感基础实在太重要了！

<div align=center><img src="/images/2021-06-13-07-37-38.png" data-action="zoom"/></div>




* content
{:toc}

---

## 1. 网络通信流程

<div align=center><img src="/images/2021-06-08-08-12-57.png" data-action="zoom"/></div>

> 图片来源：《网络是怎样连接的》

---

## 2. OSI 七层网络协议

<div align=center><img src="/images/2021-06-11-13-36-24.png" data-action="zoom"/></div>

<div align=center><img src="/images/2021-06-11-13-35-05.png" data-action="zoom"/></div>

> 图片来源：《图解 TCP_IP》

---

## 3. 数据传输封包格式

<div align=center><img src="/images/2021-06-08-08-30-32.png" data-action="zoom"/></div>

<div align=center><img src="/images/2021-06-09-11-01-49.png" data-action="zoom"/></div>

> 图片来源：《图解 TCP_IP》

<div align=center><img src="/images/2021-06-09-06-44-35.png" data-action="zoom"/></div>

> 图片来源：《网络是怎样连接的》

<div align=center><img src="/images/2021-06-09-06-44-13.png" data-action="zoom"/></div>

> 图片来源：《网络是怎样连接的》

---

### 3.1. TCP

#### 3.1.1. TCP 头部格式

<div align=center><img src="/images/2021-06-11-16-02-53.png" data-action="zoom"/></div>

> 图片来源：《图解 TCP_IP》 -- 6.7 TCP 首部格式

<div align=center><img src="/images/2021-06-08-08-22-52.png" data-action="zoom"/></div>

> 图片来源：《网络是怎样连接的》

```c
/* tcp.h */
struct tcphdr {
    __be16   source;
    __be16   dest;
    __be32   seq;
    __be32   ack_seq;
#if defined(__LITTLE_ENDIAN_BITFIELD)
    __u16    res1:4,
             doff:4,
             fin:1,
             syn:1,
             rst:1,
             psh:1,
             ack:1,
             urg:1,
             ece:1,
             cwr:1;
#elif defined(__BIG_ENDIAN_BITFIELD)
    __u16    doff:4,
             res1:4,
             cwr:1,
             ece:1,
             urg:1,
             ack:1,
             psh:1,
             rst:1,
             syn:1,
             fin:1;
#else
#error    "Adjust your <asm/byteorder.h> defines"
#endif    
    __be16   window;
    __sum16  check;
    __be16   urg_ptr;
};
```

---

#### 3.1.2. TCP 数据传输

<div align=center><img src="/images/2021-06-08-16-50-12.png" data-action="zoom"/></div>

> 图片来源：《网络是怎样连接的》

---

#### 3.1.3. TCP 握手挥手

<div align=center><img src="/images/2021-06-08-17-01-28.png" data-action="zoom"/></div>

> 图片来源：[抓包分析 tcp 握手和挥手](https://wenfh2020.com/2020/04/12/tcp-handshakes-waves/)

---

### 3.2. IPv4 头部格式

<div align=center><img src="/images/2021-06-11-13-43-59.png" data-action="zoom"/></div>

>《图解 TCP_IP》 -- 4.7 IPv4 首部

<div align=center><img src="/images/2021-06-08-08-40-07.png" data-action="zoom"/></div>

> 图片来源：《网络是怎样连接的》

```c
/* ip.h */
struct iphdr {
#if defined(__LITTLE_ENDIAN_BITFIELD)
    __u8    ihl:4,
        version:4;
#elif defined (__BIG_ENDIAN_BITFIELD)
    __u8    version:4,
            ihl:4;
#else
#error    "Please fix <asm/byteorder.h>"
#endif
    __u8    tos;
    __be16  tot_len;
    __be16  id;
    __be16  frag_off;
    __u8    ttl;
    __u8    protocol;
    __sum16 check;
    __be32  saddr;
    __be32  daddr;
    /*The options start here. */
};
```

---

### 3.3. MAC 头部格式

<div align=center><img src="/images/2021-06-08-09-27-42.png" data-action="zoom"/></div>

> 图片来源：《网络是怎样连接的》

---

### 3.4. UDP 头部格式

<div align=center><img src="/images/2021-06-11-16-10-54.png" data-action="zoom"/></div>

>图片来源：《图解 TCP_IP》 -- 6.6 UDP 的首部格式

<div align=center><img src="/images/2021-06-08-16-29-20.png" data-action="zoom"/></div>

> 图片来源：《网络是怎样连接的》

```c
/* udp.h */
struct udphdr {
    __be16   source;
    __be16   dest;
    __be16   len;
    __sum16  check;
};
```

---

## 4. 参考

* 《网络是怎样连接的》
* 《图解 TCP_IP》
* [TCP,UDP,IP包头格式及说明](https://blog.csdn.net/qq_30549833/article/details/60139328)
* [icmp的目的主机不可达消息为什么由其他ip发出？](https://blog.csdn.net/wj31932/article/details/114326471)
* [tcp连接关闭方式：close，shutdown和RST包](https://blog.csdn.net/yyfaith/article/details/80176882)
