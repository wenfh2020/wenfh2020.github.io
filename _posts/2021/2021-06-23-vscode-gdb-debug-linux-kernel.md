---
layout: post
title:  "vscode + gdb 远程调试 linux 内核源码（附视频）"
categories: kernel
tags: vscode gdb debug linux kernel
author: wenfh2020
---

前段时间才搭建起来 [gdb 调试 Linux 内核网络源码](https://wenfh2020.com/2021/05/19/gdb-kernel-networking/)（[视频](https://www.bilibili.com/video/bv1cq4y1E79C) ），但是 gdb 命令调试效率不高。磨刀不误砍柴工，所以折腾一下 **vscode**，使调试人性化一点。




* content
{:toc}

<div align=center><img src="/images/2021/2021-06-24-16-20-49.png" data-action="zoom"/></div>

---

## 1. 视频

视频连接：[vscode + gdb 远程调试 linux (EPOLL) 内核源码](https://www.bilibili.com/video/bv1yo4y1k7QJ)

<iframe class="bilibili" src="//player.bilibili.com/player.html?aid=376254064&bvid=BV1yo4y1k7QJ&cid=360457201&page=1&high_quality=1" scrolling="no" border="0" frameborder="no" framespacing="0" allowfullscreen="true"> </iframe>

---

## 2. 搭建调试环境

要搭建 vscode + gdb 调试 Linux 内核环境，首选要搭建：**[gdb 调试 Linux 内核源码](https://wenfh2020.com/2021/05/19/gdb-kernel-networking/)（[视频](https://www.bilibili.com/video/bv1cq4y1E79C)）**，然后再配置 vscode 进行测试调试。

---

## 3. vscode 配置

### 3.1. vscode 插件

* ms-vscode.cpptools

<div align=center><img src="/images/2021/2021-06-23-13-17-05.png" data-action="zoom"/></div>

* remote-ssh

> 避免 remote-ssh 工作过程中频繁要求输入登录密码，最好设置一下 ssh 免密码登录（参考：[[shell] ssh 快捷登录](https://wenfh2020.com/2020/01/07/ssh-quick-login/)）。

<div align=center><img src="/images/2021/2021-06-23-13-18-31.png" data-action="zoom"/></div>

<div align=center><img src="/images/2021/2021-06-23-13-42-26.png" data-action="zoom"/></div>

---

### 3.2. 项目调试配置

<div align=center><img src="/images/2021/2021-06-23-13-15-06.png" data-action="zoom"/></div>

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "kernel-debug",
            "type": "cppdbg",
            "request": "launch",
            "miDebuggerServerAddress": "127.0.0.1:1234",
            "program": "${workspaceFolder}/vmlinux",
            "args": [],
            "stopAtEntry": false,
            "cwd": "${workspaceFolder}",
            "environment": [],
            "externalConsole": false,
            "logging": {
                "engineLogging": false
            },
            "MIMode": "gdb",
        }
    ]
}
```

---

## 4. 测试调试

### 4.1. 虚拟机操作

```shell
# 虚拟机进入 linux 内核源码目录。
cd /root/linux-5.0.1

# 从 github 下载内核测试源码。
git clone https://github.com/wenfh2020/kernel_test.git

# 进入测试源码目录。
cd kernel_test/test_epoll_tcp_server
# make 编译
make
# 通过 qemu 启动内核测试用例。
make rootfs
# 在 qemu 窗口输入小写字符 's', 启动测试用例服务程序。
s
# 在 qemu 窗口输入小写字符 'c', 启动测试用例客户端程序。
c

# 通过 qemu 命令启动内核测试用例进行调试。
qemu-system-x86_64 -kernel ../../arch/x86/boot/bzImage -initrd ../rootfs.img -append nokaslr -S -s
# 在 qemu 窗口输入小写字符 's', 启动测试用例服务程序。
s
# 在 qemu 窗口输入小写字符 'c', 启动测试用例客户端程序。
c
```

---

### 4.2. 实体机操作

1. vscode 连接远程虚拟机。
2. vscode 打开虚拟机 Linux 内核源码。
3. vscode 在 Linux 内核源码的 eventpoll.c 文件，对对应接口（epoll_create, epoll_wait, epoll_ctl）下断点。
4. F5 快捷键启动 vscode 调试。

<div align=center><img src="/images/2021/2021-06-23-12-48-59.jpeg" data-action="zoom"/></div>

---

## 5. 小结

* 我认为在阅读 Linux 内核源码前，最好先把调试环境搭建起来，因为 Linux 内核源码庞大复杂，新手很难从复杂的源码调用关系中理清思路。
* 老师传道受业，只会给你指出一条学习路线，还会提醒你路上可能遇到哪些大坑，但是路上还有无数小坑，你只有通过实践调试，才能找到答案。
* 在求知的路上，让我们共勉😸！

---

## 6. 扩展

上面这个搭建流程是早期的制作，后面增加了一些网络驱动调试步骤，重新录了一个，详细可以参考：[《搭建 Linux 内核网络调试环境（vscode + gdb + qemu）》](https://wenfh2020.com/2021/12/03/ubuntu-qemu-linux/)

> 知乎对应文档：[搭建 Linux 内核网络调试环境（vscode + gdb + qemu）](https://zhuanlan.zhihu.com/p/445453676)

<iframe class="bilibili" src="//player.bilibili.com/player.html?aid=592292865&bvid=BV1Sq4y1q7Gv&cid=461543929&page=1&high_quality=1" scrolling="no" border="0" frameborder="no" framespacing="0" allowfullscreen="true"> </iframe>
