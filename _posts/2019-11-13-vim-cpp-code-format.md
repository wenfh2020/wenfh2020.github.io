---
layout: post
title:  "vim c++ 代码自动格式化配置"
categories: tool
tags: vim c++ code format
author: wenfh2020
---

* 安装 vim 插件 [vim-autoformat](https://github.com/Chiel92/vim-autoformat#default-formatprograms)
* 安装 Artistic Style

```shell
mkdir /work/soft/astyle
wget https://jaist.dl.sourceforge.net/project/astyle/astyle/astyle%203.1/astyle_3.1_linux.tar.gz
tar zxvf astyle_3.1_linux.tar.gz
cd /work/soft/astyle/astyle/build/gcc
make
cd ../bin
cp astyle /usr/bin/astyle
```

* 配置 vim 配置文件 .vimrc

```shell
let g:formatdef_my_cpp = '"astyle --style=attach --pad-oper --lineend=linux"'
let g:formatters_cpp = ['my_cpp']
au BufWrite * :Autoformat
```

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
