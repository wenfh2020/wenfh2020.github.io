---
layout: post
title:  "ccache 优化C++编译速度"
categories: c/c++
tags: ccache c/c++
author: wenfh2020
---



买了个低配的阿里云，1cpu, 2g 内存。基本能满足公网环境正常的功能测试，但是对于复杂的 c++ 项目编译显得有点费劲。

ccache 是个好东西，缓存了编译过的项，第一次编译源码有点慢，再次编译速度就飞快了（提升5-10倍的速度）。

Centos 下安装也很简单，执行命令 `yum install ccache` 即可。

Makefile 里 C++ 编译项要替换一下 :

```shell
CXX = g++

==>

CXX = $(shell command -v ccache >/dev/null 2>&1 && echo "ccache g++" || echo "g++")
```

---

* 文章来源：[wenfh2020.com](https://wenfh2020.com/)
