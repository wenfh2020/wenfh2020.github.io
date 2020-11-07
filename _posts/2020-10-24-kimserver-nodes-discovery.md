---
layout: post
title:  "[kimserver] 分布式系统 - 节点发现"
categories: kimserver
tags: kimserver nodes discovery
author: wenfh2020
---

[kimserver](https://github.com/wenfh2020/kimserver) 节点发现，是通过中心服务进行管理，中心管理思路清晰，逻辑相对简单，而且有很多成熟的方案，例如 zookeeper。




* content
{:toc}

---

## 1. 中心管理

### 1.1. 节点关系

* 中心服务管理是 B 图的节点管理模式，关系简单，逻辑清晰。
* 当集群节点通过中心相互发现，彼此连接，那么就成了 A 图的关系模型。

![通信解耦](/images/2020-05-21-20-02-12.png){:data-action="zoom"}

---

### 1.2. 原理

用 `zookeeper` （下面简称 zk）做实现节点发现原理：

* 子服务通过 `zk-client` 向 `zk` 注册临时保护节点。
* 子服务从 `zk` 获取并监控对应节点类型下的所有子节点信息。

> 节点发现原理可以参考下这个帖子： [《徒手教你使用zookeeper编写服务发现》](https://zhuanlan.zhihu.com/p/34156758)，我觉得它说得简单易懂。

![节点管理](/images/2020-10-24-10-11-56.png){:data-action="zoom"}

---

## 2. 整合 zk-client

### 2.1. 原理

zookeeper 源码目录下有一个 [zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c)，工作模式是多线程。而 [kimserver](https://github.com/wenfh2020/kimserver) 是多进程异步服务，要整合一个多线程的 client 进来，又不能破坏原来的异步逻辑，这里确实花了不少心思。

> [zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c) 工作方式，请参考 [《ZooKeeper C - Client 异步/同步工作方式》](https://wenfh2020.com/2020/10/17/zookeeper-c-client/)

* 创建一个新的线程，调用 `zookeeper-c-client` 的同步接口。
* 主线程向 zookeeper 发送命令，命令将以任务方式将其添加到任务队列，提供新线程消费。
* 主线程通过时钟定时消费，新线程处理任务的结果。

![整合 zookeeper-client-c](/images/2020-11-07-16-38-36.png){:data-action="zoom"}

---

### 2.2. 源码实现

从上图可以看出，这个功能的实现流程，详细实现请查看 [源码](https://github.com/wenfh2020/kimserver/blob/master/src/core/zk_client.cpp)，这里简单介绍一下对应的逻辑。

* 异步服务接口逻辑。

```c++
/* Bio 这个类功能参考了 redis 的 bio 线程实现。 */
class ZkClient : public Bio {
   public:
    ZkClient(Log* logger);
    virtual ~ZkClient();

    /* 初始化 zk client 的封装，从配置文件读取对应的信息。 */
    bool init(const CJsonObject& config);

   public:
    /* 连接 zookeeper 服务，这个是异步的。 */
    bool connect(const std::string& servers);
    /* 断线重连 */
    bool reconnect();
    /* 节点注册逻辑。 */
    bool node_register();
    /* zk 日志设置，注意要在 zookeeper-client-c 连接前调用，是 client 里面的独立日志。 */
    void set_zk_log(const std::string& path, utility::zoo_log_lvl level = utility::zoo_log_lvl_info);

    /* bio 线程调用同步接口处理任务队列的任务。 */
    virtual void process_cmd(zk_task_t* task) override;
    /* 时钟事件。 */
    virtual void on_repeat_timer() override;
    /* 时钟定时处理任务结果。 */
    virtual void process_ack(zk_task_t* task) override;

    /* zookeeper-client-c 回调线程回调通知. */
    static void on_zookeeper_watch_events(zhandle_t* zh, int type, int state, const char* path, void* privdata);
    void on_zk_watch_events(int type, int state, const char* path, void* privdata);

    /* 时钟处理任务处理结果或者 zookeeper 通知事件. */
    void on_zk_register(const kim::zk_task_t* task);
    /* 向 zk 服务获取对应节点信息。 */
    void on_zk_get_data(const kim::zk_task_t* task);
    /* zk 通知：关注的节点内容变动。 */
    void on_zk_data_change(const kim::zk_task_t* task);
    /* zk 通知：关注的节点类型下的子节点有新增或删除。 */
    void on_zk_child_change(const kim::zk_task_t* task);
    /* zk 通知：关注的节点被删除。 */
    void on_zk_node_deleted(const kim::zk_task_t* task);
    /* zk 通知：注册成功，成功在 zk 服务创建临时保护节点。 */
    void on_zk_node_created(const kim::zk_task_t* task);
    /* zk 通知：节点已成功连接 zk 服务。 */
    void on_zk_session_connected(const kim::zk_task_t* task);
    /* zk 通知：网络问题，正在努力连接。*/
    void on_zk_session_connecting(const kim::zk_task_t* task); /* reconnect. */
    /* zk 通知：节点过期，说明节点已下线或者崩溃。 */
    void on_zk_session_expired(const kim::zk_task_t* task);

   private:
    /* bio 线程处理当前服务注册 zk 服务临时保护节点逻辑。 */
    utility::zoo_rc bio_register_node(zk_task_t* task);

   private:
    /* 服务配置。 */
    CJsonObject m_config;
    /* 节点信息管理。 */
    Nodes* m_nodes = nullptr;

    /* zookeeper-client-c 接口封装 */
    utility::zk_cpp* m_zk;
    bool m_is_connected = false;
    bool m_is_registered = false;
    bool m_is_expired = false;
    int m_register_index = 0; /* for reconnect. */
};
```

* 后台线程处理同步逻辑。

```c++
/* 添加任务接口。 */
bool Bio::add_cmd_task(const std::string& path, zk_task_t::CMD cmd, const std::string& value) {
    zk_task_t* task = new zk_task_t{path, value, cmd, time_now()};
    if (task == nullptr) {
        LOG_ERROR("new task failed! path: %s", path.c_str());
        return false;
    }

    /* 任务添加到任务队列，提供后台线程消费。 */
    pthread_mutex_lock(&m_mutex);
    m_req_tasks.push_back(task);
    pthread_cond_signal(&m_cond);
    pthread_mutex_unlock(&m_mutex);
    return true;
}

/* bio 后台线程处理同步任务。 */
void* Bio::bio_process_tasks(void* arg) {
...
    while (!bio->m_stop_thread) {
        zk_task_t* task = nullptr;

        pthread_mutex_lock(&bio->m_mutex);
        while (bio->m_req_tasks.size() == 0) {
            /* wait for pthread_cond_signal. */
            pthread_cond_wait(&bio->m_cond, &bio->m_mutex);
        }
        task = *bio->m_req_tasks.begin();
        bio->m_req_tasks.erase(bio->m_req_tasks.begin());
        pthread_mutex_unlock(&bio->m_mutex);

        if (task != nullptr) {
            /* 同步处理命令任务逻辑。 */
            bio->process_cmd(task);
            /* 任务处理完成，把任务添加到任务完成队列。 */
            bio->add_ack_task(task);
        }
    }
...
}

/* 时钟处理完成任务队列。 */
void Bio::on_repeat_timer() {
    /* acks */
    handle_acks();
}

void Bio::handle_acks() {
    int i = 0;
    std::list<zk_task_t*> tasks;

    /* fetch 100 acks to handle. */
    pthread_mutex_lock(&m_mutex);
    if (m_ack_tasks.size() > 0) {
        auto it = m_ack_tasks.begin();
        while (it != m_ack_tasks.end() && i++ < 100) {
            tasks.push_back(*it);
            m_ack_tasks.erase(it++);
        }
    }
    pthread_mutex_unlock(&m_mutex);

    for (auto& v : tasks) {
        process_ack(v);
        SAFE_DELETE(v);
    }
}
```

---

## 3. 后记

坦白说，这个轮子造得有点费劲，还有很多细节地方有待优化。

---

## 4. 参考

* [徒手教你使用zookeeper编写服务发现](https://zhuanlan.zhihu.com/p/34156758)

---

> 🔥 文章来源：[《[kimserver] 分布式系统 - 节点发现》](https://wenfh2020.com/2020/10/24/kimserver-nodes-discovery/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
