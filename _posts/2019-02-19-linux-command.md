---
layout: post
title:  "Linux 常用命令"
categories: Linux
tags: Linux command
author: wenfh2020
--- 

Centos 等 Linux 平台常用命令，记录起来，方便使用。



* content
{:toc}

---

## 系统

### 机器启动

```shell
poweroff
reboot
shutdown -r now
```

---

### 修改密码

```shell
passwd root
```

---

### 查看 CPU

```shell
cat /proc/cpuinfo | grep "processor" | wc -l
```

---

### 查看系统内存情况

```shell
free -m
```

---

### 查看系统信息

```shell
uname -a
cat /proc/version
cat /etc/redhat-release
```

---

### 软链接

```shell
ln -s source dest
```

---

### 防火墙

```shell
service iptables start
service iptables stop
```

---

### 开放端口号

```shell
vi /etc/sysconfig/iptables
-A INPUT -m state --state NEW -m tcp -p tcp --dport 19007 -j ACCEPT
systemctl restart iptables.service
```

---

### 压缩解压

```shell
zip -r mydata.zip mydata
unzip mydata -d mydatabak
tar zcf mydata.tar.gz mydata
tar zxf mydata.tar.gz
```

---

### 更新文件配置

```shell
source /etc/profile
```

---

### 机器是多少位

```shell
file /sbin/init 或者 file /bin/ls
```

---

### 环境变量

```shell
env
```

---

### 用户切换

```shell
su root
exit
```

---

### 日期

```shell
date -d @1361542596 +"%Y-%m-%d %H:%M:%S"
```

---

### 进程绝对路径

```shell
top -c
htop
ls -l /proc/pid
ps -ef
```

---

## 文本

### awk

awk 动作 文件名

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

### sed

字符串处理

```shell
sed -i "s/jack/tom/g" test.txt
sed -i "s/\/usr\/local\/bin/\/usr\/bin/g" /etc/init.d/fdfs_storaged
```

---

### grep

| 命令      | 描述                       |
| --------- | -------------------------- |
| -l        | 列出文件名                 |
| -r        | 递归遍历文件夹             |
| -n        | 显示文件行数               |
| -E        | 查找多个                   |
| -i        | 大小写匹配查找字符串       |
| -w        | 匹配整个单词，而不是字符串 |
| --include | 搜索指定文件               |

找出文件（filename）中包含123或者包含abc的行

```shell
grep -E '123|abc' filename
```

只匹配整个单词，而不是字符串的一部分（如匹配‘magic’，而不是‘magical’）

```shell
grep -w pattern files
```

文件中查找字符串

```shell
grep "update" moment_audit.log | wc -l
```

递归文件夹在指定文件查找字符串

```shell
grep -r "pic" --include "*.md" .
```

---

## 磁盘文件

### ls

| 选项 | 描述                                                             |
| ---- | ---------------------------------------------------------------- |
| -a   | 列出目录所有文件，包含以.开始的隐藏文件                          |
| -A   | 列出除.及..的其它文件                                            |
| -r   | 反序排列                                                         |
| -t   | 以文件修改时间排序                                               |
| -S   | 以文件大小排序                                                   |
| -h   | 以易读大小显示                                                   |
| -l   | 除了文件名之外，还将文件的权限、所有者、文件大小等信息详细列出来 |

```shell
# 文件个数
# 不含子文件
ls -l |grep "^-"|wc -l
# 包括子文件
ls -lR|grep "^-"|wc -l
```

---

### tree

显示目录结构

```shell
tree /dir/ -L 1
```

---

### du

用于显示目录或文件的大小。

| 选项 | 描述                                |
| ---- | ----------------------------------- |
| -h   | 以K，M，G为单位，提高信息的可读性。 |
| -s   | 仅显示总计。                        |

```shell
# 查看文件夹剩余空间
du -sh dir
```

---

### df

用于显示目前在Linux系统上的文件系统的磁盘使用情况统计。

