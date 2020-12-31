---
layout: post
title:  "[libco] libco 工作流程"
categories: libco
tags: libco workflow
author: wenfh2020
---

libco 设计初衷：为了方便编写高性能网络服务。

高性能网络服务主要有两个点：IO 非阻塞 + 多路复用技术。

1. libco 使用 hook 技术解决非阻塞问题。
2. libco 事件驱动使用 (epoll/kevent)。

但是 `非阻塞 + 多路复用技术` 这个是异步回调实现方式，对用户开发非常不友好，所以协程的引入就是为了解决这个问题：用同步写代码方式实现异步功能，既保证了系统性能，又避免了复杂的异步回调逻辑。

---

libco 有三大模块：协程管理模块，hook 模块，多路复用事件驱动模块，我们看看这三大模块如何结合起来运转。




* content
{:toc}

---

## 1. 测试

我们通过 lldb 调试 `mysql_real_connect` 工作流程，查看 libco 三大模块是如何结合起来的。（[github 测试源码](https://github.com/wenfh2020/test_libco.git)）

```c++
void* co_handler_mysql_query(void* arg) {
    co_enable_hook_sys();
    ...
    if (task->mysql == nullptr) {
        task->mysql = mysql_init(NULL);
        if (!mysql_real_connect(
                task->mysql,
                db->host.c_str(),
                db->user.c_str(),
                db->psw.c_str(),
                "mysql",
                db->port,
                NULL, 0)) {
            ...
        }
    }
    ...
}

int main(int argc, char** argv) {
    ...
    db = new db_t{"127.0.0.1", 3306, "topnews", "topnews2016", "utf8mb4"};

    for (i = 0; i < g_co_cnt; i++) {
        task = new task_t{i, db, nullptr, nullptr};
        co_create(&(task->co), NULL, co_handler_mysql_query, task);
        co_resume(task->co);
    }
    co_eventloop(co_get_epoll_ct(), 0, 0);
    ...
}
```

---

## 2. 调用流程

1. 创建唤醒协程进入工作状态。
2. 遇到 connect 阻塞，通过 hook 技术，设置非阻塞。
3. 添加 fd 事件到事件驱动。
4. 将本协程切出挂起，等待事件回调唤醒。
5. 主协程监控就绪事件，等待通知唤醒工作协程。

```shell
co_create -> co_resume -> CoRoutineFunc -> co_handler_mysql_query -> socket -> fcntl(O_NONBLOCK) -> connect -> epoll_ctl(EPOLL_CTL_ADD) -> co_yield

epoll_wait -> co_resume -> co_handler_mysql_query --> epoll_ctl(EPOLL_CTL_DELETE)
```

<div align=center><img src="/images/2020-12-28-15-23-42.png" data-action="zoom"/></div>

---

### 2.1. hook

`mysql_real_connect` 为了连接 mysql 服务，创建 socket；socket 函数被 libco 成功“拦截”。

```shell
* thread #1: tid = 20679, 0x0000000000404773 test_libco`socket(domain=2, type=1, protocol=6) + 17 at co_hook_sys_call.cpp:205, name = 'test_libco', stop reason = breakpoint 1.1
    frame #0: 0x0000000000404773 test_libco`socket(domain=2, type=1, protocol=6) + 17 at co_hook_sys_call.cpp:205
  * frame #1: 0x00007f78e3427371 libmysqlclient.so.20`mysql_real_connect(mysql=0x0000000000a7e080, host=0x0000000000a57088, user=0x0000000000a570b8, passwd=0x0000000000a570e8, db=0x00000000004083bd, port=3306, unix_socket=0x0000000000000000, client_flag=0) + 2401 at client.c:4313
    frame #2: 0x0000000000401f4f test_libco`co_handler_mysql_query(arg=0x0000000000a57130) + 189 at test_libco.cpp:89
    frame #3: 0x0000000000402895 test_libco`CoRoutineFunc(co=0x0000000000a59730, (null)=0x0000000000000000) + 50 at co_routine.cpp:387
```

---

### 2.2. 非阻塞

在 libco 的 socket 实现函数里，通过 `fcntl` 将 fd 属性设置为非阻塞（`O_NONBLOCK`）。

```shell
* thread #1: tid = 20679, 0x00000000004058c5 test_libco`fcntl(fildes=16, cmd=4) + 87 at co_hook_sys_call.cpp:573, name = 'test_libco', stop reason = step in
  * frame #0: 0x00000000004058c5 test_libco`fcntl(fildes=16, cmd=4) + 87 at co_hook_sys_call.cpp:573
    frame #1: 0x0000000000404828 test_libco`socket(domain=2, type=1, protocol=6) + 198 at co_hook_sys_call.cpp:218
    frame #2: 0x00007f78e3427371 libmysqlclient.so.20`mysql_real_connect(mysql=0x0000000000a7e080, host=0x0000000000a57088, user=0x0000000000a570b8, passwd=0x0000000000a570e8, db=0x00000000004083bd, port=3306, unix_socket=0x0000000000000000, client_flag=0) + 2401 at client.c:4313
    frame #3: 0x0000000000401f4f test_libco`co_handler_mysql_query(arg=0x0000000000a57130) + 189 at test_libco.cpp:89
    frame #4: 0x0000000000402895 test_libco`CoRoutineFunc(co=0x0000000000a59730, (null)=0x0000000000000000) + 50 at co_routine.cpp:387
```

---

```c
int fcntl(int fildes, int cmd, ...) {
    HOOK_SYS_FUNC(fcntl);
    ...
    switch (cmd) {
        ...
        case F_SETFL: {
            int param = va_arg(arg_list, int);
            int flag = param;
            if (co_is_enable_sys_hook() && lp) {
                /* 设置非阻塞。 */
                flag |= O_NONBLOCK;
            }
            ret = g_sys_fcntl_func(fildes, cmd, flag);
            if (0 == ret && lp) {
                lp->user_flag = param;
            }
            break;
        }
        ...
    };
}
```

---

## 3. 事件驱动

1. 子协程通过 epoll_ctl 向 epoll 注册事件。
2. 子协程挂起当前协程，让出 CPU。
3. 主协程通过 `co_eventloop` 循环处理：就绪事件 + 时钟超时事件，并切换到事件对应的子协程。
4. 子协程处理业务完毕，通过 epoll_ctl 向 epoll 删除注册事件。

---

### 3.1. 添加事件

```shell
* thread #1: tid = 20679, 0x0000000000404884 test_libco`connect(fd=16, address=0x0000000000a80870, address_len=16) + 18 at co_hook_sys_call.cpp:233, name = 'test_libco', stop reason = breakpoint 3.1
  * frame #0: 0x0000000000404884 test_libco`connect(fd=16, address=0x0000000000a80870, address_len=16) + 18 at co_hook_sys_call.cpp:233
    frame #1: 0x00007f78e3450c36 libmysqlclient.so.20`vio_socket_connect + 14 at mysql_socket.h:707
    frame #2: 0x00007f78e3450c28 libmysqlclient.so.20`vio_socket_connect(vio=0x0000000000a808f0, addr=0x0000000000a80870, len=16, timeout=-1) + 392 at viosocket.c:940
    frame #3: 0x00007f78e34274e5 libmysqlclient.so.20`mysql_real_connect(mysql=0x0000000000a7e080, host=0x0000000000a57088, user=0x0000000000a570b8, passwd=0x0000000000a570e8, db=0x00000000004083bd, port=3306, unix_socket=0x0000000000000000, client_flag=0) + 2773 at client.c:4380
    frame #4: 0x0000000000401f4f test_libco`co_handler_mysql_query(arg=0x0000000000a57130) + 189 at test_libco.cpp:89
    frame #5: 0x0000000000402895 test_libco`CoRoutineFunc(co=0x0000000000a59730, (null)=0x0000000000000000) + 50 at co_routine.cpp:387
```

---

```c
int connect(int fd, const struct sockaddr *address, socklen_t address_len) {
    HOOK_SYS_FUNC(connect);
    ...
    //1.sys call
    int ret = g_sys_connect_func(fd, address, address_len);
    ...
    //2.wait
    int pollret = 0;
    struct pollfd pf = {0};

    for (int i = 0; i < 3; i++) {
        memset(&pf, 0, sizeof(pf));
        pf.fd = fd;
        pf.events = (POLLOUT | POLLERR | POLLHUP);

        /* 关联事件驱动，获取事件处理结果。 */
        pollret = poll(&pf, 1, 25000);

        if (1 == pollret) {
            break;
        }
    }
    ...
}

int poll(struct pollfd fds[], nfds_t nfds, int timeout) {
    HOOK_SYS_FUNC(poll);
    ...
    if (nfds_merge == nfds || nfds == 1) {
        /* 关联事件驱动，切换当前协程。 */
        ret = co_poll_inner(co_get_epoll_ct(), fds, nfds, timeout, g_sys_poll_func);
    }
    ...
}

int co_poll_inner(stCoEpoll_t *ctx, struct pollfd fds[], nfds_t nfds, int timeout, poll_pfn_t pollfunc) {
    ...
    int epfd = ctx->iEpollFd;
    stCoRoutine_t *self = co_self();

    //1.struct change
    /* fd 关联协程。 */
    stPoll_t &arg = *((stPoll_t *)malloc(sizeof(stPoll_t)));
    memset(&arg, 0, sizeof(arg));

    arg.iEpollFd = epfd;
    arg.fds = (pollfd *)calloc(nfds, sizeof(pollfd));
    arg.nfds = nfds;
    ...
    arg.pfnProcess = OnPollProcessEvent;
    arg.pArg = GetCurrCo(co_get_curr_thread_env());

    //2. add epoll
    for (nfds_t i = 0; i < nfds; i++) {
        ...
        if (fds[i].fd > -1) {
            ev.data.ptr = arg.pPollItems + i;
            ev.events = PollEvent2Epoll(fds[i].events);
            /* 向事件驱动添加关注 fd 事件。 */
            int ret = co_epoll_ctl(epfd, EPOLL_CTL_ADD, fds[i].fd, &ev);
            ...
        }
        //if fail,the timeout would work
    }

    //3.add timeout
    /* 事件添加时钟，避免超时。 */
    unsigned long long now = GetTickMS();
    arg.ullExpireTime = now + timeout;
    int ret = AddTimeout(ctx->pTimeout, &arg, now);
    int iRaiseCnt = 0;
    if (ret != 0) {
        co_log_err("CO_ERR: AddTimeout ret %d now %lld timeout %d arg.ullExpireTime %lld",
                   ret, now, timeout, arg.ullExpireTime);
        errno = EINVAL;
        iRaiseCnt = -1;
    } else {
        /* 将当前协程挂起，唤醒其它协程。等待事件驱动事件通知或者时钟过期。 */
        co_yield_env(co_get_curr_thread_env());
        /* 协程挂起后被唤醒，从这行代码开始执行。 */
        iRaiseCnt = arg.iRaiseCnt;
    }
    ...
    {
        //clear epoll status and memory
        RemoveFromLink<stTimeoutItem_t, stTimeoutItemLink_t>(&arg);
        for (nfds_t i = 0; i < nfds; i++) {
            int fd = fds[i].fd;
            if (fd > -1) {
                /* 已获得结果，清除事件数据。 */
                co_epoll_ctl(epfd, EPOLL_CTL_DEL, fd, &arg.pPollItems[i].stEvent);
            }
            /* 填充获得的数据。 */
            fds[i].revents = arg.fds[i].revents;
        }
        ...
    }
}
```

---

### 3.2. 事件循环

```shell
* thread #1: tid = 2291, 0x000000000040317e test_libco`OnPollProcessEvent(ap=0x00000000010beb20) + 24 at co_routine.cpp:659, name = 'test_libco', stop reason = step over
  * frame #0: 0x000000000040317e test_libco`OnPollProcessEvent(ap=0x00000000010beb20) + 24 at co_routine.cpp:659
    frame #1: 0x0000000000403426 test_libco`co_eventloop(ctx=0x0000000001093690, pfn=0x0000000000000000, arg=0x0000000000000000)(void*), void*) + 523 at co_routine.cpp:725
    frame #2: 0x0000000000402321 test_libco`main(argc=3, argv=0x00007ffcc7f9bf08) + 499 at test_libco.cpp:153
    frame #3: 0x00007f81bf6f7505 libc.so.6`__libc_start_main + 245
```

```c
void OnPollProcessEvent(stTimeoutItem_t *ap) {
    stCoRoutine_t *co = (stCoRoutine_t *)ap->pArg;
    /* 唤醒协程。 */
    co_resume(co);
}

void co_eventloop(stCoEpoll_t *ctx, pfn_co_eventloop_t pfn, void *arg) {
    ...
    for (;;) {
        /* 主协程通过 epoll_wait 捞出就绪事件。 */
        int ret = co_epoll_wait(ctx->iEpollFd, result, stCoEpoll_t::_EPOLL_SIZE, 1);

        stTimeoutItemLink_t *active = (ctx->pstActiveList);
        stTimeoutItemLink_t *timeout = (ctx->pstTimeoutList);
        ...
        /* 主协程捞出过期事件。 */
        TakeAllTimeout(ctx->pTimeout, now, timeout);
        ...
        Join<stTimeoutItem_t, stTimeoutItemLink_t>(active, timeout);

        lp = active->head;
        while (lp) {
            ...
            /* 主协程挂起当前协程，切换到对应子协程，处理到期事件和就绪事件结果。 */
            if (lp->pfnProcess) {
                lp->pfnProcess(lp);
            }
            lp = active->head;
        }
        ...
    }
}

```

---

## 4. 后记

1. 协程切换跳来跳去，不明白协程切换原理的同学，感觉比异步回调还难理解。libco 将切换部分逻辑封装起来了，使用者在做业务开发时，基本不需要费脑理解 libco 内部是如何调用接口进行协程切换。

2. 关于 libco 的时钟和多路复用驱动逻辑实现，其实 `libev` 实现得不错的，如果能将 `libev` 和 `libco` 整合，应该会少一些造轮子的工夫。但是 `libev` 也有一定的学习成本，而自己造轮子可控，要权衡利弊。

---

## 5. 参考

* [[libco] 协程库学习，测试连接 mysql](https://wenfh2020.com/2020/12/07/libco-learnning/)
* [[libco] 协程切换理解思路]( https://wenfh2020.com/2020/12/17/libco-switch/)
* [[libco] 协程调度](https://wenfh2020.com/2020/12/27/libco-dispatch/)
* [万字长文\|漫谈libco协程设计及实现](https://zhuanlan.zhihu.com/p/73679393)
