---
layout: post
title:  "[kimserver] zookeeper-client-c 接入流程思考"
categories: kimserver zookeeper
tags: kimserver zookeeper client thinking
author: wenfh2020
---

[kimserver](https://github.com/wenfh2020/kimserver) 是多进程异步框架，而 [zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c) 工作模式是多线程，本章整理一下将它们整合的思考过程。




* content
{:toc}

---

## 1. what

先阅读 [zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c) 源码，查看它的工作方式。

![zookeeper-client-c 工作流程](/images/2020/2020-10-18-21-59-50.png){:data-action="zoom"}

---

## 2. how

* 异步。

![异步使用流程](/images/2020/2020-11-08-12-25-55.png){:data-action="zoom"}

* 同步。

![同步使用流程](/images/2020/2020-11-08-12-27-27.png){:data-action="zoom"}

---

## 3. why

[zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c) 无论同步方式还是异步，都是通过多线程实现的。同步方式多好啊，很多逻辑不需要通过回调被打散。

* 新建一个线程跑同步接口，处理结果放到任务完成队列。
* [zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c) 通知被写进任务完成队列。
* 主线程消费任务完成队列。

![接入方案](/images/2020/2020-11-08-12-28-20.png){:data-action="zoom"}

---

## 4. 小结

从上面几个图，思路从复杂到简单，直到逻辑碎片被串联起来，这样多线程的 lib 添加进来后，不会破坏 [kimserver](https://github.com/wenfh2020/kimserver) 异步服务原来的逻辑。

---

## 5. 参考

* [zookeeper-client-c 异步/同步工作方式](https://wenfh2020.com/2020/10/17/zookeeper-c-client/)