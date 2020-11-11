---
layout: post
title:  "[kimserver] 分布式系统-多进程框架节点通信"
categories: kimserver
tags: kimserver nodes contact
author: wenfh2020
---

[kimserver](https://github.com/wenfh2020/kimserver) 是多进程框架，在分布式系统里，多进程节点之间是如何进行通信的，客户端与分布式服务集群的通信流程是怎么样的，本章主要讲解这些问题。




* content
{:toc}

---

## 1. 流程

### 1.1. 客户端与服务通信

![client 与 server 通信流程](/images/2020-11-10-10-41-39.png){:data-action="zoom"}

---

### 1.2. 服务节点通信

A 节点与 B 节点数据透传 --> A1 与 B1 子进程建立通信。

* A1 创建 socket fd。
* A1 连接 B 节点 ip / port -->  A1 连接 B0。
* A1 connect 异步返回结果，触发读写事件。
* A1 与 B0 连接成功，A1 发送连接信息（type / ip / port / index）给 B0。
* B0 接收到 A1 发的数据，将 fd 透传给对应的子进程 B1，A1 与 B1 连接成功。（[《[kimserver] 父子进程传输文件描述符》](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)
* B1 将自己的 type / ip / port / index 信息回传给 A1。
* A1 收到 B1 回包，将 B1 的 fd 保存起来。
* A1 与 B1 的通道被打通，执行转发的业务包。

![分布式系统节点通信详细流程](/images/2020-11-10-10-29-50.png){:data-action="zoom"}

---

> 🔥 文章来源：[《[kimserver] 分布式系统-多进程框架节点通信》](https://wenfh2020.com/2020/10/23/kimserver-node-contact/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
