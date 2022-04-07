---
layout: post
title:  "MacOS 安装使用 Docker"
categories: tool
tags: docker ubuntu
author: wenfh2020
---

只要开着 VMware 虚拟机，笔记本风扇经常响，尝试通过 Docker 跑比较干净的程序，看看问题是否能得到改善。




* content
{:toc}

---

## 1. 下载安装

* 到 [docker 官网](https://hub.docker.com/) 下载 docker app 安装。

<div align=center><img src="/images/2022-04-06-14-38-55.png" data-action="zoom"/></div>

* docker app。

<div align=center><img src="/images/2022-04-07-18-17-14.png" data-action="zoom"/></div>

---

## 2. docker 命令

```shell
# 拉取容器。
docker pull <image>:<version>

# 显示容器镜像。
docker images

# 显示正在运行的容器。
docker ps

# 显示所有容器，包括已停止运行容器。
docker ps -a

# 运行容器，-i 交互式操作，-t 终端，bash 默认的 shell /bin/shell 操作。
docker run -it --name <container_name> <image> bash

# 启动容器。
docker start <container_id> 

# 启动已停止容器，退出容器终端，但不会导致容器停止。
docker exec -it <container_name> bash

# 停止容器。
docker stop <container_id>

# 删除容器。
docker rm <container_id>

# 显示 docker 网络类型。
docker network list

# 显示容器的网络信息。
docker network inspect <container_id>
```

---

## 3. 容器

<div align=center><img src="/images/2022-04-07-18-13-03.png" data-action="zoom"/></div>

### 3.1. ubuntu

* 安装 docker 后，拉取容器，运行容器，使用容器。

```shell
# 查看 docker 版本。
docker --version

# docker 拉取最新 ubuntu 容器。
docker pull ubuntu

# 当前终端运行进入 ubuntu 容器。 
docker run -it --name minios ubuntu bash

# 查看当前 ubuntu 版本。
cat /etc/issue

# 更新相关插件。
apt-get update

# 安装常用插件。
apt-get install vim git openssh-server tmux zsh

# 退出容器。
exit
```

* ssh 运行容器（参考：[[shell] ssh 快捷登录](https://wenfh2020.com/2020/01/07/ssh-quick-login/)）。

```shell
# ssh 运行容器。
docker run -d -p 26122:22 --name learn ubuntu-ssh /usr/sbin/sshd -D

# 进入容器（通过 zsh）。
docker exec -it cokim zsh
```

---

### 3.2. mysql

```shell
# 拉取容器。
docker pull mysql

# 运行容器，-d 让容器在后台运行，-p 端口映射。
docker run -itd --name mysql-test -p 3306:3306 -e MYSQL_ROOT_PASSWORD=123456 mysql
```

```shell
# 安装连接客户端。
apt-get install libmysqlclient-dev python3-dev

# 连接
mysql -h116.25.xxx.xx -uroot -p
```

---

### 3.3. redis

```shell
docker pull redis:latest
docker images
docker run -itd --name redis-test -p 6379:6379 redis
docker exec -it redis-test /bin/bash
```

---

### 3.4. zookeeper

```shell
docker pull zookeeper
docker images
docker inspect 3bfde2963555
docker run -d -p 2181:2181 --name co-zookeeper --restart always 3bfde2963555
docker exec -it co-zookeeper bash
./bin/zkCli.sh
```

---

## 4. 小结

新环境重新部署软件，以前各种常用软件装半天，这些重复劳动不会为工作带来任何价值，现在很多通用的软件，通过 docker 模块化成容器，一个 docker pull 命令就能拉取下来了，极大提高了工作效率。——`活到老，学到老啊`！

---

## 5. 参考

* [acOS 下使用 Docker 搭建 ubuntu 环境](https://zhuanlan.zhihu.com/p/59548929)
* [Docker 安装 MySQL](https://www.runoob.com/docker/docker-install-mysql.html)
* [ubuntu安装protobuf](https://blog.csdn.net/u010918487/article/details/82947157)
* [Docker下安装zookeeper（单机 & 集群） ](https://www.cnblogs.com/LUA123/p/11428113.html)
* [docker --net详解_Docker网络通信](https://blog.csdn.net/weixin_34608222/article/details/113537311)
