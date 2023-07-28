---
layout: post
title:  "剖析 stl + glibc “内存泄漏” 原因"
categories: c/c++
tags: stl glibc memory leak
author: wenfh2020
---

最近项目增加了一个模块，在 Centos 系统压测，进程一直不释放内存。因为新增代码量不多，经过排查，发现 stl + glibc 这个经典组合竟然有问题，见鬼了！

通过[调试](https://wenfh2020.com/2021/11/09/gdb-glibc/)和查阅 [glibc 源码](https://ftp.gnu.org/pub/gnu/glibc/)，好不容易才搞明白它 "泄漏" 的原因。

问题在于：`ptmalloc2` 内存池的 `fast bins` 快速缓存和 `top chunk` 内存返还系统的特点导致。





* content
{:toc}

---

## 1. 现象

上测试源码看看：

<div align=center><img src="/images/2021/2021-04-21-14-09-49.png" data-action="zoom"/></div>

```c
/* g++ -g -std='c++11' example_pressure.cpp -o ep111  && ./ep111 10000 */
 
#include <string.h>
#include <unistd.h>
 
#include <iostream>
#include <list>
 
int main(int argc, char** argv) {
    if (argc != 2) {
        printf("./proc [count]\n");
        return -1;
    }
 
    int cnt = atoi(argv[1]);
    std::list<char*> free_list;
 
    for (int i = 0; i < cnt; i++) {
        char* m = new char[1024 * 64];
        memset(m, 'a', 1024 * 64);
        free_list.push_back(m);
    }
 
    for (auto& v : free_list) {
        delete[] v;
    }
 
    for (;;) {
        sleep(1);
    }
    return 0;
}
```

---

## 2. 分析

### 2.1. valgrind

用 valgrind 检查出来的结果，没有释放的部分应该是 `free_list` 没有调用 clear 导致，但显然不符合预期。

```shell
[root:.../coroutine/test_libco/libco]# valgrind  --leak-check=full --show-leak-kinds=all ./ep111 20000
==20802== Memcheck, a memory error detector
==20802== Copyright (C) 2002-2017, and GNU GPL'd, by Julian Seward et al.
==20802== Using Valgrind-3.15.0 and LibVEX; rerun with -h for copyright info
==20802== Command: ./ep111 20000
...
==20802== 
==20802== HEAP SUMMARY:
==20802==     in use at exit: 480,000 bytes in 20,000 blocks
==20802==   total heap usage: 40,000 allocs, 20,000 frees, 1,311,200,000 bytes allocated
==20802== 
==20802== 480,000 bytes in 20,000 blocks are still reachable in loss record 1 of 1
==20802==    at 0x4C2A593: operator new(unsigned long) (vg_replace_malloc.c:344)
==20802==    by 0x401186: __gnu_cxx::new_allocator<std::_List_node<char*> >::allocate(unsigned long, void const*) (new_allocator.h:104)
==20802==    by 0x4010E5: std::_List_base<char*, std::allocator<char*> >::_M_get_node() (stl_list.h:334)
==20802==    by 0x401016: std::_List_node<char*>* std::list<char*, std::allocator<char*> >::_M_create_node<char* const&>(char* const&) (stl_list.h:502)
==20802==    by 0x400F21: void std::list<char*, std::allocator<char*> >::_M_insert<char* const&>(std::_List_iterator<char*>, char* const&) (stl_list.h:1561)
==20802==    by 0x400D93: std::list<char*, std::allocator<char*> >::push_back(char* const&) (stl_list.h:1016)
==20802==    by 0x400BD8: main (example_pressure.cpp:21)
==20802== 
==20802== LEAK SUMMARY:
==20802==    definitely lost: 0 bytes in 0 blocks
==20802==    indirectly lost: 0 bytes in 0 blocks
==20802==      possibly lost: 0 bytes in 0 blocks
==20802==    still reachable: 480,000 bytes in 20,000 blocks
==20802==         suppressed: 0 bytes in 0 blocks
```

---

### 2.2. pmap

用 pmap 命令查看进程，发现 640600K 这一块 [ anon ] 内存很大，应该是这个地方“泄漏”了。

<div align=center><img src="/images/2021/2021-04-21-14-19-25.png" data-action="zoom"/></div>

> 图片来源：《深入理解计算机系统》

```shell
# pmap -p 3321
3321:   ./ep111 10000
0000000000400000      8K r-x-- ep111
0000000000601000      4K r---- ep111
0000000000602000      4K rw--- ep111
# 640600K 这里数值很大，应该是泄漏的地方了。
000000000180d000 640600K rw---   [ anon ]
00007ff2a8ce5000   1804K r-x-- libc-2.17.so
00007ff2a8ea8000   2048K ----- libc-2.17.so
00007ff2a90a8000     16K r---- libc-2.17.so
00007ff2a90ac000      8K rw--- libc-2.17.so
00007ff2a90ae000     20K rw---   [ anon ]
00007ff2a90b3000     84K r-x-- libgcc_s-4.8.5-20150702.so.1
00007ff2a90c8000   2044K ----- libgcc_s-4.8.5-20150702.so.1
00007ff2a92c7000      4K r---- libgcc_s-4.8.5-20150702.so.1
00007ff2a92c8000      4K rw--- libgcc_s-4.8.5-20150702.so.1
00007ff2a92c9000   1028K r-x-- libm-2.17.so
00007ff2a93ca000   2044K ----- libm-2.17.so
00007ff2a95c9000      4K r---- libm-2.17.so
00007ff2a95ca000      4K rw--- libm-2.17.so
00007ff2a95cb000    932K r-x-- libstdc++.so.6.0.19
00007ff2a96b4000   2044K ----- libstdc++.so.6.0.19
00007ff2a98b3000     32K r---- libstdc++.so.6.0.19
00007ff2a98bb000      8K rw--- libstdc++.so.6.0.19
00007ff2a98bd000     84K rw---   [ anon ]
00007ff2a98d2000    136K r-x-- ld-2.17.so
00007ff2a9ae0000     20K rw---   [ anon ]
00007ff2a9af2000      4K rw---   [ anon ]
00007ff2a9af3000      4K r---- ld-2.17.so
00007ff2a9af4000      4K rw--- ld-2.17.so
00007ff2a9af5000      4K rw---   [ anon ]
00007ffd62611000    132K rw---   [ stack ]
00007ffd62799000      8K r-x--   [ anon ]
ffffffffff600000      4K r-x--   [ anon ]
 total           653144K
```

---

### 2.3. malloc 内存信息

通过查看 malloc 分配的内存信息，发现 std::list::clear 后，程序已经全部释放内存。

然而这些程序已经释放掉的内存是否已经全部返还给系统了呢？答案是：<font color=red>NO</font>！glibc 缓存起来了。

`system bytes = 655974400` 刚好与 `pmap` 命令查到的堆分配内存大小一致。

> 【注意】C++ 的 new 也是调用 malloc 分配内存的。

* malloc_stats 打印 glibc 分配内存信息。

```c
/* example_pressure.cpp */
...
void print_mem_info(const char* s) {
    printf("------------------------\n");
    printf("-- %s\n", s);
    printf("------------------------\n");
    malloc_stats();
}

int main(int argc, char** argv) {
    ...
    int cnt = atoi(argv[1]);
    std::list<char*> free_list;

    print_mem_info("begin");

    for (int i = 0; i < cnt; i++) {
        char* m = new char[1024 * 64];
        memset(m, 'a', 1024 * 64);
        free_list.push_back(m);
    }

    print_mem_info("alloc blocks");

    for (auto& v : free_list) {
        delete[] v;
    }

    print_mem_info("free blocks");

    free_list.clear();
    print_mem_info("clear list.");
    ...
}
```

* 最后已经全部释放（free）内存，但是 glibc 仍然没有把内存归还系统。

```shell
# system bytes：glibc 向系统申请的内存大小。
# in use bytes：用户进程通过 malloc 向 glibc 申请分配的内存大小。
```

```shell
# g++ -g -std='c++11' example_pressure.cpp -o ep111 && ./ep111 10000
------------------------
-- begin
------------------------
Arena 0:
system bytes     =          0
in use bytes     =          0
...
------------------------
-- alloc blocks
------------------------
Arena 0:
system bytes     =  655974400 
in use bytes     =  655840000
...
------------------------
-- free blocks
------------------------
Arena 0:
system bytes     =  655974400
in use bytes     =     320000
...
------------------------
-- clear list.
------------------------
Arena 0:
system bytes     =  655974400
in use bytes     =          0
...
```

---

## 3. glibc 问题分析

ptmalloc2 是目前 Linux 用户空间默认的内存分配器，源码集成在 glibc 里。

ptmalloc2 支持多线程，它为多个线程提供了多个 `arena` 分区（malloc_state）管理内存：主分区和非主分区（main_arena/non_main_arena）。因为本文 demo 是单线程，所以我们这里只讨论 `main_arena` 场景，详细请参考文档：[glibc内存管理ptmalloc源代码分析.pdf](https://paper.seebug.org/papers/Archive/refs/heap/glibc%E5%86%85%E5%AD%98%E7%AE%A1%E7%90%86ptmalloc%E6%BA%90%E4%BB%A3%E7%A0%81%E5%88%86%E6%9E%90.pdf)。

至于 free 掉的内存 glibc 为啥没有返还给系统，通过走读和调试它的源码后，发现 `malloc_state.top` 这个 top chunk 对问题解决起着关键作用。

---

### 3.1. 系统内存分配流程

* ptmalloc2 主要通过 `sbrk` 和 `mmap` 这两个函数，向内核申请内存空间。因为上述例子是单线程的，而且每次(new/malloc)申请的内存小于 128k，所以用户空间向内核申请内存通过 sbrk 而不是 mmap。

<div align=center><img src="/images/2021/2021-04-14-17-13-58.png" data-action="zoom"/></div>

> 图片来源：[Linux内核内存管理算法Buddy和Slab](https://cloud.tencent.com/developer/article/1106795)

---

### 3.2. 关键内存结构

#### 3.2.1. malloc_chunk

ptmalloc2 每次会根据需要向内核申请一大块内存空间，并将其分割成大小不等的内存块，内存块以 `chunk` 形式进行管理。

```c
/*
  This struct declaration is misleading (but accurate and necessary).
  It declares a "view" into memory allowing access to necessary
  fields at known offsets from a given base. See explanation below.
*/
struct malloc_chunk {
    INTERNAL_SIZE_T prev_size; /* Size of previous chunk (if free).  */
    INTERNAL_SIZE_T size;      /* Size in bytes, including overhead. */

    struct malloc_chunk* fd; /* double links -- used only if free. */
    struct malloc_chunk* bk;

    /* Only used for large blocks: pointer to next larger size.  */
    struct malloc_chunk* fd_nextsize; /* double links -- used only if free. */
    struct malloc_chunk* bk_nextsize;
};
```

这个结构比较特别，已分配出去的内存结构，结构是下面这样的。

```shell
       chunk--> +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
                |             Size of previous chunk, if allocated              |
                +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
                |             Size of chunk, in bytes                     |A|M|P|
         mem--> +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
                |             User data starts here...                          .
                .                                                               .
                .             (malloc_usable_size() bytes)                      .
                .                                                               |
   nextchunk--> +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
                |             Size of chunk                                     |
                +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

malloc 给用户返回内存是 `mem` 的地址，事实上，它前面有两个 `size_t` 大小的空间分别保存了：前一个 `chunk` 大小，当前 `chunk` 大小。只有在前一个 `chunk` 空闲时，这个 prev_size 才会有效。而 fd, bk, fd_next_size, bk_nextsize 这几个成员，只有空闲块才会用到。

---

#### 3.2.2. malloc_state

可以理解为线程的内存池分区（`arena`），那些 free 接口释放的内存，会根据一定的策略缓存起来，或者返还系统。

因为 ptmalloc2 本来就是一个内存池，为了提高内存分配效率，避免用户态和内核态频繁进行交互，它需要通过一些策略，将部分用户释放(delete/free)的内存缓存起来，不马上返还给系统。而缓存起来的内存块，通过 fastbinsY 和 bins 这些数组维护起来，数组保存的是空闲内存块链表。

`top` 这个内存块指向 top chunk，它对于理解 glibc 从系统申请内存，返还内存给系统有着关键作用。

```c
typedef struct malloc_chunk* mchunkptr;
typedef struct malloc_chunk* mfastbinptr;

struct malloc_state {
    ...
    mfastbinptr fastbinsY[NFASTBINS];

    /* Base of the topmost chunk -- not otherwise kept in a bin */
    mchunkptr top;

    /* Normal bins packed as described above */
    mchunkptr bins[NBINS * 2 - 2];
    ...
};
```

|   成员    | 描述                                                                                                                                                                                                                                                         |
| :-------: | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| fastbinsY | 拥有 10 (NFASTBINS) 个元素的数组，用于存放每个 fast chunk 链表头指针，所以 fast bins 最多包含 10 个 fast chunk 的单向链表。                                                                                                                                  |
|    top    | 是一个 chunk 指针，指向分配区的 top chunk。                                                                                                                                                                                                                  |
|   bins    | 用于存储 unstored bin，small bins 和 large bins 的 chunk 链表头，small bins 一共 62 个，large bins 一共 63 个，加起来一共 125 个 bin。而 NBINS 定义为 128，其实 bin[0] 和 bin[127] 都不存在，bin[1] 为 unsorted bin 的 chunk 链表头，所以实际只有 126 bins。 |

---

### 3.3. sbrk 系统分配回收内存

测试 demo 分配小内存，当 glibc 内存池缓存不足时，glibc 会通过 sbrk 向系统申请内存给 malloc_state.top，也就是 top chunk，从它那里划分一块出来返回给用户进程。

当 top chunk 内存达到一个回收阈值时，它才会通过 sbrk 返还内存给系统。所以说理解 malloc_state.top 是解决问题的关键。

<div align=center><img src="/images/2021/2021-04-27-09-13-26.png" data-action="zoom"/></div>

---

#### 3.3.1. 内存块长期不被回收

很多时候，通过 free 释放掉的内存块，它不是紧贴 top chunk 那一块内存，它被释放后并没有合并到 top chunk，所以 top chunk 的大小没有改变，没有达到返还系统的阈值，所以空闲内存不会被返还系统，<font color=red> 如上图，如果程序刚好有一个像 n2 那样的小内存块长时间不释放，那就杯具了</font>。例如：

```c
void print_mem_info(const char* s) {
    printf("------------------------\n");
    printf("-- %s\n", s);
    printf("------------------------\n");
    malloc_stats();
    printf("------------------------\n");
}

void test() {
    char *addr, *addr2;
    int size = 64 * 1024;
    char* mems[64 * 1024];

    for (int i = 0; i < size; i++) {
        addr = (char*)malloc(4 * 1024 * sizeof(char));
        mems[i] = addr;
    }

    /* 紧贴 top chunk 的小内存块 addr2，如果一直不释放，那它前面分配的内存即使 free 掉后，
       内存池依然不会将缓存返还给系统。 */
    addr2 = (char*)malloc(1 * sizeof(char));

    for (int i = 0; i < size; i++) {
        free(mems[i]);
    }

    print_mem_info("stats info");
    for (;;) {
        sleep(1);
    }
    ...
}
```

```shell
------------------------
-- stats info
------------------------
Arena 0:
system bytes     =  269602816 # ptmalloc2 向系统申请的内存。
in use bytes     =         32 # ptmalloc2 已经分配出去给用户使用的内存，还没释放。
```

---

#### 3.3.2. fast bins 缓存

有时候即便回收的内存紧贴 top chunk，但是被释放的内存太小了，以至于内存池为了保证小内存的分配效率，而将其缓存起来放进 fast bins，而没有被 top chunk 合并。
  
例如上图图 2，就是测试 demo 图 1 的内存布局。堆内存是从低位向高位分配，但是如果 n2 内存没有被 free 掉，或者 n2 被 free 掉后，内存池为了效率，将其缓存起来了，并没有合并到 top chunk，那么即便 n2 之前的堆内存全部 free 掉了，内存池也不会将内存归还系统的。

所以对于 fast bins 这些缓存起来的小空闲内存块，需要在某一时刻对这些小空闲内存块进行处理。

正常情况下，当内存池管理的内存块不足以满足分配时，而且 top chunk 也不够空间分配了，内存池会尝试处理 fast bins 里的这些空闲小内存块，看看能否合并出足够的大空间满足分配需求。但是如果内存池里的空间一直能满足外部的分配，那么这个处理就永远不会触发。

ptmalloc2 可能早已预见了这样的场景，所以提供了 `malloc_trim` 这样的接口。能主动将 `n2` 这样的已经释放的小内存块，从 fast bins 缓存里取出来进行合并整理。这样，零散的内存碎片很可能会因为这些小内存碎片，合并成大块的连续内存，top chunk 很大概率会跟那些空闲的内存碎片连接成为一个连续的大块内存，达到返还系统的标准。

---

通过上述分析，我们可以知道，为啥 glibc 会出现"内存泄漏"了。那为啥 stl + glibc 搭配出现内存泄漏的概率那么高呢？stl 内部不少类都有动态内存管理，就像图 2 的 `n2` 这个小内存块，如果缓存起来，一直不释放，那么其它内存块即使释放，ptmalloc2 也很大几率不会将内存返还系统。

其实这不只是 stl 的问题，即便不用 stl，用户实现复杂的业务逻辑，也很可能会因为一个小内存块不释放，导致 ptmalloc2 不能将空闲内存返还系统。

---

这里测试 demo，std::list 节点也会向 glibc 申请很多小内存，std::list::clear 执行后，std::list 全部节点被 free 掉了，因为 std::list 每个节点才占 32 个字节 chunk（64 位系统），它们被 fast bins 缓存起来了，并没有触发 top chunk 的内存合并。所以 top chunk 的大小一直没有超过返还系统的阈值，所以 ptmalloc2 的缓存一直没有归还系统。

---

### 3.4. malloc_trim

上面已经剖析了小内存不回收，可能会影响内存池内存返还系统。如果小内存一直不被程序释放，那怎么办？malloc_trim！

我们知道，程序申请的内存是虚拟内存，系统寻址是通过虚拟地址转换为物理地址。所以我们可以保留虚拟内存，“释放物理内存”，等到程序真正使用需要的物理内存时，再通过断页的方式，重新加载。这样就可以就可以减少系统整体的物理内存使用。

> 详细请参考下面 malloc_trim 的源码实现：__madvise 函数的调用。

---

### 3.5. 源码分析

* 分配内存。如果内存池没有足够内存，malloc 通过 sbrk 向系统申请一块虚拟内存给 top chunk，然后再从这块内存上分配合适的内存出去。

```c
static void* _int_malloc(mstate av, size_t bytes) {
    ...
use_top:
    victim = av->top;
    size = chunksize(victim);

    /* 如果内存池没有匹配的缓存，那么从当前 top chunk 内存块划一块内存处理分配。 */
    if ((unsigned long)(size) >= (unsigned long)(nb + MINSIZE)) {
        remainder_size = size - nb;
        remainder = chunk_at_offset(victim, nb);
        av->top = remainder;
        set_head(victim, nb | PREV_INUSE | (av != &main_arena ? NON_MAIN_ARENA : 0));
        set_head(remainder, remainder_size | PREV_INUSE);

        check_malloced_chunk(av, victim, nb);
        void* p = chunk2mem(victim);
        if (__builtin_expect(perturb_byte, 0))
            alloc_perturb(p, bytes);
        return p;
    }
    /* 如果上面的 top chunk 没有足够的内存分配，那么考虑将 fast chunks 缓存的小块内存进行合并，
     *（在这里缓存的小内存块有可能前后都有比较大的空闲内存块，相互合并后，可能会合并出比较大的空闲空间。）
       看看是否能合并出足够的空间，提供分配。 */
    else if (have_fastchunks(av)) {
        malloc_consolidate(av);
        /* restore original bin index */
        if (in_smallbin_range(nb))
            idx = smallbin_index(nb);
        else
            idx = largebin_index(nb);
    }
    else {
        /* 经过上面两个步骤后，如果还是没有足够的内存，只有向内核申请内存。 */
        void* p = sysmalloc(nb, av);
        if (p != NULL && __builtin_expect(perturb_byte, 0))
            alloc_perturb(p, bytes);
        return p;
    }
    ...
}

#ifndef MORECORE
#define MORECORE sbrk
#endif

static void* sysmalloc(INTERNAL_SIZE_T nb, mstate av) {
    ...
    if (contiguous(av))
        size -= old_size;
    size = (size + pagemask) & ~pagemask;
    ...
    if (size > 0)
        brk = (char*)(MORECORE(size));
    ...
    /* Cannot merge with old top, so add its size back in */
    if (contiguous(av))
        size = (size + old_size + pagemask) & ~pagemask;
    ...
    /* finally, do the allocation */
    p = av->top;
    size = chunksize(p);

    /* 经过 sbrk 内存分配，top chunk 已经有足够的内存空间了，那么从它那里将 nb 大小的内存划分出去。 */
    if ((unsigned long)(size) >= (unsigned long)(nb + MINSIZE)) {
        remainder_size = size - nb;
        remainder = chunk_at_offset(p, nb);
        av->top = remainder;
        set_head(p, nb | PREV_INUSE | (av != &main_arena ? NON_MAIN_ARENA : 0));
        set_head(remainder, remainder_size | PREV_INUSE);
        check_malloced_chunk(av, p, nb);
        return chunk2mem(p);
    }
    ...
}
```

* 释放内存。

```c
#ifndef DEFAULT_MXFAST
#define DEFAULT_MXFAST (64 * SIZE_SZ / 4)
#endif

#define FASTBIN_CONSOLIDATION_THRESHOLD (65536UL)

static void _int_free(mstate av, mchunkptr p, int have_lock) {
    ...
    /* 小内存块有可能被缓存起来，例如 std::list 32 个字节的节点。 */
    if ((unsigned long)(size) <= (unsigned long)(get_max_fast()) /* DEFAULT_MXFAST */
#if TRIM_FASTBINS
        /*
            If TRIM_FASTBINS set, don't place chunks
            bordering top into fastbins
       */
        && (chunk_at_offset(p, size) != av->top)
#endif
    ) {
        /* 小内存块缓存到 fastbin. */
        ...
    }
    ...
    else if (!chunk_is_mmapped(p)) {
        /* free 掉的内存，可能很大，也可能因为前后有空闲块，合并成一个大空闲块，
         * top chunk 也可能达到释放的阈值，尝试收缩返还系统。 */
        if ((unsigned long)(size) >= FASTBIN_CONSOLIDATION_THRESHOLD) {
            if (have_fastchunks(av))
                malloc_consolidate(av);

            if (av == &main_arena) {
#ifndef MORECORE_CANNOT_TRIM
                if ((unsigned long)(chunksize(av->top)) >= (unsigned long)(mp_.trim_threshold))
                    systrim(mp_.top_pad, av);
#endif
            }
            ...
        }
        ...
    }
}

#ifndef MORECORE
#define MORECORE sbrk
#endif

static int systrim(size_t pad, mstate av) {
    ...
    pagesz = GLRO(dl_pagesize);
    top_size = chunksize(av->top);

    /* 释放 top chunk 这个块超出阈值那部分（以页为单位）。 */
    extra = (top_size - pad - MINSIZE - 1) & ~(pagesz - 1);

    if (extra > 0) {
        current_brk = (char*)(MORECORE(0));
        if (current_brk == (char*)(av->top) + top_size) {
            /* 以页为单位回收 top chunk 多出来的内存。 */
            MORECORE(-extra);
            ...
        }
    }
    ...
}
```

* 回收空闲内存。整理合并 fast bins 缓存的小内存块；或者回收达到一定数值的空闲内存块，通过 `__madvise` 告诉系统这些内存虽然不能从虚拟内存清除，但是可以先将其从物理内存清除，减少物理内存的使用，当虚拟内存使用到时，再通过缺页中断方式重新加载。

```c
/*
  ------------------------------ malloc_trim ------------------------------
*/
static int mtrim(mstate av, size_t pad) {
    /* 整理合并 fastbin 缓存的空闲小内存块。 */
    malloc_consolidate(av);

    const size_t ps = GLRO(dl_pagesize);
    int psindex = bin_index(ps);
    const size_t psm1 = ps - 1;

    int result = 0;
    for (int i = 1; i < NBINS; ++i)
        if (i == 1 || i >= psindex) {
            mbinptr bin = bin_at(av, i);

            for (mchunkptr p = last(bin); p != bin; p = p->bk) {
                INTERNAL_SIZE_T size = chunksize(p);

                if (size > psm1 + sizeof(struct malloc_chunk)) {
                    /* See whether the chunk contains at least one unused page.  */
                    char* paligned_mem = (char*)(((uintptr_t)p + sizeof(struct malloc_chunk) + psm1) & ~psm1);

                    assert((char*)chunk2mem(p) + 4 * SIZE_SZ <= paligned_mem);
                    assert((char*)p + size > paligned_mem);

                    /* This is the size we could potentially free.  */
                    size -= paligned_mem - (char*)p;

                    if (size > psm1) {
#ifdef MALLOC_DEBUG
                        /* When debugging we simulate destroying the memory content.  */
                        memset(paligned_mem, 0x89, size & ~psm1);
#endif
                        /* 回收达到一定数值的空闲内存块，将其从物理内存清除。 */
                        __madvise(paligned_mem, size & ~psm1, MADV_DONTNEED);

                        result = 1;
                    }
                }
            }
        }

#ifndef MORECORE_CANNOT_TRIM
    return result | (av == &main_arena ? systrim(pad, av) : 0);
#else
    return result;
#endif
}

static void malloc_consolidate(mstate av) {
    ...
    if (get_max_fast() != 0) {
        clear_fastchunks(av);
        unsorted_bin = unsorted_chunks(av);
        maxfb = &fastbin(av, NFASTBINS - 1);
        fb = &fastbin(av, 0);
        do {
            p = atomic_exchange_acq(fb, 0);
            if (p != 0) {
                do {
                    ...
                    if (nextchunk != av->top) {
                        ...
                    } else {
                        /* top chunk 有可能会因为空闲小内存的回收合并而增加，超过返还系统的阈值。 */
                        size += nextsize;
                        set_head(p, size | PREV_INUSE);
                        av->top = p;
                    }

                } while ((p = nextp) != 0);
            }
        } while (fb++ != maxfb);
    }
    ...
}
```

---

## 4. 解决方案

* 避免内存泄漏。malloc/new 出来的内存，一定要 free/delete 掉。
* 避免分阶段分配内存，后面分配的内存，长期驻留在程序不释放。
* 可以考虑定时执行 malloc_trim(0) 强制回收整理 fast bins 小空闲内存块，释放物理内存。
* 考虑使用 jemalloc 和 tcmalloc 替换 ptmalloc。

---

## 5. 参考

* [深入理解 malloc](https://hanfeng.ink/post/understand_glibc_malloc/)
* [Glibc内存管理-ptmalloc2](https://www.cnblogs.com/mysky007/p/12349508.html)
* [glibc内存管理ptmalloc源代码分析.pdf](https://paper.seebug.org/papers/Archive/refs/heap/glibc%E5%86%85%E5%AD%98%E7%AE%A1%E7%90%86ptmalloc%E6%BA%90%E4%BB%A3%E7%A0%81%E5%88%86%E6%9E%90.pdf)
* [PART 1: UNDERSTANDING THE GLIBC HEAP IMPLEMENTATION（链接需要翻墙）](https://azeria-labs.com/heap-exploitation-part-1-understanding-the-glibc-heap-implementation/)
* [PART 2: UNDERSTANDING THE GLIBC HEAP IMPLEMENTATION（链接需要翻墙）](https://azeria-labs.com/heap-exploitation-part-2-glibc-heap-free-bins/)
* [一次"内存泄漏"引发的血案](https://www.jianshu.com/p/38a4bcf564d5)
* [有感于STL的内存管理](https://www.cnblogs.com/skiwnchiwns/p/10345191.html)
* [malloc(3) — Linux manual page（链接需要翻墙）](https://man7.org/linux/man-pages/man3/malloc.3.html)
* [download glibc code](https://ftp.gnu.org/pub/gnu/glibc/)
* [centos7 安装debuginfo调试glibc源码](https://blog.51cto.com/happytree007/2148988)
* [malloc_trim(3) — Linux manual page](https://man7.org/linux/man-pages/man3/malloc_trim.3.html)
* [CentOS 安装 debuginfo-install](https://www.cnblogs.com/john-h/p/6113567.html)
* [linux内存管理概论（二）](http://lizengkun.cn/%E6%93%8D%E4%BD%9C%E7%B3%BB%E7%BB%9F/memory-management/)
* [十问 Linux 虚拟内存管理 ( 一 )](https://cloud.tencent.com/developer/article/1004428)
* [十问 Linux 虚拟内存管理 ( 二 )](https://cloud.tencent.com/developer/article/1004429)