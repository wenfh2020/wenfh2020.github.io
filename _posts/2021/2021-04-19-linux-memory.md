---
layout: post
title:  "学习 Linux 内存分配"
categories: system
tags: linux memory slab buddy
author: wenfh2020
---

学习 Linux 内核内存分配算法，简单查阅了一下相关的内核源码和收集了部分资料（大部分资料来源于广大网友）。




* content
{:toc}

---

## 1. 设备

* 设备关系。

<div align=center><img src="/images/2021-04-19-13-11-50.png" data-action="zoom"/></div>

> 图片来源：《深入理解计算机系统》- 第一章 - 计算机漫游

* 存储关系。

<div align=center><img src="/images/2021-04-19-13-13-12.png" data-action="zoom"/></div>

> 图片来源：《深入理解计算机系统》- 第一章 - 计算机漫游

---

## 2. 内存布局

* 存储。

<div align=center><img src="/images/2021-04-19-13-14-58.png" data-action="zoom"/></div>

> 图片来源：《深入理解计算机系统》- 第一章 - 计算机漫游

* 模型：node - 存储节点；zone - 管理区；page - 页面。

<div align=center><img src="/images/2021-04-15-10-46-25.png" data-action="zoom"/></div>

> 图片来源：[Linux 内存管理窥探（2）：内存模型](https://blog.csdn.net/zhoutaopower/article/details/86710017)

<div align=center><img src="/images/2021-04-15-10-59-03.png" data-action="zoom"/></div>

> 图片来源：[Linux 内存管理窥探（2）：内存模型](https://blog.csdn.net/zhoutaopower/article/details/86710017)

* 虚拟内存。

<div align=center><img src="/images/2021-04-15-10-26-18.png" data-action="zoom"/></div>

> 图片来源：[Linux 内存管理窥探（1）：内存规划与分布](https://blog.csdn.net/zhoutaopower/article/details/86700419)

<div align=center><img src="/images/2021-04-15-10-29-24.png" data-action="zoom"/></div>

> 图片来源：[Linux 内存管理窥探（1）：内存规划与分布](https://blog.csdn.net/zhoutaopower/article/details/86700419)

<div align=center><img src="/images/2021-04-10-11-10-30.png" data-action="zoom"/></div>

> 图片来源：《深入理解计算机系统》- 第九章 - 虚拟内存

* MMU 地址翻译。

<div align=center><img src="/images/2021-04-19-13-19-47.png" data-action="zoom"/></div>

> 图片来源：《深入理解计算机系统》- 第九章 - 虚拟内存

<div align=center><img src="/images/2021-04-15-12-16-33.png" data-action="zoom"/></div>

> 图片来源：[初探 MMU](https://blog.csdn.net/zhoutaopower/article/details/87934818)

* 页表分页机制。

<div align=center><img src="/images/2021-04-12-17-19-02.png" data-action="zoom"/></div>

---

## 3. 内存分配算法

Linux 系统内存分配流程。

<div align=center><img src="/images/2021-04-14-17-13-58.png" data-action="zoom"/></div>

> 图片来源：[Linux内核内存管理算法Buddy和Slab](https://cloud.tencent.com/developer/article/1106795)

---

### 3.1. buddy - 伙伴算法

伙伴算法分配内存最小单位页（page）。缺点：分配粒度大。

<div align=center><img src="/images/2021-04-14-22-12-24.png" data-action="zoom"/></div>

> 图片来源：[Linux内核内存管理算法Buddy和Slab](https://cloud.tencent.com/developer/article/1106795)

---

#### 3.1.1. 分配源码

```shell
alloc_pages ->alloc_pages_node ->__alloc_pages -> __alloc_pages_nodemask​​​​​​​ -> get_page_from_freelist -> zone_watermark_ok  -> rmqueue -> __rmqueue_smallest
```

```c
/* gfp.h */
#define alloc_pages(gfp_mask, order) \
        alloc_pages_node(numa_node_id(), gfp_mask, order)

/*
 * Allocate pages, preferring the node given as nid. When nid == NUMA_NO_NODE,
 * prefer the current CPU's closest node. Otherwise node must be valid and
 * online.
 */
static inline struct page *alloc_pages_node(int nid, gfp_t gfp_mask, unsigned int order) {
    if (nid == NUMA_NO_NODE)
        nid = numa_mem_id();

    return __alloc_pages_node(nid, gfp_mask, order);
}
```

---

## 4. slab 内存分配算法

因为 buddy 分配内存粒度大，不能高效满足小内存分配，所以引入了 slab 算法。

算法讲解得比较详细的，参考这两篇帖子：

* [slab分配器--Linux内存管理(二十二)](https://blog.csdn.net/gatieme/article/details/52705552)
* [linux 内核 内存管理 slub算法 （一） 原理](https://blog.csdn.net/lukuen/article/details/6935068)

---

### 4.1. 概述

* slab 算法框架。

<div align=center><img src="/images/2021-04-14-21-56-46.png" data-action="zoom"/></div>

> 图片来源：[Linux内核内存管理算法Buddy和Slab](https://cloud.tencent.com/developer/article/1106795)

<div align=center><img src="/images/2021-04-19-11-21-59.png" data-action="zoom"/></div>

> 图片来源：[linux 内核 内存管理 slub算法 （一） 原理](https://blog.csdn.net/lukuen/article/details/6935068)

---

### 4.2. 使用

参考内核 epoll 源码是实现，epoll 通过一颗红黑树管理监控的 fd 节点，节点通过 slab 接口管理内存。

* 初始化。

```c
/* Slab cache used to allocate "struct epitem" */
static struct kmem_cache *epi_cache __read_mostly;

static int __init eventpoll_init(void) {
    ...
    /* Allocates slab cache used to allocate "struct epitem" items */
    epi_cache = kmem_cache_create(
        "eventpoll_epi", sizeof(struct epitem), 0,
        SLAB_HWCACHE_ALIGN | SLAB_PANIC | SLAB_ACCOUNT, NULL);
    ...
}
```

* 插入节点。

```c
/*
 * Must be called with "mtx" held.
 */
static int ep_insert(struct eventpoll *ep, const struct epoll_event *event,
             struct file *tfile, int fd, int full_check) {
    ...
    struct epitem *epi;
    ...
    if (!(epi = kmem_cache_alloc(epi_cache, GFP_KERNEL)))
    return -ENOMEM;
    ...
error_create_wakeup_source:
    kmem_cache_free(epi_cache, epi);

    return error;
}
```

* 删除节点。

```c
/*
 * Removes a "struct epitem" from the eventpoll RB tree and deallocates
 * all the associated resources. Must be called with "mtx" held.
 */
static int ep_remove(struct eventpoll *ep, struct epitem *epi) {
    ...
    call_rcu(&epi->rcu, epi_rcu_free);
    ...
}

static void epi_rcu_free(struct rcu_head *head) {
    struct epitem *epi = container_of(head, struct epitem, rcu);
    kmem_cache_free(epi_cache, epi);
}
```

---

## 5. 引用

* [alloc_page分配内存空间--Linux内存管理(十七)](https://blog.csdn.net/gatieme/article/details/52704844)
* [[2015 SP] 北京大学 Principles of Operating System 操作系统原理 by 陈向群 - 伙伴系统](https://www.bilibili.com/video/BV1Gx411Q7ro?p=42)
* [slab分配器--Linux内存管理(二十二)](https://blog.csdn.net/gatieme/article/details/52705552)
* [linux 内核 内存管理 slub算法 （一） 原理](https://blog.csdn.net/lukuen/article/details/6935068)
* [Linux内核伙伴算法和Slab分配器](https://www.bilibili.com/video/BV1YV411Y7Vi?from=search&seid=1414573769292008716)
* [Linux内存管理之SLAB原理浅析。](https://blog.csdn.net/rockrockwu/article/details/79976833)
* [linux内核开发第22讲：页框和伙伴算法以及slab机制](https://www.bilibili.com/video/BV1wk4y1y7gL)
* [linux内核开发第23讲：linux内核内存管理和分配方法概述](https://www.bilibili.com/video/BV14i4y1j783)
* [linux内核开发第24讲：kmalloc()的内核源码实现](https://www.bilibili.com/video/BV1154y1k7mC)
* [linux内核开发第25讲：kmalloc()分析之高速缓存和size的对应关系](https://www.bilibili.com/video/BV1aK4y177PN/?spm_id_from=autoNext)
* [【os浅尝】话说虚拟内存~](https://www.bilibili.com/video/BV1KD4y1U7Rr/?spm_id_from=333.788.recommend_more_video.0) 
* [Linux C 进程内存布局探索(2) 堆内存从 sbrk 到 malloc 及 free](https://www.bilibili.com/video/BV1L4411M7Ki)
* [Linux C 进程内存布局探索(1) 进程内存布局基础与栈及 ASLR](https://www.bilibili.com/video/BV1Y4411n72U)
* [gdb带源码调试libc](https://xuanxuanblingbling.github.io/ctf/tools/2020/03/20/gdb/)
* [Linux内核内存管理算法Buddy和Slab](https://cloud.tencent.com/developer/article/1106795) 
* [一次 Java 进程 OOM 的排查分析（glibc 篇）](https://www.jianshu.com/p/cf4f721eb9fe) 
* [Linux下禁止使用swap及防止OOM机制导致进程被kill掉](https://blog.csdn.net/u012373717/article/details/115402873)
* [OOM和Swap分区](https://www.cnblogs.com/liujunjun/p/12404588.html)
* [Linux内核必读五本书籍（强烈推荐）](https://www.jianshu.com/p/9d612dc89028)
* [Linux服务端swap配置和监控](https://blog.csdn.net/yongning99/article/details/46558333)
* [操作系统中的多级页表到底是为了解决什么问题？](https://www.zhihu.com/question/63375062)
* [Linux是几级页表？](https://blog.csdn.net/scylhy/article/details/92834714)
* [Linux四级页表及其原理](https://www.jianshu.com/p/242ba363e4ed)
* [线程切换与进程切换以及开销](https://blog.csdn.net/qq_35701633/article/details/97398354)
* [操作系统原理：第48讲，地址转换过程及TLB的引入](https://haokan.baidu.com/v?vid=1366651870518664014&pd=bjh&fr=bjhauthor&type=video)
* [为何要内存对齐](https://www.cnblogs.com/feng9exe/p/10046072.html)
* [利用CPU缓存实现高性能程序](https://mp.weixin.qq.com/s/ahvC7nI0Sw39zcgH6g7Hmw)
* [伙伴系统内存分配算法](https://www.bilibili.com/video/BV1Gx411Q7ro?p=42)
* [伙伴算法和Slab机制](https://blog.csdn.net/vhnxoiovxq/article/details/82735628)
* [Glibc 的malloc源代码分析](https://developer.aliyun.com/article/6274)
* [linux内核开发第10讲：x86段页式内存管理和页表映射机制](https://www.bilibili.com/video/BV1zt4y1U7rq?from=search&seid=12156928026814062829)
* [Linux内核伙伴算法和Slab分配器](https://www.bilibili.com/video/BV1YV411Y7Vi?from=search&seid=1414573769292008716)