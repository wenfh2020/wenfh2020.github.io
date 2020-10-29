---
layout: post
title:  "protobuf / json 数据转换"
categories: c/c++
tags: protobuffer json
author: wenfh2020
---

protobuf 3.0 版本支持 protobuf 与 json 数据结构相互转换。



* content
{:toc}

---

## 1. 转换接口

protobuf 与 json 数据转换接口在 `google/protobuf/util/json_util.h` 文件里。

```c++
/* protobuf 数据转换成 json 结构。 */
inline util::Status MessageToJsonString(const Message& message, std::string* output);
/* json 数据结构转换为 protobuf 数据结构。 */
inline util::Status JsonStringToMessage(StringPiece input, Message* message);
```

---

## 2. 测试源码

* protobuf 结构。

```protobuf
syntax = "proto3";
package kim;

message addr_info{
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

* 测试。

```c++
...
#include <google/protobuf/util/json_util.h>

void convert() {
    kim::node_info node;
    node.set_name("111111");
    node.mutable_addr_info()->set_bind("wruryeuwryeuwrw");
    node.mutable_addr_info()->set_port(342);
    node.mutable_addr_info()->set_gate_bind("fsduyruwerw");
    node.mutable_addr_info()->set_gate_port(4853);

    node.set_node_type("34rw343");
    node.set_conf_path("reuwyruiwe");
    node.set_work_path("ewiruwe");
    node.set_worker_cnt(3);

    std::string json_string;
    google::protobuf::util::JsonPrintOptions options;
    options.add_whitespace = true;
    options.always_print_primitive_fields = true;
    options.preserve_proto_field_names = true;
    MessageToJsonString(node, &json_string, options);

    std::cout << json_string << std::endl;

    node.Clear();
    if (JsonStringToMessage(json_string, &node).ok()) {
        std::cout << "json to protobuf: "
                  << node.name()
                  << ", "
                  << node.mutable_addr_info()->bind()
                  << std::endl;
    }
}

int main(int argc, char** argv) {
    convert();
    return 0;
}
```

* 测试源码运行结果。

```shell
{
 "name": "111111",
 "addr_info": {
  "bind": "wruryeuwryeuwrw",
  "port": 342,
  "gate_bind": "fsduyruwerw",
  "gate_port": 4853
 },
 "node_type": "34rw343",
 "conf_path": "reuwyruiwe",
 "work_path": "ewiruwe",
 "worker_cnt": 3
}

json to protobuf: 111111, wruryeuwryeuwrw
```

---

## 3. 参考

* [protobuf 官网](https://developers.google.com/protocol-buffers/)
* [protobuf github](https://github.com/protocolbuffers/protobuf)
* [protobuf json 文档](https://developers.google.com/protocol-buffers/docs/proto3#json)
* [c++ - 协议(protocol)buffer3和json](https://www.coder.work/article/121306)

---

> 🔥 文章来源：[《protobuf / json 数据转换》](https://wenfh2020.com/2020/10/28/protobuf-convert-json/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
