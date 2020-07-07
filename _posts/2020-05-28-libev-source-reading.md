---
layout: post
title:  "libev 源码理解方式"
categories: c/c++
tags: libev
author: wenfh2020
---

理解 libev 工作流程，[官方文档](http://pod.tst.eu/http://cvs.schmorp.de/libev/ev.pod#code_ev_timer_code_relative_and_opti) 和网上有很多资料可以查阅（[事件库之Libev（一）](https://my.oschina.net/u/917596/blog/176658)，[随笔分类 - libev](https://www.cnblogs.com/gqtcgq/category/1043758.html)）。libev 源码，宏的使用频率比较高，也因为这样，源码理解起来比较费脑，可以展开宏查阅源码，或者通过调试方式，理解 libev 的工作流程。redis-ae 事件管理与 libev 有点类似，也可以相互比较一下。




* content
{:toc}


---

## 1. 展开宏

程序编译流程：预编译，编译，汇编器，链接。预编译阶段，还没涉及程序语义解析，可以将文件的宏进行展开。

libev 核心逻辑在 `ev.c` 文件，对这个文件进行预编译（其它文件也可以参考这个方法）。

```shell
gcc -E ev.c -o ev.i
```

* 宏展开前

```c
// ev.c
void noinline
ev_timer_start (EV_P_ ev_timer *w) EV_THROW
{
  if (expect_false (ev_is_active (w)))
    return;

  ev_at (w) += mn_now;

  assert (("libev: ev_timer_start called with negative timer repeat value", w->repeat >= 0.));

  EV_FREQUENT_CHECK;

  ++timercnt;
  ev_start (EV_A_ (W)w, timercnt + HEAP0 - 1);
  array_needsize (ANHE, timers, timermax, ev_active (w) + 1, EMPTY2);
  ANHE_w (timers [ev_active (w)]) = (WT)w;
  ANHE_at_cache (timers [ev_active (w)]);
  upheap (timers, ev_active (w));

  EV_FREQUENT_CHECK;

  /*assert (("libev: internal timer heap corruption", timers [ev_active (w)] == (WT)w));*/
}
```

* 宏展开后

```c
// ev.i
void __attribute__ ((__noinline__))
ev_timer_start (struct ev_loop *loop, ev_timer *w)
{
  if (__builtin_expect ((!!((0 + ((ev_watcher *)(void *)(w))->active))),(0)))
    return;

  ((WT)(w))->at += ((loop)->mn_now);
  ...
  do { } while (0);

  ++((loop)->timercnt);
  ev_start (loop, (W)w, ((loop)->timercnt) + (4 - 1) - 1);
  if (__builtin_expect ((!!((((W)(w))->active + 1) > (((loop)->timermax)))),(0))) { int __attribute__ ((__unused__)) ocur_ = (((loop)->timermax)); (((loop)->timers)) = (ANHE *)array_realloc (sizeof (ANHE), (((loop)->timers)), &(((loop)->timermax)), (((W)(w))->active + 1)); ; };
  (((loop)->timers) [((W)(w))->active]).w = (WT)w;
  (((loop)->timers) [((W)(w))->active]).at = (((loop)->timers) [((W)(w))->active]).w->at;
  upheap (((loop)->timers), ((W)(w))->active);

  do { } while (0);
}
```

---

## 2. gdb 调试

1. 下载 libev 源码：[源码地址](http://dist.schmorp.de/libev/)
   > 地址如果打不开，可能被墙了。
2. 修改源码目录下的 configure 文件，将所有编译优化项（CFLAGS），修改为 CFLAGS="-g O0"。
3. 编译安装源码：./configure && make && make install
4. gdb 调试测试源码。

> 详细请参考：[gdb & libev 调试视频](https://www.bilibili.com/video/BV1U54y1D7uM/)

![libev 调试](/images/2020-05-28-21-04-53.png){:data-action="zoom"}

---

## 3. 对比 redis-ae

redis 事件管理 `aeEventLoop` 与 libev 类似。总体来说，libev 要比 redis 功能丰富实用，redis 不用 libev，可能 redis 作者希望源码更可控。

* libev 处理事件类型更丰富，`aeEventLoop` 只处理了文件事件和时钟事件。
* redis `aeEventLoop` 有 `beforesleep` 和 `aftersleep` 等操作处理。

```c
void aeMain(aeEventLoop *eventLoop) {
    eventLoop->stop = 0;
    while (!eventLoop->stop) {
        if (eventLoop->beforesleep != NULL)
            eventLoop->beforesleep(eventLoop);
        aeProcessEvents(eventLoop, AE_ALL_EVENTS|AE_CALL_AFTER_SLEEP);
    }
}
```

* libev 很多源码细节做得更好，例如：
  1. 时钟，redis 用的是列表存储（不优化的原因，目前时钟事件并不多，暂时没有改进的必要），而 libev 用数组存储时钟事件，通过堆排序，过期策略做得非常高效。
  2. 例如 epoll_ctl 出现重复插入事件错误（EEXIST），libev 会主动进行修改 EPOLL_CTL_MOD。而 redis 这种场景，就直接返回错误，让用户处理了。

```c
// libev - ev_epoll.c
static void epoll_modify (EV_P_ int fd, int oev, int nev) {
    ...
    if (expect_true (!epoll_ctl (backend_fd, oev && oldmask != nev ? EPOLL_CTL_MOD : EPOLL_CTL_ADD, fd, &ev)))
      return;
    ...
    // 错误处理。
    else if (expect_true (errno == EEXIST))
    {
      /* EEXIST means we ignored a previous DEL, but the fd is still active */
      /* if the kernel mask is the same as the new mask, we assume it hasn't changed */
      if (oldmask == nev)
        goto dec_egen;

      if (!epoll_ctl (backend_fd, EPOLL_CTL_MOD, fd, &ev))
        return;
    }
    ...
}

// redis - ep_epoll.c
static int aeApiAddEvent(aeEventLoop *eventLoop, int fd, int mask) {
    aeApiState *state = eventLoop->apidata;
    struct epoll_event ee = {0}; /* avoid valgrind warning */
    /* If the fd was already monitored for some event, we need a MOD
     * operation. Otherwise we need an ADD operation. */
    int op = eventLoop->events[fd].mask == AE_NONE ?
            EPOLL_CTL_ADD : EPOLL_CTL_MOD;

    ee.events = 0;
    mask |= eventLoop->events[fd].mask; /* Merge old events */
    if (mask & AE_READABLE) ee.events |= EPOLLIN;
    if (mask & AE_WRITABLE) ee.events |= EPOLLOUT;
    ee.data.fd = fd;
    if (epoll_ctl(state->epfd,op,fd,&ee) == -1) return -1;
    return 0;
}
```

---

## 4. 参考

* [官网](http://software.schmorp.de/pkg/libev.html)
* [官方源码](http://dist.schmorp.de/libev/)
* [官方文档](http://pod.tst.eu/http://cvs.schmorp.de/libev/ev.pod#code_ev_timer_code_relative_and_opti)
* [事件库之Libev（一）](https://my.oschina.net/u/917596/blog/176658)
* [随笔分类 - libev](https://www.cnblogs.com/gqtcgq/category/1043758.html)
* [[redis 源码走读] 事件 - 定时器](https://wenfh2020.com/2020/04/06/ae-timer/)
* [[redis 源码走读] 事件 - 文件事件](https://wenfh2020.com/2020/04/09/redis-ae-file/)
* [Libev轻网络库 源码浅析](http://chenzhenianqing.com/articles/1051.html)
* [__builtin_expect 说明](https://www.jianshu.com/p/2684613a300f)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/2020/05/28/libev-source-reading/)
