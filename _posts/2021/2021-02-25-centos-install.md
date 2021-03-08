---
layout: post
title:  "Centos7 常用软件安装"
categories: 工具
tags: centos install
author: wenfh2020
---

记录 Centos7 常用软件安装的步骤流程。




* content
{:toc}

---

## 1. zsh

* 安装。

```shell
# 安装 zsh。
yum install zsh -y
# 切换到 zsh。
chsh -s /bin/zsh
# 安装 oh-my-zsh
wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh
chmod +x install.sh
./install.sh
# 更新配置。
vi /etc/profile
# profile 添加内容。
# export LC_ALL=en_US.UTF-8
# export LC_CTYPE=en_US.UTF-8
source /etc/profile
```

* 修改主题。

```shell
# 主题。
ls ~/.oh-my-zsh
# 修改主题。
vim ~/.zshrc
# 填充喜欢的主题。
# ZSH_THEME="mh"
# 刷新配置。
source ~/.zshrc
```

---

## 2. tmux

参考： [tmux 常用快捷键](https://wenfh2020.com/2020/11/05/tmux/)。

---

## 3. vimplus

参考：[超级强大的vim配置(vimplus)--续集](https://www.cnblogs.com/highway-9/p/5984285.html)

```shell
git clone https://github.com/chxuan/vimplus.git ~/.vimplus
cd ~/.vimplus
./install.sh
```

---

## 4. mysql

* 服务端：脚本一键安装。mysql 安装包默认是 5.6.22 版本，mysql 用户名和密码是 root，可自行修改脚本配置。

```shell
wget https://raw.githubusercontent.com/wenfh2020/shell/master/mysql/mysql_setup.sh
chmod +x mysql_setup.sh
./mysql_setup.sh
service mysqld start
```

* mysqlclient

```shell
yum install mysql -y
```
