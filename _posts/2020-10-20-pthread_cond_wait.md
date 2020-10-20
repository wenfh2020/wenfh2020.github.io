---
layout: post
title:  "pthread_cond_wait"
categories: c/c++
tags: 多线程 pthread_cond_wait
author: wenfh2020
---

这个函数（`pthread_cond_wait`）理解起来有点费劲，现在结合它的实现源码画个 UML 看看。

> 内核源码看着有点费劲，理解不一定正确。




* content
{:toc}

---

## 1. pthread_cond_wait

The pthread_cond_wait() function atomically blocks the current thread waiting on the condition variable specified by cond, and releases the mutex specified by mutex.

The waiting thread unblocks only after another thread calls pthread_cond_signal(3), or pthread_cond_broadcast(3) with the same condition variable, and the current thread reac-
quires the lock on mutex.

---

## 2. 流程

`pthread_cond_wait` 主要做这几件事。

1. 解锁。
2. 睡眠等待。
3. 被唤醒（pthread_cond_signal / pthread_cond_broadcast）。
4. 回复唤醒者。
5. 上锁。

![pthread_cond_wait 工作流程](/images/2020-10-20-17-33-25.png){:data-action="zoom"}

---

## 3. glibc 源码

`pthread_cond_wait` 源码实现在文件 [pthread_cond_wait.c](https://code.woboq.org/userspace/glibc/nptl/pthread_cond_wait.c.html)。

```c
/* pthread_cond_wait.c */
int
__pthread_cond_wait (pthread_cond_t *cond, pthread_mutex_t *mutex) {
  return __pthread_cond_wait_common (cond, mutex, NULL);
}

static __always_inline int
__pthread_cond_wait_common(pthread_cond_t* cond, pthread_mutex_t* mutex,
                           const struct timespec* abstime) {
    ...
    /* 解锁。 */
    err = __pthread_mutex_unlock_usercnt(mutex, 0);
    ...
    unsigned int signals = atomic_load_acquire(cond->__data.__g_signals + g);
    do {
        while (1) {
            ...
            /* If our group will be closed as indicated by the flag on signals,
             don't bother grabbing a signal.  */
            if (signals & 1)
                goto done;
            /* If there is an available signal, don't block.  */
            if (signals != 0)
                break;
            ...
            if (abstime == NULL) {
                /* 睡眠等待。 */
                err = futex_wait_cancelable(
                    cond->__data.__g_signals + g, 0, private);
            } else {
                /* 限时等待。 */
            }

            if (__glibc_unlikely(err == ETIMEDOUT)) {
                __condvar_dec_grefs(cond, g, private);
                /* 超时唤醒。 */
                __condvar_cancel_waiting(cond, seq, g, private);
                result = ETIMEDOUT;
                goto done;
            }
        }
    }

    ...
    /* 回复信号发送者。 */
    futex_wake(cond->__data.__g_signals + g, 1, private);
    ...

done:
    /* 确认唤醒。 */
    __condvar_confirm_wakeup(cond, private);
    /* 解锁。*/
    err = __pthread_mutex_cond_lock(mutex);
    /* XXX Abort on errors that are disallowed by POSIX?  */
    return (err != 0) ? err : result;
}
```

---

## 4. 测试源码

```c++
bool Bio::bio_init() {
    ...
    /* 创建线程。 */
    pthread_create(&thread, &attr, bio_process_tasks, this);
    ...
}

bool Bio::add_req_task(...) {
    zk_task_t* task = new zk_task_t;
    ...
    pthread_mutex_lock(&m_mutex);
    m_req_tasks.push_back(task);
    /* 发“信号”唤醒在睡眠的线程。*/
    pthread_cond_signal(&m_cond);
    pthread_mutex_unlock(&m_mutex);
    return true;
}

void* Bio::bio_process_tasks(void* arg) {
    ...
    while (!bio->m_stop_thread) {
        ...
        pthread_mutex_lock(&bio->m_mutex);
        while (bio->m_req_tasks.size() == 0) {
            /* 没有数据就睡眠。减少资源的损耗。 */
            pthread_cond_wait(&bio->m_cond, &bio->m_mutex);
        }
        /* 有数据就取出数据进行处理。 */
        task = *bio->m_req_tasks.begin();
        bio->m_req_tasks.erase(bio->m_req_tasks.begin());
        pthread_mutex_unlock(&bio->m_mutex);
        ...
    }

    return nullptr;
}

```

---

## 5. 参考

* [pthread_cond_wait函数实现](https://www.cnblogs.com/kuikuitage/p/12907904.html)
* [Linux Futex浅析](http://blog.sina.com.cn/s/blog_e59371cc0102v29b.html)
* [pthread_cond_wait()](https://www.cnblogs.com/diyingyun/archive/2011/11/25/2263164.html)
* [pthread_cond_wait()用法分析](https://blog.csdn.net/hairetz/article/details/4535920)

---

> 🔥 文章来源：[《lldb 使用》](https://wenfh2020.com/2020/10/20/lldb/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
