---
layout: post
title:  "[co_kimserver] co_kimserver 简介"
categories: co_kimserver libco
tags: libco
author: wenfh2020
---

[co_kimserver](https://github.com/wenfh2020/co_kimserver) 是基于 [libco](https://github.com/Tencent/libco) 的高性能 TCP 网络通信框架。

> 详细请查看：[github](https://github.com/wenfh2020/co_kimserver) 。




* content
{:toc}

---

## 1. 简述

`co_kimserver` 是高性能 TCP 网络通信框架。

* 多进程工作模式（manager/workers）。
* 基于腾讯开源的轻量级协程库 [libco](https://github.com/Tencent/libco)。
* 主要使用 C/C++11 语言开发。
* 支持 tcp 协议。
* 使用 protobuf 封装通信协议。
* 支持访问 mysql, redis (client: hiredis)。
* 通过 zookeeper 管理服务节点，支持分布式微服务部署。

---

## 2. 运行环境

项目支持 Linux 平台。源码依赖第三方库：

* mysqlclient
* protobuf3
* hiredis
* crypto++
* zookeeper_mt ([安装 zookeeper-client-c](https://wenfh2020.com/2020/10/17/zookeeper-c-client/))

>【注意】libco 不兼容 jemalloc / tcmalloc，出现死锁。

---

## 3. 架构

单节点多进程工作模式，支持多节点分布式部署。

### 3.1. 单节点

* manager 父进程：负责子进程管理调度，外部连接初始接入。
* worker 子进程：负责客户端详细连接逻辑。
* module 动态库：业务源码实现。(参考：[co_kimserver/src/modules/](https://github.com/wenfh2020/co_kimserver/tree/main/src/modules))

<div align=center><img src="/images/2021-03-25-16-54-06.png" data-action="zoom"/></div>

---

### 3.2. 多节点

服务节点通过 `zookeeper` 发现其它节点。（下图是客户端与服务端多节点建立通信流程。）

<div align=center><img src="/images/2021-03-25-16-54-26.png" data-action="zoom"/></div>

