---
layout: post
title:  "探索惊群 ④ - nginx - accept_mutex"
categories: nginx kernel
tags: linux nginx thundering herd
author: wenfh2020
---

由主进程创建的 listen socket，要被 fork 出来的子进程共享，但是为了避免多个子进程同时争抢共享资源，nginx 采用一种策略：使得多个子进程，同一时段，只有一个子进程能获取资源，就不存在共享资源的争抢问题。

成功获取锁的，能获取一定数量的资源，而其它没有成功获取锁的子进程，不能获取资源，只能等待成功获取锁的进程释放锁后，nginx 多进程再重新进入锁竞争环节。



* content
{:toc}

---

1. [探索惊群 ①](https://wenfh2020.com/2021/09/25/thundering-herd/)
2. [探索惊群 ② - accept](https://wenfh2020.com/2021/09/27/thundering-herd-accept/)
3. [探索惊群 ③ - nginx 惊群现象](https://wenfh2020.com/2021/09/29/nginx-thundering-herd/)
4. [探索惊群 ④ - nginx - accept_mutex（★）](https://wenfh2020.com/2021/10/10/nginx-thundering-herd-accept-mutex/)
5. [探索惊群 ⑤ - nginx - NGX_EXCLUSIVE_EVENT](https://wenfh2020.com/2021/10/11/thundering-herd-nginx-epollexclusive/)
6. [探索惊群 ⑥ - nginx - reuseport](https://wenfh2020.com/2021/10/12/thundering-herd-tcp-reuseport/)
7. [探索惊群 ⑦ - 文件描述符透传](https://wenfh2020.com/2021/10/13/thundering-herd-transfer-socket/)

---

## 1. 配置

nginx 通过修改配置开启 accept_mutex 功能特性。

```shell
# vim /usr/local/nginx/conf/nginx.conf
events {
    ...
    accept_mutex on;
    ...
}
```

---

## 2. 解决方案

### 2.1. 负载均衡

nginx 子进程通过抢共享锁 🔐 实现负载均衡，现在用下面的伪代码去理解它的实现原理。

```c
int main() {
    efd = epoll_create();

    while (1) {
        if (is_disabled) {
            ...
            /* 不抢，但是为了避免一直不抢，也要递减它的 disable 程度。*/
            is_disabled = reduce_disabled();
        } else {
            /* 抢。*/
            if (try_lock()) {
                /* 抢锁成功，epoll 关注 listen_fd 的 POLLIN 事件。 */
                if (!is_locked) {
                    epoll_ctl(efd, EPOLL_CTL_ADD, listen_fd, ...);
                    is_locked = true;
                }
            } else {
                if (is_locked) {
                    /* 抢锁失败，epoll 不再关注 listen_fd 事件。 */
                    epoll_ctl(efd, EPOLL_CTL_DEL, listen_fd, ...);
                    is_locked = false;
                }
            }
        }

        /* 超时等待链接资源到来。 */
        n = epoll_wait(...)
        if (n > 0) {
            if (is_able_to_accept) {
                /* 链接资源到来，取出链接。*/
                client_fd = accept();
                /* 每次取出链接后，重新检查 disabled 值。*/
                is_disabled = check_disabled();
            }
        }

        if (is_locked) {
            unlock();
        }
    }

    return 0;
}
```

nginx 通过 `ngx_accept_disabled` 负载均衡数值控制抢锁的时机，每次 accept 完链接资源后，都检查一下它。

```c
ngx_accept_disabled = ngx_cycle->connection_n / 8 - ngx_cycle->free_connection_n;
```

connection_n 最大连接数是固定的；free_connection_n 空闲连接数是变化的。只有在 ngx_accept_disabled > 0 的情况下，进程才不愿意抢锁，换句话说，就是已使用链接大于总链接的 7/8 了，`空闲链接快用完了，原来拥有锁的进程才不会频繁去抢锁`。

```c
/* src/event/ngx_event.c */
ngx_int_t ngx_accept_disabled;   /* 资源分配负载均衡值。 */

/* src/event/ngx_event_accept.c */
void ngx_event_accept(ngx_event_t *ev) {
    ...
    do {
        ...
#if (NGX_HAVE_ACCEPT4)
        if (use_accept4) {
            s = accept4(lc->fd, &sa.sockaddr, &socklen, SOCK_NONBLOCK);
        } else {
            s = accept(lc->fd, &sa.sockaddr, &socklen);
        }
#else
        s = accept(lc->fd, &sa.sockaddr, &socklen);
#endif
        ...
        /* 每次 accept 链接资源后，都检查一下负载均衡数值。*/
        ngx_accept_disabled = ngx_cycle->connection_n / 8
                              - ngx_cycle->free_connection_n;

        c = ngx_get_connection(s, ev->log);
        ...
    } while (ev->available);
}

/* src/event/ngx_event.c */
void ngx_process_events_and_timers(ngx_cycle_t *cycle) {
    ...
    if (ngx_use_accept_mutex) {
        if (ngx_accept_disabled > 0) {
            /* ngx_accept_disabled > 0，说明很少空闲链接了，放弃抢锁。 */
            ngx_accept_disabled--;
        } else {
            /* 通过锁竞争，获得获取资源的权限。 */
            if (ngx_trylock_accept_mutex(cycle) == NGX_ERROR) {
                return;
            }
            ...
        }
    }
    ...
}
```

---

### 2.2. 独占资源

#### 2.2.1. 概述

核心逻辑在这个函数 `ngx_trylock_accept_mutex`，获得锁的子进程，可以将共享的 listen socket 通过 epoll_ctl 添加到事件驱动进行监控，当有资源到来时，子进程通过 epoll_wait 获得通知处理。而没有获得锁的子进程的 epoll 没有关注 listen socket 的事件，所以它们的 epoll_wait 是不会通知 listen socket 的事件。

<div align=center><img src="/images/2021/2021-10-11-12-57-59.png" data-action="zoom"/></div>

---

#### 2.2.2. 源码分析

通过调试查看函数调用的堆栈工作流程。

```shell
# 子进程获取锁添加然后 listen socket 逻辑。
ngx_trylock_accept_mutex (cycle=0x72a6a0) at src/event/ngx_event_accept.c:323
# 子进程循环处理网络事件和时钟事件函数。
0x0000000000442059 in ngx_process_events_and_timers (cycle=0x72a6a0) at src/event/ngx_event.c:223
# 子进程工作逻辑。
0x000000000044f7c2 in ngx_worker_process_cycle (cycle=0x72a6a0, data=0x0) at src/os/unix/ngx_process_cycle.c:719
0x000000000044c804 in ngx_spawn_process (cycle=0x72a6a0, proc=0x44f714 <ngx_worker_process_cycle>, data=0x0, name=0x4da39f "worker process", respawn=-3) at src/os/unix/ngx_process.c:199
0x000000000044eb1e in ngx_start_worker_processes (cycle=0x72a6a0, n=2, type=-3) at src/os/unix/ngx_process_cycle.c:344
0x000000000044e31c in ngx_master_process_cycle (cycle=0x72a6a0) at src/os/unix/ngx_process_cycle.c:130
0x000000000040bdcf in main (argc=1, argv=0x7fffffffe578) at src/core/nginx.c:383
```

> 参考：[gdb 调试 nginx（附视频）](https://wenfh2020.com/2021/06/25/gdb-nginx/)

可以通过下面源码分析查看抢锁的流程。

```shell
ngx_worker_process_cycle
|-- ngx_process_events_and_timers
    |-- ngx_trylock_accept_mutex
     if |-- ngx_shmtx_trylock
        |-- ngx_enable_accept_events
            |-- ngx_add_event
                |-- epoll_ctl(efd, EPOLL_CTL_ADD, listen_fd, ...);
   else |-- ngx_disable_accept_events
            |-- ngx_del_event
                |-- epoll_ctl(efd, EPOLL_CTL_DEL, listen_fd, ...);
    |-- ngx_process_events
    |-- ngx_shmtx_unlock
```

```c
/* src/event/ngx_event.c */
ngx_shmtx_t           ngx_accept_mutex;      /* 进程共享互斥锁。 */
ngx_uint_t            ngx_use_accept_mutex;  /* accept_mutex 开启状态。 */
ngx_uint_t            ngx_accept_mutex_held; /* 表示当前进程是否可以获取资源。 */
ngx_int_t             ngx_accept_disabled;   /* 资源分配负载均衡值。 */

/* src/os/unix/ngx_process_cycle.c 
 * 子进程循环处理事件。*/
static void ngx_worker_process_cycle(ngx_cycle_t *cycle, void *data) {
    ...
    for ( ;; ) {
        ...
        ngx_process_events_and_timers(cycle);
        ...
    }
}

/* src/event/ngx_event.c 
 * 定时器事件和网络事件处理。*/
void ngx_process_events_and_timers(ngx_cycle_t *cycle) {
    ...
    if (ngx_use_accept_mutex) {
        /* 当 ngx_accept_disabled 越小，那么就越快执行抢锁的逻辑。 */
        if (ngx_accept_disabled > 0) {
            ngx_accept_disabled--;
        } else {
            /* 通过锁竞争，获得获取资源的权限。 */
            if (ngx_trylock_accept_mutex(cycle) == NGX_ERROR) {
                return;
            }
            ...
        }
    }
    ...
    /* 处理事件。 */
    (void) ngx_process_events(cycle, timer, flags);
    ...
    if (ngx_accept_mutex_held) {
        /* 释放锁。 */
        ngx_shmtx_unlock(&ngx_accept_mutex);
    }
    ...
}

/* src/event/ngx_event_accept.c */
ngx_int_t ngx_trylock_accept_mutex(ngx_cycle_t *cycle) {
    /* 尝试获得锁。 */
    if (ngx_shmtx_trylock(&ngx_accept_mutex)) {
        ...
        if (ngx_accept_mutex_held && ngx_accept_events == 0) {
            return NGX_OK;
        }

        /* 将 listen socket 添加到 epoll 事件驱动里。 */
        if (ngx_enable_accept_events(cycle) == NGX_ERROR) {
            ngx_shmtx_unlock(&ngx_accept_mutex);
            return NGX_ERROR;
        }

        ngx_accept_events = 0;
        /* 修改持锁的状态。 */
        ngx_accept_mutex_held = 1;

        return NGX_OK;
    }

    if (ngx_accept_mutex_held) {
        /* 获取锁失败，如果之前是曾经成功获取锁的，不能再获取资源了，将 listen socket 从 epoll 里删除。 */
        if (ngx_disable_accept_events(cycle, 0) == NGX_ERROR) {
            return NGX_ERROR;
        }

        /* 改变持锁的状态。 */
        ngx_accept_mutex_held = 0;
    }

    return NGX_OK;
}

/* 子进程 epoll_ctl 关注 listen socket 事件。 */
ngx_int_t ngx_enable_accept_events(ngx_cycle_t *cycle) {
    ngx_uint_t         i;
    ngx_listening_t   *ls;
    ngx_connection_t  *c;

    ls = cycle->listening.elts;
    for (i = 0; i < cycle->listening.nelts; i++) {
        c = ls[i].connection;
        ...
        /* 将共享的 listen socket 通过 epoll_ctl 添加到子进程的 epoll 中，
         * 当该 socket 有新的链接进来，epoll_wait 会通知处理。  */
        if (ngx_add_event(c->read, NGX_READ_EVENT, 0) == NGX_ERROR) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}

/* 子进程 epoll_ctl 取消关注 listen socket 事件。 */
static ngx_int_t ngx_disable_accept_events(ngx_cycle_t *cycle, ngx_uint_t all) {
    ngx_uint_t         i;
    ngx_listening_t   *ls;
    ngx_connection_t  *c;

    ls = cycle->listening.elts;
    for (i = 0; i < cycle->listening.nelts; i++) {
        c = ls[i].connection;
        ...
        /* 子进程将共享的 listen socket 从 epoll 中删除，不再关注它的事件。 */
        if (ngx_del_event(c->read, NGX_READ_EVENT, NGX_DISABLE_EVENT)
            == NGX_ERROR)
        {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}
```

---

#### 2.2.3. 抢锁成功率

很多时候，原来抢到锁的进程，大概率会重新抢到锁，原因在于 `抢锁时机`。

1. 原来抢到锁的进程，在抢到锁后会先处理完事件（`ngx_process_events`），然后才会释放锁，在这个过程中，其它进程一直抢不到：因为它们都是盲目地抢，不知道锁什么时候释放，而抢到锁的进程它释放锁后，自己马上抢回，相对于其它进程盲目地抢，它的成功率更高。😎
2. 原来抢到锁的进程，什么时候才会不抢呢，就是要满足这个条件：ngx_accept_disabled > 0。因为 ngx_accept_disabled = ngx_cycle->connection_n / 8 - ngx_cycle->free_connection_n，一般情况下，当已使用链接超过了 7/8 了，也就是说**空闲链接快用完了**，才不愿意抢锁了。如果配置的链接总数很大，那么预分配的空闲链接没那么快用完，那么原进程就一直抢，因为它一释放锁就马上去抢，它抢到锁的成功率自然高！😂

所以基于上面两个条件，可能会导致：有些进程很忙，有些进程比较闲。

---

## 3. 缺点

1. nginx 是多进程框架，accept_mutex 解决惊群的策略，使得在同一个时间段，多个子进程始终只有一个子进程可以 accept 链接资源，这样，不能充分利用其它子进程进行并发处理，在密集的短链接场景中，链接的吞吐将会遇到瓶颈。
2. 避免了内核抢锁问题，转换为应用层抢锁，虽然抢的频率降低，但是进程多了，抢锁效率依然是个问题。
3. 通过 `ngx_accept_disabled` 去解决负载均衡问题，因为上述抢锁时机问题，可能会导致某个子进程长时间占用锁，其它子进程得不到 accept 链接资源的机会。😂

---

通过 nginx 的更新日志，我们发现 2016 年这个 accept_mutex 功能被默认关闭。

```shell
Changes with nginx 1.11.3                                        26 Jul 2016

    *) Change: now the "accept_mutex" directive is turned off by default.
    ...
```

---

## 4. 参考

* [Nginx的accept_mutex配置](https://blog.csdn.net/adams_wu/article/details/51669203)
* [Nginx 是如何解决 epoll 惊群的](https://ld246.com/article/1588731832846)
* [关于ngx_trylock_accept_mutex的一些解释](https://blog.csdn.net/brainkick/article/details/9081017)
