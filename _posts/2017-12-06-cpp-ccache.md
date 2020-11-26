---
layout: post
title:  "ccache 优化 C++ 编译速度"
categories: tool
tags: ccache c/c++
author: wenfh2020
---

买了个低配的阿里云，1cpu, 2g 内存。基本能满足公网环境正常的功能测试，但是对于复杂的 c++ 项目编译显得有点费劲。

ccache 是个好东西，缓存了编译过的项，第一次编译源码有点慢，再次编译速度就飞快了（提升5-10倍的速度）。



* content
{:toc}

---

Centos 下安装也很简单，安装：

```shell
yum install ccache
```

项目里替换一下 Makefile 的编译项:

```shell
CXX = g++

==>

CXX = $(shell command -v ccache >/dev/null 2>&1 && echo "ccache g++" || echo "g++")
```
