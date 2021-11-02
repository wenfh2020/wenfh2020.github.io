---
layout: post
title:  "探索惊群 ①"
categories: network
tags: thundering herd
author: wenfh2020
---

惊群比较抽象，类似于抢红包 😁。它多出现在高性能的多进程/多线程服务中，例如：nginx。

`探索惊群` 系列文章将深入 Linux (5.0.1) 内核，透过 `多进程模型` 去剖析惊群现象、惊群原理、惊群的解决方案。

1. [探索惊群 ①](https://wenfh2020.com/2021/09/25/thundering-herd/)
2. [探索惊群 ② - accept](https://wenfh2020.com/2021/09/27/thundering-herd-accept/)
3. [探索惊群 ③ - nginx 惊群现象](https://wenfh2020.com/2021/09/29/nginx-thundering-herd/)
4. [探索惊群 ④ - nginx - accept_mutex](https://wenfh2020.com/2021/10/10/nginx-thundering-herd-accept-mutex/)
5. [探索惊群 ⑤ - nginx - NGX_EXCLUSIVE_EVENT](https://wenfh2020.com/2021/10/11/thundering-herd-nginx-epollexclusive/)
6. [探索惊群 ⑥ - nginx - reuseport](https://wenfh2020.com/2021/10/12/thundering-herd-tcp-reuseport/)
7. [探索惊群 ⑦ - 文件描述符透传](https://wenfh2020.com/2021/10/13/thundering-herd-transfer-socket/)





* content
{:toc}

---

## 1. 概述

* 惊群现象：多进程正在睡眠等待 `共享` 资源，当资源到来时，多个进程同时被唤醒，争抢资源。

* 惊群影响：多进程被唤醒后争抢共享资源过程中，有的进程发现资源被前面的进程抢光了，自己做了无用功；也可能有的抢得多，有的抢得少，资源分配不均；既然是对公共资源的并发争抢，那也少不了锁的竞争消耗。

* 惊群原因：进程 `唤醒` 时机问题。

---

## 2. 惊群优缺点

### 2.1. 缺点

1. 部分进程被唤醒抢不到资源做了无用功。
2. 资源争抢，每个进程可能抢到的资源不一样，——资源分配不均。
3. 无效的进程上下文切换，增加了系统开销。
4. 内核通过锁保护共享资源的读写安全，如果进程过多，锁竞争会导致进程的 CPU 使用率低。

---

### 2.2. 优点

我们不能因为惊群的缺点而否定它存在的价值。

因为几十年前，海量用户的高并发场景并不常见，同时计算机的空间也不是无限的，所以当资源到来时，系统自然而然地希望进程能快速地将已经到来的资源处理掉，从而腾出空间给新的资源。

而惊群，让等待资源的多个进程同时唤醒工作那是 `最简单直接快速` 的做法，虽然多个进程争抢资源，消耗了一定的性能。

---

## 3. 解决方案

怎么解决呢？这需要围绕两个方面去展开。

1. 避免共享资源争抢。
2. 资源尽量合理分配。

---

我们换个角度去思考，如果红包私发，而不是扔进群组里，那别人还废什么劲去抢？！这个思路就是解决惊群问题的关键：`不抢`！—— 同一时段，只有一个进程有权限获取共享资源。

---

## 4. 测试

### 4.1. 环境

| cpu 核心 | 内存  |                                系统                                | nginx 版本 | nginx 子进程个数 |
| :------: | :---: | :----------------------------------------------------------------: | :--------: | :--------------: |
|    4     |  4g   | ubuntu-20.04.3-desktop-amd64<br/>(Linux version 5.11.0-37-generic) |   1.20.1   |        4         |

---

### 4.2. 性能

压测 nginx 各种惊群解决方案的性能。

* 速度。

| <font color=red>clients</font> | ngx-no | ngx-accept_mutex | ngx-reuseport | ngx-NGX_EXCLUSIVE_EVENT |
| :----------------------------: | :----: | :--------------: | :-----------: | :---------------------: |
|              1000              | 0.10 s |      0.08 s      |    0.11 s     |                         |
|              3000              | 0.20 s |      1.13 s      |    0.17 s     |                         |
|              5000              | 0.30 s |      1.15 s      |    0.24 s     |                         |
|              8000              | 0.39 s |      1.22 s      |    0.30 s     |                         |
|             10000              | 0.48 s |      1.19 s      |    0.38 s     |                         |
|             15000              | 0.66 s |      1.29 s      |    0.53 s     |
|             20000              | 0.85 s |      3.28 s      |    0.71 s     |
|             25000              | 1.30 s |      3.30 s      |    0.86 s     |                         |

* 能耗。

| <font color=red>clients</font> | ngx-no | ngx-accept_mutex | ngx-reuseport | ngx-NGX_EXCLUSIVE_EVENT |
| :----------------------------: | :----: | :--------------: | :-----------: | :---------------------: |
|                                |        |                  |               |                         |

---

### 4.3. 测试客户端

用 golang 协程实现了并发链接的小工具。

```go
/* ./main --cnt 1000 */

package main

import (
    "flag"
    "fmt"
    "net"
    "sync"
    "sync/atomic"
    "time"
)

const (
    timeFmt = "2006-01-02 15:04:05.000"
    connCnt = 1000
)

var cnt int
var failed int32
var wait sync.WaitGroup

func main() {
    flag.IntVar(&cnt, "cnt", connCnt, "connect count")
    flag.Parse()

    wait.Add(cnt)

    begin := time.Now()
    fmt.Println("---\nbegin time:", begin.Format(timeFmt))

    for i := 0; i < cnt; i++ {
        go func(index int) {
            addr, _ := net.ResolveTCPAddr("tcp", "127.0.0.1:80")
            c, err := net.DialTCP("tcp", nil, addr)
            if err != nil {
                atomic.AddInt32(&failed, 1)
                fmt.Printf("%d, connect failed!, err: %v\n", index, err)
            } else {
                // fmt.Printf("%d, connect ok!\n", index)
                defer c.Close()
            }
            wait.Done()
        }(i)
    }

    wait.Wait()

    end := time.Now().Format(timeFmt)
    spend := time.Now().Sub(begin).Seconds()
    fmt.Println("end time:", end)
    fmt.Printf("cnt: %d, failed: %d, spend: %v\n", cnt, failed, spend)
}
```

---

## 参考

* [Nginx惊群效应引起的系统高负载](https://zhuanlan.zhihu.com/p/401910162)
