---
layout: post
title:  "[数据库] mysql 常用命令配置"
categories: database
tags: mysql config command
author: wenfh2020
---

记录 mysql 常用配置和命令。





* content
{:toc}

---

## 1. 安装

### 1.1. server

* mysql 5.6

  脚本一键安装。安装包默认是 5.6.22 版本，mysql 用户名和密码是 root，可自行修改脚本配置。

```shell
wget https://raw.githubusercontent.com/wenfh2020/shell/master/mysql/mysql_setup.sh
chmod +x mysql_setup.sh
./mysql_setup.sh
service mysqld start
```

* mysql 5.7。

```shell
cd /usr/local/src
wget https://dev.mysql.com/get/mysql57-community-release-el7-11.noarch.rpm
rpm -ivh mysql57-community-release-el7-11.noarch.rpm
yum install -y mysql-server
systemctl start mysqld
# 开机启动。
systemctl enable mysqld
# 获取临时密码。
cat /var/log/mysqld.log|grep 'A temporary password'
# 登录修改密码。
mysql -u root -p
# 允许设置密码。
mysql> alter user user() identified by "root";
# 设置新密码。
mysql> update mysql.user set authentication_string=password('root') where user='root' and Host ='localhost';
```

---

### 1.2. mysqlclient

```shell
# centos
yum install mysql -y

# ubuntu
apt-get install mysql-client libmysqlclient-dev python3-dev
```

---

## 2. 主从配置

需要开通端口允许访问，或者关闭防火墙测试。

```shell
# centos7
systemctl stop firewalld.service
```

| 类型   | IP            |
| :----- | :------------ |
| master | 192.168.0.200 |
| slave  | 192.168.0.201 |

---

### 2.1. master

* 修改配置，然后重启。配置 my.cnf，填充同步日志（log-bin）和服务id（server_id）（唯一，随便填，这里使用 ip 最后数字）。

```shell
# find / -name 'my.cnf'
# /usr/local/mysql/my.cnf
# vim /usr/local/mysql/my.cnf
[mysqld]
log-bin=mysql-bin
server_id=200
```

* 授权 slave，ip: 192.168.0.201，user: mytest，pwd: mytest。

```shell
GRANT REPLICATION SLAVE,FILE ON *.* TO 'mytest'@'192.168.0.201' IDENTIFIED BY 'mytest';
```

* 查询 master 数据状态。

```shell
mysql> show master status;
+------------------+----------+--------------+------------------+-------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set |
+------------------+----------+--------------+------------------+-------------------+
| mysql-bin.000009 |      890 |              |                  |                   |
+------------------+----------+--------------+------------------+-------------------+
```

* 配置 slave，重启 slave。参考下面章节。
* 配置完成后，master 写入数据，查看 slave 同步状况。

```shell
# 创建测试数据库。
mysql> CREATE DATABASE IF NOT EXISTS mytest DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_general_ci;

# 创建测试表。
mysql> use mytest;
mysql> CREATE TABLE `test_async_mysql` (
    ->     `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
    ->     `value` varchar(32) NOT NULL,
    ->     PRIMARY KEY (`id`)
    -> ) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4;

# 插入数据
mysql> insert into mytest.test_async_mysql (value) values ('hello world');
```

---

### 2.2. slave

* 修改配置 my.cnf，然后重启。

```shell
[mysqld]
log-bin=mysql-bin
server_id=201
```

* 设置 master 接入信息。

```shell
mysql> change master to master_host='192.168.0.200',master_user='mytest',master_password='mytest',master_log_file='mysql-bin.000009',master_log_pos=890;
```

* 开启 slave 功能。

```shell
mysql> start slave;
```

* 查看主从同步情况。

```shell
mysql> show slave status\G
*************************** 1. row ***************************
               Slave_IO_State: Waiting for master to send event
                  Master_Host: 192.168.0.200
                  Master_User: mytest
                  Master_Port: 3306
                Connect_Retry: 60
              Master_Log_File: mysql-bin.000009
          Read_Master_Log_Pos: 1055
               Relay_Log_File: mysql-relay-bin.000004
                Relay_Log_Pos: 448
        Relay_Master_Log_File: mysql-bin.000009
             Slave_IO_Running: Yes （正常）
            Slave_SQL_Running: Yes （正常）
