---
layout: post
title:  "stl + glibc 内存泄漏"
categories: c/c++
tags: timer map stl
author: wenfh2020
---

最近压力测试一个项目，top 发现某进程内存一直占用着不释放，折腾了很久才定位到 glibc 内部内存泄漏。

水平有限，不知道深层原因，解决方案，定时执行 malloc_trim(0) 强制释放空闲空间。





* content
{:toc}

---

## 1. 测试实例

写了个测试实例，在 Centos 系统测试，进程一直不释放内存。

测试源码，用了 std::list 数据结构，如果不使用 stl，用数组就没有这问题，真的见鬼了，简简单单的几行源码。

最后如何定位到 glibc 内部泄漏呢？测试程序换 jemalloc 内存池就没有出现这个问题，所以基本可以确认出问题的位置。

<div align=center><img src="/images/2021-04-08-16-40-23.png" data-action="zoom"/></div>


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

## 2. valgrind

用 valgrind 检查不出问题出在哪。std::list 内部应该有内存池数据没有释放，但是也只占用了一点内存 `480,000 bytes`。

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

## 3. 解决方案

定时执行 malloc_trim(0) 强制释放空闲空间。Centos 用户层向内核申请空间，默认通过 glibc，glibc 有内存池，避免频繁访问内核，消耗资源。

深层原因：参考帖子： [一次"内存泄漏"引发的血案](https://www.jianshu.com/p/38a4bcf564d5)

---

## 4. 参考

* [一次"内存泄漏"引发的血案](https://www.jianshu.com/p/38a4bcf564d5)