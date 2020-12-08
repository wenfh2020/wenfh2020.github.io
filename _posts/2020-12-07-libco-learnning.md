---
layout: post
title:  "学习协程库-libco"
categories: 网络
tags: libco
author: wenfh2020
---

历史原因，一直使用 libev 作为服务底层；异步框架虽然性能比较高，但新人学习和使用门槛非常高，而且串行的逻辑被打散为状态机，这也会严重影响生产效率。

用同步方式实现异步功能，既保证了异步性能优势，又使得同步方式实现源码思路清晰，容易维护，这是协程的优势。带着这样的目的学习微信开源的一个轻量级网络协程库：[libco](https://github.com/Tencent/libco) 。




* content
{:toc}

---

## 1. 概述

关于协程的工作原理剖析，这两个帖子，说得挺好的：

* [微信开源C++协程库Libco—原理与应用](https://blog.didiyun.com/index.php/2018/11/23/libco/)
* [云风 coroutine 协程库源码分析](https://www.cyhone.com/articles/analysis-of-cloudwu-coroutine/)

---

## 2. Q & A

在学习协程的时候有几个问题，需要搞清楚：

* 几个概念：阻塞，非阻塞，同步，异步，锁。

* 协程是什么东西。
  > 协程是用户态里轻量级的线程，它是工程师根据程序运行原理，造的一个轮子。

* 协程解决了什么问题。
  > 用同步方式写代码，实现异步功能。

* 协程使用，需要上锁吗？
  > 协程本质上是单线程的串行功能，单线程是不需要锁的，多线程需要根据业务场景确定是否需要上锁。

* 协程实现原理。
  > 核心原理：在用户态，程序根据一定的逻辑，切换程序在系统运行的上下文。

* libco 主要有啥功能。
  > 协程模块，多路复用模块，hook 模块。

---

## 3. 源码布局

![源码对象](/images/2020-12-07-22-12-57.png){:data-action="zoom"}

---

## 4. 其它

待续。。。

---

## 5. 参考

* [云风 coroutine 协程库源码分析](https://www.cyhone.com/articles/analysis-of-cloudwu-coroutine/)
* [微信 libco 协程库源码分析](https://www.cyhone.com/articles/analysis-of-libco/)
* [C/C++协程库libco：微信怎样漂亮地完成异步化改造](https://blog.csdn.net/shixin_0125/article/details/78848561)
* [单机千万并发连接实战](https://zhuanlan.zhihu.com/p/21378825)
* [【腾讯Bugly干货分享】揭秘：微信是如何用libco支撑8亿用户的](https://segmentfault.com/a/1190000007407881)
* [简述 Libco 的 hook 层技术](https://blog.csdn.net/liushengxi_root/article/details/88421227)
* [动态链接黑魔法: Hook 系统函数](http://kaiyuan.me/2017/05/03/function_wrapper/)
* [协程](https://blog.csdn.net/liushengxi_root/category_8548171.html)
* [Linux进程-线程-协程上下文环境的切换与实现](https://zhuanlan.zhihu.com/p/254883122)
* [微信开源C++协程库Libco—原理与应用](https://blog.didiyun.com/index.php/2018/11/23/libco/)