```

---

## 3. 慢日志

参考：[Mysql数据库慢查询日志的使用](https://zhuanlan.zhihu.com/p/113429595)

---

### 3.1. 配置

#### 3.1.1. 修改配置文件

通过修改配置文件设置，永久生效。

* 查找 mysql 配置文件。

```shell
find / -name 'my.cnf'
/usr/local/mysql/my.cnf
```

* 修改配置文件内容。

```shell
# vim /usr/local/mysql/my.cnf
slow_query_log=ON
long_query_time=1
slow_query_log_file=/data/mysql/localhost-slow.log
```

* 重新启动

```shell
service mysqld restart
```

---

#### 3.1.2. 命令设置

通过命令设置，临时生效。

* 查询慢日志设置。

```shell
mysql> show variables like 'slow%';
+---------------------+--------------------------------+
| Variable_name       | Value                          |
+---------------------+--------------------------------+
| slow_launch_time    | 2                              |
| slow_query_log      | OFF                            |
| slow_query_log_file | /data/mysql/localhost-slow.log |
+---------------------+--------------------------------+
```

* 开启慢日志。

```shell
mysql> set global slow_query_log ='ON';
mysql> show variables like 'slow_query_log';
+----------------+-------+
| Variable_name  | Value |
+----------------+-------+
| slow_query_log | ON    |
+----------------+-------+
```

* 显示慢日志超时时间。

```shell
mysql> show variables like 'long%';
+-----------------+-----------+
| Variable_name   | Value     |
+-----------------+-----------+
| long_query_time | 10.000000 |
+-----------------+-----------+
```

* 设置慢日志超时时间。

```shell
# 设置。
mysql> set long_query_time=1;
Query OK, 0 rows affected (0.00 sec)

# 效果。
mysql> show variables like 'long%';
+-----------------+----------+
| Variable_name   | Value    |
+-----------------+----------+
| long_query_time | 1.000000 |
+-----------------+----------+
```

---

### 3.2. 分析

#### 3.2.1. 日志文件

```shell
mysql> select count(*) from mytest.test_async_mysql;
+----------+
| count(*) |
+----------+
|  3117853 |
+----------+
1 row in set (31.03 sec)
```

```shell
➜  src more /data/mysql/localhost-slow.log
...
# Time: 210319 16:24:12
# User@Host: root[root] @ localhost []  Id:    50
# Query_time: 31.034545  Lock_time: 0.000166 Rows_sent: 1  Rows_examined: 3117853
SET timestamp=1616142252;
select count(*) from mytest.test_async_mysql;
```

---

#### 3.2.2. mysqldumpslow

参考：[mysql慢日志 :slow query log 分析数据](https://blog.csdn.net/saga_gallon/article/details/72897332)

```shell
mysqldumpslow /data/mysql/localhost-slow.log


Reading mysql slow query log from /data/mysql/localhost-slow.log
Count: 3  Time=301.42s (904s)  Lock=0.00s (0s)  Rows=0.0 (0), root[root]@[127.0.0.1]
  update mytest.test_async_mysql set value = 'S' where id = N

Count: 1  Time=31.03s (31s)  Lock=0.00s (0s)  Rows=1.0 (1), root[root]@localhost
  select count(*) from mytest.test_async_mysql
