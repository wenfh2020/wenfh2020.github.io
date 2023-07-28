---
layout: post
title:  "(ubuntu) vscode + gdb 调试 c++"
categories: c/c++
tags: gdb vscode debug c++
author: wenfh2020
---

vscode + gdb 简单调试 ubuntu 上的 c/c++ stl 源码。




* content
{:toc}

---

## 1. 系统

ubuntu 14.04 系统。

```shell
root@ubuntu:~/src/test# uname -r
4.4.0-142-generic

root@ubuntu:~/src/test# g++ --version
g++ (Ubuntu 9.4.0-1ubuntu1~14.04) 9.4.0
Copyright (C) 2019 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

---

## 2. 配置

在 .vscode 目录上添加两个文件：launch.json，tasks.json。

<div align=center><img src="/images/2022/2022-02-19-22-37-06.png" data-action="zoom"/></div>

* launch.json，选择对应的调试器和调试目录。

```json
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

* tasks.json，下面是根据 c++11 设置的编译参数，可以根据自己的需要填充对应参数。

```json
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
                "-D_GLIBCXX_DEBUG",
                "-o",
                "${fileBasenameNoExtension}"
            ]
        }
    ]
}
```

---

## 3. 调试

编写对应的测试源码，下断点进行调试。

<div align=center><img src="/images/2022/2022-02-19-22-44-07.png" data-action="zoom"/></div>
