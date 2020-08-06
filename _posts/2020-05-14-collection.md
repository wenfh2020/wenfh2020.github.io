---
layout: post
title:  "Collection"
categories: 技术
tags: collection
author: wenfh2020
--- 

常用知识整理和收藏，方便查阅。



* content
{:toc}

---

**图难于其易，为大于其细，天下难事，必作于易，天下大事，必作于细。** -- 《道德经》

## 1. 常用查询

| 选项     | 链接                                                                                                                                                                                                                                                            |
| :------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Redis    | [Redis 官网](https://redis.io/)<br/>[Redis 中文官方网站](http://www.redis.cn/)<br/>[Redis 教程](https://www.runoob.com/redis/redis-tutorial.html) <br/>[Redis 作者博客](http://antirez.com/) <br/> [Redis 源码](https://github.com/antirez/redis/tree/unstable) |
| C/C++    | [C 语言教程](https://www.runoob.com/cprogramming/c-tutorial.html) <br/> [C++ 官网](http://www.cplusplus.com/) <br/> [C++ 参考手册](https://zh.cppreference.com/)                                                                                                |
| Linux    | [Linux 命令大全](https://www.runoob.com/linux/linux-command-manual.html)<br/>[Linux 内核源码分析](https://www.cnblogs.com/tolimit/default.html?page=1)<br/>[Linux man pages online](http://man7.org/linux/man-pages/)                                           |
| Go       | [Golang 官网](https://golang.google.cn/)                                                                                                                                                                                                                        |
| asm      | [汇编常用指令](https://blog.csdn.net/qq_36982160/article/details/82950848)                                                                                                                                                                                      |
| shell    | [Shell 教程 \| 菜鸟教程](https://www.runoob.com/linux/linux-shell.html)                                                                                                                                                                                         |
| html/css | [HTML 教程](http://caibaojian.com/w3c/html/)<br/>[CSS 教程](http://caibaojian.com/w3c/css/)                                                                                                                                                                     |

---

## 2. 常看博客

* [云风的 BLOG](https://blog.codingnow.com/)
* [峰云就她了](http://xiaorui.cc/)

---

## 3. 书籍

| 类型     | 名称                                                                                                                                                                  |
| :------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C/C++    | 《C++ Primer》 <br/>《Effect C++》 <br/>《More Effect++》<br/>《STL 源码剖析》<br/>《跟我一起学 Makefile》                                                            |
| Go       | 《go 语言编程》                                                                                                                                                       |
| Python   | 《The Django Book 2.0 中文译本》                                                                                                                                      |
| Linux    | 《深入理解计算机系统》<br/>《UNIX环境高级编程》<br/>《鸟哥的 Linux 私房菜》系列 <br/>《程序员的自我修养》<br/>《跟老男孩学 Linux 运维》<br/> 《Linux 内核设计与实现》 |
| Network  | 《Linux 高性能服务器编程》     <br/> 《TCP/IP 详解》系列                                                                                                              |
| DataBase | 《Redis 设计与实现》<br/> 《MySQL性能调优与架构设计》                                                                                                                 |
| 算法     | 《算法导论》                                                                                                                                                          |
| 面试     | 《剑指offer》                                                                                                                                                         |

---

## 4. 收藏

| 类型  | 链接                                                                                                                                                                                                                                                                                                                                                                                                            |
| :---- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 系统  | [「图文结合」Linux 进程、线程、文件描述符的底层原理](https://www.solves.com.cn/news/hlw/2020-03-15/13907.html) <br/> [Linux slab 分配器剖析](https://www.ibm.com/developerworks/cn/linux/l-linux-slab-allocator/index.html) <br/> [用户空间_内核空间以及内存映射](https://www.solves.com.cn/news/hlw/2020-03-15/13907.html) <br/> [Linux进程调度器-进程切换](https://www.cnblogs.com/LoyenWang/p/12386281.html) |
| c/c++ | [STL 源码剖析](https://www.kancloud.cn/digest/stl-sources/) <br/> [我在项目中经常使用的c++11新特性](https://zhuanlan.zhihu.com/p/102419965?utm_source=qq)                                                                                                                                                                                                                                                       |
| redis | [redis-stat](https://github.com/junegunn/redis-stat)                                                                                                                                                                                                                                                                                                                                                            |
| 管理  | [UML类图与类的关系详解](http://www.uml.org.cn/oobject/201104212.asp)                                                                                                                                                                                                                                                                                                                                            |
| ebook | [book1](https://evanli.github.io/programming-book/Git/) <br/> [book2](https://github.com/wenfh2020/books) <br/> [book3](https://github.com/hello2dj/Books-1)   <br/> [book4](https://github.com/yuebaii/books)     <br/> [book5](https://github.com/lancetw/ebook-1)                                                                                                                                            |
| 素材  | [iconarchive](http://www.iconarchive.com/) <br/> [download video from url](https://en.savefrom.net/11/)                                                                                                                                                                                                                                                                                                         |

---

## 5. 开源

| 类型   | 项目                                                                                               |
| :----- | :------------------------------------------------------------------------------------------------- |
| c/c++  | [libev](http://software.schmorp.de/pkg/libev.html) <br/> [redis](https://github.com/antirez/redis) |
| golang | [codis](https://github.com/CodisLabs/codis) <br/> [kingshard](https://github.com/flike/kingshard)  |

---

## 6. 源码走读方法

* 了解需求文档。
* 应用并熟悉工作流程。
* 走读源码，理解核心数据结构，接口。
  > 逻辑复杂的源码，采用减法，独立抽取核心源码到一个文件，将其逻辑关联起来。
* 通过 uml 抽象出业务对象，建立彼此的时序关系，走通流程。
* 验证逻辑结果。
* 输出总结，落地文档。

---

## 7. 其它

* [github + jekyll 博客](https://github.com/Gaohaoyang/gaohaoyang.github.io)
  [本博客](https://wenfh2020.com/2020/02/17/make-blog/)主要采用这个模版搭建。搭建框架，请参考[这个文档](https://github.com/wonderseen/wonderseen.github.io)的搭建流程。
* [The GNU C Library (glibc)](https://www.gnu.org/software/libc/)

---

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/2020/05/14/collection/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
