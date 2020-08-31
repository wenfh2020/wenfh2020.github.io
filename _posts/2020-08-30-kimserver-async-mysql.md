---
layout: post
title:  "[kimserver] C++ 异步非阻塞 Mysql 连接池"
categories: kimserver
tags: kimserver async mysql pool
author: wenfh2020
---

感觉 `mysql` 非阻塞异步链接很小众，能够搜索出来的资料很少。只要做单进程的异步服务，就绕不开数据库。很幸运，`mariadb` 提供了异步接口，在 github 上找到一个项目（[mysql_async](https://github.com/liujian0616/mysql_async)）是结合 libev 实现的异步项目，正合我意！接下来对其进行改造。




* content
{:toc}

---

## 1. 异步接口文档

Mariadb 提供异步接口，官网文档 [Non-blocking API Reference](https://mariadb.com/kb/en/non-blocking-api-reference/)。

---

## 2. 安装

异步 client driver 需要依赖 mariadb 的 `mariadb-connector-c`，下面是源码安装步骤流程。

* Linux

```shell
sudo yum -y install git gcc openssl-devel make cmake
git clone https://github.com/MariaDB/mariadb-connector-c.git
mkdir build && cd build
cmake ../mariadb-connector-c/ -DCMAKE_INSTALL_PREFIX=/usr
make
sudo make install
```

> [Installing Connector C for Mariadb](https://stackoverflow.com/questions/51603067/installing-connector-c-for-mariadb)

---

* MacOS

`mariadb-connector-c` 依赖 `openssl` 库，根据你的安装路径设置依赖关系：`OPENSSL_ROOT_DIR`， `OPENSSL_LIBRARIES`。

```shell
wget http://mariadb.mirror.iweb.com//connector-c-3.1.9/mariadb-connector-c-3.1.9-src.tar.gz
tar zxf mariadb-connector-c-3.1.9-src.tar.gz
mkdir build && cd build
sudo cmake ../mariadb-connector-c-3.1.9-src/ -DCMAKE_INSTALL_PREFIX=/usr/local -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl -DOPENSSL_LIBRARIES=/usr/local/opt/openssl/lib
sudo make && make install
```

---

## 3. 性能

通过压测，对同步异步工作情况进行对比。用 Mac 机器本地压力测试 10,000 个数据。单进程，单链接，同步异步读写相差不会很大，但是单进程异步客户端支持多条链接同时工作，这样性能就上来了。

 | links | driver | read / s | write / s |
 | :---- | :----- | :------- | :-------- |
 | 1     | sync   | 18913.9  | 2706.23   |
 | 1     | async  | 13576.3  | 3773.74   |
 | 5     | async  | 35166.9  | 12635.7   |
 | 10    | async  | 40861.2  | 17500.7   |

---

## 4. 源码

### 4.1. 原理

虽然是异步非阻塞操作，但是 mysql 不像 redis 的 pipline 那样支持批量处理命令。所以，每个命令都是一个一个发送给 mysql 服务处理的：先处理完成一个，再处理一个，并不是一下子发多个，然后 mysql 返回多个结果，所以单链接的异步处理，与同步处理比较，并没有什么优势可言。但是异步处理，支持多个链接同时并行处理，这样并发就上来了。

测试项目的异步链接池基于 libev 对链接事件进行管理，我们来看看读数据的流程逻辑：

![异步 client 读数据逻辑](/images/2020-08-30-15-11-33.png){:data-action="zoom"}

---

### 4.2. 配置

```json
{
    "database": {
        "test": {
            "host": "127.0.0.1",
            "port": 3306,
            "user": "root",
            "password": "root123!@#",
            "charset": "utf8mb4",
            "max_conn_cnt": 5
        }
    }
}
```

---

### 4.3. 连接池接口

尽量简化连接池接口，只有 3 个对外接口：初始化，读数据，写数据。

> 详细连接池源码可以查看 [github](https://github.com/wenfh2020/kimserver/tree/master/src/core/db)

```c++
/* 回调接口定义. */
typedef void(MysqlExecCallbackFn)(const MysqlAsyncConn*, sql_task_t* task);
typedef void(MysqlQueryCallbackFn)(const MysqlAsyncConn*, sql_task_t* task, MysqlResult* res);

/* 初始化数据库信息，读取配置，加载数据库连接信息。*/
bool init(CJsonObject& config);
/* 写数据接口。*/
bool async_exec(const char* node, MysqlExecCallbackFn* fn, const char* sql, void* privdata = nullptr);
/* 读数据接口。*/
bool async_query(const char* node, MysqlQueryCallbackFn* fn, const char* sql, void* privdata = nullptr);
```

---

### 4.4. 测试源码

* 详细测试源码可以查看 [github](https://github.com/wenfh2020/kimserver/tree/master/src/test/test_mysql/test_async)

```c++
int main(int args, char** argv) {
    ...
     struct ev_loop* loop = EV_DEFAULT;
    kim::DBMgr* pool = new kim::DBMgr(m_logger, loop);
    ...
    for (int i = 0; i < g_test_cnt; i++) {
        if (g_is_write) {
            snprintf(sql, sizeof(sql), 
                "insert into mytest.test_async_mysql (value) values ('%s %d');", "hello world", i);
            if (!pool->async_exec("test", &mysql_exec_callback, sql)) {
                LOG_ERROR("exec sql failed! sql: %s", sql);
                return 1;
            }
        } else {
            snprintf(sql, sizeof(sql), "select value from mytest.test_async_mysql where id = 1;");
            if (!pool->async_query("test", &mysql_query_callback, sql)) {
                LOG_ERROR("quert sql failed! sql: %s", sql);
                return 1;
            }
        }
    }
    ...
}
```

---

## 5. 参考

* [kimserver](https://github.com/wenfh2020/kimserver)
* [mysql_async](https://github.com/liujian0616/mysql_async/)
* [在 C/C++ 异步 I/O 中使用 MariaDB 的非阻塞接口](https://cloud.tencent.com/developer/article/1336510)
* [Non-blocking API Reference](https://mariadb.com/kb/en/non-blocking-api-reference/)

---

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/2020/08/30/kimserver-async-mysql/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
