---
layout: post
title:  "物联网数据通信 mqtt - mosquitto"
categories: golang
tags: mqtt mosquitto
author: wenfh2020
---

前段时间在跟进智慧农场项目，数据服务与硬件对接，需要用到 `mqtt` 解决方案 `mosquitto`。通过 golang 建立数据服务，获取硬件数据。



* content
{:toc}

---

## 1. 流程

* 硬件往 mqtt broker 指定 topic 上 pub 数据。
* 数据服务系统 订阅（sub）对应的 topic，接收数据。

---

* 硬件设备。

<div align=center><img src="/images/2021-01-07-09-31-49.png" data-action="zoom"/></div>

* 工作流程。

<div align=center><img src="/images/2020-11-08-11-31-48.png" data-action="zoom"/></div>

---

## 2. mosquitto

mosquitto 是一款实现了消息推送协议 MQTT v3.1 的开源消息代理软件，提供轻量级的，支持可发布/可订阅的消息推送模式，使设备对设备之间的短消息通信变得简单，比如现在应用广泛的低功耗传感器，手机、嵌入式计算机、微型控制器等移动设备。

> 上述 mosquitto 介绍文字来源 [百度百科](https://baike.baidu.com/item/mosquitto/3172080?fr=aladdin)。

---

### 2.1. 安装

```shell
# macos 安装
brew install mosquitto

# centos 安装
yum install mosquitto
```

---

### 2.2. 修改配置

```shell
# vim /usr/local/etc/mosquitto/mosquitto.conf

# 修改 mosquitto 服务 ip
bind_address 127.0.0.1

# 修改 mosquitto 服务端口。
port 1883
```

---

### 2.3. 运行

* MacOS

```shell
# 启动服务。
brew services start mosquitto

# 关闭服务。
brew services stop mosquitto
```

* Centos7

```shell
# 启动服务。
systemctl start mosquitto

# 关闭服务。
systemctl stop mosquitto
```

---

### 2.4. 测试

* 订阅 topic

```shell
mosquitto_sub -t news
```

* 发布 topic

```shell
mosquitto_pub -t news -m "hello"
```

---

## 3. 机器对外开放端口

* MacOS

```shell
# 打开防火墙设置。
# sudo vim /etc/pf.conf

# 添加开放端口。
pass in proto tcp from any to any port 1883

# 刷新端口设置。
sudo pfctl -f /etc/pf.conf
```

* Centos7

```shell
# 修改防火墙，添加开放端口。
vi /etc/sysconfig/iptables

# 添加开放的端口。
-A INPUT -m state --state NEW -m tcp -p tcp --dport 1883 -j ACCEPT

# 刷新防火墙设置。
systemctl restart iptables.service
```

---

## 4. golang 测试

通过 mosquitto client，订阅设备给 mosquitto 发布的数据。

### 4.1. 环境搭建

golang 运行环境在跑 mqtt client 以前已经成功搭建，现在搭建缺失的环节。

* 获取 client。

```shell
go get github.com/eclipse/paho.mqtt.golang
```

* 如果上面命令获取失败，可以修改配置，再操作。

```shell
export GO111MODULE=on
export GOPROXY=https://goproxy.io
```

* 如果 golang.org 文件夹下缺失文件，下载对应包。

```shell
git clone https://github.com/golang/tools.git
git clone -v  https://github.com/golang/net.git
```

---

### 4.2. 源码

硬件通过 msgpack 封装了协议。

> demo 借鉴了这个帖子 [《以mosquitto为服务, 用golang实现简单的mqtt发布和订阅》](https://blog.csdn.net/c_cppcoder/article/details/104520091)，谢谢！

```go
package main

import (
    "bytes"
    "fmt"
    "reflect"
    "time"

    MQTT "github.com/eclipse/paho.mqtt.golang"
    "github.com/vmihailenco/msgpack"
)

var (
    /* 发布和订阅的 topic。 */
    mqttTopic   = "news"
    /* mqtt 服务 ip 和 端口。 */
    mqttHostURL = "tcp://127.0.0.1:1883"
)

/* 订阅数据回调 */
func subCallBackFunc(c MQTT.Client, msg MQTT.Message) {
    if !c.IsConnected() {
        return
    }

    /* 硬件通过 msgpack 封包，解析 msgpack。 */
    var out map[string]interface{}
    err := msgpack.Unmarshal(msg.Payload(), &out)
    if err != nil {
        panic(err)
    }

    fmt.Println("mqtt topic: ", msg.Topic())
    fmt.Printf("version: [%v], msg id: [%v], time: [%v], ip: [%v], mac[%v]\n",
        out["v"], out["mid"], out["time"], out["ip"], out["mac"])
    ...
}

/* client 连接 mqtt broker。 */
func connMQTT(broker, user, passwd string) (bool, MQTT.Client) {
    opts := MQTT.NewClientOptions()
    opts.AddBroker(broker)
    opts.SetUsername(user)
    opts.SetPassword(passwd)

    mc := MQTT.NewClient(opts)
    if token := mc.Connect(); token.Wait() && token.Error() != nil {
        return false, mc
    }

    return true, mc
}

/* 订阅。 */
func subscribe() {
    ok, mc := connMQTT(mqttHostURL, "", "")
    if !ok {
        fmt.Println("sub mqtt failed!")
        return
    }
    /* 订阅对应的 topic 信息。 */
    mc.Subscribe(mqttTopic, 0x00, subCallBackFunc)
}

func main() {
    subscribe()
    for {
        time.Sleep(time.Second)
    }
}
```

---

## 5. 参考

* [go get 指令没有反应/出错/超时](https://blog.csdn.net/ELiGwz/article/details/101783339)
* [以mosquitto为服务, 用golang实现简单的mqtt发布和订阅](https://blog.csdn.net/c_cppcoder/article/details/104520091)
* [msgpack](https://github.com/vmihailenco/msgpack)
