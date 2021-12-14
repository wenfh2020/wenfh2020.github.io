---
layout: post
title:  "ubuntu14.04 + qemu 搭建 Linux 网络调试环境"
categories: tool
tags: perf
author: wenfh2020
---

linux 上的各种环境搭建，看着简单，就是总跑不起来 ——困顿，无力，抓狂 😖，这个 qemu 的网桥，搭的我那个怀疑人生。。。。



* content
{:toc}

---

## 1. 环境

macos + vmware + ubuntu  + gdb + qemu + linux kernel。

> 调试环境是跑在虚拟机里的，相信 windows 也能搭建起来。

| 环境         | 版本                                                        |
| :----------- | :---------------------------------------------------------- |
| macos        | macOS Monterey - 12.0.1                                     |
| vmware       | VMware Fusion - 专业版 12.0.0 (16880131)                    |
| ubuntu       | 14.04.6                                                     |
| gdb          | GNU gdb (GDB) 8.3                                           |
| qemu         | QEMU emulator version 2.0.0 (Debian 2.0.0+dfsg-2ubuntu1.46) |
| linux kernel | linux-5.0.1                                                 |

---

## 2. 流程

* 本地下载 ubuntu 14.04

```shell
# 镜像下载链接。
http://mirrors.aliyun.com/ubuntu-releases/14.04/ubuntu-14.04.6-desktop-amd64.iso
```

* vmware 安装 ubuntu。

1. 虚拟系统磁盘空间，尽量给大一些，例如 100 G。
2. 通过 root 权限安装 linux 内核。

* 安装常用工具。

```shell
# 设置 root 密码。
sudo passwd
# 切换 root 用户。
su root

# 安装部分工具。
apt-get install vim git tmux openssh-server -y

# 添加 alias 方便操作终端。
vim ~/.bashrc
# 添加 alias c='clear'
source ~/.bashrc

# 启动 ssh. 避免后面 qemu 调试导致界面卡死，可以远程关闭进程。
ps -e | grep ssh
sudo /etc/init.d/ssh start
```

* 源码安装 gdb。

```shell
# 升级安装相关组件。
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt install software-properties-common
sudo apt-get update
sudo apt-get install gcc-snapshot -y
gcc --version
sudo apt install gcc-9 g++-9 -y
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 --slave /usr/bin/g++ g++ /usr/bin/g++-9
gcc --version

# 删除 gdb
gdb -v | grep gdb
apt remove gdb -y

# 下载解压 gdb
cd /root
#wget https://mirror.bjtu.edu.cn/gnu/gdb/gdb-8.3.tar.xz
wget http://ftp.gnu.org/gnu/gdb/gdb-8.3.tar
tar -xvf gdb-8.3.tar.xz

# 修改 gdb/remote.c 代码。
cd gdb-8.3
vim gdb/remote.c
```

```c
/* Further sanity checks, with knowledge of the architecture.  */
// if (buf_len > 2 * rsa->sizeof_g_packet)
//   error (_("Remote 'g' packet reply is too long (expected %ld bytes, got %d "
//      "bytes): %s"),
//    rsa->sizeof_g_packet, buf_len / 2,
//    rs->buf.data ());

if (buf_len > 2 * rsa->sizeof_g_packet) {
    rsa->sizeof_g_packet = buf_len;
    for (i = 0; i < gdbarch_num_regs(gdbarch); i++) {
        if (rsa->regs[i].pnum == -1)
            continue;
        if (rsa->regs[i].offset >= rsa->sizeof_g_packet)
            rsa->regs[i].in_g_packet = 0;
        else
            rsa->regs[i].in_g_packet = 1;
    }
}
```

* 下载编译 linux 内核。

```shell
# 安装编译依赖项。
apt install build-essential flex bison libssl-dev libelf-dev libncurses-dev -y

# 下载内核源码。
cd /root
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.0.1.tar.xz
xz -d linux-5.0.1.tar.xz
tar -xvf linux-5.0.1.tar
cd linux-5.0.1

# 设置调试的编译菜单。
make menuconfig

# 下面选项如果没有选上的，选上（点击空格键），然后 save 保存设置，退出 exit。
##################################################################
Device Drivers --> 
    Network device support --> 
    Universal TUN/TAP device driver support

Networking support --> 
    Networking options --> 
        802.1d Ethernet Bridging

Kernel hacking  --->
    Compile-time checks and compiler options  ---> 
         [*] Compile the kernel with debug info
         [*] Provide GDB scripts for kernel debugging

Processor type and features  --->
    [*] Randomize the address of the kernel image (KASLR)
##################################################################

# 编译内核。
make -j8
```

---

