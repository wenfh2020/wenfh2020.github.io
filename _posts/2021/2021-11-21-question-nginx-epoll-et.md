---
layout: post
title:  "[知乎回答] Nginx为啥使用ET模式Epoll？"
categories: 知乎 nginx kernel epoll
tags: working
author: wenfh2020
---

[**知乎问题**](https://www.zhihu.com/question/21202701/answer/2230298669)：

Web服务器nginx使用ET模式的epoll。我想问，它相对LT模式epoll有哪些优势呢？另外一篇帖子（[epoll的边沿触发模式(ET)真的比水平触发模式(LT)快吗？(当然LT模式也使用非阻塞IO，重点是要求ET模式下的代码不能造成饥饿](https://www.zhihu.com/question/20502870?q=Nginx%E4%B8%BA%E5%95%A5%E4%BD%BF%E7%94%A8ET%E6%A8%A1%E5%BC%8FEpoll%EF%BC%9F))）说ET不一定比LT快，那么为什么要使用ET模式呢？




* content
{:toc}

---

## 1. 源码

这个问题，其实回到了 epoll 的 LT 与 ET 模式的区别。

看过 epoll 内核源码的朋友可能都会很惊讶，LT 和 ET 的区别核心就几行代码，主要看 Linux 内核的 eventpoll.c 文件这几行源码（[github](https://github.com/torvalds/linux/blob/42eb8fdac2fc5d62392dcfcf0253753e821a97b0/fs/eventpoll.c#L1700)）。

```c
/* Linux 5.0.1 - fs/eventpoll.c */
static __poll_t ep_send_events_proc(struct eventpoll *ep,
                                    struct list_head *head, void *priv) {
    ...
    /* 遍历处理 txlist（原 ep->rdllist 数据）就绪队列结点，
     * 获取事件拷贝到用户空间。*/
    list_for_each_entry_safe(epi, tmp, head, rdllink) {
        if (esed->res >= esed->maxevents) 
            break;
        ...
        /* 先从就绪队列（头部）删除 epi。*/
        list_del_init(&epi->rdllink);

        /* 获取 epi 对应 fd 的就绪事件。 */
        revents = ep_item_poll(epi, &pt, 1);
        if (!revents)
            /* 如果没有就绪事件，说明就绪事件已经处理完了，就返回。
             * （这时候，epi 已经从就绪队列中删除了。） */
            continue;
        ...
        /* 主要看这一行哈~~~~ */
        else if (!(epi->event.events & EPOLLET)) {
            /* lt 模式，前面删除掉了的就绪事件节点，重新追加到就绪队列尾部。*/
            list_add_tail(&epi->rdllink, &ep->rdllist);
            ...
        }
    }
    ...
}
```

---

## 2. nginx

其实为啥 epoll 会设计 LT 和 ET 两种工作模式呢？我大胆猜测一下它的设计意图：事件处理的紧急程度。

> 举个 🌰：你有急事打电话找人，如果对方一直不接，那你只有一直打，直到他接电话为止，这就是 lt 模式；如果不急，电话打过去对方不接，那就等有空再打，这就是 et 模式。

---

我们接下去分析一下 nginx，使用 strace 命令，可以轻松获得 nginx 的 epoll 相关系统调用。通过 strace 日志你会发现，除了 listen socket 默认是使用 LT 模式的，其它 accept 出来的 client fd，基本都是使用 ET 模式的。

从上面”设计意图“理解，显然 listen socket 要比 accept 出来的 socket 事件紧急度要高啊！因为你不把 listen socket 的链接 accept 出来，哪里来数据处理啊；其次 listen socket 的完全队列长度是有限制的，如果不快点将链接数据捞出来，队列可能就会溢出了，所以 listen socket 采用 LT 模式，当触发可读事件后，内核就一直通知应用层快点调用 accept 将链接取出来。而 accept 出来的 socket 相对来说，优先级就没那么高了，所以设置为 ET 模式，当然将它设置为 LT 模式好像也没什么问题，真的是这样么？

---

## 3. 优先权

在高并发系统里，LT 模式与 ET 模式其实有一个比较容易忽视的差别：新事件处理的”优先“程度。

ET 模式会使得新的其它 client fd 的就绪事件能快速被处理。（在高并发系统里，有海量事件，每个事件都希望自己快点被处理啊~~~）

可以看下图 epoll_wait 的工作时序，假如 epoll_wait 每次最大从内核取一个事件。

<div align=center><img src="/images/2023/2023-07-01-16-02-17.png" data-action="zoom"></div>

如果是 LT 模式，（就绪队列上的节点）epi 节点刚开始在内核被删除，然后数据从内核空间拷贝到用户空间后，内核马上将这个被删除的节点重新追加回就绪队列，这个速度很快，所以后面来的其它的 client fd 的就绪事件很大几率会排在已经处理过的事件后面。

而 ET 模式呢，数据从内核拷贝到用户空间后，内核不会重新将就绪事件节点添加回就绪队列，当事件在用户空间操作完后，用户空间根据需要重新将这个事件通过 epoll_ctl 添加回就绪队列--如果事件还没有完全处理完毕。（又或者这个节点因为有新的数据到来，重新触发了就绪事件而被添加回就绪队列）。从节点被删除到重新添加这个环节，这中间的过程是比较“漫长”的，所以新来的其它事件节点能排在旧的节点前面，能快速处理。

分析到这里，可能大概理解 nginx 使用 LT 和 ET 模式的场景了。

> 这个道理有点像排队打饭，一个队列上，有些同学要打包两份饭，如果每次只能打包一份，lt 模式就是，这些同学打包了一份之后，马上重新回去排队，再打一份。et 模式是，这些同学先打包一份，然后拿回去吃掉了，再回来排队，在高峰期显然整个排队的效率和结果不一样。

---

## 4. 参考

* [[内核源码] epoll lt / et 模式区别](https://wenfh2020.com/2020/06/11/epoll-lt-et/)