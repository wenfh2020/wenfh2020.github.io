---
layout: post
title:  "[nginx 源码走读] 内存池"
categories: nginx
tags: nginx c
author: wenfh2020
mathjax: true
---

内存池原理：内存池预申请一块比较大的连续内存空间，当外部向内存池申请内存分配时，内存池从连续内存空间中，划分一部分出去，剩下部分是空闲的空间，当有新的分配，再划分一部分出去，直到内存池中没有足够的内存空间分配给新的申请，那么内存池再申请新的连续内存块。当然内存池分配出去的内存，也会回收使它重新成为空闲空间，重复利用。这样，内存池避免频繁向内核申请/释放内存，从而提高系统性能。

nginx 内存池源码([ngx_palloc.c](https://github.com/nginx/nginx/blob/master/src/core/ngx_palloc.c))，通过链式管理大小内存块，实现内存管理。



* content
{:toc}

---

## 1. 内存池使用测试

`ngx_palloc.c` 代码耦合不是很大，可以扣出来用 `gdb` 跟踪其工作流程。

> 测试源码已上传 [github](https://github.com/wenfh2020/c_test/blob/master/nginx/pool/pool.cpp)，测试视频已上传 [bilibili](https://www.bilibili.com/video/bv1TA41187Jp) 。

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

## 2. 接口

* 对外接口

| 接口             | 描述               |
| :--------------- | :----------------- |
| ngx_create_pool  | 创建内存池。       |
| ngx_destroy_pool | 释放内存池。       |
| ngx_reset_pool   | 重置内存池。       |
| ngx_memalign     | 内存对齐申请空间。 |
| ngx_palloc       | 分配内存。         |
| ngx_pfree        | 释放存块。         |

* 私有接口

| 接口             | 描述                                                                                   |
| :--------------- | :------------------------------------------------------------------------------------- |
| ngx_palloc_small | 分配小内存，内存池有足够空闲空间，从空闲空间分配，否则内存池申请新的小内存块进行分配。 |
| ngx_palloc_block | 分配小内存块块。                                                                       |
| ngx_palloc_large | 申请大块内存块。                                                                       |

---

## 3. 内存池

![nginx 内存池](/images/2020-04-25-17-15-19.png){: data-action="zoom"}

---

### 3.1. 内存池数据结构

nginx 内存池，将大小内存的分配分开管理：

* `ngx_pool_data_t` 链表管理小内存块。
* `ngx_pool_large_t` 链表管理大内存块。
* 系统小内存的申请频率比较高，分配的粒度比较小，容易在一块连续空闲内存上进行多次分配。
* 大内存分配频率相对较低，而且在一块有限的连续内存上，可分配次数比较少，这样会产生比较大的碎片。

这样，nginx 将大小内存的申请分开管理，逻辑更清晰，复杂度降低了，效率更高。

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

### 3.2. 小内存块

小内存块通过链表进行管理，内存分配过程，涉及到结点上空闲内存匹配是链表的遍历，复杂度是 $O(n)$，为了提高效率，增加了`failed` 分配内存失败次数统计（具体逻辑在分配函数里）

```c
typedef struct {
    u_char               *last;
    u_char               *end;
    ngx_pool_t           *next;
    ngx_uint_t            failed;
} ngx_pool_data_t;
```

---

### 3.3. 大内存块

大内存块由单向链表管理，没有复杂的空闲内存管理逻辑。

```c
typedef struct ngx_pool_large_s  ngx_pool_large_t;
struct ngx_pool_large_s {
    ngx_pool_large_t     *next;
    void                 *alloc;
};
```

---

### 3.4. 内存文件

```c
struct ngx_chain_s {
    ngx_buf_t    *buf;
    ngx_chain_t  *next;
};
```

---

## 4. 源码

### 4.1. 创建内存池

```c
ngx_int_t
ngx_os_init(ngx_log_t *log) {
    ...
    ngx_pagesize = getpagesize();
    ...
}

// 
#define NGX_MAX_ALLOC_FROM_POOL  (ngx_pagesize - 1)

// 数据对齐有利于提高 cpu 读数据效率。
#define NGX_POOL_ALIGNMENT       16

// size 参数是小内存块大小。
ngx_pool_t *
ngx_create_pool(size_t size, ngx_log_t *log) {
    ngx_pool_t  *p;

    // 分配 16 字节对齐的内存空间。
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

---

### 4.2. 释放内存池

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

---

### 4.3. 内存对齐申请空间

内存对齐，涉及到 cpu 工作效率，是高性能系统不可缺少的一环。

```c
#if (NGX_HAVE_POSIX_MEMALIGN)

void *
ngx_memalign(size_t alignment, size_t size, ngx_log_t *log) {
    void  *p;
    int    err;

    err = posix_memalign(&p, alignment, size);

    if (err) {
        p = NULL;
    }

    return p;
}

#elif (NGX_HAVE_MEMALIGN)

void *
ngx_memalign(size_t alignment, size_t size, ngx_log_t *log) {
    void  *p;

    p = memalign(alignment, size);
    if (p == NULL) {
        ...
    }

    return p;
}

#else

#define ngx_memalign(alignment, size, log)  ngx_alloc(size, log)

#endif

#ifndef NGX_ALIGNMENT
#define NGX_ALIGNMENT   sizeof(unsigned long)    /* platform word */
#endif
```

---

### 4.4. 分配内存

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

---

### 4.5. 分配小内存

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

    // 遍历链表后找不到合适的空闲空间，申请新的内存块。
    return ngx_palloc_block(pool, size);
}
```

---

### 4.6. 分配小内存块

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

    // 数据结构信息头后存储空闲数据。
    m += sizeof(ngx_pool_data_t);

    // 从 m 开始，计算以NGX_ALIGNMENT对齐的偏移位置指针。
    m = ngx_align_ptr(m, NGX_ALIGNMENT);

    // 分配 size 大小的空闲空间出去。
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

---

### 4.7. 申请大块内存

大块内存已分配的大块数据，除了内存块头部信息是可以重复利用的，数据不会重复利用，不用将被 ngx_pfree 释放掉。

```c
static void *
ngx_palloc_large(ngx_pool_t *pool, size_t size) {
    void              *p;
    ngx_uint_t         n;
    ngx_pool_large_t  *large;

    p = ngx_alloc(size, pool->log);
    if (p == NULL) {
        return NULL;
    }

    n = 0;

    // 重复利用已分配的大内存块结点信息。
    for (large = pool->large; large; large = large->next) {
        if (large->alloc == NULL) {
            large->alloc = p;
            return p;
        }

        // 防止大量的链表遍历降低效率（粒度那么小，会不会造成大量碎片？）。
        if (n++ > 3) {
            break;
        }
    }

    // 为数据结构申请空间。
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

---

### 4.8. 释放大内存块

只是释放数据，没有释放块的数据结构头。为了重复利用数据结构头信息，所以释放数据并没有删除链表结点，这里通过链表遍历进行删除，效率会不会很低。

```c
ngx_int_t
ngx_pfree(ngx_pool_t *pool, void *p) {
    ngx_pool_large_t  *l;

    for (l = pool->large; l; l = l->next) {
        if (p == l->alloc) {
            ngx_free(l->alloc);
            l->alloc = NULL;
            return NGX_OK;
        }
    }

    return NGX_DECLINED;
}
```

---

### 4.9. 重置内存池

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

## 5. 问题

nginx 的内存池实现足够精简高效，但是依然有些问题不能兼顾到：

* 链表管理：
  链表的查找遍历时间复杂度是 $O(n)$。`ngx_pfree` 效率不高。
* 小内存块链表，current 问题：
  当遇到密集地分配比较大的小内存场景时，导致已分配结点，分配失败，failed 次数增加。current 指向新的结点，由于是单向链表，前面的结点其实还有足够的空闲空间分配给其它小内存的，导致空闲空间利用率不高。
* 大内存块链表，重复利用已分配的信息头问题：
  遍历粒度很小，是否会产生大量内存碎片。
* 小内存回收问题：
  内存池只对大内存块进行内存回收，并没有小内存块的内存回收管理。只有 `ngx_reset_pool`， `ngx_destroy_pool` 是对其进行销毁处理的。

所以综合以上问题，这个内存池只适合于轻量级的内存管理。

---

## 6. 参考

* [Nginx 源码分析-- 内存池(pool)的分析 三](https://www.cnblogs.com/jzhlin/archive/2012/06/07/ngx_palloc.html)
* [nginx源码分析--内存对齐处理](https://blog.csdn.net/unix21/article/details/12913287)
* [利用cpu缓存实现高性能程序](https://cloud.tencent.com/developer/article/1449440)
* [ngx_align_ptr](https://blog.csdn.net/mangobar/article/details/52668859)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)