## 4. 搭建静态 IP

### 4.1. 本地机器网络

<div align=center><img src="/images/2021-12-04-08-06-10.png" data-action="zoom"/></div>

<div align=center><img src="/images/2021-12-04-08-07-17.png" data-action="zoom"/></div>

<div align=center><img src="/images/2021-12-04-08-08-26.png" data-action="zoom"/></div>

### 4.2. 虚拟机

* 修改静态 IP.

```shell
# vim /etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address 192.168.10.144
gateway 192.168.10.1
netmask 255.255.255.0
```

* 修改域名。

```shell
# vim /etc/resolvconf/resolv.conf.d/base
nameserver 192.168.10.1
nameserver 8.8.8.8
```

* 命令刷新网络（如果没有效果，重启虚拟机看看）。

```shell
sudo NetworkManager restart
```

---

## 5. 搭建网桥

* 相关命令。

```shell
apt-get update
apt-get install bridge-utils        # 虚拟网桥工具
apt-get install uml-utilities       # UML（User-mode linux）工具

ifconfig <你的网卡名称(能上网的那张)> down    # 首先关闭宿主机网卡接口
brctl addbr br0                     # 添加名为 br0 的网桥
brctl addif br0 <你的网卡名称>        # 在 br0 中添加一个接口
brctl stp br0 off                   # 如果只有一个网桥，则关闭生成树协议
brctl setfd br0 1                   # 设置 br0 的转发延迟
brctl sethello br0 1                # 设置 br0 的 hello 时间
ifconfig br0 0.0.0.0 promisc up     # 启用 br0 接口
ifconfig <你的网卡名称> 0.0.0.0 promisc up    # 启用网卡接口
dhclient br0                        # 从 dhcp 服务器获得 br0 的 IP 地址
brctl show br0                      # 查看虚拟网桥列表
brctl showstp br0                   # 查看 br0 的各接口信息
```

* 修改配置文件。

```shell
auto lo
iface lo inet loopback

auto br0
iface br0 inet dhcp

bridge_ports eth0
bridge_fd 9
bridge_hello 2
bridge_maxage 12
bridge_stp off

auto tap0
iface tap0 inet manual
pre-up tunctl -t tap0 -u root
pre-up ifconfig tap0 0.0.0.0 promisc up
post-up brctl addif br0 tap0
```

