---
layout: post
title:  "[shell] sed 插入多行文本"
categories: Linux
tags: shell sed
author: wenfh2020
---

今天刚好在做一个一件安装的脚本，需要用 `sed` 插入多行文本，感觉这个操作有点费劲，所以在这记录一下。



* content
{:toc}

---

## 1. 脚本

脚本意图：

1. 删除 2 - 7 行的文本。
2. 从第 2 行插入多行文本。

```shell
#!/bin/sh

work_path=$(dirname $0)
cd $work_path
work_path=$(pwd)

file_name=test

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
        sed -i "" "2,7d" test
        sed -i "" "2$insert" $file_name
    else
        sed -i "2,7d" test
        sed -i "2$insert" $file_name
    fi
}

insert_func
```

---

## 2. 参考

* [sed使用(mac版)](https://www.jianshu.com/p/f50dc95fe4b5)
* [Linux sed 命令](https://www.runoob.com/linux/linux-comm-sed.html)
