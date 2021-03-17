---
layout: post
title:  "mysql 常用命令配置"
categories: mysql
tags: mysql config command
author: wenfh2020
---

记录 mysql 常用配置和命令。





* content
{:toc}

---

## 1. 安装

* server

脚本一键安装。安装包默认是 5.6.22 版本，mysql 用户名和密码是 root，可自行修改脚本配置。

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

## 3. 远程访问

允许 `mytest` 用户远程访问。

```shell
mysql> mysql -uroot -proot;
mysql> use mysql;
mysql> update user set host = '%' where user ='mytest';
mysql> flush privileges;
```

---

## 4. 参考

* [Mysql 主从复制配置](https://www.jianshu.com/p/8b95dba5b191)
* [is not allowed to connect to this mysql server](https://blog.csdn.net/iiiiiilikangshuai/article/details/100905996)
