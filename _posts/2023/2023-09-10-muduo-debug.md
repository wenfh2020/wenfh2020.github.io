---
layout: post
title:  "[muduo] vscode + gdb 调试 muduo"
categories: c/c++ muduo
author: wenfh2020
---

在 Centos 上配置 C++ 多线程网络库 muduo 的 vscode + gdb 调试环境。



---

* content
{:toc}

## 1. 运行系统

muduo 服务程序运行环境：

```shell
# cat /etc/redhat-release
CentOS Linux release 7.9.2009 (Core)
# cat /proc/version
Linux version 3.10.0-1127.19.1.el7.x86_64 (mockbuild@kbuilder.bsys.centos.org) 
(gcc version 4.8.5 20150623 (Red Hat 4.8.5-39) (GCC) )
```

---

## 2. 安装

拉取 muduo 2.0.2 稳定版本。

> 还有其它部分依赖，缺啥补啥~

```shell
# 安装依赖。
yum install protobuf
yum install libcurl zlib hiredis
yum install boost
yum install boost-devel
yum install boost-doc

# 拉取代码 2.0.2 版本。
wget https://github.com/chenshuo/muduo/archive/refs/tags/v2.0.2.tar.gz
tar zxf v2.0.2.tar.gz
cd muduo-2.0.2
```

---

## 3. 编译脚本

编写 muduo debug 版本的编译脚本 build_debug.sh，放在 muduo 源码目录下。

* 脚本源码。

```shell
#!/bin/sh

cd `dirname $0`
work_path=`pwd`
cd $work_path

BUILD_TYPE=debug ./build.sh install -j4

[ $? -ne 0 ] && echo "build failed" && exit 1
cd ../build/debug-install-cpp11/lib/
cp libmuduo_base.a libmuduo_net.a /usr/local/lib64
[ $? -ne 0 ] && echo "copy failed!" && exit 1
cd -
echo "done!"
```

* 脚本使用。

```shell
cd muduo-2.0.2
chmod +x build_debug.sh
build_debug.sh
```

---

## 4. 测试源码

在 muduo 源码文件夹下创建简单的 TCP 服务实例 test.cpp 进行测试。

* 源码目录。

```shell
    ➜  muduo-2.0.2 tree -L 1
    ├── BUILD.bazel
(*) ├── build_debug.sh
    ├── build.sh
    ├── ChangeLog
    ├── ChangeLog2
    ├── CMakeLists.txt
    ├── compile_commands.json -> ../build/debug-cpp11/compile_commands.json
    ├── contrib
    ├── examples
(*) ├── test
(*) ├── test.cpp
    └── WORKSPACE
```

* CPP 源码。

```cpp
// test.cpp
// g++ -O0 test.cpp -std=c++11 -lmuduo_net -lmuduo_base -lpthread -o test
#include <muduo/base/Logging.h>
#include <muduo/net/EventLoop.h>
#include <muduo/net/TcpServer.h>

using std::placeholders::_1;
using std::placeholders::_2;
using std::placeholders::_3;

void onConnection(const muduo::net::TcpConnectionPtr& conn) {
    LOG_INFO << "new conn from: " << conn->peerAddress().toIpPort() << " to "
             << conn->localAddress().toIpPort() << " is "
             << (conn->connected() ? "connected" : "disconnected");
}

void onMessage(const muduo::net::TcpConnectionPtr& conn,
               muduo::net::Buffer* buf,
               muduo::Timestamp time) {
    muduo::string msg(buf->retrieveAllAsString());
    LOG_INFO << conn->name() << " echo " << msg.size() << " bytes, "
             << "data received at " << time.toString();
    conn->send(msg);
}

int main() {
    muduo::net::EventLoop loop;
    muduo::net::InetAddress listen_addr(8888);
    muduo::net::TcpServer server(&loop, listen_addr, "test-tcp-server");

    server.setConnectionCallback(std::bind(&onConnection, _1));
    server.setMessageCallback(std::bind(&onMessage, _1, _2, _3));
    server.start();
    loop.loop();
}
```

* 测试服务输出。

```shell
# 编译测试代码。
g++ -O0 test.cpp -std=c++11 -lmuduo_net -lmuduo_base -lpthread -o test
# 运行测试实例。
./test
# 测试程序输出。 
20230910 01:02:45.640819Z 21097 INFO  TcpServer::newConnection [test-tcp-server] - new connection [test-tcp-server-0.0.0.0:8888#1] from 127.0.0.1:32824 - TcpServer.cc:73
20230910 01:02:45.641029Z 21097 INFO  new conn from: 127.0.0.1:32824 to 127.0.0.1:8888 is connected - test.cpp:10
20230910 01:02:56.719027Z 21097 INFO  test-tcp-server-0.0.0.0:8888#1 echo 3 bytes, data received at 1694307776.718978 - test.cpp:19
```

* 使用 telnet 进行测试。

```shell
telnet 127.0.0.1 8888
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
1
1
```

---

## 5. vscode 调试配置

在 muduo 源码目录下的 .vscode 文件夹，编写对应的配置文件。

> 配置好后，打开测试 test.cpp 文件，设置调试断点，F5 快捷键，vscode 调试 test.cpp 文件。

<div align=center><img src="/images/2023/2023-09-10-10-05-09.png" data-action="zoom"></div>

* luanch.json

```shell
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "(gdb) Launch",
            "type": "cppdbg",
            "request": "launch",
            "program": "${workspaceFolder}/${fileBasenameNoExtension}",
            "args": [],
            "stopAtEntry": false,
            "cwd": "${workspaceFolder}",
            "environment": [],
            "externalConsole": false,
            "MIMode": "gdb",
            "preLaunchTask": "build",
            "setupCommands": [
                {
                    "description": "Enable pretty-printing for gdb",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                }
            ]
        }
    ]
}
```

* tasks.json

```shell
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build",
            "type": "shell",
            "command": "g++",
            "args": [
                "-g",
                "-O0",
                "${file}",
                "-std=c++11",
                "-lmuduo_net",
                "-lmuduo_base",
                "-lpthread",
                "-o",
                "${fileBasenameNoExtension}"
            ]
        }
    ]
}
```

<div align=center><img src="/images/2023/2023-09-10-10-03-54.png" data-action="zoom"></div>
