---
layout: post
title:  "Siege HTTP 压力测试"
categories: 网络
tags: siege 压力测试
author: wenfh2020
---

siege 是一个轻量级的压力测试工具，http 测试方便实用。



* content
{:toc}

---

## 概述

压力测试是服务开发中十分重要的一环，需要测试服务在高并发的环境下功能的稳定性以及性能的瓶颈，根据测试结果输出详细的测试数据，有针对性地对服务进行优化。

## 测试机器

| 选项     | 描述                                                                                                       |
| :------- | :--------------------------------------------------------------------------------------------------------- |
| **系统** | CentOS release 6.5 (Final)                                                                                 |
| **CPU**  | model name   : Intel(R) Pentium(R) CPU G2030 @ 3.00GHz <br/> processor       : 1 <br/> cpu cores       : 2 |
| **系统** | MemTotal:      3624428 kB                                                                                  |

---

## Siege

它是一款开源的压力测试工具，设计用于评估WEB应用在压力下的承受能力。可以根据配置对一个WEB站点进行多用户的并发访问，记录每个用户所有请求过程的相应时间，并在一定数量的并发访问下重复进行。

---

### 安装

通过 yum install siege 命令可以安装，但是一般会根据系统源进行下载，下载的版本比较低，建议根据下列操作步骤安装最新版本。

```shell
wget http://download.joedog.org/siege/siege-4.0.4.tar.gz
tar -zxvf siege-4.0.4.tar.gz
cd siege-4.0.4/
./configure
make
make install
```

---

### 命令参数

```shell
siege  -c 并发用户数 -r 循环次数 --header "http协议头设置"  '请求链接'
```

> 【注意】根据机器的情况，siege一般并发的用户数，默认是 255，最高可以设置 1000 个或者更多（需要修改配置limit限制，vim /root/.siege/siege.conf，siege 工具每个用户会启用一个线程比较耗性能，所以根据实际情况设置用户数量），因为 HTTP 是短连接，机器端口号是 0 - 65535，并发数太高，siege很容易会把本地的端口耗尽。

---

### 测试方法

测试 50000 个数据包，500 个用户每个用户发送 100 个测试包。

header 头填充 Cookie 的相关信息，token 和 userid。

操作方法：POST

协议：url: http://192.168.1.1:1111/xxx/im/relation/user/friend/check

协议包体：./friend_check.json

```shell
siege -c 500 -r 100 --header "Cookie:token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyaWQjIsImV4cCI6MTU1MjE4MTAzMH0.Cz8MN2kREkueZC4tAwGw_r0qv7b0oRgli8mYOozXHG8;userid=2" 'http://192.168.1.1:1111/xxx/im/relation/user/friend/check POST < ./friend_check.json'
```

---

### 测试结果

| 选项                    | 描述                 |
| :---------------------- | :------------------- |
| Transactions            | 已完成的事务总数     |
| Availability            | 完成的成功率         |
| Elapsed time            | 总共使用的时间       |
| Data transferred        | 响应中数据的总大小   |
| Response time           | 显示网络连接的速度   |
| Transaction rate        | 平均每秒完成的事务数 |
| Throughput              | 平均每秒传送的数据量 |
| Concurrency             | 实际最高并发链接数   |
| Successful transactions | 成功处理的次数       |
| Failed transactions     | 失败处理的次数       |
| Longest transaction     | 最长事务处理的时间   |
| Shortest transaction    | 最短事务处理时间     |

结果：

```shell
Transactions:                 500000 hits
Availability:                 100.00 %
Elapsed time:                 115.34 secs
Data transferred:              19.55 MB
Response time:                  0.20 secs
Transaction rate:            4335.01 trans/sec
Throughput:                     0.17 MB/sec
Concurrency:                  865.90
Successful transactions:      500000
Failed transactions:               0
Longest transaction:            3.03
Shortest transaction:           0.00
```

---

### 系统负载

压力测试过程中系统负载情况

![系统负载](/images/2020-03-11-08-23-10.png)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
