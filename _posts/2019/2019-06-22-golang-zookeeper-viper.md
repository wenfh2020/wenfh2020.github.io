---
layout: post
title:  "golang & viper config & zookeeper"
categories: golang zookeeper
tags: golang zookeeper viper
author: wenfh2020
---

服务启动，一般都需要读取本地的配置文件。如果配置文件可以远程管理，那将是个不错的想法。



* content
{:toc}

---

## 1. 概述

我们可以通过 zookeeper 管理配置文件内容。服务注册到 zookeeper，当配置文件变更，zookeeper 实时通知服务更新服务的配置文件内容。golang 语言环境下，viper 是一个不错的配置插件。下面是服务读取远程配置到本地的实现流程：

![获取远程配置逻辑](/images/2020/2020-09-08-22-49-33.png){:data-action="zoom"}

---

## 2. 源码

具体源码实现请参考 [github](https://github.com/wenfh2020/go-test/tree/master/project/test_zk_viper)。

```go
func main() {
    /* 初始化配置文件远程管理对象。 */
    InitConfigCenter()
    /* 获取配置文件。 */
    config, err := GetModule("/test/test.yml", "")
    if err != nil {
        panic(err)
    }
    /* 获取配置文件内容。 */
    fmt.Println(config.GetInt("test"))
    common.InitSignal()
}
```
