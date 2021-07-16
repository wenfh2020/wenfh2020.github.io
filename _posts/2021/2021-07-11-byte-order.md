---
layout: post
title:  "字节序转换关系"
categories: network
tags: byte-order
author: wenfh2020
---

梳理一下字节序的转换关系：大端字节序（big endian），小端字节序（little endian）和网络字节序。




* content
{:toc}

---

## 1. 概述

* 大小端。
  
  计算机硬件有两种储存数据的方式：大端字节序（big endian）和小端字节序（little endian）。
  
  考虑一个 16 位整数，它由 2 个字节组成。内存中存储这两个字节有两种方法：

  1. **小端**：将低序字节存储在起始地址；
  2. **大端**：将高序字节存储在起始地址。

<div align=center><img src="/images/2021-07-11-17-17-40.png" data-action="zoom"/></div>

  > 上述文字主要来源于：《UNIX 网络编程》- 3.4 字节排序函数。

* 网络字节序。
  
  网络字节顺序是TCP/IP中规定好的一种数据表示格式，它与具体的CPU类型、操作系统等无关，从而可以保证数据在不同主机之间传输时能够被正确解释。网络字节顺序采用大端（big-endian）排序方式。
  
> 上述文字主要来源于：[网络字节序](https://baike.baidu.com/item/%E7%BD%91%E7%BB%9C%E5%AD%97%E8%8A%82%E5%BA%8F/12610557)。

---

## 2. 字节序关系

* 字节序转换函数。
  
```c
#include <netinet/in.h>

/* 返回网络字节序的值。 */
uint16_t htons(uint16_t host16bitvalude);
uint32_t htonl(uint32_t host32bitvalude);

/* 返回主机字节序的值。 */
uint16_t ntohs(uint16_t net16bitvalue);
uint32_t ntohl(uint32_t net32bitvalue);
```

---

* 转换流程。
  
  举个🌰：client 与 server 通信，16 位整数字节序转换流程：htons --> 网络字节序（大端） --> ntohs。

  其实这里面有两个环节：

  1. （htons）客户端主机字节序转网络字节序。
  2. （ntohs）网络字节序转服务器主机字节序。

<div align=center><img src="/images/2021-07-11-20-32-22.png" data-action="zoom"/></div>

  我们再看看 glibc 字节序转换的源码实现，htons 和 ntohs 居然指向同一个函数。
  
  小结：网络字节序默认是大端的，只要 <font color=red> 主机字节序是小端的 </font>，在传输过程中都要进行字节序转换。

```c
/*./inet/htons.c */
#undef htons
#undef ntohs

uint16_t
htons (x)
     uint16_t x;
{
#if BYTE_ORDER == BIG_ENDIAN
  return x;
#elif BYTE_ORDER == LITTLE_ENDIAN
  return __bswap_16 (x);
#else
# error "What kind of system is this?"
#endif
}
weak_alias (htons, ntohs)
```

```c
/* ./sysdeps/x86/bits/byteswap-16.h */
#ifdef __GNUC__
# if __GNUC__ >= 2
#  define __bswap_16(x) \
     (__extension__                                  \
      ({ register unsigned short int __v, __x = (unsigned short int) (x);     \
     if (__builtin_constant_p (__x))                      \
       __v = __bswap_constant_16 (__x);                      \
     else                                      \
       __asm__ ("rorw $8, %w0"                          \
            : "=r" (__v)                          \
            : "0" (__x)                              \
            : "cc");                              \
     __v; }))
# else
/* This is better than nothing.  */
#  define __bswap_16(x) \
     (__extension__                                  \
      ({ register unsigned short int __x = (unsigned short int) (x);          \
     __bswap_constant_16 (__x); }))
# endif
#else
static __inline unsigned short int
__bswap_16 (unsigned short int __bsx) {
  return __bswap_constant_16 (__bsx);
}
#endif

/* Swap bytes in 16 bit value.  */
#define __bswap_constant_16(x) \
     ((unsigned short int) ((((x) >> 8) & 0xff) | (((x) & 0xff) << 8)))

```

---

## 3. C 语言实现大小端判断

```c
int little = 1;
if (*(char*)(&little) == 0) {
    printf("big endian\n");
} else {
    printf("little endian\n");
}
```

---

## 4. 参考

* 《UNIX 网络编程》
