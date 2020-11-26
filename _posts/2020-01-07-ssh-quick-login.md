---
layout: post
title:  "[shell] ssh 快捷登录"
categories: Linux
tags: Linux quick login
author: wenfh2020
--- 

快捷登录阿里云效果

![效果](/images/2020-02-20-17-22-08.png){: data-action="zoom"}



* content
{:toc}

---

## 1. 机器

本地机器：macOS

远程机器：120.25.83.123

---

## 2. 配置

* 本地配置

```shell
# 创建密匙
ssh-keygen -t rsa

# 拷贝密匙到远程机器
scp ~/.ssh/id_rsa.pub root@120.25.83.123:~/.ssh/id_rsa.pub.mac
```

* 远程配置

```shell
cd ~/.ssh
cat id_rsa.pub.mac >> authorized_keys
```

* 本地快捷登录设置

> 我本地使用的默认 shell 是 zsh

```shell
# 添加 alias 别名快捷命令
echo "alias sgx='ssh root@120.25.83.123'" >> ~/.zshrc
# 配置生效
source ~/.zshrc
```

---

## 3. 参考

* [ssh免密码快速登录配置](https://www.cnblogs.com/bingoli/p/10567734.html)
