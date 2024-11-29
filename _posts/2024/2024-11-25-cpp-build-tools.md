---
layout: post
title:  "[C++] 提高 C++ 项目编译速度的神兵利器"
categories: c/c++
author: wenfh2020
stickie: true
---

最近接手的一个 Linux C++ 项目，编译速度把我折腾得怀疑人生。

—— 源码编译经过优化，全编译时间硬是从 半个小时 缩短到 `3 分钟` ！！！（OMG，此处省略一万字...）

划重点，三板斧：

1. 多核并行编译：  make -j$(nproc)
2. 编译缓存工具：  [ccache](https://wenfh2020.com/2017/12/06/cpp-ccache/)
3. 分布式编译工具：[distcc](https://www.distcc.org/)



* content
{:toc}

---



## 1. 优化手段

|手段|描述|
|:---:|:----|
|<span style="display:inline-block;width:60px">并行编译</span>|`make -j N` 是 make 工具中用来并行编译的一个选项，-j 参数后面跟的是并行任务的数量 N，这表示你希望 make 在编译过程中启动多少个并行的编译进程。|
|ccache|编译缓存工具，通过缓存编译过程中的中间结果和元数据，避免对相同代码的重复编译。第一次编译时，由于没有缓存，可能会稍慢；而从第二次编译开始，利用之前的缓存，编译速度大幅提升。|
|distcc|分布式编译工具，通过将编译任务分发到多台计算机上并行处理，从而加速编译过程。其主要目的是充分利用其他机器的计算资源，提高编译效率。|

> 部分文字来源：ChatGPT

<div align=center><img src="/images/2024/2024-11-29-11-26-01.png" width="85%" data-action="zoom"></div>


---

## 2. distcc 配置

搭建 distcc 编译环境并不复杂，但使用前仍建议先看它的 [官网](https://www.distcc.org/)，以及 [官方部署文档](https://raw.githubusercontent.com/distcc/distcc/master/INSTALL)。

distcc 是 C/S 工作模式，须要服务端和客户端进行安装配置。

1. 客户端 - 开发机器 - 192.168.1.122 - 12  核（逻辑核心）
2. 服务端 - 闲置机器 - 192.168.1.36  - 48  核（逻辑核心）

> 1. 编译是 IO + CPU 密集型工作，最后还是得拼硬件啊 ^_^！！！
> 2. 因为涉及到远程编译，得保证带宽噢！

* 客户端机器编译过程。

<div align=center><img src="/images/2024/2024-11-25-12-25-01.png" width="85%" data-action="zoom"></div>

* 远程服务端机器编译效果。

<div align=center><img src="/images/2024/2024-11-25-12-30-01.png" width="85%" data-action="zoom"></div>

---

### 2.1 服务端配置

* 后台启动 distcc。

```shell
distccd --daemon --allow 192.168.1.122 --verbose --log-file=/tmp/distcc.log

# 如果你在 192.168.1.0/24 网络中运行 distcc，
# 并希望允许该网络中的所有机器使用 distcc 编译，也可以这样运行
# distccd --daemon --allow 192.168.1.0/24 --verbose --log-file=/tmp/distcc.log
```

> 服务端默认监听 3632 端口，防火墙要支持该端口的访问。
>
> 使用过程中出现什么问题，可以通过 `--log-file` 对应的日志跟踪问题。

---

### 2.2 客户端配置

* 写入 `~/.bashrc` 配置文件。

```shell
# 配置远程主机，指定 192.168.1.36 编译，localhost 本地也参与编译。
export DISTCC_HOSTS="192.168.1.36 localhost"
# 配置输出日志路径（方便调试）
export DISTCC_LOG='/tmp/distcc.log'
# 输出详细日志 1/2/3
export DISTCC_VERBOSE=1
```

* 观察编译任务分布情况。

```shell
# 每秒输出一次
distccmon-text 1
```

---

## 3. cmake 构建脚本

C++ 项目源码使用 cmake 构建编译脚本，结合编译工具优化源码编译脚本。

* 查找工具脚本：distcc_ccache_compiler.cmake。
  
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
include(../distcc_ccache_compiler.cmake)
```

---

## 4. 参考

* [ccache 优化 C++ 编译速度](https://wenfh2020.com/2017/12/06/cpp-ccache/)
* [如何加速 C++ 文件的编译速度](https://www.cnblogs.com/CocoML/p/14643379.html)
* [centos安装 distcc + ccache 加快c/c++编译](https://blog.csdn.net/niu91/article/details/111491038)
* [分布式编译的艺术：DistCC 的高效应用与实践](https://www.showapi.com/news/article/66c125854ddd79f11a0f6173)
* [linux编译命令：tmpfs，make，distcc，ccache](https://www.cnblogs.com/forforever/p/13637082.html)
* [distcc加速内核编译](https://www.cnblogs.com/forforever/p/13637082.html)
