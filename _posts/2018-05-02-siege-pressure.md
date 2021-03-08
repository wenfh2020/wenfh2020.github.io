---
layout: post
title:  "Siege HTTP 压力测试"
categories: 工具
tags: siege pressure
author: wenfh2020
---

siege 是一个轻量级的压力测试工具，http 测试方便实用。



* content
{:toc}

---

## 1. 概述

压测是服务开发中十分重要的一环，需要测试服务在高并发环境下，功能的稳定性以及性能瓶颈，并根据测试结果输出详细的测试数据，有针对性地对服务进行优化。

---

## 2. 测试机器

| 选项     | 描述                                                                                                       |
| :------- | :--------------------------------------------------------------------------------------------------------- |
| **系统** | CentOS release 6.5 (Final)                                                                                 |
| **CPU**  | model name   : Intel(R) Pentium(R) CPU G2030 @ 3.00GHz <br/> processor       : 1 <br/> cpu cores       : 2 |
| **系统** | MemTotal:      3624428 kB                                                                                  |

---

## 3. Siege

### 3.1. 安装

通过 `yum install siege` 命令可以安装默认版本；或者下载对应版本安装。

```shell
wget http://download.joedog.org/siege/siege-4.0.4.tar.gz
tar -zxvf siege-4.0.4.tar.gz
cd siege-4.0.4/
./configure
make
make install
```

---

#### 3.1.1. 命令参数

* 详细参数查询。

```shell
man siege
```

* 具体参数使用事例。

```shell
siege  -c 并发用户数 -r 循环次数 --header "http协议头设置" '请求链接'
```

---

#### 3.1.2. 配置

配置默认路径在 `~/.siege/siege.conf`。

| 配置项     | 描述                                                                                                                                                                               |
| :--------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| limit      | 测试线程限制。默认是 255，最高可以设置 1000 个或者更多，一般一个线程对应一个模拟用户，线程越多，越耗资源，所以根据自己的需要设置限制和设置测试用户数量。否则很容易将系统资源跑满。 |
| connection | 长短链接设置。长链接（connection = keep-alive），短链接（connection = close）。                                                                                                    |
| benchmark  | 是否延迟发送。要测试最大限度的服务并发，可以打开此项。                                                                                                                             |

---

### 3.2. 测试方法

测试 50000 个数据包，500 个用户每个用户发送 100 个测试包。

header 头填充 Cookie 的相关信息，token 和 userid。

操作方法：POST

协议：url: http://192.168.1.1:1111/xxx/im/relation/user/friend/check

协议包体：./friend_check.json

```shell
siege -c 500 -r 100 --header "Cookie:token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyaWQjIsImV4cCI6MTU1MjE4MTAzMH0.Cz8MN2kREkueZC4tAwGw_r0qv7b0oRgli8mYOozXHG8;userid=2" 'http://192.168.1.1:1111/xxx/im/relation/user/friend/check POST < ./friend_check.json'
```

---

### 3.3. 测试结果

siege 命令测试结果。

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

---

### 3.4. 系统负载

压力测试过程中系统负载情况。

![系统负载](/images/2020-03-11-08-23-10.png){: data-action="zoom"}

---

## 4. 多协议测试组合

```shell
./http_pressure.sh
```

* http_pressure.sh

```shell
#!/bin/sh
siege -c 200 -r 200 -f ./urls.txt
```

* urls.txt

```shell
http://127.0.0.1:3355/kim/helloworld/ POST {"uid":"hello world"}
http://127.0.0.1:3355/kim/test_cmd/ POST {"test":"test_cmd"}
http://127.0.0.1:3355/kim/test_redis/ POST {"key": "key123", "value": "hello_world"}
```
