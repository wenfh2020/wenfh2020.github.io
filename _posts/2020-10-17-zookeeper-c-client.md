---
layout: post
title:  "zookeeper-client-c 异步/同步工作方式"
categories: zookeeper
tags: zookeeper sync async c client
author: wenfh2020
---

zookeeper 有 [zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c)，它可以被编译成静态库进行工作。

client 提供了两种接口：同步 / 异步。同步和异步接口都是通过多线程实现。下面通过走读源码，理解它们的工作方式，这样方便我们对它进行二次封装。




* content
{:toc}

---

## 1. Linux 安装

[zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c) 在 [zookeeper](https://github.com/apache/zookeeper) 的子目录下。

* 安装脚本。

```shell
yum install -y ant
yum install -y cppunit-devel
# 下载的是 2018 年的版本，最新版本根据文档，执行 ant 命令会失败。
wget https://github.com/apache/zookeeper/archive/release-3.4.13.tar.gz
tar zxf release-3.4.13.tar.gz
cd zookeeper-release-3.4.13
ant clean jar
ant compile_jute
cd src/c
autoreconf -if
./configure
make && make install
```

* 安装结果。

```shell
# 安装静态库到 /usr/local/lib/ 目录下。
libtool: install: /usr/bin/install -c .libs/libzookeeper_st.a /usr/local/lib/libzookeeper_st.a
...
libtool: install: /usr/bin/install -c .libs/libzookeeper_mt.a /usr/local/lib/libzookeeper_mt.a
...
# 安装对应的头文件到 /usr/local/include 目录下。
/usr/bin/mkdir -p '/usr/local/include/zookeeper'
/usr/bin/install -c -m 644 include/zookeeper.h include/zookeeper_version.h include/zookeeper_log.h include/proto.h include/recordio.h generated/zookeeper.jute.h '/usr/local/include/zookeeper'

```

---

## 2. 使用

[zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c) 同步接口使用，需要添加编译宏 `THREADED`。

这里是别人的封装的轻量级 `同步` [C++ 测试源码](https://github.com/yandaren/zk_cpp)。

---

### 2.1. 编译脚本

* 添加宏 `THREADED`。
* 添加静态库 `zookeeper_mt`。

```shell
# 测试源码编译脚本。
g++ -g -std='c++11' -DTHREADED zk_cpp_test.cpp zk_cpp.cpp -lzookeeper_mt -o test_zk
```

---

### 2.2. 测试源码

即便是同步使用方式，也有部分异步回调的接口。因为监控的节点变化和节点数据变化不是实时发生的。

```c++
/* 监控节点数据变化。 */
void data_change_event(const std::string& path, const std::string& new_value) {...}
/* 监控父节点的子节点变化（添加/删除）。 */
void child_change_events(const std::string& path, const std::vector<std::string>& children) {...}

/* zk_cpp_test.cpp */
int main() {
    ...
    /* 创建 zk client 对象。 */
    utility::zk_cpp zk;

    do {
        /* 初始 zk client 对象。 */
        utility::zoo_rc ret = zk.connect(urls);
        ...
        std::string cmd;
        while (std::cin >> cmd) {
            ...
            else if (cmd == "get") {
                /* 同步获取节点接口。 */
                utility::zoo_rc ret = zk.get_node(path.c_str(), value, nullptr, true);
            }
            ...
            else if (cmd == "watch_data") {
                /* 同步返回当前数据，记录下回调函数，当节点数据有变化异步回调。 */
                utility::zoo_rc ret = zk.watch_data_change(path.c_str(), data_change_event, &value);
            }
            else if (cmd == "watch_child") {
                /* 同步返回当前数据，记录下回调函数，当节点数据有变化异步回调。 */
                utility::zoo_rc ret = zk.watch_children_event(path.c_str(), child_change_events, &children);
            }
            ...
        }
    } while (0);
    ...
}
```

---

## 3. zookeeper-client-c 源码分析

![client 工作流程](/images/2020-10-18-21-59-50.png){:data-action="zoom"}

### 3.1. 创建子线程

`zookeeper-client-c` 初始化时，会创建两个子线程。换句话说，只要使用这个库，最少得有三个线程：主线程 + 两个子线程。

* 网络线程：客户端网络读写 IO。
* 回调线程：已处理完成的请求放进完成队列，进行异步回调。

```c
/* zookeeper.c */
zhandle_t *zookeeper_init(const char *host, ...) {
    ...
    return zookeeper_init_internal(...);
    ...
}

static zhandle_t *zookeeper_init_internal(...) {
    ...
    if (adaptor_init(zh) == -1) {
        goto abort;
    }
    ...
}

int adaptor_init(zhandle_t *zh) {
    ...
    start_threads(zh);
    return 0;
}

/* 启动两个子线程分别处理：客户端请求，服务回调。 */
void start_threads(zhandle_t *zh) {
    ...
    /* 处理客户端网络读写 io。 */
    rc = pthread_create(&adaptor->io, 0, do_io, zh);
    /* 已处理完成的包会放进完成队列，让另外一个线程进行处理。 */
    rc = pthread_create(&adaptor->completion, 0, do_completion, zh);
    ...
}
```

---

### 3.2. 同步异步接口

zk client 与 zk server 通信常用接口。

| 同步             | 异步              | 描述                                             |
| :--------------- | :---------------- | :----------------------------------------------- |
| zoo_create       | zoo_acreate       | 创建节点。                                       |
| zoo_get          | zoo_aget          | 获取节点数据。                                   |
| zoo_exists       | zoo_aexists       | 检查节点是否存在。                               |
| zoo_delete       | zoo_adelete       | 删除节点。                                       |
| zoo_get_children | zoo_aget_children | 获取节点的孩子节点。                             |
| zoo_set_acl      | zoo_aset_acl      | 设置权限控制。                                   |
| zoo_get_acl      | zoo_aget_acl      | 获取节点的权限。                                 |
| \                | zoo_add_auth      | 添加认证，如果认证失败，会异步回调，并断开连接。 |

---

参考节点删除接口，其它接口实现方式大同小异。

* 接口设计风格。
  
  同步接口 `zoo_delete`，异步接口 `zoo_adelete`，接口设计比较简约，接口有前缀 `zoo_`，异步接口在 `zoo_` 后面多了个 `a`。

* 同步。

  `zoo_delete` 同步接口，调用了异步接口 `zoo_adelete`。同步方式其实是给异步接口上锁，直到接口流程处理完毕，才解锁。

```c
/* zookeeper.h */
ZOOAPI int zoo_delete(zhandle_t *zh, const char *path, int version);

/* zookeeper.c */
int zoo_delete(zhandle_t *zh, const char *path, int version) {
    /* 创建锁对象。 */
    struct sync_completion *sc = alloc_sync_completion();
    int rc;
    if (!sc) {
        return ZSYSTEMERROR;
    }
    /* 调用异步接口。 */
    rc = zoo_adelete(zh, path, version, SYNCHRONOUS_MARKER, sc);
    if (rc == ZOK) {
        /* 上锁睡眠，直到处理完服务回复才被唤醒。 */
        wait_sync_completion(sc);
        rc = sc->rc;
    }
    /* 释放锁对象。 */
    free_sync_completion(sc);
    return rc;
}

/* 创建锁。 */
struct sync_completion *alloc_sync_completion(void) {
    struct sync_completion *sc = (struct sync_completion *)calloc(1, sizeof(struct sync_completion));
    if (sc) {
        pthread_cond_init(&sc->cond, 0);
        pthread_mutex_init(&sc->lock, 0);
    }
    return sc;
}

/* mt_adaptor.c */
int wait_sync_completion(struct sync_completion *sc) {
    /* 上锁。 */
    pthread_mutex_lock(&sc->lock);
    /* 没处理完进入睡眠状态，等待唤醒。 */
    while (!sc->complete) {
        pthread_cond_wait(&sc->cond, &sc->lock);
    }
    /* 解锁。 */
    pthread_mutex_unlock(&sc->lock);
    return 0;
}

/* 释放锁。 */
void free_sync_completion(struct sync_completion *sc) {
    if (sc) {
        pthread_mutex_destroy(&sc->lock);
        pthread_cond_destroy(&sc->cond);
        free(sc);
    }
}
```

* 异步

```c
/* 回调函数。 */
typedef void (*void_completion_t)(int rc, const void *data);

/* zookeeper.h */
ZOOAPI int zoo_adelete(zhandle_t *zh, const char *path, int version,
        void_completion_t completion, const void *data);

/* zookeeper.c */
int zoo_adelete(zhandle_t *zh, const char *path, int version,
                void_completion_t completion, const void *data) {
    /* 内存序列化对象。 */
    struct oarchive *oa;
    /* 请求包头。 */
    struct RequestHeader h = {get_xid(), ZOO_DELETE_OP};
    /* 请求包内容。 */
    struct DeleteRequest req;
    int rc = DeleteRequest_init(zh, &req, path, version);
    if (rc != ZOK) {
        return rc;
    }
    /* 创建内存序列化对象，序列化写入包头和包内容。 */
    oa = create_buffer_oarchive();
    rc = serialize_RequestHeader(oa, "header", &h);
    rc = rc < 0 ? rc : serialize_DeleteRequest(oa, "req", &req);
    enter_critical(zh);
    /* 添加异步接口回调数据。 */
    rc = rc < 0 ? rc : add_void_completion(zh, h.xid, completion, data);
    /* 将数据包的序列化数据写入发送队列。 */
    rc = rc < 0 ? rc : queue_buffer_bytes(&zh->to_send, get_buffer(oa), get_buffer_len(oa));
    leave_critical(zh);
    free_duplicate_path(req.path, path);
    /* We queued the buffer, so don't free it */
    close_buffer_oarchive(&oa, 0);

    LOG_DEBUG(LOGCALLBACK(zh), "Sending request xid=%#x for path [%s] to %s", h.xid, path, zoo_get_current_server(zh));
    /* make a best (non-blocking) effort to send the requests asap */
    /* 发包。 */
    adaptor_send_queue(zh, 0);
    return (rc < 0) ? ZMARSHALLINGERROR : ZOK;
}
```

---

<font color=red> 吐槽一下： </font>

> 这个 lib 的异步是假异步，异步接口到处都是锁，回调函数由回调线程调用，即便调用异步接口，整个进程仍然都是多线程操作，并非单进程单线程的异步。所以这个 lib 从开始设计就只适合于多线程环境使用。

---

### 3.3. 异步网络 IO

逻辑在`网络线程`中实现。

* 连接 zk 服务的 socket 被设置异步 `O_NONBLOCK` 非阻塞。
* 网络 IO 事件通过 `poll` 进行管理。
* 发送请求数据到 zk 服务；接收 zk 服务回包。
* 监控网络时间事件回复：
  1. 异步接口访问，结果将被放进回调队列，等待回调线程处理。
  2. 同步接口访问，结果将被当前网络线程处理，并唤醒处于休眠状态的调用接口线程。
     > 注意：同步接口使用，编译的时候需要设置多线程编译宏（`THREADED`）

```c
/* mt_adaptor.c
 * 网络 IO 线程处理逻辑。*/
void *do_io(void *v) {
    zhandle_t *zh = (zhandle_t *)v;
    struct pollfd fds[2];
    ...
    while (!zh->close_requested) {
        ...
        /* 创建异步 socket 连接 zookeeper。 */
        zookeeper_interest(zh, &fd, &interest, &tv);
        if (fd != -1) {
            /* 通过 poll 监听 fd 的读写事件。*/
            fds[1].fd = fd;
            fds[1].events = (interest & ZOOKEEPER_READ) ? POLLIN : 0;
            fds[1].events |= (interest & ZOOKEEPER_WRITE) ? POLLOUT : 0;
            maxfd = 2;
        }
        timeout = tv.tv_sec * 1000 + (tv.tv_usec / 1000);

        /* 通过 poll 获取当前 fd 读写事件。 */
        poll(fds, maxfd, timeout);
        if (fd != -1) {
            interest = (fds[1].revents & POLLIN) ? ZOOKEEPER_READ : 0;
            interest |= ((fds[1].revents & POLLOUT) || (fds[1].revents & POLLHUP)) ? ZOOKEEPER_WRITE : 0;
        }
        ...
        /* 处理从 poll 捞出的读写事件。 */
        zookeeper_process(zh, interest);
        ...
    }
    ...
}

/* zookeeper.c
 * 创建非阻塞 socket，连接 zk 服务。 */
int zookeeper_interest(zhandle_t *zh, socket_t *fd, int *interest,
                       struct timeval *tv) {
    ...
    if (*fd == -1) {
        ...
        /* 创建 socket 对象。 */
        zh->fd->sock = socket(zh->addr_cur.ss_family, sock_flags, 0);
        ...
        /* 设置 socket 网络通信不延迟。 */
        zookeeper_set_sock_nodelay(zh, zh->fd->sock);
        /* 设置 socket 非阻塞。 */
        zookeeper_set_sock_noblock(zh, zh->fd->sock);
        rc = zookeeper_connect(zh, &zh->addr_cur, zh->fd->sock);
        ...
    }
    ...
}

/* zookeeper.c
 * 处理网络读写事件。*/
int zookeeper_process(zhandle_t *zh, int events) {
    ...
    /* 根据 poll 取出的读写事件 events 读写数据。 */
    rc = check_events(zh, events);
    ...
    /* 处理 zk 服务回复包逻辑。 */
    while (rc >= 0 && (bptr = dequeue_buffer(&zh->to_process))) {
        struct ReplyHeader hdr;
        struct iarchive *ia = create_buffer_iarchive(
            bptr->buffer, bptr->curr_offset);
        deserialize_ReplyHeader(ia, "hdr", &hdr);

        if (hdr.xid == PING_XID) {
            /* 心跳回复。 */
            ...
        } else if (hdr.xid == WATCHER_EVENT_XID) {
            /* zk 服务通知监听事件。 */
            ...
            /* 事件放进完成队列（completions_to_process）等待回调线程处理。*/
            queue_completion(&zh->completions_to_process, c, 0);
        }
        ...
        else {
            completion_list_t *cptr = dequeue_completion(&zh->sent_requests);
            ...
            /* 异步方式的回调放进完成队列（completions_to_process）等待回调线程处理。 */
            if (cptr->c.void_result != SYNCHRONOUS_MARKER) {
                LOG_DEBUG(LOGCALLBACK(zh), "Queueing asynchronous response");
                cptr->buffer = bptr;
                queue_completion(&zh->completions_to_process, cptr, 0);
            } else {
#ifdef THREADED
                /* 多线程同步模式，在本线程处理回复包，并唤醒等待的请求接口线程。 */
                struct sync_completion
                    *sc = (struct sync_completion *)cptr->data;
                sc->rc = rc;

                /* 当前线程同步处理回复包。 */
                process_sync_completion(zh, cptr, sc, ia);

                /* 唤醒调用接口的线程。*/
                notify_sync_completion(sc);
                free_buffer(bptr);
                zh->outstanding_sync--;
                destroy_completion_entry(cptr);
#else
                abort_singlethreaded(zh);
#endif
            }
        }
}

/* 唤醒调用了同步接口，正在睡眠的线程。 */
void notify_sync_completion(struct sync_completion *sc) {
    pthread_mutex_lock(&sc->lock);
    sc->complete = 1;
    pthread_cond_broadcast(&sc->cond);
    pthread_mutex_unlock(&sc->lock);
}

/* 处理从 poll 取出的读写事件，将发送队列的数据发出去，将读出来的数据放进处理队列。 */
static int check_events(zhandle_t *zh, int events) {
    ...
    /* 写事件。 */
    if (zh->to_send.head && (events & ZOOKEEPER_WRITE)) {
        /* 发送数据。 */
        int rc = flush_send_queue(zh, 0);
        ...
    }
    ...
    /* 读事件。 */
    if (events & ZOOKEEPER_READ) {
        int rc;
        if (zh->input_buffer == 0) {
            zh->input_buffer = allocate_buffer(0, 0);
        }
        /* 读数据。 */
        rc = recv_buffer(zh, zh->input_buffer);
        ...
        if (rc > 0) {
            get_system_time(&zh->last_recv);
            if (zh->input_buffer != &zh->primer_buffer) {
                if (is_connected(zh) || !is_sasl_auth_in_progress(zh)) {
                    /* 回复包，放进处理队列。 */
                    queue_buffer(&zh->to_process, zh->input_buffer, 0);
        }
        ...
        zh->input_buffer = 0;
     }
     ...
}
```

---

### 3.4. 回调

异步接口实现调用 / 节点监控事件，都是通过异步回调进行通知。异步回调逻辑，在回调线程中实现。

```c
void *do_completion(void *v) {
    ...
    while (!zh->close_requested) {
        ...
        /* 处理完成事件队列。 */
        process_completions(zh);
    }
    ...
}

/* handles async completion (both single- and multithreaded) */
void process_completions(zhandle_t *zh) {
    completion_list_t *cptr;
    /* 从列表中，拿出一个节点出来出来。 */
    while ((cptr = dequeue_completion(&zh->completions_to_process)) != 0) {
        struct ReplyHeader hdr;
        buffer_list_t *bptr = cptr->buffer;
        struct iarchive *ia = create_buffer_iarchive(bptr->buffer, bptr->len);
        deserialize_ReplyHeader(ia, "hdr", &hdr);

        /* 如果是监控事件，那么进行监控回调。 */
        if (hdr.xid == WATCHER_EVENT_XID) {
            ...
            deliverWatchers(zh, type, state, evt.path, &cptr->c.watcher_result);
            ...
        } else {
            /* 如果是请求回复，那么回调对应的回调函数。 */
            deserialize_response(zh, cptr->c.type, hdr.xid, hdr.err != 0, hdr.err, cptr, ia);
        }
        ...
    }
}
```

---

## 4. 小结

* [zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c) 提供同步异步接口。
* 它是多线程工作方式。两个线程分别是：网络 IO 线程 和 回调处理线程。
* 网络 IO 是异步非阻塞通信。
* 通过 `poll` 管理 fd。

---

## 5. 问题

* 异步接口回调，通过回调线程处理。同步接口阻塞在网络线程，当网络请求收到回复，网络线程才会唤醒阻塞。显然异步性能要高于同步，但是同步方式在多线程模式下工作，可以避免逻辑割裂。
* 异步回调方式是通过子线程回调，同步方式也有监控事件通过子线程回调，所以这个回调函数涉及到多线程操作，需要注意回调数据原子性的操作，这个问题隐藏得比较深。
* 这个库是用 `poll` 管理 fd 相关逻辑，所以如果要将库的 fd 取出来绑定到主线程的 `epoll` 估计不那么容易。

---

## 6. 参考

* [zk_cpp](https://github.com/yandaren/zk_cpp)
* [Zookeeper 教程](https://www.runoob.com/w3cnote/zookeeper-tutorial.html)
* [Zookeeper C API 指南](https://www.cnblogs.com/haippy/archive/2013/02/21/2920280.html)
* [pthread_cond_wait()](https://www.cnblogs.com/diyingyun/archive/2011/11/25/2263164.html)
* [pthread_cond_broadcast & pthread_cond_signal](https://www.cnblogs.com/XiaoXiaoShuai-/p/11855408.html)
* [Zookeeper C客户端库编译](https://blog.csdn.net/jinguangliu/article/details/87191236)

---

> 🔥 文章来源：[《ZooKeeper C - Client 异步/同步工作方式》](https://wenfh2020.com/2020/10/17/zookeeper-c-client/)


>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
