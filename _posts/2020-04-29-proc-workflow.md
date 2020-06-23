---
layout: post
title:  "程序工作流程（Linux）"
categories: Linux
tags: system Linux
author: wenfh2020
---

程序的工作流程：高级语言 -> 编译器 -> 低级语言指令 -> 系统管理运行程序 <---> 硬件。



* content
{:toc}

## 1. 进程虚拟内存

进程不允许直接访问物理内存，系统通过虚拟内存方式管理进程内存。

![进程地址空间](/images/2020-02-20-14-22-08.png){: data-action="zoom"}

> 图片来源 《深入理解计算机系统》8.2.3 私有地址空间

---

## 2. 工作流程

高级语言 -> 编译器 -> 低级语言指令 -> 系统加载运行

* 程序编译执行流程。

![编译流程](/images/2020-04-28-12-54-46.png){: data-action="zoom" }

* 程序启动退出流程。

![程序启动退出流程](/images/2020-04-29-10-38-48.png){:data-action="zoom"}

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

* 程序运行流程。

![程序运行流程](/images/2020-04-29-11-39-52.png){:data-action="zoom"}

---

## 3. 参考

* 《深入理解计算机系统》
* 《UNIX 环境高级编程》

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/2020/04/29/proc-workflow/)