```shell
# 查看磁盘空间
df -h
```

---

### tail

```shell
tail -f file
tail -f file | grep '123'
```

---

### find

```shell
find   path   -option   [   -print ]   [ -exec   -ok   command ]   {} \;
```

| 选项                    | 描述                                         |
| ----------------------- | -------------------------------------------- |
| -name name, -iname name | 文件名称符合 name 的文件。iname 会忽略大小写 |
| -size                   | 文件大小                                     |
| -type                   | 文件类型<br/>f 一般文件<br/>d 目录           |

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
```

---

### git

git 命令查看简单文档或 man git

| 参数     | 描述                                                                                              |
| -------- | ------------------------------------------------------------------------------------------------- |
| pull     | 拉取文件                                                                                          |
| push     | 提交文件<br/>git push -u origin master  <br/> https://www.cnblogs.com/qianqiannian/p/6008140.html |
| log      | 文件是否存在<br/>获取简单的日志<br/>git log --pretty=oneline                                      |
| status   | 目录文件状态<br/>git status .                                                                     |
| checkout | 检索文件<br/>git checkout sync_pic.sh                                                             |
| clone    | 拉取源码 <br/>git clone https://github.com/enki/libev.git                                         |
| remote   | 查看 git 项目路径<br/>git remote -v                                                               |

---

## 权限

### 执行权限

```shell
chmod +x _file
chown -Rf imdev:imdev _folder
```

---

## 进程线程

### 查找进程

```shell
ps aux | grep _proxy_srv
```

---

### 进程启动绝对路径

```shell
ps -ef | grep xxx
ll /proc/pid ｜ grep exe
```

---

### 查进程名称对应的 pid

```shell
ps -ef | grep process_name | grep -v "grep" | awk '{print $2}' 
pidof redis-server
```

---

### 进程启动时间

```shell
ps -p PID -o lstart
ps -ef | grep redis | awk '{print $2}' | xargs ps -o pid,tty,user,comm,lstart,etime -p
```

---

### 查看线程

```shell
top -H -p pid
ps -efL | mysql | wc -l
pstree -p 1234 | wc -l
```

---

## 网络

### scp

1. scp -P端口号 本地文件路径 username@服务器ip:目的路径
2. 从服务器下载文件到本地，scp -P端口号 username@ip:路径 本地路径

```shell
scp -P端口号 username@ip:路径 本地路径
scp -r root@120.25.44.163:/home/hhx/srv_20150120.tar.gz .
scp /Users/wenfh2020/src/other/c_test/normal/proc/main.cpp root@120.25.44.163:/home/other/c_test/normal/proc
```

---

### ssh

```shell
ssh -p22 root@120.25.44.163
```

---

### tcpdump

Linux tcpdump [命令](https://www.runoob.com/linux/linux-comm-tcpdump.html)用于倾倒网络传输数据

| 选项 | 描述                                                      |
| ---- | --------------------------------------------------------- |
| -c   | <数据包数目> 收到指定的数据包数目后，就停止进行倾倒操作。 |
| -i   | <网络界面> 使用指定的网络截面送出数据包。                 |
| -n   | 不把主机的网络地址转换成名字。                            |
| -q   | 快速输出，仅列出少数的传输协议信息。                      |
| -v   | 详细显示指令执行过程。                                    |
| -vv  | 更详细显示指令执行过程。                                  |
| -w   | <数据包文件> 把数据包数据写入指定的文件。                 |

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

### wget

```shell
wget http://debuginfo.centos.org/6/x86_64/glibc-debuginfo-2.12-1.80.el6.x86_64.rpm
```

---

### netstat

netstat 命令用于显示网络状态

```
netstat [-acCeFghilMnNoprstuvVwx][-A<网络类型>][--ip]
```

| 选项 | 描述                                       |
| ---- | ------------------------------------------ |
| -a   | 显示所有连线中的Socket。                   |
| -l   | 显示监控中的服务器的Socket。               |
| -n   | 直接使用IP地址，而不通过域名服务器。       |
| -p   | 显示正在使用Socket的程序识别码和程序名称。 |
| -t   | 显示TCP传输协议的连线状况。                |
| -u   | 显示UDP传输协议的连线状况。                |

```shell
netstat -nat|grep -i "80"|wc -l
```

---

### lsof

```shell
 lsof -i:30004
