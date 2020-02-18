---
layout: post
title:  "ssh 快捷登录"
categories: Linux
tags: Linux
author: wenfh2020
--- 

快捷登录阿里云效果

![效果](https://upload-images.jianshu.io/upload_images/4321487-576fb7036b4e979c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)



* content
{:toc}

---

## 机器

本地机器：macOS

远程机器：120.25.83.123

---

## 配置

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

## 参考

* [ssh免密码快速登录配置](https://www.cnblogs.com/bingoli/p/10567734.html)