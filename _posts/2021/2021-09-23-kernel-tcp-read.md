---
layout: post
title:  "[内核源码] Linux 网络数据接收读取流程（TCP）- NAPI"
categories: kernel
tags: linux kernel tcp receive
author: wenfh2020
---

走读 Linux（5.0.1）源码，理解 TCP 网络数据接收和读取工作流程（NAPI）。

要搞清楚数据的接收和读取流程，需要梳理这几个角色之间的关系：网卡（e1000），主存，CPU，网卡驱动，内核，应用程序。




* content
{:toc}

---

## 1. 简述

简述数据接收处理流程。

1. 网卡（NIC）接收数据。
2. 网卡通过 DMA 方式将接收到的数据写入主存。
3. 网卡通过硬中断通知 CPU 处理主存上的数据。
4. 网卡驱动（NIC driver）启用软中断，消费主存上的数据。
5. 内核（TCP/IP）协议层层处理数据，将数据缓存到对应的 socket 上。
6. 应用程序读取对应 socket 上已接收的数据。

<div align=center><img src="/images/2021-11-19-17-49-58.png" data-action="zoom"/></div>

> 图片来源：《图解 TCP_IP》

---

## 2. 总流程

1. 网卡驱动注册到内核，方便内核与网卡进行交互。
2. 内核启动网卡，为网卡工作分配资源（ring buffer）和注册硬中断处理 e1000_intr。
3. 网卡（NIC）接收数据。
4. 网卡通过 DMA 方式将接收到的数据写入主存（步骤 2 内核通过网卡驱动将 DMA 内存地址信息写入网卡寄存器，使得网卡获得 DMA 内存信息）。
5. 网卡触发硬中断，通知 CPU 已接收数据。
6. CPU 收到网卡的硬中断，调用对应的处理函数 e1000_intr。
7. 网卡驱动函数先禁止网卡中断，避免频繁硬中断，降低内核的工作效率。
8. 网卡驱动将 napi_struct.poll_list 挂在 softnet_data.poll_list 上，方便后面软中断调用 napi_struct.poll 获取网卡数据。
9. 然后启用 NET_RX_SOFTIRQ -> net_rx_action 内核软中断。
10. 内核软中断线程消费网卡 DMA 方式写入主存的数据。
11. 内核软中断遍历 softnet_data.poll_list，调用对应的 napi_struct.poll -> e1000_clean 读取网卡 DMA 方式写入主存的数据。
12. e1000_clean 遍历 ring buffer 通过 dma_sync_single_for_cpu 接口读取 DMA 方式写入主存的数据，并将数据拷贝到 e1000_copybreak 创建的 skb 包。
13. 网卡驱动读取到 skb 包后，将该包传到协议层处理（e1000_receive_skb），处理过的 skb 包将会追加到 socket.sock.sk_receive_queue 队列，等待应用处理。接下来如果 read / epoll_wait 阻塞等待读取数据，那么唤醒进程/线程。
14. 网卡驱动读取了网卡写入的数据后，需要清理已读的（ring buffer）数据，而且要通知网卡已读（ring buffer）数据的位置，将位置信息写入网卡 RDT 寄存器，方便网卡继续工作（writel(i, hw->hw_addr + rx_ring->rdt)）。
15. 网卡驱动重新设置允许网卡触发硬中断，重新触发步骤 3，接收数据。
16. 用户程序（或被唤醒）调用 read 接口读取 socket.sock.sk_receive_queue 上的数据并拷贝到用户空间。

<div align=center><img src="/images/2021-12-28-12-21-49.png" data-action="zoom"/></div>

---

## 3. 要点

网卡 PCI 驱动，NAPI 中断缓解技术，软硬中断，DMA 内存直接访问技术。

* 源码结构关系。

<div align=center><img src="/images/2021-12-26-22-09-16.png" data-action="zoom"/></div>

* 要点关系。

<div align=center><img src="/images/2021-12-28-12-27-31.png" data-action="zoom"/></div>

---

### 3.1. 网卡驱动

网卡是硬件，内核通过网卡驱动控制网卡。

网卡 e1000 的 intel 驱动（e1000_driver）在 linux 目录：drivers/net/ethernet/intel/e1000

驱动注册（e1000_probe）到内核，启动网卡（e1000_open），为网卡分配系统资源，方便内核与网卡进行交互。

