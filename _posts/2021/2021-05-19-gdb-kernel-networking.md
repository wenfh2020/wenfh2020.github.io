---
layout: post
title:  "gdb 调试 Linux 内核网络源码（附视频）"
categories: kernel
tags: gdb Linux qemu networking kernel
author: wenfh2020
---

最近在看 Linux 内核的网络部分源码，在 MacOS 上搭建调试环境，通过 gdb 调试，熟悉内核网络接口的工作流程。

> 调试环境搭建视频：[gdb 调试 Linux 内核网络源码](https://www.bilibili.com/video/bv1cq4y1E79C)。






* content
{:toc}

---

## 1. 目标

* 目标：gdb 调试 Linux 内核网络部分源码。
* 环境：macos + vmware + ubuntu + qemu + gdb + linux kernel。
* 参考：[构建调试Linux内核网络代码的环境MenuOS系统](https://www.cnblogs.com/AmosYang6814/p/12027988.html)。

<div align=center><img src="/images/2021-05-19-16-08-52.png" data-action="zoom"/></div>

---

## 2. 流程

* 下载 ubuntu 14.04

```shell
http://mirrors.aliyun.com/ubuntu-releases/14.04/ubuntu-14.04.6-desktop-amd64.iso
```

* vmware 安装 ubuntu。

1. 虚拟系统磁盘空间，尽量给大一些，例如 100 G。
2. 通过 root 权限安装 linux 内核。

```shell
# 设置 root 密码。
sudo passwd
# 切换 root 用户。
su root

# 安装部分工具。
apt-get install vim tmux openssh-server git -y

# 添加 alias 方便操作终端。
vim ~/.bashrc
# 添加 alias c='clear'
source ~/.bashrc

# 启动 ssh. 避免后面 qemu 调试导致界面卡死，可以远程关闭进程。
ps -e | grep ssh
sudo /etc/init.d/ssh start
```

* 下载编译 linux 内核。

```shell
# 下载内核源码。
cd /root
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.0.1.tar.xz
xz -d linux-5.0.1.tar.xz
tar -xvf linux-5.0.1.tar
cd linux-5.0.1

apt install build-essential flex bison libssl-dev libelf-dev libncurses-dev -y

# 设置调试的编译菜单。
make menuconfig

# 下面选项如果没有选上的，选上，然后 save 保存设置，退出 exit。
Kernel hacking  --->
     Compile-time checks and compiler options  ---> 
         [*] Compile the kernel with debug info
         [*]     Provide GDB scripts for kernel debugging


Processor type and features  --->
    [*] Randomize the address of the kernel image (KASLR) 

# 编译内核。
make -j8

mkdir rootfs
```

* 调试内核。

```shell
# 下载测试项目。
cd ..
git clone https://github.com/mengning/menu.git
cd menu
vim Makefile
# 修改编译项：
# qemu-system-x86_64 -kernel ../linux-5.0.1/arch/x86/boot/bzImage -initrd ../rootfs.img

# 安装模拟器 qemu 和编译环境。
apt install qemu libc6-dev-i386

# 编译测试项目。
make rootfs

# 调试 kernel
qemu-system-x86_64 -kernel ../linux-5.0.1/arch/x86/boot/bzImage -initrd ../rootfs.img -append nokaslr -S -s

cd ../linux-5.0.1

# 发现低版本的 gdb 调试出现问题，需要升级。
gdb ./vmlinux
```

* 安装高版本 gdb

```shell
cd /root
gdb -v | grep gdb
apt remove gdb -y
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt install software-properties-common
sudo apt-get update
sudo apt-get install gcc-snapshot -y
gcc --version
sudo apt install gcc-9 g++-9 -y
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 --slave /usr/bin/g++ g++ /usr/bin/g++-9
gcc --version
wget https://mirror.bjtu.edu.cn/gnu/gdb/gdb-8.3.tar.xz
tar -xvf gdb-8.3.tar.xz
cd gdb-8.3
# 修改 gdb/remote.c 代码。
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
    for (i = 0; i < gdbarch_num_regs (gdbarch); i++){
            if (rsa->regs[i].pnum == -1)
                continue;
            if (rsa->regs[i].offset >= rsa->sizeof_g_packet)
                rsa->regs[i].in_g_packet = 0;
            else
                rsa->regs[i].in_g_packet = 1;
        }
    }
```

```shell
./configure
make -j8
cp gdb/gdb /usr/bin/
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 0 --slave /usr/bin/g++ g++ /usr/bin/g++-9
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 100
```

* 调试 tcp 网络通信。

```shell
cd /root/linux-5.0.1
git clone https://github.com/mengning/linuxnet.git
# 拷贝文件到 menu
cd linuxnet/lab2
# 修改拷贝的路径。
vim Makefile
# cp test_reply.c ../../../menu/test.c
# cp syswrapper.h ../../../menu

make

cd ../../../menu
make rootfs
cd ../linux-5.0.1/linuxnet/lab3
# qemu-system-x86_64 -kernel ../../arch/x86/boot/bzImage -initrd ../rootfs.img

make rootfs

# 调试
qemu-system-x86_64 -kernel ../../arch/x86/boot/bzImage -initrd ../rootfs.img -append nokaslr -S -s
```

```shell
cd /root/linux-5.0.1
gdb ./vmlinux
# 下断点。
b tcp_v4_connect
b inet_csk_accept
c
```

用户可以根据自己的需要去下断点，也可以修改 linuxnet 源码进行调试。

<div align=center><img src="/images/2021-05-19-17-43-51.png" data-action="zoom"/></div>

---

vscode + gdb 调试 Linux 内核更好一点。详看：[vscode + gdb 远程调试 linux 内核源码（附视频）](https://wenfh2020.com/2021/06/23/vscode-gdb-debug-linux-kernel/)

---

## 3. 参考

* [构建调试Linux内核网络代码的环境MenuOS系统](https://www.cnblogs.com/AmosYang6814/p/12027988.html)
* [初始化MenuOS的网络设置，跟踪分析TCP协议](https://www.lanqiao.cn/courses/1198/learning/?id=9010)
* [mengning/net](https://github.com/mengning/net/tree/master/doc)
* [QEMU 网络配置一把梭 [archived]](https://wzt.ac.cn/2019/09/10/QEMU-networking/)