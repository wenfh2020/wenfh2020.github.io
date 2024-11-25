---
layout: post
title:  "[C++] 提高 C++ 项目编译速度的神兵利器"
categories: c/c++
author: wenfh2020
stickie: true
---

最近接手的一个 Linux C++ 项目，编译速度把我折腾得怀疑人生。

—— 编译经过优化，全编译时间硬是从 半个小时 缩短到 `3 分钟` ！！！

划重点，三板斧：

1. 多核并行编译：  make -j$(nproc)
2. 编译缓存工具：  [ccache](https://wenfh2020.com/2017/12/06/cpp-ccache/)
3. 分布式编译工具：distcc



* content
{:toc}

---



## 1. 优化简介

|:---:|:----|
|手段|描述|
|<span style="display:inline-block;width:60px">并行编译</span>|Linux 项目通过 CMake 构建的，编译过程中，没发现使用多核，将对应的脚本 make 命令后面添加上 `-j$(nproc)` 参数，支持多核编译，编译速度有惊人的提高。|
|ccache|编译缓存工具，它通过缓存已编译过的文件来减少重复编译，从而提高构建效率。项目第一次编译，因为没有编译缓存可能相对会慢，第二次编译，使用前面编译的缓存结果，速度直线提高。|
|distcc|分布式编译工具，它允许多个计算机并行编译源代码，从而加速编译过程。目的就是利用其它机器的资源。|

---

## 2. cmake 构建脚本

* 查找工具脚本：distcc_ccahe_compiler.cmake。
  
  脚本目的是编译器编译过程中查找 ccache/distcc 工具，便于项目引入工具脚本进行编译。

```shell
# 查找 ccache 和 distcc
find_program(CCACHE_PROGRAM ccache)
find_program(DISTCC_PROGRAM distcc)

# 初始化 launcher 列表
set(COMPILER_LAUNCHERS "")

# 如果找到 ccache，添加到 launcher 列表
if(CCACHE_PROGRAM)
    message(STATUS "Found ccache: ${CCACHE_PROGRAM}")
    list(APPEND COMPILER_LAUNCHERS "${CCACHE_PROGRAM}")
endif()

# 如果找到 distcc，添加到 launcher 列表
if(DISTCC_PROGRAM)
    message(STATUS "Found distcc: ${DISTCC_PROGRAM}")
    list(APPEND COMPILER_LAUNCHERS "${DISTCC_PROGRAM}")
endif()

# 如果 launcher 列表不为空，设置 CMake 的 launcher
if(COMPILER_LAUNCHERS)
    message(STATUS "Using compiler launchers: ${COMPILER_LAUNCHERS}")
    set(CMAKE_C_COMPILER_LAUNCHER ${COMPILER_LAUNCHERS})
    set(CMAKE_CXX_COMPILER_LAUNCHER ${COMPILER_LAUNCHERS})
else()
    message(WARNING "Neither ccache nor distcc found, using default compiler settings")
endif()
```

---

* CMakeLists.txt。
  
  在项目的编译脚本（CMakeLists.txt）中引入前面的工具脚本。

```shell
include(../distcc_ccahe_compiler.cmake)
```

---

## 3. distcc 配置

distcc 是 C/S 工作模式，须要服务端和客户端进行安装配置。

我的开发机器是双核的，刚好有一台闲置的 48 核机器，可以利用上。

1. 客户端 - 开发机器 - 192.168.1.122 - 12  核（逻辑核心）
2. 服务端 - 闲置机器 - 192.168.1.36  - 48  核（逻辑核心）

> 1. 编译是 IO + CPU 密集型工作，最后还是得拼硬件啊 ^_^！！！
> 2. 因为涉及到远程编译，得保证带宽噢！

* 本地客户端编译过程。

<div align=center><img src="/images/2024/2024-11-25-12-25-01.png" width="85%" data-action="zoom"></div>

* 远程服务端编译效果。

<div align=center><img src="/images/2024/2024-11-25-12-30-01.png" width="85%" data-action="zoom"></div>

---

### 3.1 服务端配置

* 后台启动 distcc。

```shell
distccd --daemon --allow 192.168.1.122 --verbose --log-file=/tmp/distcc.log
```

> 服务端默认监听 3632 端口，防火墙要支持该端口的访问。
>
> 使用过程中出现什么问题，可以通过 `--log-file` 对应的日志跟踪问题。

---

### 3.2 客户端配置

* 写入 `/etc/distcc.conf` 配置文件。

```shell
# 配置远程主机，指定 192.168.1.36 使用最多 42 个并行编译进程
export DISTCC_HOSTS="192.168.1.36/42,lzo"
# 设置本地编译 4 个任务（可以根据自己需要配置）
export DISTCC_SLOTS="4"
# 编译核心，提供 make -j$(nproc) 使用，从配置读取核心数值
CORES=32
```

* 后台启动 distcc。

```shell
distccd --daemon --allow 192.168.1.122 --verbose --log-file=/tmp/distcc.log
```

---

## 4. 参考

* [ccache 优化 C++ 编译速度](https://wenfh2020.com/2017/12/06/cpp-ccache/)
* [如何加速 C++ 文件的编译速度](https://www.cnblogs.com/CocoML/p/14643379.html)
* [centos安装 distcc + ccache 加快c/c++编译](https://blog.csdn.net/niu91/article/details/111491038)
* [分布式编译的艺术：DistCC 的高效应用与实践](https://www.showapi.com/news/article/66c125854ddd79f11a0f6173)
* [linux编译命令：tmpfs，make，distcc，ccache](https://www.cnblogs.com/forforever/p/13637082.html)
* [distcc加速内核编译](https://www.cnblogs.com/forforever/p/13637082.html)
