---
layout: post
title:  "fork 进程测试 copy-on-write"
categories: Linux
tags: fork copy-on-write
author: wenfh2020
---

父进程 fork 子进程后，子进程通过 `copy-on-write` 模式获得父进程内存，也就是子进程共用了大部分父进程内存，只有当子进程在修改自己进程内存后，共享部分，才会把那些修改的拷贝出来，这样可以节省系统大量内存分配。



* content
{:toc}

---

## 1. 系统

macos

---

## 2. 测试

测试对象申请一块内存，主进程 fork 子进程后监测子进程对内存数据修改前后状况。

![子进程数据修改前](/images/2020-03-11-10-09-06.png){: data-action="zoom"}

![子进程数据修改后](/images/2020-03-11-10-09-21.png){: data-action="zoom"}

> 测试进程跑得比较快，跑了两次去抓图，所以两次抓图的进程不一样。感兴趣的朋友可以拿[源码](https://github.com/wenfh2020/c_test/blob/master/normal/proc.cpp)测试下。

---

## 3. 测试源码

[源码](https://github.com/wenfh2020/c_test/blob/master/normal/proc.cpp)

```c++
alloc_data g_data;

int main() {
    pid_t pid = fork();
    if (0 == pid) {
        printf("child pid: %d, data ptr: %#lx\n", getpid(),
               (unsigned long)&g_data);
        sleep(5);  // update data before
        printf("child pid: %d, reset data:\n", getpid());
        g_data.reset();
        sleep(5);  // update data later
        exit(0);
    } else if (pid > 0) {
        printf("parent pid: %d, data ptr: %#lx\n", getpid(),
               (unsigned long)&g_data);
    } else {
        printf("fork fail\n");
        exit(1);
    }

    printf("parent end, pid: %d\n", getpid());
    return 0;
}
```

---

## 4. 测试结果

```shell
alloc, data ptr: 0x602140, array ptr: 0x602148
parent pid: 29118, data ptr: 0x602140
child pid: 29126, data ptr: 0x602140
child pid: 29126, reset data:
reset data, data ptr: 0x602140, array ptr: 0x602148
delete data, pid: 29126
child 29126 terminated normally with exit status = 0
sig_child_handler end, errno: 0
parent end, pid: 29118
delete data, pid: 29118
```

1. 子进程拷贝父进程的数据，数据地址（虚拟地址）是一样的。
2. 父进程 alloc 了一次数据，delete 了两次数据，子进程只是拷贝了父进程数据，没有跑父进程 fork 前的代码逻辑。
3.子进程有自己的独立空间， 子进程修改数据后，copy-on-write，子进程空间将分配新的数据空间存储新数据（top 查看进程负载情况）。

---

## 5. 参考

* 《深入理解计算机系统》第二部分，8.4 章 进程控制

---

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
