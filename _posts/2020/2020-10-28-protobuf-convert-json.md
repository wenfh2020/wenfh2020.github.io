---
layout: post
title:  "protobuf / json 数据转换（C++）"
categories: c/c++
tags: protobuffer json
author: wenfh2020
---

protobuf 3.0 版本支持 protobuf 与 json 数据相互转换。



* content
{:toc}

---

## 1. 转换接口

protobuf 与 json 数据转换接口在 `google/protobuf/util/json_util.h` 文件里。

```cpp
/* protobuf 转 json。 */
inline util::Status MessageToJsonString(const Message& message, std::string* output);

/* json 换 protobuf。 */
inline util::Status JsonStringToMessage(StringPiece input, Message* message);
```

---

## 2. 测试

* protobuf 文件（[nodes.proto](https://github.com/wenfh2020/c_test/blob/master/protobuf/nodes.proto)）。

```protobuf
syntax = "proto3";
package kim;

message addr_info {
    string bind = 1;      /* bind host for inner server. */
    uint32 port = 2;      /* port for inner server. */
    string gate_bind = 3; /* bind host for user client. */
    uint32 gate_port = 4; /* port for user client. */
}

message node_info {
    string name = 1;         /* read from config and register to zk. */
    addr_info addr_info = 2; /* network addr info. */
    string node_type = 3;    /* node type in cluster. */
    string conf_path = 4;    /* config path. */
    string work_path = 5;    /* process work path. */
    int32 worker_cnt = 6;    /* number of worker's processes. */
}
```

* 执行脚本将 proto 文件生成 C++ protobuf 代码。

```shell
protoc -I. *.proto --cpp_out=. 
```

* 测试代码（[test_proto_json.cpp](https://github.com/wenfh2020/c_test/blob/master/protobuf/test_proto_json.cpp)）。

```cpp
#include <google/protobuf/util/json_util.h>
#include <iostream>
#include "nodes.pb.h"
using google::protobuf::util::JsonStringToMessage;

bool proto_to_json(const google::protobuf::Message& message, std::string& json) {
    google::protobuf::util::JsonPrintOptions options;
    options.add_whitespace = true;
    options.always_print_primitive_fields = true;
    options.preserve_proto_field_names = true;
    return MessageToJsonString(message, &json, options).ok();
}

bool json_to_proto(const std::string& json, google::protobuf::Message& message) {
    return JsonStringToMessage(json, &message).ok();
}

int main() {
    kim::node_info node;
    std::string json_string;

    node.set_name("111111");
    node.set_node_type("34rw343");
    node.set_conf_path("reuwyruiwe");
    node.set_work_path("ewiruwe");
    node.set_worker_cnt(3);

    node.mutable_addr_info()->set_bind("xxxxxxxxxx");
    node.mutable_addr_info()->set_port(342);
    node.mutable_addr_info()->set_gate_bind("fsduyruwerw");
    node.mutable_addr_info()->set_gate_port(4853);

    /* protobuf 转 json。 */
    if (!proto_to_json(node, json_string)) {
        std::cout << "protobuf convert json failed!" << std::endl;
        return 1;
    }
    std::cout << "protobuf convert json done!" << std::endl
              << json_string << std::endl;

    node.Clear();
    std::cout << "-----" << std::endl;

    /* json 转 protobuf。 */
    if (!json_to_proto(json_string, node)) {
        std::cout << "json to protobuf failed!" << std::endl;
        return 1;
    }
    std::cout << "json to protobuf done!" << std::endl
              << "name: " << node.name() << std::endl
              << "bind: " << node.mutable_addr_info()->bind()
              << std::endl;
    return 0;
}
```

* 编译运行。

```shell
g++ -std='c++11' nodes.pb.cc test_proto_json.cpp -lprotobuf -lpthread -o pj && ./pj
```

* 程序运行结果。

```shell
protobuf convert json done!
{
 "name": "111111",
 "addr_info": {
  "bind": "xxxxxxxxxx",
  "port": 342,
  "gate_bind": "fsduyruwerw",
  "gate_port": 4853
 },
 "node_type": "34rw343",
 "conf_path": "reuwyruiwe",
 "work_path": "ewiruwe",
 "worker_cnt": 3
}

-----
json to protobuf done!
name: 111111
bind: xxxxxxxxxx
```

---

## 3. 参考

* [protobuf 官网](https://developers.google.com/protocol-buffers/)
* [protobuf github](https://github.com/protocolbuffers/protobuf)
* [protobuf json 文档](https://developers.google.com/protocol-buffers/docs/proto3#json)
* [c++ - 协议(protocol)buffer3和json](https://www.coder.work/article/121306)
