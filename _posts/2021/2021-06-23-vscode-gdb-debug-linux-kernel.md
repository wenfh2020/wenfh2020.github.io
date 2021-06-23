---
layout: post
title:  "vscode + gdb 远程调试 linux 内核源码"
categories: system
tags: vscode gdb debug linux kernel
author: wenfh2020
---

前段时间才搭建起来 gdb 调试 linux 内核调试环境（参考视频：[gdb 调试 Linux 内核网络源码](https://www.bilibili.com/video/bv1cq4y1E79C) ），但是 gdb 命令调试效率不高。磨刀不误砍柴工，所以折腾一下 **vscode**，使调试人性化一点。



* content
{:toc}

---

## 1. 部署调试环境

部署流程参考：[gdb 调试 Linux 内核网络源码（附视频）](https://wenfh2020.com/2021/05/19/gdb-kernel-networking/)

---

## 2. vscode 配置

### 2.2. vscode 插件

* ms-vscode.cpptools

<div align=center><img src="/images/2021-06-23-13-17-05.png" data-action="zoom"/></div>

* remote-ssh

> 避免 remote-ssh 工作过程中频繁要求输入登录密码，最好设置一下 ssh 免密码登录（参考：[[shell] ssh 快捷登录](https://wenfh2020.com/2020/01/07/ssh-quick-login/)）。

<div align=center><img src="/images/2021-06-23-13-18-31.png" data-action="zoom"/></div>

<div align=center><img src="/images/2021-06-23-13-42-26.png" data-action="zoom"/></div>

---

### 2.1. 项目调试配置

<div align=center><img src="/images/2021-06-23-13-15-06.png" data-action="zoom"/></div>

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

## 3. 小结

流程比较简单，vscode 插件安装完，启动调试即可。

<div align=center><img src="/images/2021-06-23-12-48-59.jpeg" data-action="zoom"/></div>
