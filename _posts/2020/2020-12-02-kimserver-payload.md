---
layout: post
title:  "[kimserver] 统计负载信息"
categories: kimserver
tags: kimserver payload
author: wenfh2020
---

简单统计进程负载信息，信息以 json 格式保存在 zookeeper，方便后台页面管理节点。




* content
{:toc}

---

## 1. 负载统计数据结构

数据结构：payload.proto，用 protobuf 来设计数据结构，方便数据读写，并且 protobuf 可以转 json（参考 [《protobuf / json 数据转换》](https://wenfh2020.com/2020/10/28/protobuf-convert-json/)）。

```protobuf
/* 节点信息。*/
message NodeData {
    string zk_path = 1;    /* zookeeper 节点路径。 */
    string node_type = 2;  /* 节点类型, gate/logic/... */
    string node_host = 3;  /* 内部服务集群通信 host。 */
    uint32 node_port = 4;  /* 内部服务集群通信 port。 */
    string gate_host = 5;  /* 对外通信 host。 */
    uint32 gate_port = 6;  /* 对外通信 port。 */
    uint32 worker_cnt = 7; /* 子进程个数。 */
};

/* 进程负载信息。*/
message Payload {
    uint32 worker_index = 1; /* 进程 id，父进程默认 0。 */
    uint32 conn_cnt = 2;     /* 连接个数. */
    uint32 cmd_cnt = 3;      /* 单位时间内处理命令个数。*/
    uint32 read_cnt = 4;     /* 读数据次数。 */
    uint32 read_bytes = 5;   /* 读数据量。*/
    uint32 write_cnt = 6;    /* 写数据次数。*/
    uint32 write_bytes = 7;  /* 写数据量。*/
    double create_time = 8;  /* 更新负载时间。*/
};

/* 统计负载信息。*/
message PayloadStats {
    NodeData node = 1;            /* 节点信息。*/
    Payload manager = 2;          /* 父进程负载信息。*/
    repeated Payload workers = 3; /* 多个子进程负载信息。*/
};
```

---

## 2. 统计流程

1. 子进程统计负载信息。
2. 子进程定时将负载信息发送给父进程。
3. 父进程统计自己的以及多个子进程上报的负载信息。
4. 父进程定时将统计信息转化为 json 数据，更新到 zookeeper 对应节点。

![负载统计流程](/images/2020/2020-12-02-23-22-36.png){:data-action="zoom"}

---

## 3. zookeeper 目录

### 3.1. 创建负载节点

1. 进程向 zookeeper 注册节点。
2. 节点注册成功后获得节点名称，在 zookeeper 对应目录更新负载信息。

---

### 3.2. 系统配置信息

kimserver 配置信息，详细配置解析请参考 [《[kimserver] 配置文件 config.json》](https://wenfh2020.com/2020/12/02/kimserver-config/)

```shell
{
    ...
    "zookeeper": {                       # zookeeper 中心节点管理配置。用于节点发现，节点负载等功能。
        "servers": "127.0.0.1:2181",     # redis 服务连接信息。
        "log_path": "zk.log",            # zookeeper-client-c 日志。
        "nodes": {                       # 节点发现配置。
            "root": "/kimserver/nodes",  # 节点发现根目录，保存了各个节点信息，每个节点启动需要往这个目录注册节点信息。
            "subscribe_node_type": [     # 当前节点关注的其它节点类型数组。用于集群里，节点之间相互通信。填充信息可以根据上面 node_type 配置。
                "gate",                  # 接入节点类型。
                "logic"                  # 逻辑节点类型。
            ]
        },
        "payload": {                     # zookeeper 节点负载信息。节点会定时刷新（1次/s），同步当前节点负载。
            "root": "/kimserver/payload" # 节点发现根目录。
        }
    }
}
```

---

### 3.3. zookeeper 数据

* 负载节点目录结构。

```shell
# sudo zkCli
# ls -R /kimserver
/kimserver
/kimserver/nodes
/kimserver/payload
/kimserver/nodes/gate
/kimserver/nodes/logic
# gate 节点注册的节点。
/kimserver/nodes/gate/kim-gate-gate0000000078
# logic 节点注册的节点。
/kimserver/nodes/logic/kim-logic-logic0000000025
/kimserver/payload/gate
/kimserver/payload/logic
# gate 节点创建的负载目录。
/kimserver/payload/gate/kim-gate-gate0000000078
# logic 节点创建的负载目录。
/kimserver/payload/logic/kim-logic-logic0000000025
```

* 负载节点数据。

```shell
# sudo zkCli
get /kimserver/payload/gate/kim-gate-gate0000000078
```

```json
{
    "node": {
        "zk_path": "/kimserver/nodes/gate/kim-gate-gate0000000078",
        "node_type": "gate",
        "node_host": "127.0.0.1",
        "node_port": 3344,
        "gate_host": "127.0.0.1",
        "gate_port": 3355,
        "worker_cnt": 1
    },
    "manager": {
        "worker_index": 0,
        "conn_cnt": 110,
        "cmd_cnt": 9915,
        "read_cnt": 547,
        "read_bytes": 2606151,
        "write_cnt": 102401,
        "write_bytes": 2606101,
        "create_time": 1606921932.438947
    },
    "workers": [{
        "worker_index": 1,
        "conn_cnt": 106,
        "cmd_cnt": 9915,
        "read_cnt": 546,
        "read_bytes": 2606101,
        "write_cnt": 102400,
        "write_bytes": 2606080,
        "create_time": 1606921931.451669
    }]
}
```

---

## 4. 源码实现

详细源码实现，请参考 `core/network.cpp` （[github](https://github.com/wenfh2020/kimserver/blob/master/src/core/network.cpp)）

```cpp
/* 时钟定时执行（默认每秒一次）。 */
void Network::on_repeat_timer(void* privdata) {
    if (is_manager()) {
        ...
        /* 主进程上报负载统计信息给 zookeeper。 */
        report_payload_to_zookeeper();
    } else {
        /* 子进程上报统计信息给父进程. */
        report_payload_to_parent();
    }
    ...
}
```

---

## 5. 参考

* [protobuf / json 数据转换](https://wenfh2020.com/2020/10/28/protobuf-convert-json/)
* [[kimserver] 配置文件 config.json](https://wenfh2020.com/2020/12/02/kimserver-config/)
* [[kimserver] 分布式系统 - 节点发现](https://wenfh2020.com/2020/10/24/kimserver-nodes-discovery/)