> [PCI](https://baike.baidu.com/item/PCI%E6%80%BB%E7%BA%BF/132135?fr=aladdin) 是 Peripheral Component Interconnect (外设部件互连标准) 的缩写，它是目前个人电脑中使用最为广泛的接口，几乎所有的主板产品上都带有这种插槽。

---

### 3.2. NAPI

NAPI ([New API](https://en.wikipedia.org/wiki/New_API)) 中断缓解技术，它是 Linux 上采用的一种提高网络处理效率的技术。一般情况下，网卡接收到数据，通过硬中断通知 CPU 进行处理，但是当网卡有大量数据进来时，频繁的中断使得网卡和CPU处理效率低下，所以系统采用了中断+轮询技术，提升数据接收效率（详细流程请参考上面的总流程图）。

> 举个🌰：餐厅人少时，客户点菜，服务员可以一对一提供服务，客户点一个菜，服务员记录一下；但是人多了，服务员就忙不过来了，服务员每张桌子给一张菜单，客户慢慢看，选好菜了，就通知服务员处理，这样效率就高很多了。

---

### 3.3. 中断

中断分上下半部。

1. 上半部硬中断主要保存数据，网卡通过硬中断通知 CPU 有数据到来。
2. 下半部 CPU 通过软中断处理接收的数据。

* 注册中断。

```shell
# 内核启动初始化，注册软中断。
kernel_init
|-- net_dev_init
    |-- open_softirq(NET_RX_SOFTIRQ, net_rx_action);

##########################################

# ioctl 接口触发开启网卡。
ksys_ioctl
|-- do_vfs_ioctl
    |-- __dev_open
        |-- e1000_configure
            |-- e1000_configure_rx
                |-- adapter->clean_rx = e1000_clean_rx_irq; # 软中断处理接收数据包。
        |-- e1000_request_irq
            |-- request_irq(adapter->pdev->irq, e1000_intr, ...); # 注册 NIC 硬中断 e1000_intr。
```

* 硬中断处理。

```shell
do_IRQ
|-- e1000_intr
    |-- ew32(IMC, ~0); # 禁止 NIC 硬中断。
    |-- __napi_schedule
        |-- list_add_tail(&napi->poll_list, &sd->poll_list); # 将 napi poll 挂在 softnet_data 上。
        |-- __raise_softirq_irqoff(NET_RX_SOFTIRQ); # 开启软中断。
```

* 软中断。

```shell
# 软中断，处理数据包，放进 socket buffer，数据包处理完后，开启硬中断。
__do_softirq
|-- net_rx_action
    |-- napi_poll # 遍历 softnet_data.poll_list
        |-- e1000_clean
            |-- e1000_clean_rx_irq
                |-- e1000_receive_skb
                    |-- napi_gro_receive
                        |-- napi_skb_finish
                            |-- ip_rcv
                                |-- tcp_v4_rcv
            |-- e1000_irq_enable # 开启 NIC 硬中断。
```

---

### 3.4. DMA

DMA（Direct Memory Access）可以使得外部设备可以不用 CPU 干预，直接把数据传输到内存，这样可以解放 CPU，提高系统性能。它是 NAPI 中断缓解技术，实现的重要一环。

#### 3.4.1. 网卡与驱动交互

1. 系统通过 ring buffer 环形缓冲区管理内存描述符，通过一致性 DMA 映射（`dma_alloc_coherent`）描述符数组，方便 CPU 和网卡同步访问。
2. 环形缓冲区内存描述符指向的内存通过 DMA 流式映射（`dma_map_single`），提供网卡写入。
3. 网卡接收到数据，写入网卡缓存。
4. 当网卡开始收到一个完整的数据包后，通过硬中断通知 CPU。
5. CPU 接收到硬中断，禁止网卡再触发硬中断，然后唤醒 CPU 软中断。
6. 软中断从主存中读取处理网卡 DMA 方式写入的数据（skb），并将数据交给网络层处理。
7. 在有限的时间内一定数量的主存上的数据处理完后，系统将空闲的（ring buffer）内存描述符提供给网卡，方便网卡下次写入。
8. 重新开启网卡硬中断，走上述步骤 3。

---

#### 3.4.2. ring buffer

例如：e1000 网卡环形缓冲区（`e1000_rx_ring`）。

系统分配内存缓冲区，映射为 DMA 内存，提供网卡直接访问。

下面描述了 NIC <--> DMA <--> RAM 三者之间的关系。

<div align=center><img src="/images/2021-12-25-06-12-34.png" data-action="zoom"/></div>

> 图片来源：[stack overflow](https://stackoverflow.com/questions/47450231/what-is-the-relationship-of-dma-ring-buffer-and-tx-rx-ring-for-a-network-card?answertab=votes#tab-top)

* ring buffer 数据结构。

```c
/* drivers/net/ethernet/intel/e1000/e1000.h */
/* board specific private data structure */
struct e1000_adapter {
    ...
    /* RX */
    bool (*clean_rx)(struct e1000_adapter *adapter,
             struct e1000_rx_ring *rx_ring,
             int *work_done, int work_to_do);
    void (*alloc_rx_buf)(struct e1000_adapter *adapter,
                 struct e1000_rx_ring *rx_ring,
                 int cleaned_count);
    struct e1000_rx_ring *rx_ring;      /* One per active queue */
    ...
};

#ifdef CONFIG_ARCH_DMA_ADDR_T_64BIT
typedef u64 dma_addr_t;
#else
typedef u32 dma_addr_t;
#endif

struct e1000_rx_ring {
    /* pointer to the descriptor ring memory */
    void *desc; /* 内存描述符（e1000_rx_desc）数组。 */
    /* physical address of the descriptor ring */
    dma_addr_t dma; /* e1000_rx_desc 数组的一致性 DMA 地址。 */
    /* length of descriptor ring in bytes */
    unsigned int size; /* e1000_rx_desc 数组占用空间大小。 */
    /* number of descriptors in the ring */
    unsigned int count; /* e1000_rx_desc 描述符个数。 */
    /* next descriptor to associate a buffer with */
    unsigned int next_to_use; /* 刷新最新空闲内存位置，写入网卡寄存器通知网卡（网卡接着上次最后的写入位置，可以一直写到 next_to_use 这个位置）。*/
    /* next descriptor to check for DD status bit */
    unsigned int next_to_clean; /* Descriptor Done 标记下次要从该位置取出数据。*/
    /* array of buffer information structs */
    struct e1000_rx_buffer *buffer_info; /* 流式 DMA 内存，提供网卡通过内存描述符访问内存，DMA 方式写入数据。 */
    struct sk_buff *rx_skb_top;

    /* cpu for rx queue */
    int cpu;

    u16 rdh;
    u16 rdt;
};

/* 描述符指向的内存块（skb）。 */
struct e1000_rx_buffer {
    union {
        struct page *page; /* jumbo: alloc_page */
        u8 *data; /* else, netdev_alloc_frag */
    } rxbuf;
    dma_addr_t dma;
};

/* Receive Descriptor - 内存描述符。*/
struct e1000_rx_desc {
    /* buffer_addr 指向 e1000_rx_buffer.dma 地址。*/
    __le64 buffer_addr; /* Address of the descriptor's data buffer */
    __le16 length;      /* Length of data DMAed into data buffer */
    __le16 csum;        /* Packet checksum */
    /* status：网卡写入数据到内存描述符对应的内存块，当前内存数据状态。 */
    u8 status;          /* Descriptor status */
    u8 errors;          /* Descriptor Errors */
    __le16 special;
};
```

* 工作流程。

```shell
e1000_open
|-- e1000_setup_all_tx_resources
    |-- e1000_setup_tx_resources
        |-- txdr->desc = dma_alloc_coherent # 一致性 DMA 映射内存描述符（CPU 和网卡可以同步访问）。
|-- e1000_configure(adapter);
    |-- e1000_alloc_rx_buffers
        |-- e1000_alloc_frag # 分配数据接收空间 skb。
        |-- dma_map_single(..., DMA_FROM_DEVICE) # 流式 DMA 映射内存到网卡设备。
        |-- writel(i, hw->hw_addr + rx_ring->rdt); # 将新的空闲描述符位置，写入网卡寄存器，通知网卡获取重新写入数据。

# 软中断调用驱动接口，从主存上读取网卡写入的数据，
__do_softirq
|-- net_rx_action
    |-- napi_poll
        |-- e1000_clean
            |-- e1000_clean_rx_irq
                |-- e1000_copybreak # 从网卡写入主存的数据（skb），拷贝一份出来。
                    |-- e1000_alloc_rx_skb # 创建一个新的 skb，方便数据拷贝。
                    |-- dma_sync_single_for_cpu # 驱动通过该接口访问网卡 DMA 方式写入的数据。
                    |-- skb_put_data # 将数据写入 skb。
                |-- e1000_receive_skb # 从 ring buffer 取出网卡写入的数据。
                |-- e1000_alloc_rx_buffers # 对应的 DMA 内存已经被系统读取，那么将该空闲的内存信息传递给网卡重新写入数据。（这个函数，不展开了，参考上面相应描述。）
```

* ring buffer 偏移原理。
  
  e1000_rx_ring.desc 指针指向了一个 e1000_rx_desc 数组，网卡和网卡驱动都通过这个数组进行读写数据。这个数组被称为 `环形缓冲区`：通过数组下标遍历数组，下标指向数组末位后，重新指向数组第一个位置，看起来像个环形结构，——理解它需要些抽象思维；因为网卡和网卡驱动都操作它，所以每个对象都维护了自己的一套 `head` 和 `tail` 进行标识。

1. 初始状态，下标都指向数组一个元素 偏移原理。e1000_rx_ring.desc[0]。
2. 网卡接收到数据通过 DMA 方式拷贝到主存（e1000_rx_ring.desc[i] -> e1000_rx_buffer），如下图，NIC.RDH 顺时针偏移，NIC.RDT 到 NIC.RDH 的 e1000_rx_desc (->e1000_rx_buffer) 都填充了接收数据。
3. 网卡驱动顺时针遍历 ring buffer，根据 e1000_rx_ring.desc[i].status 状态，读取 e1000_rx_ring.desc[i] 指向的 e1000_rx_buffer 数据块，因为读取数据有时间限制和读取数据权值限制，网卡驱动不一定能完全读取完成网卡写入主存的数据，所以最后读取的数据位置要标识起来，通过 e1000_rx_ring.next_to_clean 记录下一次要读取的数据位置。
4. 既然网卡驱动已经读取了数据，那么已读取的数据已经没用了，可以清理掉，提供给网卡继续写，顺时针清理，把清理到的位置记录起来 e1000_rx_ring.next_to_use，下次继续清理。
5. 但是这时候网卡还不知道驱动消费了哪些数据，那么驱动清理掉数据后，将已清理最后的位置（e1000_rx_ring.next_to_use - 1）通过写入网卡寄存器 RDT，告诉网卡，下次可以写入数据，从 NIC.RDH 到 NIC.RDT。

<div align=center><img src="/images/2021-12-28-17-46-31.png" data-action="zoom"/></div>

---

## 4. 参考

* 《Linux 内核源码剖析 - TCP/IP 实现》
* [What is the relationship of DMA ring buffer and TX/RX ring for a network card?](https://stackoverflow.com/questions/47450231/what-is-the-relationship-of-dma-ring-buffer-and-tx-rx-ring-for-a-network-card?answertab=votes#tab-top)
* [Linux网络协议栈：NAPI机制与处理流程分析（图解）](https://blog.csdn.net/Rong_Toa/article/details/109401935)
* [NAPI机制分析](https://sites.google.com/site/emmoblin/smp-yan-jiu/napi)
* [图解Linux网络包接收过程](https://blog.csdn.net/zhangyanfei01/article/details/110621887?spm=1001.2014.3001.5501)
* [Linux e1000网卡驱动流程](https://blog.csdn.net/hui6075/article/details/51196056?spm=1001.2014.3001.5501)
* [(转)网络数据包收发流程(三)：e1000网卡和DMA](http://blog.sina.com.cn/s/blog_858820890102w0a9.html)
* [linux网络流程分析（一）---网卡驱动](https://www.cnblogs.com/gogly/archive/2012/06/10/2541573.html)
* [Cache和DMA一致性](https://zhuanlan.zhihu.com/p/109919756)
* [dma基础_一文读懂dma的方方面面](https://zhuanlan.zhihu.com/p/413978652)
* [Linux网络系统原理笔记](https://blog.csdn.net/qq_33588730/article/details/105177754)
* [Linux 基础之网络包收发流程](https://blog.csdn.net/yangguosb/article/details/103562983)
* [如果让你来设计网络](https://mp.weixin.qq.com/s?__biz=Mzk0MjE3NDE0Ng%3D%3D&idx=1&mid=2247489907&scene=21&sn=a296cb42467cab6f0a7847be32f52dae#wechat_redirect)
* [Linux网络 - 数据包的接收过程](https://segmentfault.com/a/1190000008836467)
* [Linux网络包收发总体过程](https://www.cnblogs.com/zhjh256/p/12227883.html)
* [NAPI模式--中断和轮询的折中以及一个负载均衡的问题](https://blog.csdn.net/dog250/article/details/5302853)
* [【互联网后台技术】网卡的ring buffer调整](http://blog.sina.com.cn/s/blog_7f2122c50100v7tg.html)
* [网卡收包流程](https://mp.weixin.qq.com/s/UhF2KCASoIhTiKXPFOPiww)
* [15 \| 网络优化（上）：移动开发工程师必备的网络优化知识](https://blog.csdn.net/ChinaDragon10/article/details/109635774)
* [网卡的 Ring Buffer 详解](https://www.cnblogs.com/mauricewei/p/10502300.html)
* [Redis高负载下的中断优化](https://mp.weixin.qq.com/s?__biz=MjM5NjQ5MTI5OA%3D%3D&mid=2651747704&idx=3&sn=cd76ad912729a125fd56710cb42792ba)
* [1. 网卡收包](https://www.jianshu.com/p/3b5cee1e88a2)
* [2. NAPI机制](https://www.jianshu.com/p/7d4e36c0abe8)
* [3. GRO机制](https://www.jianshu.com/p/376ce301da65)
* [网络收包流程-报文从网卡驱动到网络层（或者网桥)的流程（非NAPI、NAPI）(一)](https://blog.csdn.net/hzj_001/article/details/100085112)
* [深入理解Linux网络技术内幕 第10章 帧的接收](https://blog.csdn.net/weixin_44793395/article/details/106593127)
* [数据包如何从物理网卡到达云主机的应用程序？](https://vcpu.me/packet_from_nic_to_user_process/)
