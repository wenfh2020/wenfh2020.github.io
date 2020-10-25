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

客户端与服务集群通信流程。

---

### 1.1. 总流程

1. client 连接接入服务（gate），然后给 gate 发送 request。
2. gate 接收到 client 发送的 request，它不处理，它转发给后面的逻辑服务（logic）处理。
3. logic 处理 gate 发送的 request，给 gate 回复处理结果 ack。
4. gate 收到 logic 的 ack 然后给 client 回复。

> 服务集群通过 zookeeper（后面简称 zk）管理，所以节点可以通过 zk 发现其它节点。

![分布式系统节点通信总流程](/images/2020-10-24-10-57-14.png){:data-action="zoom"}

---

### 1.2. 详细通信流程

1. 通过域名解析获取离 client 最近的服务 ip。
2. nginx 做服务集群 proxy。
3. nginx 根据负载均衡策略，接入到某个 gate 服务节点。
4. gate 主进程将接入连接分派给合适的子进程（详细请参考 [《[kimserver] 父子进程传输文件描述符》](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)）。
5. gate workerA 收到 client 发送的数据，它不处理，转发给 logic（gate 是如何知道 logic 节点的？前面说了通过 zk 进行节点发现）。
6. gate 与 logic 建立连接，这里又回到了步骤 4。
7. gate 子进程能成功接入 logic 的某个子进程。

---

![分布式系统节点通信详细流程](/images/2020-10-25-09-40-12.png){:data-action="zoom"}

---

> 🔥 文章来源：[《[kimserver] 分布式系统-多进程框架节点通信》](https://wenfh2020.com/2020/10/23/kimserver-node-contact/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
