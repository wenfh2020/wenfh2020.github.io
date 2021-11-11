---
layout: post
title:  "[kimserver] 分布式系统-多进程框架节点通信"
categories: kimserver
tags: kimserver nodes contact
author: wenfh2020
---

[kimserver](https://github.com/wenfh2020/kimserver) 是多进程框架，在分布式系统里，多进程节点之间是如何进行通信的，客户端与分布式服务集群的通信流程是怎么样的，本章主要讲解这些问题。




* content
{:toc}

---

## 1. 流程

### 1.1. 客户端与服务通信

![client 与 server 通信流程](/images/2020-11-10-10-41-39.png){:data-action="zoom"}

---

### 1.2. 服务节点通信

A 节点与 B 节点数据透传 --> A1 与 B1 子进程建立通信。

* A1 创建 socket fd。
* A1 连接 B 节点 ip / port -->  A1 连接 B0。
* A1 connect 异步返回结果，触发读写事件。
* A1 与 B0 连接成功，A1 发送连接信息（type / ip / port / index）给 B0。
* B0 接收到 A1 发的数据，将 fd 透传给对应的子进程 B1，A1 与 B1 连接成功。（[《[kimserver] 父子进程传输文件描述符》](https://wenfh2020.com/2020/10/23/kimserver-socket-transfer/)
* B1 将自己的 type / ip / port / index 信息回传给 A1。
* A1 收到 B1 回包，将 B1 的 fd 保存起来。
* A1 与 B1 的通道被打通后，发送缓冲区里等待发送的的业务数据包。

![分布式系统节点通信详细流程](/images/2020-11-10-10-29-50.png){:data-action="zoom"}

---

## 2. 源码

核心逻辑在 `sys_cmd.h/sys_cmd.cpp` 文件里实现。

kimserver 作为异步服务，核心功能是把异步的逻辑封装在 `Cmd` 沙盒里，但是系统内部节点通信逻辑复杂，逻辑牵涉到多种数据结构调用，而且分开多个 `Cmd` 模块，让逻辑更加零散，维护起来，会让人云里雾绕。

所以笔者，将系统的父子进程异步通信逻辑集中在一个文件里实现，逻辑相对清晰，而且方便维护。

---

### 2.1. 实现逻辑

![源码逻辑](/images/2020-11-25-08-54-00.png){:data-action="zoom"}

---

### 2.2. 接入

节点间相互连接的接口调用，主要参考 `network.cpp/auto_send` 函数的实现。

```cpp
/* network.cpp */
bool Network::auto_send(const std::string& host, int port, int worker_index,
                        const MsgHead& head, const MsgBody& body) {
    ...
    /* 创建 socket，等待连接。 */
    fd = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
    if (fd == -1) {
        LOG_ERROR("client connect server failed! errstr: %s", m_errstr);
        return false;
    }

    /* 创建连接对象。 */
    c = create_conn(fd);
    if (c == nullptr) {
        close_fd(fd);
        LOG_ERROR("create conn failed! fd: %d", fd);
        return false;
    }
    ...
    /* 关注连接读事件。 */
    w = m_events->add_read_event(fd, c->get_ev_io(), this);
    if (w == nullptr) {
        LOG_ERROR("add read event failed! fd: %d", fd);
        goto error;
    }

    /* 关注连接写事件。 */
    w = m_events->add_write_event(fd, w, this);
    if (w == nullptr) {
        LOG_ERROR("add write event failed! fd: %d", fd);
        goto error;
    }
    ...
    /* 设置连接状态为准备连接，需要先建立节点间的通信才算真正连接成功。 */
    c->set_state(Connection::STATE::TRY_CONNECT);

    /* 将需要发送的数据，添加进等待发送缓存，当连接成功后，进行发送。 */
    if (c->conn_write_waiting(head, body) == Codec::STATUS::ERR) {
        LOG_ERROR("write waiting data failed! fd: %d", fd);
        goto error;
    }

    /* 添加连接超时时钟。 */
    if (!add_io_timer(c, 1.5)) {
        LOG_ERROR("add io timer failed! fd: %d", fd);
        goto error;
    }

    /* A1 connect to B1, and save B1's connection.
     * 记录节点连接信息。*/
    node_id = format_nodes_id(host, port, worker_index);
    m_node_conns[node_id] = c;
    c->set_node_id(node_id);
    /* 启动链接。 */
    connect(fd, (struct sockaddr*)&saddr, sizeof(struct sockaddr));
    ...
}
```

---

### 2.3. 协议处理流程

节点相互连接协议通信实现，详细信息，参考源码实现。

```cpp
/* auto_send(...)
 * A1 contact with B1. (auto_send func)
 *
 * A1: node A's worker.
 * B0: node B's manager.
 * B1: node B's worker.
 *
 * process_sys_message(.)
 * 1. A1 connect to B0. (inner host : inner port)
 * 2. A1 send CMD_REQ_CONNECT_TO_WORKER to B0.
 * 3. B0 send CMD_RSP_CONNECT_TO_WORKER to A1.
 * 4. B0 transfer A1's fd to B1.
 * 5. A1 send CMD_REQ_TELL_WORKER to B1.
 * 6. B1 send CMD_RSP_TELL_WORKER A1.
 * 7. A1 send waiting buffer to B1.
 * 8. B1 send ack to A1.
 */
Cmd::STATUS SysCmd::process(Request& req) {
    return (m_net->is_manager()) ? process_manager_msg(req) : process_worker_msg(req);
}

Cmd::STATUS SysCmd::process_manager_msg(Request& req) {
    LOG_TRACE("process manager message.");
    switch (req.msg_head()->cmd()) {
        case CMD_REQ_CONNECT_TO_WORKER: {
            return on_req_connect_to_worker(req);
        }
        ...
        default: {
            return Cmd::STATUS::UNKOWN;
        }
    }
}

Cmd::STATUS SysCmd::process_worker_msg(Request& req) {
    /* worker. */
    LOG_TRACE("process worker's msg, head cmd: %d, seq: %u",
              req.msg_head()->cmd(), req.msg_head()->seq());

    switch (req.msg_head()->cmd()) {
        case CMD_RSP_CONNECT_TO_WORKER: {
            return on_rsp_connect_to_worker(req);
        }
        case CMD_REQ_TELL_WORKER: {
            return on_req_tell_worker(req);
        }
        case CMD_RSP_TELL_WORKER: {
            return on_rsp_tell_worker(req);
        }
        ...
        default: {
            return Cmd::STATUS::UNKOWN;
        }
    }
}
```
