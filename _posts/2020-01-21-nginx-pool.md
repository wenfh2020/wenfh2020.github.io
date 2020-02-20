---
layout: post
title:  "[nginx 源码走读] 内存池"
categories: nginx
tags: nginx c
author: wenfh2020
mathjax: 1
---

nginx 内存池([源码](https://github.com/nginx/nginx/blob/master/src/core/ngx_palloc.c))通过大小内存块的链式管理逻辑大致如下图(部分**内存对齐**的细节没有添加进去)：

![内存池](/images/2020-02-20-16-40-53.png)


* content
{:toc}

---

## 内存池数据结构

### 小内存块

小内存块是通过链表进行管理，内存分配过程，涉及到结点上空闲内存匹配是链表的遍历，复杂度是 $O(n)$，为了提高效率，增加了`failed` 分配内存失败次数统计（具体逻辑在分配函数里）

```c
typedef struct {
    u_char               *last;
    u_char               *end;
    ngx_pool_t           *next;
    ngx_uint_t            failed;
} ngx_pool_data_t;
```

### 大内存块

大内存块没有复杂的空闲空间管理逻辑，都是直接分配单独的结点，需要销毁时直接释放。

```c
typedef struct ngx_pool_large_s  ngx_pool_large_t;
struct ngx_pool_large_s {
    ngx_pool_large_t     *next;
    void                 *alloc;
};
```

### 内存文件

```c
struct ngx_chain_s {
    ngx_buf_t    *buf;
    ngx_chain_t  *next;
};
```

### 内存池

nginx 内存池，主要通过大小空闲内存块两个链表进行维护， 内存池主要是对小块内存（`max`）进行逻辑管理达到重复利用。

 1. 小内存分配，在小内存块`ngx_pool_data_t`链表进行分配。
 2. 大内存分配，在大内存块`ngx_pool_large_t`链表分配。

可能因为大块内存长度比较大，重复利用率比较低，而且占用空间比较大，不宜长期留存在物理内存空间上，所以作者不对大块内存进行复杂大内存空间管理。

```c
typedef struct ngx_pool_s ngx_pool_t;
struct ngx_pool_s {
    ngx_pool_data_t       d;      // 小内存块数据链表
    size_t                max;    // 小内存块最大空间长度
    ngx_pool_t           *current;// 当前小内存块
    ngx_chain_t          *chain;  // 内存缓冲区链表（不详细分析）
    ngx_pool_large_t     *large;  // 大内存块数据链表
    ngx_pool_cleanup_t   *cleanup;// 释放内存池回调链表
    ngx_log_t            *log;    // 日志
};
```

---

## 接口

### 创建内存池

```c
ngx_int_t
ngx_os_init(ngx_log_t *log) {
    ngx_pagesize = getpagesize();
}

#define NGX_MAX_ALLOC_FROM_POOL  (ngx_pagesize - 1)
#define NGX_POOL_ALIGNMENT       16

ngx_pool_t *
ngx_create_pool(size_t size, ngx_log_t *log) {
    ngx_pool_t  *p;

    // 分配 16 字节对齐的内存。
    p = ngx_memalign(NGX_POOL_ALIGNMENT, size, log);
    if (p == NULL) {
        return NULL;
    }

    // 小内存块内存空间结构 (数据结构信息头 + 已分配内存 + 空闲内存)。
    p->d.last = (u_char *) p + sizeof(ngx_pool_t);
    p->d.end = (u_char *) p + size;
    p->d.next = NULL;
    p->d.failed = 0;

    // 小块内存大小，空闲内存最大小于 page size。
    size = size - sizeof(ngx_pool_t);
    p->max = (size < NGX_MAX_ALLOC_FROM_POOL) ? size : NGX_MAX_ALLOC_FROM_POOL;

    // 起始位置，指向初始结点。
    p->current = p;
    p->chain = NULL;
    p->large = NULL;
    p->cleanup = NULL;
    p->log = log;

    return p;
}
```

### 内存对齐申请空间

内存对齐，涉及到 cpu 工作效率，是高性能系统不可缺少的一环，有空可以深入研究。

```c
#if (NGX_HAVE_POSIX_MEMALIGN)

void *
ngx_memalign(size_t alignment, size_t size, ngx_log_t *log) {
    void  *p;
    int    err;

    err = posix_memalign(&p, alignment, size);

    if (err) {
        ngx_log_error(NGX_LOG_EMERG, log, err,
                      "posix_memalign(%uz, %uz) failed", alignment, size);
        p = NULL;
    }

    ngx_log_debug3(NGX_LOG_DEBUG_ALLOC, log, 0,
                   "posix_memalign: %p:%uz @%uz", p, size, alignment);

    return p;
}

#elif (NGX_HAVE_MEMALIGN)

void *
ngx_memalign(size_t alignment, size_t size, ngx_log_t *log) {
    void  *p;

    p = memalign(alignment, size);
    if (p == NULL) {
        ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                      "memalign(%uz, %uz) failed", alignment, size);
    }

    ngx_log_debug3(NGX_LOG_DEBUG_ALLOC, log, 0,
                   "memalign: %p:%uz @%uz", p, size, alignment);

    return p;
}


#else

#define ngx_memalign(alignment, size, log)  ngx_alloc(size, log)

#endif

#ifndef NGX_ALIGNMENT
#define NGX_ALIGNMENT   sizeof(unsigned long)    /* platform word */
#endif
```

### 释放内存池

除了对大小内存块数据进行释放，还增加了回调操作的设计，方便开发者进行部分具体的业务处理。

```c
void
ngx_destroy_pool(ngx_pool_t *pool) {
    ngx_pool_t          *p, *n;
    ngx_pool_large_t    *l;
    ngx_pool_cleanup_t  *c;

    // 释放回调处理。
    for (c = pool->cleanup; c; c = c->next) {
        if (c->handler) {
            ngx_log_debug1(NGX_LOG_DEBUG_ALLOC, pool->log, 0,
                           "run cleanup: %p", c);
            c->handler(c->data);
        }
    }

    // 释放大内存块
    for (l = pool->large; l; l = l->next) {
        if (l->alloc) {
            ngx_free(l->alloc);
        }
    }

    // 释放小内存块
    for (p = pool, n = pool->d.next; /* void */; p = n, n = n->d.next) {
        ngx_free(p);

        if (n == NULL) {
            break;
        }
    }
}
```

### 分配内存

如果分配的内存在小内存块空间范围内，就通过小内存块空闲链表中分配，否则直接分配到大内存块链表中。

```c
void *
ngx_palloc(ngx_pool_t *pool, size_t size) {
#if !(NGX_DEBUG_PALLOC)
    if (size <= pool->max) {
        return ngx_palloc_small(pool, size, 1);
    }
#endif
    return ngx_palloc_large(pool, size);
}
```

`pool->max` 查看 `ngx_create_pool` 的实现：

```c
size = size - sizeof(ngx_pool_t);
p->max = (size < NGX_MAX_ALLOC_FROM_POOL) ? size : NGX_MAX_ALLOC_FROM_POOL;
```

### 分配小内存

满足条件 `size <= pool->max` 的小内存的空间分配，遍历小内存块链表，从已分配的空间中查找合适的空闲空间进行分配，否则再创建新的小内存块进行匹配。

```c
static ngx_inline void *
ngx_palloc_small(ngx_pool_t *pool, size_t size, ngx_uint_t align) {
    u_char      *m;
    ngx_pool_t  *p;
    // 遍历查找起始位置。
    p = pool->current;

    do {
        // 从小内存块中，查找剩余空间，检查是否有足够的剩余空间分配。
        m = p->d.last;
        if (align) {
            // 从 m 开始，计算以NGX_ALIGNMENT对齐的偏移位置指针。
            m = ngx_align_ptr(m, NGX_ALIGNMENT);
        }

        // 如果有足够空间，就返回分配的空间，空闲内存减少 size 大小
        if ((size_t) (p->d.end - m) >= size) {
            p->d.last = m + size;
            return m;
        }

        // 检查下一个结点
        p = p->d.next;
    } while (p);

    // 遍历链表后找不到合适的，申请新的内存块。
    return ngx_palloc_block(pool, size);
}
```

### 分配小内存块

```c
static void *
ngx_palloc_block(ngx_pool_t *pool, size_t size) {
    u_char      *m;
    size_t       psize;
    ngx_pool_t  *p, *new;

    // 获取小内存块链表第一个块内存空间大小。
    psize = (size_t) (pool->d.end - (u_char *) pool);

    // 分配 16字节对齐的空间。
    m = ngx_memalign(NGX_POOL_ALIGNMENT, psize, pool->log);
    if (m == NULL) {
        return NULL;
    }

    // 设置新结点信息。
    new = (ngx_pool_t *) m;
    new->d.end = m + psize;
    new->d.next = NULL;
    new->d.failed = 0;

    // 数据结构信息头后存储空闲数据
    m += sizeof(ngx_pool_data_t);

    // 从 m 开始，计算以NGX_ALIGNMENT对齐的偏移位置指针
    m = ngx_align_ptr(m, NGX_ALIGNMENT);

    // 分配 size 大小的空闲空间出去
    new->d.last = m + size;

    // 原来的内存块结点均分配失败，要将失败的分配记录下来。
    for (p = pool->current; p->d.next; p = p->d.next) {
        if (p->d.failed++ > 4) {
            pool->current = p->d.next;
        }
    }

    // 新的空闲内存块结点添加到链表末尾
    p->d.next = new;
    return m;
}
```

### 申请大块内存

大块内存已分配的大块数据，除了内存块头部信息是可以重复利用的，数据不会重复利用，不用将被 ngx_pfree 释放掉。

```c
static void *
ngx_palloc_large(ngx_pool_t *pool, size_t size)
{
    void              *p;
    ngx_uint_t         n;
    ngx_pool_large_t  *large;

    p = ngx_alloc(size, pool->log);
    if (p == NULL) {
        return NULL;
    }

    n = 0;

    // 重复利用已分配的大内存块结点信息
    for (large = pool->large; large; large = large->next) {
        if (large->alloc == NULL) {
            large->alloc = p;
            return p;
        }

        // 防止大量的链表遍历降低效率（粒度那么小，会不会造成大量碎片？）
        if (n++ > 3) {
            break;
        }
    }

    // 为数据结构申请空间
    large = ngx_palloc_small(pool, sizeof(ngx_pool_large_t), 1);
    if (large == NULL) {
        ngx_free(p);
        return NULL;
    }

    // 新结点插入到表头，有点像 lru，将活跃数据放到前面去。
    large->alloc = p;
    large->next = pool->large;
    pool->large = large;

    return p;
}
```

### 释放大内存块

只是释放数据，没有释放块的数据结构头。为了重复利用数据结构头信息，所以释放数据并没有删除链表结点，这里通过链表遍历进行删除，效率会不会很低。

```c
ngx_int_t
ngx_pfree(ngx_pool_t *pool, void *p) {
    ngx_pool_large_t  *l;

    for (l = pool->large; l; l = l->next) {
        if (p == l->alloc) {
            ngx_log_debug1(NGX_LOG_DEBUG_ALLOC, pool->log, 0,
                           "free: %p", l->alloc);
            ngx_free(l->alloc);
            l->alloc = NULL;
            return NGX_OK;
        }
    }

    return NGX_DECLINED;
}
```

### 重置内存池

```c
void
ngx_reset_pool(ngx_pool_t *pool) {
    ngx_pool_t        *p;
    ngx_pool_large_t  *l;

    for (l = pool->large; l; l = l->next) {
        if (l->alloc) {
            ngx_free(l->alloc);
        }
    }

    // 每个小内存块空闲内存指针，指向数据结构头后面
    for (p = pool; p; p = p->d.next) {
        p->d.last = (u_char *) p + sizeof(ngx_pool_t);
        p->d.failed = 0;
    }

    pool->current = pool;
    pool->chain = NULL;
    pool->large = NULL;
}

```

---

## 问题

nginx 的内存池实现足够精简高效，但是依然有些问题不能兼顾到：

* 链表管理：
  链表的查找遍历时间复杂度是 $O(n)$。`ngx_pfree` 效率不高。
* 小内存块链表，current 问题：
  当遇到密集地分配比较大的小内存场景时，导致已分配结点，分配失败，failed 次数增加。current 指向新的结点，由于是单向链表，前面的结点其实还有足够的空闲空间分配给其它小内存的，导致空闲空间利用率不高。
* 大内存块链表，重复利用已分配的信息头问题：
  遍历粒度很小，是否会产生大量内存碎片。
* 小内存回收问题：
  内存池只对大内存块进行内存回收，并没有小内存块的内存回收管理。只有 `ngx_reset_pool`， `ngx_destroy_pool` 是对其进行销毁处理的。

---

所以综合以上问题，这个内存池只适合于轻量级的内存管理。

---

## 测试

nginx 代码耦合不是很大，可以扣出来调试跟踪一下工作流程。（[源码](https://github.com/wenfh2020/c_test/blob/master/nginx/pool/pool.cpp)）

```c
int main() {
    ngx_pool_t *pool = ngx_create_pool(2 * 1024);
    void *p = ngx_palloc(pool, 256);
    void *p2 = ngx_palloc(pool, 1024);
    void *p3 = ngx_palloc(pool, 1024);
    void *p4 = ngx_palloc(pool, 256);
    void *p5 = ngx_palloc(pool, 1024);
    void *p6 = ngx_palloc(pool, 1024);
    void *p7 = ngx_palloc(pool, 4 * 1024);

    ngx_pool_cleanup_t *c = (ngx_pool_cleanup_t *)ngx_pool_cleanup_add(pool, 0);
    memcpy(p, "hello world!", strlen("hello world!") + 1);
    c->handler = test_cleanup;
    c->data = p;

    ngx_destroy_pool(pool);
    return 0;
}
```

---

## 参考

[Nginx 源码分析-- 内存池(pool)的分析 三](https://www.cnblogs.com/jzhlin/archive/2012/06/07/ngx_palloc.html)

[nginx源码分析--内存对齐处理](https://blog.csdn.net/unix21/article/details/12913287)

[利用cpu缓存实现高性能程序](https://cloud.tencent.com/developer/article/1449440)

[ngx_align_ptr](https://blog.csdn.net/mangobar/article/details/52668859)