---
layout: post
title:  "高性能服务异步通信逻辑"
categories: 网络
tags: async
author: wenfh2020
---

最近整理了一下服务程序异步通信逻辑思路。异步逻辑与同步逻辑处理差别比较大，异步逻辑可能涉及多次回调才能完成一个请求处理，逻辑被碎片化，切分成串行的步骤。习惯了写同步逻辑的朋友，有可能思维上转不过来。



* content
{:toc}

---

* 高性能异步非阻塞服务，底层一般用多路复用 I/O 模型对事件进行管理，Linux 平台用 epoll。
* epoll 支持异步事件逻辑。epoll_wait 会将就绪事件从内核中取出进行处理。
* 服务处理事件，每个 fd 对应一个事件处理器 callback 处理取出的 events。
* callback 逻辑被分散为逻辑步骤 `step`，这些步骤一般是异步串行处理，时序跟同步差不多，只是异步逻辑可能需要回调多次才能处理完一个完整的逻辑。

![高性能异步框架通信流程](/images/2020-06-11-21-28-24.png){:data-action="zoom"}

> 设计图来源：《[异步服务框架通信流程](https://www.processon.com/view/5ee1d7de7d9c084420107b53)》

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/2020/06/11/server-async-logic/)