```

---

## shell

### 语法

#### for

```shell
for p in paths
do
done
```

---

#### [if](https://www.runoob.com/linux/linux-shell-test.html)

```shell
if [ ! -d "$dir" ]; then
else
fi
```

---

#### 数组

```shell
align=1
unalign=0
array=(1, 2, 4, 8, 16, 32,64)

for x in ${array[*]}
do
    gcc -g -O0 align.cpp -o align  && time ./align $x $align
    echo '-------'
    gcc -g -O0 align.cpp -o align  && time ./align $x $unalign
    echo '>>>>>>>'
done
```

---

#### 文件

| 参数 | 描述               |
| ---- | ------------------ |
| -d   | 文件夹是否存在     |
| -x   | 文件是否有执行权限 |
| -f   | 文件是否存在       |

---

#### 数值比较

| 参数 | 描述     |
| ---- | -------- |
| -eq  | 等于     |
| -ne  | 不等于   |
| -gt  | 大于     |
| -ge  | 大于等于 |
| -lt  | 小于     |
| -le  | 小于等于 |

---

#### 字符串

| 参数 | 描述              |
| ---- | ----------------- |
| =    | 等于              |
| !=   | 等于              |
| -z   | 字符串的长度为0   |
| -n   | 字符串的长度不为0 |

---

### 其它

#### 有空格的路径 grep 操作

```shell
infos=`grep -r $src_pic_path --include '*.md' . | tr " " "\?"`
```

---

#### 有空格路径进行 sed 操作

```shell
sed -i '' "s:$src_pic_path:\.\/pic:g" $file
```

---

#### printf

```shell
printf '%d\n' 0xA
printf '%X\n' 320

local end_time=`date +"%Y-%m-%d %H:%M:%S"`
printf "%-10s %-11s" "end:" $end_time
```

---

### 命令

#### xargs

是给命令传递参数的一个过滤器

```shell
find /etc -name "*.conf" | xargs ls –l
cat url-list.txt | xargs wget –c
find / -name *.jpg -type f -print | xargs tar -cvzf images.tar.gz
```

---

## 工具

### top

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

![image-20191113091943326](/images/image-20191113091943326.png)

---

### htop

![image-20191112180503405](/images/image-20191112180503405.png)

---

### iftop

![image-20191112175351966](/images/image-20191112175351966.png)

---

### nload

![image-20191112180429804](/images/image-20191112180429804.png)

---

### nethogs

![image-20191112175719733](/images/image-20191112175719733.png)

---

### iotop

![image-20191112212348819](/images/image-20191112212348819.png)

---

### vmstat

命令查看内存转换情况，跟踪转换的频率

swap 原因：系统内存不足会产生 swap，磁盘的速度读写速度是比较慢的，这会影响性能。

```shell
free
vmstat
top
```

vmstat 1 每秒输出一次统计结果

不是 swap 空间占用性能就会下降，要看 si so 频率。

![image-20191113090543751](/images/image-20191113090543751.png)

---

### strace

```shell
# 跟踪具体的进程信息
strace -p <PID>
# 统计
strace -cp <PID>
# 单独跟踪某个被定位的内核函数
strace -T -e clone -p <PID>
# 显示调用高耗能内核函数的业务代码。
strace-eclone php -r 'exec("ls");'
```

---

## 参考

* [Linux 命令大全](https://www.runoob.com/linux/linux-command-manual.html)

---

* 更精彩内容，请关注作者博客：[wenfh2020.com](https://wenfh2020.com/)