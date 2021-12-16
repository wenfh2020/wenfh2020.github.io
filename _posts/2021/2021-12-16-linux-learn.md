---
layout: post
title:  "学习 linux 内核一阶段小结"
categories: kernel
tags: kernel linux learn
author: wenfh2020
---

做服务端多年，但是学习 linux 内核才一年多，深入研究源码后，解决了我之前的很多疑惑。

前段时间在回答知乎问题时，顺便做了个小结，现在把自己的回答整理了一下搬到这里。

**流程**：先熟练使用应用层接口 -> 看书看博客搞懂内核对应知识点的工作原理 -> 搭建内核调试环境 -> 画图将知识点串联起来。



* content
{:toc}

---

## 1. 熟悉原理

看源码前，先把原理搞懂。

1. 首先要熟悉应用层接口的使用，起码有了感性认识。
2. 查看 Linux 的经典书籍，一本书不可能面面俱到，有时候某一本某些章节讲得很好，某些章节就弱一点，所以经常几本一起看，尽量搞懂知识点原理。
3. 看一些大佬的博客，平时会经常看 [@小林coding](https://www.zhihu.com/people/lin-zhi-rong-8) [@张彦飞](https://www.zhihu.com/people/zhang-yan-fei-26-61) 的图解系列，图比较多，很多时候要比那些书本更通俗易懂，谢谢这些大佬哈~

---

## 2. 书籍

下面是我最近有在看的几本[书籍](https://wenfh2020.com/2021/05/07/my-books/)：

<div align=center><img src="/images/2021-12-16-19-33-56.png" data-action="zoom"/></div>

---

## 3. 搭建调试环境

好了，原理都理解得差不多了，再去看源码。

Linux 源码大部分都是 c 语言写的，函数指针满天飞，很多时候，你不知道这些指针都指向哪个具体函数，如果单纯找源码，你可能半天都不一定找到。接下来，我搭建了 Linux 的内核调试环境，下断点，一步一步调试，这样阅读源码又方便多了。（[demo](https://github.com/wenfh2020/kernel_test)）

<iframe class="bilibili" src="//player.bilibili.com/player.html?aid=592292865&bvid=BV1Sq4y1q7Gv&cid=461543929&page=1&high_quality=1" scrolling="no" border="0" frameborder="no" framespacing="0" allowfullscreen="true"> </iframe>

---

## 4. 画图

最后不要怕麻烦，画 uml 图，将源码的运行流程时序画出来，将知识点串联起来，这样思路就清晰多了。

<div align=center><img src="/images/2021-11-09-11-25-11.png" data-action="zoom"/></div>

> 图片来源：[tcp + epoll 内核睡眠唤醒工作流程](https://wenfh2020.com/2021/12/16/tcp-epoll-wakeup/)

<div align=center><img src="/images/2021-07-27-21-18-33.png" data-action="zoom"/></div>

> 图片来源：[linux 内核 listen (tcp/IPv4) 结构关系](https://processon.com/view/60fa6dfe7d9c083494e37a9a)
