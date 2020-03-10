---
layout: post
title:  "静群效应理解"
categories: 网络
tags: 网络 惊群效应
author: wenfh2020
---

惊群效应理解：多个进程或者线程阻塞等待同一个事件，当事件到来，多线程或者多进程同时被唤醒，只有一个线程或进程获得资源。通俗点说：往鸡群里仍一颗稻谷，鸡群争抢，只有一个成功，其它失败。



* content
{:toc}

---

## 现象

火焰图观察 accept，或者用 strace 命令观察底层调用。可以用脚本获取对应进程的火焰图。

```shell
#!/bin/sh

if [ $# -lt 1 ]; then
    echo 'input pid'
    exit 1
fi

rm -f perf.*
perf record -F 99 -p $1 -g -- sleep 60
perf script -i perf.data &> perf.unfold
stackcollapse-perf.pl perf.unfold &> perf.folded
flamegraph.pl perf.folded > perf.svg
```

---

## 结果

线程或进程切换，内核需要保存上下文以及寄存器等资源，频繁切换会导致系统资源损耗。

---

## 解决方案

解决 epoll 的惊群问题：

1. 代码同步加锁（参考 nginx 源码）。
2. 设置 socket 属性 SO_REUSEPORT （Linux 系统内核层面解决，这个方案简单，参考 nginx 这个属性设置）

---

## 原理

当用 epoll 事件处理高并发事件模型时候，多个进程或线程 epoll_wait 会阻塞等待网络事件，当有新的 client connect 进来，epoll_wait 会同时被会唤醒争抢这个链接资源，然后调用 accept 处理，争抢资源失败的 accept 会返回 EAGAIN。

---

## 测试

[源码](https://github.com/wenfh2020/c_test/blob/master/network/thundering_herd/main.cpp) server 是 epoll 事件模型，client 用 telnet 即可。

---

## 参考

* [一个epoll惊群导致的性能问题](https://www.ichenfu.com/2017/05/03/proxy-epoll-thundering-herd/)
* [Linux惊群效应详解](https://blog.csdn.net/lyztyycode/article/details/78648798)
* [Linux 最新SO_REUSEPORT特性](https://www.cnblogs.com/Anker/p/7076537.html)

---

* 更精彩内容，请关注作者博客：[wenfh2020.com](https://wenfh2020.com/)
