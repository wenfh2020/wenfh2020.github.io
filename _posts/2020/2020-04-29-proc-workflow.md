---
layout: post
title:  "程序工作流程（Linux）"
categories: system
tags: system Linux
author: wenfh2020
---

程序的工作流程：高级语言 -> 编译器 -> 低级语言指令 -> 系统管理运行程序 <---> 硬件。



* content
{:toc}

---

## 1. 程序工作流程

高级语言 -> 编译器 -> 低级语言指令 -> 系统加载运行

---

### 1.1. 编译加载

<div align=center><img src="/images/2021/2021-04-11-10-31-05.png" data-action="zoom"/></div>

---

### 1.2. 启动退出

![程序启动退出流程](/images/2020/2020-04-29-10-38-48.png){:data-action="zoom"}

> 图片来源： 《UNIX 环境高级编程》7.3.2 atexit函数

```c
// glibc - start.c
static void
start1 (ARG_DUMMIES argc, argp)
     DECL_DUMMIES
     int argc;
     char *argp;
{
  char **argv = &argp;

  /* The environment starts just after ARGV.  */
  __environ = &argv[argc + 1];

  /* If the first thing after ARGV is the arguments
     themselves, there is no environment.  */
  if ((char *) __environ == *argv)
    /* The environment is empty.  Make __environ
       point at ARGV[ARGC], which is NULL.  */
    --__environ;

  /* Do C library initializations.  */
  __libc_init (argc, argv, __environ);

  /* Call the user program.  */
  exit (main (argc, argv, __environ));
}
```

---

### 1.3. 运行时

![程序运行流程](/images/2020/2020-04-29-11-39-52.png){:data-action="zoom"}

<div align=center><img src="/images/2021/2021-09-25-12-57-23.png" data-action="zoom"/></div>

> 图片来源：《Linux Performance and Tuning Guidelines》

---

## 2. 进程虚拟内存

用户进程一般不允许直接访问物理内存，系统通过虚拟内存方式管理进程内存。

![进程地址空间](/images/2020/2020-02-20-14-22-08.png){: data-action="zoom"}

> 图片来源 《深入理解计算机系统》8.2.3 私有地址空间

<div align=center><img src="/images/2021/2021-04-10-11-10-30.png" data-action="zoom"/></div>

> 图片来源：《深入理解计算机系统》- 第九章 - 虚拟内存

---

## 3. 参考

* 《深入理解计算机系统》
* 《UNIX 环境高级编程》
* [linux下同一个进程的不同线程之间如何共享虚拟地址空间？](https://www.bilibili.com/video/BV1vz4y1C7vq)
* [【os浅尝】话说虚拟内存~](http://127.0.0.1:4000/2020/04/29/proc-workflow/)