> 参考：[qemu虚拟机与外部网络的通信](https://blog.csdn.net/zhaihaifei/article/details/58624063)

---

### 5.1. 问题

* 搭建网桥后上不了网。

```shell
ifconfig br0 down
brctl delbr br0
sudo service network-manager stop
sudo rm /var/lib/NetworkManager/NetworkManager.state
sudo service network-manager start
```

---

## 6. 启动 qemu

* 网络配置。

```shell
-net nic -net tap,ifname=tap0,script=no,downscript=no
```

* 相关命令。

```shell
qemu-system-x86_64 -smp 2 -m 2048 -enable-kvm -net nic -net tap,ifname=tap0,script=no linux.img

qemu-system-x86_64 -kernel ../../arch/x86/boot/bzImage -initrd ../rootfs.img -append nokaslr -S -s -net nic -net tap,ifname=tap0,script=no

qemu-system-x86_64 -kernel ../../arch/x86/boot/bzImage -initrd ../rootfs.img -append nokaslr -net nic -net tap,ifname=tap0,script=no

qemu-system-x86_64 -kernel ../../arch/x86/boot/bzImage -initrd ../rootfs.img -net nic -net tap,ifname=tap0,script=no

qemu-system-x86_64 -smp 2 -m 2048 -kernel ../../arch/x86/boot/bzImage -net nic -net tap,ifname=tap0,script=no -initrd ../rootfs.img


sudo qemu-system-x86_64 -hda $FILENAME -net nic,model=e1000,macaddr=DE:AD:BE:EF:3E:10 net tap -m 512 -vnc 10.60.1.124:10

qemu-system-x86_64 -kernel arch/x86/boot/bzImage -append "root=/dev/sda1 console=tty0" -nographic -net nic -net tap,ifname=tap0,script=no,downscript=no

qemu-system-x86_64 -kernel ../linux-5.0.1/arch/x86/boot/bzImage -initrd ../rootfs.img -append nokaslr -nographic

qemu-system-x86_64 -kernel ../../arch/x86/boot/bzImage -initrd ../rootfs.img -S -s


qemu-system-x86_64 -kernel arch/x86/boot/bzImage -append "root=/dev/sda1 console=tty0" -nographic -net nic -net tap,mac=02:ca:fe:f0:0d:01,ifname=tap0,script=no,downscript=no
```

---

## 7. 参考

* [Ubuntu 设置网桥后不能上网解决方法](https://blog.csdn.net/shizao/article/details/85264776)
* [qemu虚拟机与外部网络的通信](https://blog.csdn.net/zhaihaifei/article/details/58624063)
* [从源码编译linux-4.9内核并运行一个最小的busybox文件系统（最新整理版）](https://www.bilibili.com/read/cv11271232?spm_id_from=333.999.0.0)
* [linux内核开发第1讲：从源码编译 linux-4.9.229 内核和 busybox 文件系统](https://www.bilibili.com/video/BV1Vo4y117Xx?spm_id_from=333.999.0.0)
* [QEMU 网络配置一把梭](https://wzt.ac.cn/2021/05/28/QEMU-networking/)
* [Ubuntu 设置网桥后不能上网解决方法](https://blog.csdn.net/shizao/article/details/85264776)
* [基于Nokaslr的Linux内核编译与单步跟踪](https://zhuanlan.zhihu.com/p/440856634)
* [qemu与宿主机通过网桥链接通讯](https://blog.csdn.net/qq_39153421/article/details/116642646?ops_request_misc=%257B%2522request%255Fid%2522%253A%2522163887850616780255258270%2522%252C%2522scm%2522%253A%252220140713.130102334.pc%255Fblog.%2522%257D&request_id=163887850616780255258270&biz_id=0&utm_medium=distribute.pc_search_result.none-task-blog-2~blog~first_rank_v2~rank_v29-22-116642646.pc_v2_rank_blog_default&utm_term=QEMU&spm=1018.2226.3001.4450)
* [Ubuntu 安装 qemu 运行 Linux 3.16](https://blog.csdn.net/Mculover666/article/details/105251880)
* [Qemu连接外网的配置方法](https://blog.csdn.net/Mculover666/article/details/105664454?ops_request_misc=%257B%2522request%255Fid%2522%253A%2522163887850616780255258270%2522%252C%2522scm%2522%253A%252220140713.130102334.pc%255Fblog.%2522%257D&request_id=163887850616780255258270&biz_id=0&utm_medium=distribute.pc_search_result.none-task-blog-2~blog~first_rank_v2~rank_v29-24-105664454.pc_v2_rank_blog_default&utm_term=QEMU&spm=1018.2226.3001.4450)
* [qemu虚拟机与外部网络的通信](https://blog.csdn.net/zhaihaifei/article/details/58624063)
* [【原创】Linux虚拟化KVM-Qemu分析（八）之virtio初探](https://www.cnblogs.com/LoyenWang/p/14322824.html)
* [在Ubuntu下使用QEMU连网](https://blog.csdn.net/yang1111111112/article/details/104579608)
* [图解Linux网络包接收过程](https://zhuanlan.zhihu.com/p/256428917)
* [Linux网络协议栈：NAPI机制与处理流程分析（图解）](https://blog.csdn.net/Rong_Toa/article/details/109401935)
* [1. 网卡收包](https://www.jianshu.com/p/3b5cee1e88a2)
* [2. NAPI机制](https://www.jianshu.com/p/7d4e36c0abe8)
* [3. GRO机制](https://www.jianshu.com/p/376ce301da65)
* [网络收包流程-报文从网卡驱动到网络层（或者网桥)的流程（非NAPI、NAPI）(一)](https://blog.csdn.net/hzj_001/article/details/100085112)
* [New API](https://en.wikipedia.org/wiki/New_API)
* [NAPI模式--中断和轮询的折中以及一个负载均衡的问题](https://blog.csdn.net/dog250/article/details/5302853)
* [深入理解Linux网络技术内幕 第10章 帧的接收](https://blog.csdn.net/weixin_44793395/article/details/106593127)
* [Redis高负载下的中断优化](https://mp.weixin.qq.com/s?__biz=MjM5NjQ5MTI5OA%3D%3D&mid=2651747704&idx=3&sn=cd76ad912729a125fd56710cb42792ba)
* [ethtool原理介绍和解决网卡丢包排查思路](https://segmentfault.com/a/1190000022998507?hmsr=toutiao.io&utm_campaign=toutiao.io&utm_medium=toutiao.io&utm_source=toutiao.io)
* [数据包如何从物理网卡到达云主机的应用程序？](https://vcpu.me/packet_from_nic_to_user_process/)
* [Linux基础之网络包收发流程](https://blog.csdn.net/yangguosb/article/details/103562983)
* [Linux网络包收发总体过程](https://www.cnblogs.com/zhjh256/p/12227883.html)
* [Linux网络 - 数据包的接收过程](https://segmentfault.com/a/1190000008836467)
