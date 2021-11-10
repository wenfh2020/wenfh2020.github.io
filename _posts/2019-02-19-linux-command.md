---
layout: post
title:  "Linux 常用命令"
categories: system
tags: Linux command
author: wenfh2020
---

Centos 等 Linux 平台常用命令，记录起来，方便使用。



* content
{:toc}

---

<div align=center><img src="/images/2021-06-26-06-17-04.png" data-action="zoom"/></div>

<div align=center><img src="/images/2021-06-26-06-17-30.jpeg" data-action="zoom"/></div>

> 图片来源：[Linux Performance](https://www.brendangregg.com/linuxperf.html)。

## 1. 系统

### 1.1. 机器启动

```shell
poweroff
reboot
shutdown -r now
```

---

### 1.2. 修改密码

```shell
passwd root
```

---

### 1.3. 查看 CPU 信息

```shell
# cpu 个数。
cat /proc/cpuinfo | grep "processor" | wc -l

# cpu 信息。
lscpu
```

---

### 1.4. 查看系统信息

```shell
uname -a
cat /proc/version
cat /etc/redhat-release
```

---

### 1.5. 软链接

```shell
ln -s source dest
```

---

### 1.6. 压缩解压

```shell
zip -r mydata.zip mydata
unzip mydata -d mydatabak
tar zcf mydata.tar.gz mydata
tar zxf mydata.tar.gz
```

---

### 1.7. 更新文件配置

```shell
source /etc/profile
```

---

### 1.8. 机器是多少位

```shell
file /sbin/init 或者 file /bin/ls
```

---

### 1.9. 环境变量

```shell
env
```

---

### 1.10. 用户切换

```shell
su root
exit
```

---

### 1.11. 日期

```shell
date -d @1361542596 +"%Y-%m-%d %H:%M:%S"
```

---

### 1.12. 同步时间

```shell
# 修改中国时间
rm -rf /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 同步远程时间。
yum install -y ntpdate
ntpdate ntp.aliyun.com
```

---

### 1.13. 进程绝对路径

```shell
top -c
htop
ls -l /proc/pid
ps -ef
```

---

## 2. 内存

### 2.1. 查看系统内存情况

```shell
free -m
```

---

### 2.2. 查看进程内存映像

```shell
pmaps -p <pid>
```

---

### 2.3. vmstat

命令查看内存转换情况，跟踪转换的频率

swap 原因：系统内存不足会产生 swap，磁盘的速度读写速度是比较慢的，这会影响性能。

```shell
free
vmstat
top
```

vmstat 1 每秒输出一次统计结果

不是 swap 空间占用性能就会下降，要看 si so 频率。

<div align=center><img src="/images/image-20191113090543751.png" data-action="zoom"/></div>

> 参考 [《Linux vmstat命令详解》](https://www.cnblogs.com/ftl1012/p/vmstat.html)

---

## 3. 文本

### 3.1. awk

awk [操作] [文件名]

```shell
echo 'this is a test' | awk '{print $0}'
echo 'this is a test' | awk '{print $3}'
awk -F ':' '{ print $1 }' demo.txt
echo 'this is a test' | awk '{print $NF}'
awk -F ':' '{print $1, $(NF-1)}' demo.txt
awk -F ':' '{if ($1 > "m") print $1; else print "---"}' demo.txt
du | awk '{print $1}' |sort -nr
ps -ef | grep gdb | grep -v grep | awk '{print $3}' | xargs sudo kill -9
```

---

### 3.2. sed

字符串处理。

* linux

```shell
# replace
sed -i "s/jack/tom/g" test.txt
sed -i "s/\/usr\/local\/bin/\/usr\/bin/g" /etc/init.d/fdfs_storaged

# find and delete line.
sed '/gettimeofday/d' /tmp/connect.slave
```

* mac

```shell
sed -i '' 's/\/usr\/local\/bin/\/usr\/bin/g' /etc/init.d/fdfs_storaged
```

---

### 3.3. grep

|   命令    | 描述                                             |
| :-------: | ------------------------------------------------ |
|    -l     | 列出文件名。                                     |
|    -r     | 递归遍历文件夹。                                 |
|    -n     | 显示文件行数。                                   |
|    -E     | 查找多个。                                       |
|    -i     | 大小写匹配查找字符串。                           |
|    -w     | 匹配整个单词，而不是字符串。                     |
| --include | 搜索指定文件。                                   |
|    -A     | 列出搜索到的内容后面的几行内容。 grep xxxx -A 10 |

找出文件（filename）中包含123或者包含abc的行

```shell
grep -E '123|abc' filename
```

只匹配整个单词，而不是字符串的一部分（如匹配‘magic’，而不是‘magical’）。

```shell
grep -w pattern files
```

文件中查找字符串。

```shell
grep "update" moment_audit.log | wc -l
```

递归文件夹在指定文件查找字符串。

```shell
grep -r "pic" --include "*.md" .
```

---

## 4. 磁盘文件

### 4.1. ls

| 选项  | 描述                                                             |
| :---: | ---------------------------------------------------------------- |
|  -a   | 列出目录所有文件，包含以.开始的隐藏文件                          |
|  -A   | 列出除.及..的其它文件                                            |
|  -r   | 反序排列                                                         |
|  -t   | 以文件修改时间排序                                               |
|  -S   | 以文件大小排序                                                   |
|  -h   | 以易读大小显示                                                   |
|  -l   | 除了文件名之外，还将文件的权限、所有者、文件大小等信息详细列出来 |

```shell
# 文件个数
# 不含子文件
ls -l |grep "^-"|wc -l
# 包括子文件
ls -lR|grep "^-"|wc -l
```

---

### 4.2. tree

显示目录结构

```shell
tree /dir/ -L 1
```

---

### 4.3. du

用于显示目录或文件的大小。

| 选项  | 描述                                |
| :---: | ----------------------------------- |
|  -h   | 以K，M，G为单位，提高信息的可读性。 |
|  -s   | 仅显示总计。                        |

```shell
# 查看文件夹大小。
du -sh dir

# 从小到大排列文件。
du | sort -n -k1
```

---

### 4.4. df

用于显示目前在Linux系统上的文件系统的磁盘使用情况统计。

```shell
# 查看磁盘空间
df -h
```

---

### 4.5. tail

```shell
tail -f file
tail -f file | grep '123'
```

---

### 4.6. find

```shell
man find
```

```shell
find path -option [print] [-exec -ok command] {} \;
```

| 选项                    | 描述                                         |
| ----------------------- | -------------------------------------------- |
| -name name, -iname name | 文件名称符合 name 的文件。iname 会忽略大小写 |
| -size                   | 文件大小                                     |
| -type                   | 文件类型<br/>f 一般文件<br/>d 目录           |
| -perm                   | 对应文件目录权限                             |

```shell
# 查找删除文件
find / -name "*.mp3" |xargs rm -rf

# 查询最近两个小时修改过的文件
find /work/imdev/IM3.0 -iname "*" -mmin -120 -type f

# linux 命令行转换，将源码文件 tab 替换为 4 个空格
find . -regex '.*\.h\|.*\.hpp\|.*\.cpp' ! -type d -exec bash -c 'expand -t 4 "$0" > /tmp/e && mv /tmp/e "$0"' {} \;

# 查找大于 500 字节的文件，并且删除。
find ./ -size +500 | xargs rm -f

# 找出空文件
find / -type f -size 0 -exec ls -l {} \;

# 在某路径，查找带 xxx 关键字的所有文件，列出文件完整路径，文件行数。
find ~/src/other/c_test -name '*.cpp' -type f | xargs grep -n 'include'

# 将文件转换为 unix 格式
find . -type f -exec dos2unix {} \;

# 查找有执行权限文件
find . -perm -111

# 查找指定文件，将文件拷贝到指定目录。
find . -name '*.so' -type f -exec cp -f {} ../../bin/modules \;
```

---

## 5. 权限

### 5.1. 执行权限

```shell
chmod +x _file
chown -Rf imdev:imdev _folder
```

---

## 6. 进程线程

### 6.1. 查找进程

```shell
ps aux | grep _proxy_srv
```

---

### 6.2. 进程启动绝对路径

```shell
ps -ef | grep xxx
ll /proc/pid ｜ grep exe
```

---

### 6.3. 查进程名称对应的 pid

```shell
ps -ef | grep process_name | grep -v "grep" | awk '{print $2}' 
pidof redis-server
```

---

### 6.4. 进程启动时间

```shell
ps -p PID -o lstart
ps -ef | grep redis | awk '{print $2}' | xargs ps -o pid,tty,user,comm,lstart,etime -p
```

---

### 6.5. 查看线程

```shell
top -H -p pid
ps -efL | mysql | wc -l
pstree -p 1234 | wc -l
```

---

## 7. 网络

### 7.1. 防火墙

```shell
service iptables start
service iptables stop
```

---

### 7.2. 开放端口

```shell
# centos
vi /etc/sysconfig/iptables
-A INPUT -m state --state NEW -m tcp -p tcp --dport 19007 -j ACCEPT
systemctl restart iptables.service
```

---

### 7.3. scp

1. scp -P端口号 本地文件路径 username@服务器ip:目的路径
2. 从服务器下载文件到本地，scp -P端口号 username@ip:路径 本地路径

```shell
scp -P端口号 username@ip:路径 本地路径
scp -r root@120.25.44.163:/home/hhx/srv_20150120.tar.gz .
scp /Users/wenfh2020/src/other/c_test/normal/proc/main.cpp root@120.25.44.163:/home/other/c_test/normal/proc
```

---

### 7.4. rsync

```shell
#!/bin/sh

work_path=$(dirname $0)
cd $work_path
work_path=$(pwd)

rsync -avz --exclude="*.o" \
    --exclude=".git" \
    --exclude=".vscode" \
    --exclude="*.so" \
    --exclude="*.a" \
    --exclude="*.log" \
    --exclude="co_kimserver" \
    --exclude="test/test_log/test_log" \
    --exclude="test/test_mysql_mgr/test_mysql_mgr" \
    --exclude="test/test_tcp/test_tcp" \
    --exclude="test/test_tcp/test_tcp_pressure" \
    --exclude="test/test_mysql/test_mysql" \
    --exclude="test/test_timer/test_timer" \
    ~/src/other/coroutine/co_kimserver/ root@192.168.0.155:/home/other/coroutine/back
```

---

### 7.5. nslookup

查域名对应的 ip

```shell
# nslookup wenfh2020.com

Server:     116.116.116.116
Address:    116.116.116.116#53

Non-authoritative answer:
Name:   wenfh2020.com
Address: 120.25.83.163
```

---

### 7.6. ssh

```shell
ssh -p22 root@120.25.44.163
```

---

### 7.7. tcpdump

Linux tcpdump [命令](https://www.runoob.com/linux/linux-comm-tcpdump.html)用于倾倒网络传输数据

| 选项  | 描述                                                      |
| :---: | --------------------------------------------------------- |
|  -c   | <数据包数目> 收到指定的数据包数目后，就停止进行倾倒操作。 |
|  -i   | <网络界面> 使用指定的网络截面送出数据包。                 |
|  -n   | 不把主机的网络地址转换成名字。                            |
|  -q   | 快速输出，仅列出少数的传输协议信息。                      |
|  -v   | 详细显示指令执行过程。                                    |
|  -vv  | 更详细显示指令执行过程。                                  |
|  -w   | <数据包文件> 把数据包数据写入指定的文件。                 |

```shell
tcpdump port 80 and host www.baidu.com
tcpdump  host 192.168.100.18 and dst host 10.10.10.122
tcpdump -i eth0 -vnn dst host 10.10.10.122
tcpdump -i eth0 -vnn src host 192.168.100.18 and dst port 8060

#生产环境内网抓包。
tcpdump -i eth1 port 12911 -vvvv -nnn -w 123.cap

#内循环 127.0.0.1
tcpdump -i lo port 8333
tcpdump -i eth0 host api.fyber.com and port 80 -w 123.cap
```

---

### 7.8. wget

```shell
wget http://debuginfo.centos.org/6/x86_64/glibc-debuginfo-2.12-1.80.el6.x86_64.rpm
```

---

### 7.9. netstat

netstat 命令用于显示网络状态

```shell
netstat [-acCeFghilMnNoprstuvVwx][-A<网络类型>][--ip]
```

| 选项  | 描述                                       |
| :---: | ------------------------------------------ |
|  -a   | 显示所有连线中的Socket。                   |
|  -l   | 显示监控中的服务器的Socket。               |
|  -n   | 直接使用IP地址，而不通过域名服务器。       |
|  -p   | 显示正在使用Socket的程序识别码和程序名称。 |
|  -t   | 显示TCP传输协议的连线状况。                |
|  -u   | 显示UDP传输协议的连线状况。                |

```shell
netstat -nat|grep -i "80"|wc -l
```

---

### 7.10. ss

参考：[Linux网络状态工具ss命令使用详解](http://www.ttlsa.com/linux-command/ss-replace-netstat/)

---

### 7.11. lsof

* 查询端口对应的信息

```shell
lsof -i:30004
```

* 查询进程打开的文件

```shell
lsof -p <pid>
```

---

### 7.12. nc

```shell
# 启动监听 8333 端口的服务。
nc -l 8333
# 连接指定服务，显示数据。
nc -nvv 127.0.0.1 8333
```

---

## 8. 其它

### 8.1. 有空格的路径 grep 操作

```shell
infos=`grep -r $src_pic_path --include '*.md' . | tr " " "\?"`
```

---

### 8.2. 有空格路径进行 sed 操作

```shell
sed -i '' "s:$src_pic_path:\.\/pic:g" $file
```

---

### 8.3. printf

```shell
printf '%d\n' 0xA
printf '%X\n' 320

local end_time=`date +"%Y-%m-%d %H:%M:%S"`
printf "%-10s %-11s" "end:" $end_time
```

---

### 8.4. xargs

是给命令传递参数的一个过滤器。

```shell
find /etc -name "*.conf" | xargs ls –l
cat url-list.txt | xargs wget –c
find / -name *.jpg -type f -print | xargs tar -cvzf images.tar.gz
```

---

### 8.5. mysql 常用命令

不同平台下，启动 mysql 服务。

```shell
# MacOS
brew services start mysql

# centos7
systemctl start mysqld
```

---

## 9. 工具

### 9.1. top

```shell
#显示完整命令
top -c
# 查看字段解析
shift + f 
# 内存排序
shift + m
# cpu 排序
shit + p 
```

<div align=center><img src="/images/image-20191113091943326.png" data-action="zoom"/></div>

---

### 9.2. htop

<div align=center><img src="/images/image-20191112180503405.png" data-action="zoom"/></div>

---

### 9.3. iftop

<div align=center><img src="/images/image-20191112175351966.png" data-action="zoom"/></div>

---

### 9.4. nload

<div align=center><img src="/images/image-20191112180429804.png" data-action="zoom"/></div>

---

### 9.5. nethogs

<div align=center><img src="/images/image-20191112175719733.png" data-action="zoom"/></div>

---

### 9.6. iotop

```shell
[root:...rver/src/test/test_pressure]# iotop -botq |grep kim-
16:12:21  5201 be/4 root        0.00 B/s    2.05 M/s  0.00 %  0.00 % kim-gate_w_1
16:12:21  5202 be/4 root        0.00 B/s 1031.49 K/s  0.00 %  0.00 % kim-gate_w_2
16:12:21  5208 be/4 root        0.00 B/s 2023.31 K/s  0.00 %  0.00 % kim-logic_w_1
16:12:22  5195 be/4 root        0.00 B/s    3.78 K/s  0.00 %  0.00 % kim-gate   .
16:12:22  5201 be/4 root        0.00 B/s    2.26 M/s  0.00 %  0.00 % kim-gate_w_1
16:12:22  5202 be/4 root        0.00 B/s    2.91 M/s  0.00 %  0.00 % kim-gate_w_2
16:12:22  5208 be/4 root        0.00 B/s 1721.45 K/s  0.00 %  0.00 % kim-logic_w_1
```

<div align=center><img src="/images/image-20191112212348819.png" data-action="zoom"/></div>

---

### 9.7. strace

> macos: dtruss

```shell
# 跟踪具体的进程信息
strace -p <PID>

# 统计
strace -cp <PID>

# 单独跟踪某个被定位的内核函数
strace -T -e clone -p <PID>

# 显示调用高耗能内核函数的业务代码。
strace-eclone php -r 'exec("ls");'

# 抓取进程启动工作流程
strace -s 512 -o /tmp/sentinel.log ./redis-sentinel sentinel.conf
```

---

## 10. 参考

* [Linux 命令大全](https://www.runoob.com/linux/linux-command-manual.html)
