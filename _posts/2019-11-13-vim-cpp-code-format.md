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

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
