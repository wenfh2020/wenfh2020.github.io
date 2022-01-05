---
layout: post
title:  "[kimserver] 配置文件 config.json"
categories: kimserver
tags: kimserver config
author: wenfh2020
---

kimserver 配置文件用的是 json 文件（config.json），保存于 bin 目录下（[github](https://github.com/wenfh2020/kimserver/tree/master/bin)）。

json 数据结构优点很多，缺点也不少（例如不能添加注释），文章主要解析配置文件内容。





* content
{:toc}

---

## 1. 配置内容

```shell
{
    "server_name": "kim-gate",              # 服务器名称。
    "worker_cnt": 1,                        # 子进程个数，因为 kimserver 是多进程框架，类似 nginx。
    "node_type": "gate",                    # 节点类型。微服务，可以定义不同节点类型，不同节点间可以相互通信。
    "node_host": "127.0.0.1",               # 服务集群内部通信 host。
    "node_port": 3344,                      # 服务集群内部通信端口。
    "gate_host": "127.0.0.1",               # 服务对外开放 host。(对外部客户端或者第三方服务。)
    "gate_port": 3355,                      # 服务对外开放端口。
    "gate_codec": "protobuf",               # 服务对外协议类型。目前暂时支持两种协议类型：protobuf / http。
    "keep_alive": 30,                       # 服务对外连接保活有效时间。
    "log_path": "kimserver.log",            # 日志文件。
    "log_level": "info",                    # 日志等级。(trace / debug / notice / warning / err / crit 等。)
    "modules": [                            # 业务功能插件，动态库数组。
        "module_test.so"
    ],
    "redis": {                              # redis 连接池配置，支持配置多个。
        "test": {                           # redis 配置节点，支持配置多个。
            "host": "127.0.0.1",            # redis 连接 host。
            "port": 6379                    # redis 连接 port。
        }
    },
    "database": {                           # mysql 数据库连接池配置。
        "test": {                           # mysql 数据库配置节点，支持配置多个。
            "host": "127.0.0.1",            # mysql host。
            "port": 3306,                   # mysql port。
            "user": "root",                 # mysql 用户名。
            "password": "root123!@#",       # mysql 密码。
            "charset": "utf8mb4",           # mysql 字符集。
            "max_conn_cnt": 5               # mysql 连接池最大连接数。
        }
    },
    "zookeeper": {                          # zookeeper 中心节点管理配置。用于节点发现，节点负载等功能。
        "servers": "127.0.0.1:2181",        # redis 服务连接信息。
        "log_path": "zk.log",               # zookeeper-client-c 日志。
        "nodes": {                          # 节点发现配置。
            "root": "/kimserver/nodes",     # 节点发现根目录，保存了各个节点信息，每个节点启动需要往这个目录注册节点信息。
            "subscribe_node_type": [        # 当前节点关注的其它节点类型数组。用于集群里，节点之间相互通信。填充信息可以根据上面 node_type 配置。
                "gate",                     # 接入节点类型。
                "logic"                     # 逻辑节点类型。
            ]
        },
        "payload": {                        # zookeeper 节点负载信息。节点会定时刷新（1次/s），同步当前节点负载。
            "root": "/kimserver/payload"    # 节点发现根目录。
        }
    }
}
```
