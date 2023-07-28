---
layout: post
title:  "Centos7 vim 编码环境 (C++/golang)"
categories: tool
tags: vim golang c++ code centos
author: wenfh2020
---

记录 Centos7 系统下，用 vim 编写 C++/golang 源码的方法和工具使用总结。



* content
{:toc}

---

![效果图](/images/2020/2020-04-22-13-31-34.png){: data-action="zoom"}

## 1. 环境

Centos 7.4

```shell
# cat /proc/version
Linux version 3.10.0-693.2.2.el7.x86_64 (builder@kbuilder.dev.centos.org) (gcc version 4.8.5 20150623 (Red Hat 4.8.5-16) (GCC) )

# go version
go version go1.9.2 linux/amd64
```

## 2. 工具使用

### 2.1. tmux

分屏利器，这货确实好用。曾经用 xshell 每个窗口开一个 tab ，现在赶脚很笨很笨。（讲真，两个显示器一起工作，也是爽得不要不要的）

---

### 2.2. zsh

比较人性化的终端比 bash shell 好用，个人喜欢它的主题 ZSH_THEME="mh"，安装包的 141 个主题，每个主题都试了一遍，感觉还是这个简洁实用 --强迫症。

---

### 2.3. vimplus

一键安装 vim 各种插件，感谢作者的贡献，节约的是时间，多出来的却是生命！个人喜欢 `colorscheme torte` 或者 `morning` 主题，后面可以微调 .vimrc，调整自己适合的使用方案。

---

## 3. ycm (YouCompleteMe)

代码编辑自动补全神器。系统版本低的朋友，建议不要装，例如 Centos 6.5； python, vim, gcc, glibc, 等等各种升级，折腾得让你怀疑人生，墙裂建议各位不要轻易升级 glibc，说多也是泪。直接上 Centos7.4，系统自带版本 vim7.4 还是有点低，升级到 8.0 就能正常支持 ycm 了，注意：vim8.0 编译需要支持 python。

---

场景：单窗口，单文件，打开 vim 。

内存： 100M 左右，一般使用过程中，不可能只打开一个的，所以你懂的。

CPU：代码量少的文件，编辑很流畅，不怎么耗 CPU，笔者编辑 2000 行代码的文件，在补全括号的过程中，有时会发现卡顿，单核 CPU 短暂的跑满。也就2-3s。所以硬件配置不高的朋友，要注意这个问题。

总结：多数场景下，文件比较小，基本不影响使用，编辑大文件需要注意。

---

### 3.1. c++

ycm 对于复杂的 C++ 项目，无法跳转问题。错误：Can't jump to definition

默认的  .ycm_extra_conf.py 只包含了基本的系统目录。ycm 并没有想象中那么智能，它不知道你开发的复杂的项目代码文件的依赖关系，你需要告诉它。就像 Makefile，如果 -I 路径写得不对，代码也是编译不通过的。所以需要拷贝一份 .ycm_extra_conf.py 文件到项目的根目录，打开该文件找到标识 flags = [，参考 Makefile 中依赖的路径，也把相关的依赖路径填充进去（支持相对路径）。注意：.ycm_extra_conf.py 设置相对路径的，vim 需要在根目录（.ycm_extra_conf.py 所在路径）打开这样 ycm 才能正常跳转。

---

### 3.2. golang

`vim-go`：Golang 开发环境的vim插件。vim-go 这货有点坑，有些依赖代码用的是墙外的链接，不能翻墙的，:GoInstallBinaries 怎么安装都漏东西，升级失败。参考插件配置，缺哪个，补哪个。

参考：https://www.golangtc.com/download/package

![golang 编译依赖配置](/images/2020/2020-04-22-13-30-01.png){: data-action="zoom"}
