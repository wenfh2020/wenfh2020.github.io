---
layout: post
title:  "Linux 文件目录权限"
categories: Linux
tags: linux file right
author: wenfh2020
---

Linux 文件权限属性，比较基础的知识，很多地方都可以查，在这记录一下。



* content
{:toc}

---

## 权限

我们用 `ls -l` 来看看目录下文件的属性。第一列是文件属性权限。

```shell
# ls -l
-rw-r--r--  1 wenfh2020  staff   803B 12  8 05:33 common.cpp
-rw-r--r--  1 wenfh2020  staff   659B 12  8 08:00 common.h
drwxr-xr-x  7 wenfh2020  staff   224B  3 13 14:51 lru
-rwxr-xr-x  1 wenfh2020  staff    32K  3 11 18:00 main
-rw-r--r--  1 wenfh2020  staff   2.7K 12 30 05:59 main.cpp
```

![权限属性](/images/2020-03-17-09-07-22.png)

---

## 修改权限

可以用 `chmod` 命令进行修改。命令相关操作可以参考[Linux chmod命令](https://www.runoob.com/linux/linux-comm-chmod.html)

---

## 参考

* [Linux 文件基本属性](https://www.runoob.com/linux/linux-file-attr-permission.html)
* [Linux文件和目录的777、755、644权限解释](https://www.cnblogs.com/ccw869476711/p/9213398.html)

---

* 更精彩内容，可以关注我的博客：[wenfh2020.com](https://wenfh2020.com/)
