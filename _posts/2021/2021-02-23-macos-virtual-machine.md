---
layout: post
title:  "MacOS 通过虚拟机（Virtual Function）安装 Centos7"
categories: tool
tags: macos virtual machine centos7
author: wenfh2020
---

MacOS 通过虚拟机运行 Centos7，虚拟机：VMware Function 12。





* content
{:toc}

---

## 1. 虚拟机

MacOS 用虚拟机：VMWare Fusion 12。

>【注意】MacOS 升级到 Big Sur 后，必须安装虚拟机 VMWare Fusion 12 以上的。

参考：[升级MacOS Big Sur之后vware虚拟机打不开解决方案](https://blog.csdn.net/qq_45712772/article/details/109691206)

* 虚拟机软件下载：
  
  百度网盘连接：https://pan.baidu.com/s/1kFC3SzYkta9YKOJyBxFVrA
  
  百度网盘密码：ng68

* 序列号。
  
  > [VMware Fusion Pro 12.0.0最新序列号](https://www.xuchengen.cn/475)。

---

## 2. Centos7 系统安装

* 系统之家下载 Centos7 系统映象：[CentOS 7.7 X64官方正式版系统（64位）](http://www.xitongzhijia.net/linux/202002/174203.html)。
* VMWare Fusion 虚拟机安装系统映象。

```shell
# cat /etc/redhat-release
CentOS Linux release 7.7.1908 (Core)
# uname -a
Linux localhost.localdomain 3.10.0-1062.el7.x86_64 #1 SMP Wed Aug 7 18:08:02 UTC 2019 x86_64 x86_64 x86_64 GNU/Linux
```

<div align=center><img src="/images/2021-02-23-16-52-56.png" data-action="zoom"/></div>

---

### 2.1. 网络

虚拟机安装好 centos7 系统后，还不能上网，需要配置网络，打开配置文件，填充网络内容。

* 虚拟机系统网络适配。

<div align=center><img src="/images/2021-02-23-16-40-18.png" data-action="zoom"/></div>

* 打开文件，根据实体机网络，修改虚拟机对应网络信息，设置固定网络 IP。

```shell
vi /etc/sysconfig/network-scripts/ifcfg-ens33
```

```shell
TYPE="Ethernet"
PROXY_METHOD="none"
BROWSER_ONLY="no"
DEFROUTE="yes"
IPV4_FAILURE_FATAL="no"
IPV6INIT="yes"
IPV6_AUTOCONF="yes"
IPV6_DEFROUTE="yes"
IPV6_FAILURE_FATAL="no"
IPV6_ADDR_GEN_MODE="stable-privacy"
NAME="ens33"
UUID="892448df-69be-4637-a3eb-a793f2781189"
DEVICE="ens33"

# 设置固定的网络信息。
ONBOOT="yes"
BOOTPROTO="static"
IPADDR=192.168.0.200
GATEWAY=192.168.0.1
NETMASK=255.255.255.0
DNS1=114.114.114.114
```

* 本实体机网络信息。

<div align=center><img src="/images/2021-02-23-16-34-54.png" data-action="zoom"/></div>

<div align=center><img src="/images/2021-02-23-16-33-59.png" data-action="zoom"/></div>

* 重启网络。

```shell
systemctl stop NetworkManager
systemctl disable NetworkManager
systemctl restart network.service
```

* 测试网络。

```shell
ping www.baidu.com
```

---

### 2.2. yum

网络调通后，yum 安装软件还不能用，修改下载源。

参考：[CentOS 7 yum Loaded plugins: fastestmirror, langpacks Loading mirror speeds from cached hostfile](https://blog.csdn.net/baidu_33615716/article/details/102696313)

* 安装 epel。

```shell
yum install epel-release
```

* 修改配置文件：fastestmirror.conf。

```shell
vim /etc/yum/pluginconf.d/fastestmirror.conf
```

```shell
[main]
# 修改数值为 0.
enabled=0
```

* 修改配置文件：yum.conf。

```shell
vim /etc/yum.conf
```

```shell
[main]
# 修改数值为 0
plugins=0
```

---

### 2.3. ssh

在虚拟机上操作终端比较麻烦，最好在实体机上操作，为虚拟机开通 ssh 功能。

参考：

* [linux ssh 虚拟机下CentOS7开启SSH连接](https://blog.csdn.net/mengzuchao/article/details/80261836)。
* [[shell] ssh 快捷登录](https://wenfh2020.com/2020/01/07/ssh-quick-login/)

---

如果 ssh DNS 解析慢，可以修改配置。

```shell
# vi /etc/ssh/sshd_config
UseDNS no
# GSSAPI options
GSSAPIAuthentication no
# service sshd restart
```

---

### 2.4. 防火墙

参考： [CentOS 7 ：Failed to start IPv4 firewall with iptables.](https://blog.csdn.net/ls1645/article/details/78750561)

```shell
# 防火墙状态
systemctl status firewalld

# 关闭防火墙
systemctl stop firewalld.service
```

---

### 2.5. 磁盘扩容

参考 [Mac VMware Fusion 中修改 centos7 虚拟机的磁盘空间、扩容](https://www.jianshu.com/p/38eaf0c0a77d)。
