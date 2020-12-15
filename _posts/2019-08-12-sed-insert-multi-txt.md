---
layout: post
title:  "[shell] sed 插入多行文本"
categories: Linux
tags: shell sed
author: wenfh2020
---

用 `sed` 命令插入多行文本，感觉这个操作有点费劲，所以在这记录一下。




* content
{:toc}

---

## 1. 脚本意图

1. 删除 2 - 7 行的文本。
2. 从第 2 行插入多行文本。

---

## 2. 脚本使用

```shell
./script your_path
```

---

## 3. 脚本源码

```shell
#!/bin/sh

work_path=$(dirname $0) 
cd $work_path
work_path=$(pwd)

if [ $# -ne 1 ]; then
    echo "./script [file_name]"
    exit 1
fi

file_name=$1

insert='i\
if test \"x${ac_cv_env_CFLAGS_set}\" = \"x\"; then : \ 
    CFLAGS=\"-fPIC\" \
fi \
if test \"x${ac_cv_env_CXXFLAGS_set}\" = \"x\"; then : \ 
    CXXFLAGS=\"-fPIC\" \
fi
'

insert_func() {
    if [ $(uname -s) == "Darwin" ]; then
        # mac
        sed -i "" "2,7d" $file_name
        sed -i "" "2$insert" $file_name
    else
        # linux
        sed -i "2,7d" $file_name
        sed -i "2$insert" $file_name
    fi  
}

insert_func
```

---

## 4. 参考

* [sed使用(mac版)](https://www.jianshu.com/p/f50dc95fe4b5)
* [Linux sed 命令](https://www.runoob.com/linux/linux-comm-sed.html)
