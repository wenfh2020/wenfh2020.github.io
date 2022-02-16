---
layout: post
title:  "[知乎回答] 如何设计内存池？"
categories: c/c++ 知乎 
tags: memory leak pool
author: wenfh2020
---

[**知乎问题**](https://www.zhihu.com/question/25527491/answer/2262793593)：

内存池的优点就是可以减少内存碎片，分配内存更快，可以避免内存泄露等优点。那我们如何去设计一个内存池呢？能不能给个你的大致思考过程或者步骤，比如，首先要设计一个内存分配节点（最小单元），再设计几个内存分配器（函数），等等。不是太清晰。望大神指点。




* content
{:toc}

---

## 1. 内存池

redis 在 Linux 上有三种内存池选择：

1. glibc 上的 ptmalloc（[ptmalloc 文档](https://paper.seebug.org/papers/Archive/refs/heap/glibc%E5%86%85%E5%AD%98%E7%AE%A1%E7%90%86ptmalloc%E6%BA%90%E4%BB%A3%E7%A0%81%E5%88%86%E6%9E%90.pdf)）。
2. 谷歌的 tcmalloc。
3. jemalloc。

可以先参考一下这三个内存池，找一个感兴趣的内存池源码进行阅读。

---

轻量级的也可以参考 nginx 的内存池：[ngx_pool_t](https://github.com/nginx/nginx/blob/master/src/core/ngx_palloc.h)，但是它的内存回收管理比较弱。

![nginx 内存池](/images/2020-04-25-17-15-19.png){: data-action="zoom"}

> 设计图来源：《[nginx 内存池结构图](https://www.processon.com/view/5e24d976e4b049828093bebe)》

---

## 2. 内存池要点

1. 除了考虑从大块内存上高效地将小内存划分出去，还要注意内存碎片问题。
2. 当回收内存时要注意是否需要将相邻的空闲内存块进行合并管理。
3. 当内存池的空闲内存到达一定的阈值时，要合理地返还系统。

---

## 3. 内存池泄漏问题

### 3.1. 原理

为什么不建议自己写内存池呢？

因为自己曾经遇到过一个棘手的[内存泄漏问题](https://wenfh2020.com/2021/04/08/glibc-memory-leak/
)，幸运的是当时项目增加的代码量不多，也花了不少精力，才定位在 Linux libc 库里面的 ptmalloc 出现”泄漏“。

主要是它向内核申请了大量内存，但是并不返还系统，原因：申请的都是小内存（<=128k），它都是通过 brk 申请的，ptmalloc 通过 brk 申请的内存，返还系统有个特点：必须是紧挨着当前 brk 申请的空闲内存块的内存空间，它被用户释放了，后面紧挨着的其它空闲内存才会被返还系统。

> 看下图，只要 n2 这块小内存用户不释放，其它节点内存释放了，也不给返还系统。

<div align=center><img src="/images/2021-04-27-09-13-26.png" data-action="zoom"/></div>

所以程序在 Linux 上分配内存，需要避免分阶段分配内存，就是后面分配的内存如果一直不释放，前面申请的内存即便释放了，底层可能不给你返还系统，出现"泄漏"的问题。

如果搞不清楚这些，那些搞个内存池项目，内存资源长期驻留的就更危险了。

---

### 3.2. 泄漏 demo

有兴趣的朋友可以在 Linux 上跑一下下面代码。

1. 观察程序运行的结果。
2. 然后屏蔽掉 addr 的内存申请看看。
3. 或者一行一行开启注释掉的两行源码。
4. 又或者调换这两行源码顺序。

```c
/* test_memory.c
 * gcc -g -O0 -W test_memory.c -o tm123 && ./tm123 */

#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define BLOCK_CNT (256 * 1024)
#define BLOCK_SIZE (4 * 1024)

int main() {
    int i;
    char *addr, *blks[BLOCK_CNT];

    for (i = 0; i < BLOCK_CNT; i++) {
        blks[i] = (char *)malloc(BLOCK_SIZE * sizeof(char));
    }

    addr = (char *)malloc(2 * sizeof(char));

    for (i = 0; i < BLOCK_CNT; i++) {
        free(blks[i]);
    }

    // free(addr);
    // malloc_trim(0);

    malloc_stats();
    for (;;) {
        sleep(1);
    }

    return 0;
}
```

---

## 4. 参考

* [如何设计内存池？](https://www.zhihu.com/question/25527491/answer/2262793593)
* [[nginx 源码走读] 内存池](https://wenfh2020.com/2020/01/21/nginx-pool/)
* [剖析 stl + glibc “内存泄漏” 原因](https://wenfh2020.com/2021/04/08/glibc-memory-leak/)
