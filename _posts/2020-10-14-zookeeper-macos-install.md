---
layout: post
title:  "[zookeeper] MacOS 安装 ZooKeeper"
categories: zookeeper
tags: zookeeper macos install
author: wenfh2020
---

最近在做服务集群的节点发现，服务远程配置信息。以前造过类似的服务管理轮子，虽然是轻量级，但与 zookeeper (后面简称 zk) 这种成熟的解决方案比较，还有一段距离。使用 zk 最直接的好处：能少写代码，方便维护，用最低的成本快速实现功能。

---

zk 是 java 系，需要先安装 java，然后再安装 zk。zk 的搭建比较简单，网上很多文档（[《Zookeeper 安装配置》](https://www.runoob.com/w3cnote/zookeeper-setup.html)），这里记录一下 `MacOS` 的搭建。



* content
{:toc}

---

## 1. 安装 jdk

* 到 [java 官网](https://www.oracle.com/java/technologies/javase/javase-jdk8-downloads.html)下载对应系统的 jdk 安装。（[MacOS 安装包](https://download.oracle.com/otn/java/jdk/8u261-b12/a4634525489241b9a9e1aa73d9e118e6/jdk-8u261-macosx-x64.dmg?AuthParam=1602481348_7c31337aa7bdd8edc735b7f63fb2b1e7)）

* 检验安装是否成功。

```shell
# java-version
java version "1.8.0_261"
Java(TM) SE Runtime Environment (build 1.8.0_261-b12)
Java HotSpot(TM) 64-Bit Server VM (build 25.261-b12, mixed mode)
```

* 配置 jdk。（我系统用 zsh，所以配置 zsh。）

```shell
# vim ~/.zshrc
JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk1.8.0_261.jdk/Contents/Home
export JAVA_HOME
CLASS_PATH="$JAVA_HOME/lib"
PATH=".$PATH:$JAVA_HOME/bin"
# source ~/.zshrc
```

---

## 2. 安装 zk

* MacOS 安装命令。

```shell
brew install zookeeper
```

* 启动 zk 服务。（服务默认端口：2181）

```shell
# sudo zkServer start
ZooKeeper JMX enabled by default
Using config: /usr/local/etc/zookeeper/zoo.cfg
Starting zookeeper ... STARTED  
```

* 启动 zk client，连接 zk 服务。

```shell
# sudo zkCli
/usr/bin/java
Connecting to localhost:2181
Welcome to ZooKeeper!
JLine support is enabled

WATCHER::

WatchedEvent state:SyncConnected type:None path:null
[zk: localhost:2181(CONNECTED) 0] ls /kimserver
[access, db]
[zk: localhost:2181(CONNECTED) 1]
```

---

## 3. 参考

* [Zookeeper 教程](https://www.runoob.com/w3cnote/zookeeper-tutorial.html)
* [Java SE Development Kit 8 Downloads](https://www.oracle.com/java/technologies/javase/javase-jdk8-downloads.html)

---

> 🔥 文章来源：[《zookeeper 异步 C++ client》](https://wenfh2020.com/2020/10/14/zk-async-c-client/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
