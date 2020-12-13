---
layout: post
title:  "libco 协程库学习，测试连接 mysql"
categories: c/c++
tags: libco mysql mysqlclient
author: wenfh2020
---

历史原因，一直使用 libev 作为服务底层；异步框架虽然性能比较高，但新人学习和使用门槛非常高，而且串行的逻辑被打散为状态机，这也会严重影响生产效率。

用同步方式实现异步功能，既保证了异步性能优势，又使得同步方式实现源码思路清晰，容易维护，这是协程的优势。带着这样的目的学习微信开源的一个轻量级网络协程库：[libco](https://github.com/Tencent/libco) 。





* content
{:toc}

---

## 1. 概述

libco 是轻量级的协程库，看完下面几个帖子，应该能搞懂它的工作原理。

1. [微信开源C++协程库Libco—原理与应用](https://blog.didiyun.com/index.php/2018/11/23/libco/)
2. [漫谈微信libco协程设计及实现（万字长文）](https://runzhiwang.github.io/2019/06/21/libco/)
3. [动态链接黑魔法: Hook 系统函数](http://kaiyuan.me/2017/05/03/function_wrapper/)
4. [libco 分析(上)：协程的实现](http://kaiyuan.me/2017/07/10/libco/)
5. [libco 分析(下)：协程的管理](http://kaiyuan.me/2017/10/20/libco2/)

---

## 2. 问题

带着问题学习 libco：

* 搞清这几个概念：阻塞，非阻塞，同步，异步，锁。
* 协程是什么东西，与进程和线程有啥关系。
* 协程解决了什么问题。
* 协程在什么场景下使用。
* 协程切换原理。
* 协程切换时机。
* 协程需要上锁吗？
* libco 主要有啥功能。（协程管理，epoll/kevent，hook）

---

## 3. libco 源码结构布局

将 libco 的源码结构展开，这样方便理清它的内部结构关系。

![源码对象](/images/2020-12-07-22-12-57.png){:data-action="zoom"}

---

## 4. mysql 测试

* 测试目标：测试 libco 协程性能，以及是否能将 mysqlclient 同步接口进行异步改造。
* 测试系统：CentOS Linux release 7.7.1908 (Core)
* 测试源码：[github](https://github.com/wenfh2020/test_libco.git)。
* 测试视频：[gdb & libco & mysql](https://www.bilibili.com/video/bv1QV41187wz)

<div align=center>
<a href="https://www.bilibili.com/video/bv1QV41187wz">
<img src="/images/2020-12-11-21-41-13.png" border="0" width="60%">
</a>
</div>

---

### 4.1. 测试源码

```c++
/* 数据库信息。 */
typedef struct db_s {
    std::string host;
    int port;
    std::string user;
    std::string psw;
    std::string charset;
} db_t;

/* 协程任务。 */
typedef struct task_s {
    int id;            /* 任务 id。 */
    db_t* db;          /* 数据库信息。 */
    MYSQL* mysql;      /* 数据库实例指针。 */
    stCoRoutine_t* co; /* 协程指针。 */
} task_t;

/* 协程处理函数。 */
void* co_handler_mysql_query(void* arg) {
    co_enable_hook_sys();
    ...
    /* 同步方式写数据库访问代码。 */
    for (i = 0; i < g_co_query_cnt; i++) {
        g_cur_test_cnt++;

        /* 读数据库 select。 */
        query = "select * from mytest.test_async_mysql where id = 1;";
        if (mysql_real_query(task->mysql, query, strlen(query))) {
            show_error(task->mysql);
            return nullptr;
        }
        res = mysql_store_result(task->mysql);
        mysql_free_result(res);
    }
    ...
}

int main(int argc, char** argv) {
    ...
    /* 协程个数。 */
    g_co_cnt = atoi(argv[1]);
    /* 每个协程 mysql query 次数。 */
    g_co_query_cnt = atoi(argv[2]);
    /* 数据库信息。 */
    db = new db_t{"127.0.0.1", 3306, "root", "123456", "utf8mb4"};

    for (i = 0; i < g_co_cnt; i++) {
        task = new task_t{i, db, nullptr, nullptr};
        /* 创建协程。 */
        co_create(&(task->co), NULL, co_handler_mysql_query, task);
        /* 唤醒协程。 */
        co_resume(task->co);
    }

    /* 循环处理协程事件逻辑。 */
    co_eventloop(co_get_epoll_ct(), 0, 0);
    ...
}
```

---

## 5. hook

在 Centos 系统，查看 hook 是否成功，除了测试打印日志，其实还有其它比较直观的方法。

---

### 5.1. strace

用 strace 查看底层的调用，我们看到 `mysql_real_connect` 内部的 connect，被 hook 成功，connect 前，被替换为 libco 的 connect 了。socket 在 connect 前，被修改为 `O_NONBLOCK` 。

```shell
# strace -s 512 -o /tmp/libco.log ./test_libco 1 1
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 4
fcntl(4, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(4, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
connect(4, {sa_family=AF_INET, sin_port=htons(3306), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
```

---

### 5.2. gdb

上神器 gdb，在 co_hook_sys_call.cpp 文件的 read 和 write 函数下断点。

命中断点，查看函数调用堆栈，libco 在 Centos 系统能成功 hook 住 mysqlclient 的阻塞接口。

```shell
#0  read (fd=fd@entry=9, buf=buf@entry=0x71fc30, nbyte=nbyte@entry=19404) at co_hook_sys_call.cpp:299
#1  0x00007ffff762b30a in read (__nbytes=19404, __buf=0x71fc30, __fd=9) at /usr/include/bits/unistd.h:44
#2  my_read (Filedes=Filedes@entry=9, Buffer=Buffer@entry=0x71fc30 "", Count=Count@entry=19404, MyFlags=MyFlags@entry=0)
    at /export/home/pb2/build/sb_0-37309218-1576675139.51/rpm/BUILD/mysql-5.7.29/mysql-5.7.29/mysys/my_read.c:64
#3  0x00007ffff7624966 in inline_mysql_file_read (
    src_file=0x7ffff78424b0 "/export/home/pb2/build/sb_0-37309218-1576675139.51/rpm/BUILD/mysql-5.7.29/mysql-5.7.29/mysys/charset.c", 
    src_line=383, flags=0, count=19404, buffer=0x71fc30 "", file=9)
    at /export/home/pb2/build/sb_0-37309218-1576675139.51/rpm/BUILD/mysql-5.7.29/mysql-5.7.29/include/mysql/psi/mysql_file.h:1129
#4  my_read_charset_file (loader=loader@entry=0x7ffff7ed7270, filename=filename@entry=0x7ffff7ed7320 "/usr/share/mysql/charsets/Index.xml", 
    myflags=myflags@entry=0) at /export/home/pb2/build/sb_0-37309218-1576675139.51/rpm/BUILD/mysql-5.7.29/mysql-5.7.29/mysys/charset.c:383
```

---

## 6. 压测结果

从测试结果看，单进程单线程，多个协程是同时进行的，“并发”量也随着协程个数增加而增加，跟测试预期一样。

```shell
# ./test_libco 1 10000
id: 0, test cnt: 10000, cur spend time: 1.778823
total cnt: 10000, total time: 1.790962, avg: 5583.591448

# ./test_libco 2 10000
id: 0, test cnt: 10000, cur spend time: 2.328348
id: 1, test cnt: 10000, cur spend time: 2.360431
total cnt: 20000, total time: 2.373994, avg: 8424.620726

# ./test_libco 3 10000
id: 0, test cnt: 10000, cur spend time: 2.283759
id: 2, test cnt: 10000, cur spend time: 2.352147
id: 1, test cnt: 10000, cur spend time: 2.350272
total cnt: 30000, total time: 2.370038, avg: 12658.024719
```

---

## 7. 小结

* 通过学习其他大神的帖子，和走读源码，终于对协程有了比较清晰的认知。
* 测试 libco，Centos 功能正常，但 MacOS 下不能成功 Hook 住阻塞接口。
* libco 是轻量级的，它主要应用于高并发的 IO 密集型场景，所以你看到它绑定了多路复用模型。从测试来看，虽然支持 MacOS 和 Linux，但是只有 Linux 是好用的。
* libco 很不错，所以我选择 golang 🐶。

---

## 8. 参考

* [云风 coroutine 协程库源码分析](https://www.cyhone.com/articles/analysis-of-cloudwu-coroutine/)
* [微信 libco 协程库源码分析](https://www.cyhone.com/articles/analysis-of-libco/)
* [C/C++协程库libco：微信怎样漂亮地完成异步化改造](https://blog.csdn.net/shixin_0125/article/details/78848561)
* [单机千万并发连接实战](https://zhuanlan.zhihu.com/p/21378825)
* [【腾讯Bugly干货分享】揭秘：微信是如何用libco支撑8亿用户的](https://segmentfault.com/a/1190000007407881)
* [简述 Libco 的 hook 层技术](https://blog.csdn.net/liushengxi_root/article/details/88421227)
* [动态链接黑魔法: Hook 系统函数](http://kaiyuan.me/2017/05/03/function_wrapper/)
* [libco 分析(上)：协程的实现](http://kaiyuan.me/2017/07/10/libco/)
* [libco 分析(下)：协程的管理](http://kaiyuan.me/2017/10/20/libco2/)
* [协程](https://blog.csdn.net/liushengxi_root/category_8548171.html)
* [Linux进程-线程-协程上下文环境的切换与实现](https://zhuanlan.zhihu.com/p/254883122)
* [微信开源C++协程库Libco—原理与应用](https://blog.didiyun.com/index.php/2018/11/23/libco/)
* [腾讯协程库libco的原理分析](https://blog.csdn.net/brainkick/article/details/48676403?utm_source=blogxgwz1)
* [C++ 协程的近况、设计与实现中的细节和决策](https://www.jianshu.com/p/837bb161793a)
* [漫谈微信libco协程设计及实现（万字长文）](https://runzhiwang.github.io/2019/06/21/libco/)
* [Android PLT hook 概述](https://caikelun.io/post/2018-05-01-android-plt-hook-overview/)