```

---

## 4. explain 优化

参考：[【MySQL优化】——看懂explain](https://blog.csdn.net/jiadajing267/article/details/81269067)

```shell
mysql> explain select count(*) from mytest.test_async_mysql;
+----+-------------+------------------+-------+---------------+---------+---------+------+---------+-------------+
| id | select_type | table            | type  | possible_keys | key     | key_len | ref  | rows    | Extra       |
+----+-------------+------------------+-------+---------------+---------+---------+------+---------+-------------+
|  1 | SIMPLE      | test_async_mysql | index | NULL          | PRIMARY | 4       | NULL | 2743104 | Using index |
+----+-------------+------------------+-------+---------------+---------+---------+------+---------+-------------+
```

---

## 5. 功能

### 5.1. 远程访问

允许 `mytest` 用户远程访问。

```shell
mysql> mysql -uroot -proot;
mysql> use mysql;
mysql> update user set host = '%' where user ='mytest';
mysql> flush privileges;
```

---

### 5.2. 连接情况

* 当前所有连接。`show PROCESSLIST / show full PROCESSLIST`。

```shell
mysql> show PROCESSLIST;
+------+------+-----------------+--------+---------+------+----------+------------------+
| Id   | User | Host            | db     | Command | Time | State    | Info             |
+------+------+-----------------+--------+---------+------+----------+------------------+
|  945 | root | 127.0.0.1:24046 | mytest | Query   |    0 | starting | show PROCESSLIST |
| 1387 | root | 127.0.0.1:35109 | mysql  | Sleep   |  816 |          | NULL             |
| 1388 | root | 127.0.0.1:35111 | mysql  | Sleep   |  816 |          | NULL             |
...
```

* 查看最大连接数。

```shell
mysql> show variables like '%max_connections%';
+-----------------+-------+
| Variable_name   | Value |
+-----------------+-------+
| max_connections | 151   |
+-----------------+-------+
```

* 设置最大连接数。

```shell
mysql> set GLOBAL max_connections = 200;
Query OK, 0 rows affected (0.00 sec)

mysql> show variables like '%max_connections%';
+-----------------+-------+
| Variable_name   | Value |
+-----------------+-------+
| max_connections | 200   |
+-----------------+-------+
```

* 当前使用连接数。

```shell
mysql> show global status like 'Max_used_connections';
+----------------------+-------+
| Variable_name        | Value |
+----------------------+-------+
| Max_used_connections | 102   |
+----------------------+-------+
```

---

## 6. 命令

### 6.1. 数据库

* 展示数据库。

```shell
show databases;
```

* 选择数据库。

```shell
use <xxx>
```

* 建库。

```shell
CREATE DATABASE IF NOT EXISTS mytest DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_general_ci;
```

---

### 6.2. 表

* 展示数据库表。

```shell
show tables;
```

* 建表。

```shell
CREATE TABLE `test_async_mysql` (
    `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
    `value` varchar(32) NOT NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4; 
```

* 查数据。

```shell
select value from mytest.test_async_mysql where id = 1;
```

* 插入数据。

```shell
insert into mytest.test_async_mysql (value) values ('hello world');
```

* 改数据。

```shell
update mytest.test_async_mysql set value = 'hello world 2' where id = 1;
```

* 删除数据。

```shell
delete from mytest.test_async_mysql where id = 1;
```

---

## 7. 参考

* [CentOS 7.4使用yum源安装MySQL 5.7.20](http://www.linuxidc.com/Linux/2017-12/149614.htm)
* [You must reset your password using ALTER USER statement before executing thi](https://blog.csdn.net/qq_38366063/article/details/100736999)
* [Mysql 主从复制配置](https://www.jianshu.com/p/8b95dba5b191)
* [is not allowed to connect to this mysql server](https://blog.csdn.net/iiiiiilikangshuai/article/details/100905996)
* [MySQL 连接数满情况的处理](https://www.jianshu.com/p/6689474434f7)
* [MySQL连接数Max_used_connections过多处理方法](https://blog.csdn.net/chenludaniel/article/details/102752598)
* [Mysql数据库慢查询日志的使用](https://zhuanlan.zhihu.com/p/113429595)
* [mysql慢日志 :slow query log 分析数据](https://blog.csdn.net/saga_gallon/article/details/72897332)
* [数据库 \| mysql慢日志查询](https://zhuanlan.zhihu.com/p/85565647)
* [【MySQL优化】——看懂explain](https://blog.csdn.net/jiadajing267/article/details/81269067)