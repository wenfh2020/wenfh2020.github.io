---
layout: post
title:  "[redis 源码走读] sentinel 哨兵"
categories: redis
tags: redis sentinel
author: wenfh2020
---

redis 有主从数据复制功能。多个实例通过读写分离，使得单进程的 redis 可以充分利用多核性能。

一般情况下 master 可读可写，slave 只读。当 master 节点掉线或异常退出后，redis 集群只剩下 slave 节点，它们不支持写操作。这时必须重新找一个 master，方法就是从剩下的 slave 节点中，选出一个，并把它角色转变为 master，使得 redis 集群能恢复工作。

这时故障转移管理者 `sentinel` 应运而生。它负责 redis 集群管理工作，保证高可用性能。



* content
{:toc}

---

## 1. sentinel 作用

1. 监控： 检查 redis 节点健康状况。
2. 故障转移：当 redis 集群节点出现故障时，及时自动进行故障转移。
3. 通知：检测到 redis 实例出现故障，通过 api 进行通知用户。
4. 提供配置：用户可以查询当前 redis 集群节点信息。例如：查询哪个 redis 节点是 master，哪个是 slave。

> 故障检测，故障发现，故障转移。

---

## 2. 节点关系

1. sentinel 节点间相互链接通信。
2. sentinel 每个节点与 redis 每个节点相互链接通信。
3. redis 节点 master 与 slave 相互链接通信，数据复制需要。slave 之间一般不相互链接通信，除非是 `slave` 与 `sub-slave` 关系。

> sentinel 之间的通信，sentinel 与 redis 节点间的通信。

![高可用节点通信关系](/images/2020-06-06-15-48-59.png){:data-action="zoom"}

---

## 3. 故障转移流程

需要多个 sentinel 确认 redis 节点掉线，并选举其中一个 sentinel 作为 leader 进行故障转移。

1. 其中一个 sentinel 监控到 master 掉线。该 master 被认为是主观掉线。
2. 所有 sentinel 都监控到 master 掉线，要把 master 确认为客观掉线。
3. 从 sentinel 中选出一个 sentinel 作为 leader 对 redis 集群进行故障转移。
4. sentienl leader 从剩余的 slave 中，选出一个，并将其设置为 master。

---

## 4. 问题

1. 选举流程。
2. 监控故障。
3. 发现故障，主客观掉线。
4. 故障转移流程。
5. sentinel 与 redis 通信流程。

---

## 5. 参考

* [Redis Sentinel Documentation](https://redis.io/topics/sentinel)
* [[redis 源码走读] 主从数据复制（上）](https://wenfh2020.com/2020/05/17/redis-replication/)
* [[redis 源码走读] 主从数据复制（下）](https://wenfh2020.com/2020/05/31/redis-replication-next/)
* 《redis 实现与设计》
* [分布式算法之选举算法Raft](https://blog.csdn.net/cainaioaaa/article/details/79881296)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
