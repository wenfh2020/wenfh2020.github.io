---
layout: post
title:  "[redis 源码走读] zmalloc"
categories: redis
tags: redis zmalloc
author: wenfh2020
---

redis 内存管理实现，有三种方案：

1. `jemalloc` (谷歌)
2. `tcmalloc` （facebook）
3. `libc` （系统）

其中 `jemalloc`， `tcmalloc` 是第三方的实现，`libc` 的实现做了一些简单的封装。




* content
{:toc}

## 1. 内存池方案

```c
// 理解宏对相关库的引入使用。
#if defined(USE_TCMALLOC)
#define ZMALLOC_LIB ("tcmalloc-" __xstr(TC_VERSION_MAJOR) "." __xstr(TC_VERSION_MINOR))
#include <google/tcmalloc.h>
#if (TC_VERSION_MAJOR == 1 && TC_VERSION_MINOR >= 6) || (TC_VERSION_MAJOR > 1)
#define HAVE_MALLOC_SIZE 1
#define zmalloc_size(p) tc_malloc_size(p)
#else
#error "Newer version of tcmalloc required"
#endif

#elif defined(USE_JEMALLOC)
#define ZMALLOC_LIB ("jemalloc-" __xstr(JEMALLOC_VERSION_MAJOR) "." __xstr(JEMALLOC_VERSION_MINOR) "." __xstr(JEMALLOC_VERSION_BUGFIX))
#include <jemalloc/jemalloc.h>
#if (JEMALLOC_VERSION_MAJOR == 2 && JEMALLOC_VERSION_MINOR >= 1) || (JEMALLOC_VERSION_MAJOR > 2)
#define HAVE_MALLOC_SIZE 1
#define zmalloc_size(p) je_malloc_usable_size(p)
#else
#error "Newer version of jemalloc required"
#endif

#elif defined(__APPLE__)
#include <malloc/malloc.h>
#define HAVE_MALLOC_SIZE 1
#define zmalloc_size(p) malloc_size(p)
#endif

#ifndef ZMALLOC_LIB
#define ZMALLOC_LIB "libc"
#ifdef __GLIBC__
#include <malloc.h>
#define HAVE_MALLOC_SIZE 1
#define zmalloc_size(p) malloc_usable_size(p)
#endif
#endif
```

---

## 2. 核心接口

* 内存管理
  如果是 `libc` 实现的内存管理，内存分配会加一个前缀，保存内存长度。有点像 `nginx` 的字符串结构。分配内存返回内容指针，释放内存，指针要从数据部分移动到内存长度部分。

```c
// nginx 字符串结构
typedef struct {
    size_t      len;
    u_char     *data;
} ngx_str_t;
```

```c
#ifdef HAVE_MALLOC_SIZE
#define PREFIX_SIZE (0)
#else
#if defined(__sun) || defined(__sparc) || defined(__sparc__)
#define PREFIX_SIZE (sizeof(long long))
#else
#define PREFIX_SIZE (sizeof(size_t))
#endif
#endif

// 分配内存
void *zmalloc(size_t size) {
    // 内存长度前缀
    void *ptr = malloc(size + PREFIX_SIZE);

    if (!ptr) zmalloc_oom_handler(size);
#ifdef HAVE_MALLOC_SIZE
    update_zmalloc_stat_alloc(zmalloc_size(ptr));
    return ptr;
#else
    *((size_t *)ptr) = size;
    // 统计
    update_zmalloc_stat_alloc(size + PREFIX_SIZE);
    // 返回内容内存
    return (char *)ptr + PREFIX_SIZE;
#endif
}

// 释放内存
void zfree(void *ptr) {
#ifndef HAVE_MALLOC_SIZE
    void *realptr;
    size_t oldsize;
#endif

    if (ptr == NULL) return;
#ifdef HAVE_MALLOC_SIZE
    update_zmalloc_stat_free(zmalloc_size(ptr));
    free(ptr);
#else
    // 指针移动到内存起始位置
    realptr = (char *)ptr - PREFIX_SIZE;
    oldsize = *((size_t *)realptr);
    // 统计
    update_zmalloc_stat_free(oldsize + PREFIX_SIZE);
    free(realptr);
#endif
}
```

* 内存对齐和统计
  `used_memory` 统计内存使用
  分配内存，内存对齐是为了提高 cpu 效率。但是 `update_zmalloc_stat_alloc`

```c
#define update_zmalloc_stat_alloc(__n) do { \
    size_t _n = (__n); \
    // 对齐 \
    if (_n&(sizeof(long)-1)) _n += sizeof(long)-(_n&(sizeof(long)-1)); \
    atomicIncr(used_memory,__n); \
} while(0)
```

这个函数的实现让人费解，代码对 `_n` 进行操作，最后却保存了 `__n` 。github 上虽然提出了这个[问题](https://github.com/antirez/redis/issues/4739)，貌似没有得到解决.

历史版本 [blame](https://github.com/antirez/redis/blame/9390c384b88de6b2363c3f33ba42bd25c1c3346d/src/zmalloc.c)

![历史](/images/2020/2020-02-20-16-47-12.png){: data-action="zoom"}

当前版本 [blame](https://github.com/antirez/redis/blame/unstable/src/zmalloc.c)

![当前](/images/2020/2020-02-20-16-47-28.png){: data-action="zoom"}

---

* 获得系统已使用内存

redis 内存申请几乎都调用 zmalloc 接口，每次申请和回收都会被 `used_memory` 记录起来。当系统处理 `maxmemory` 的时候，就要知道系统使用了多少内存，从而进行一些回收数据的策略。

```c
size_t zmalloc_used_memory(void) {
    size_t um;
    atomicGet(used_memory,um);
    return um;
}
```

---

## 3. 参考

* [关于redis源码的内存分配,jemalloc,tcmalloc,libc](https://blog.csdn.net/libaineu2004/article/details/79400357)
