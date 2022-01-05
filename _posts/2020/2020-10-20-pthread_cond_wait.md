---
layout: post
title:  "pthread_cond_wait"
categories: c/c++
tags: 多线程 pthread_cond_wait
author: wenfh2020
---

这个函数，在多线程场景与锁结合使用。如果某些线程没事干，就把它阻塞，等待唤醒，这样可以避免线程空跑，浪费系统资源。




* content
{:toc}

---

## 1. pthread_cond_wait

The pthread_cond_wait() function atomically blocks the current thread waiting on the condition variable specified by cond, and releases the mutex specified by mutex. The waiting thread unblocks only after another thread calls pthread_cond_signal(3), or pthread_cond_broadcast(3) with the same condition variable, and the current thread reac-
quires the lock on mutex.

---

## 2. 使用

```cpp
bool Bio::bio_init() {
    ...
    /* 创建线程。 */
    pthread_create(&thread, &attr, bio_process_tasks, this);
    ...
}

/* 添加数据。 */
bool Bio::add_req_task(...) {
    ...
    pthread_mutex_lock(&m_mutex);
    m_req_tasks.push_back(task);
    /* 发“信号”唤醒正在睡眠的一个线程。*/
    pthread_cond_signal(&m_cond);
    pthread_mutex_unlock(&m_mutex);
    ...
}

/* 线程处理函数。 */
void* Bio::bio_process_tasks(void* arg) {
    ...
    while (!bio->m_stop_thread) {
        ...
        pthread_mutex_lock(&bio->m_mutex);
        while (bio->m_req_tasks.size() == 0) {
            /* 没有数据就睡眠阻塞，等待唤醒。 */
            pthread_cond_wait(&bio->m_cond, &bio->m_mutex);
        }
        /* 处理数据。*/
        task = *bio->m_req_tasks.begin();
        bio->m_req_tasks.erase(bio->m_req_tasks.begin());
        pthread_mutex_unlock(&bio->m_mutex);
        ...
    }

    return nullptr;
}
```

---

## 3. 流程

`pthread_cond_wait` 主要做这几件事。

1. 解锁。
2. 阻塞等待唤醒。
3. 被唤醒（pthread_cond_signal / pthread_cond_broadcast）。
4. “回复”唤醒者。
5. 重新上锁。

![pthread_cond_wait 工作流程](/images/2020-10-20-17-33-25.png){:data-action="zoom"}

---

## 4. glibc 源码

`pthread_cond_wait` 实现在 `glibc` 的 [pthread_cond_wait.c](https://code.woboq.org/userspace/glibc/nptl/pthread_cond_wait.c.html) 文件。个人不熟悉内核源码，理解可能有偏差 ^_^！

```c
/* pthread_cond_wait.c */
versioned_symbol (libpthread, __pthread_cond_wait, pthread_cond_wait, GLIBC_2_3_2);

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
                /* 睡眠阻塞等待。 */
                err = futex_wait_cancelable(
                    cond->__data.__g_signals + g, 0, private);
            } else {
                ...
                /* 限时阻塞等待。 */
                err = futex_reltimed_wait_cancelable(...);
                ...
            }
            ...
            if (__glibc_unlikely(err == ETIMEDOUT)) {
                __condvar_dec_grefs(cond, g, private);
                /* 超时唤醒。 */
                __condvar_cancel_waiting(cond, seq, g, private);
                result = ETIMEDOUT;
                goto done;
            }
            ...
        }
    }
    ...
    /* “回复”唤醒者。 */
    futex_wake(cond->__data.__g_signals + g, 1, private);
    ...
done:
    /* 确认唤醒。 */
    __condvar_confirm_wakeup(cond, private);
    /* 上锁。*/
    err = __pthread_mutex_cond_lock(mutex);
    /* XXX Abort on errors that are disallowed by POSIX?  */
    return (err != 0) ? err : result;
}
```

---

## 5. 参考

* [pthread_cond_wait函数实现](https://www.cnblogs.com/kuikuitage/p/12907904.html)
* [Linux Futex浅析](http://blog.sina.com.cn/s/blog_e59371cc0102v29b.html)
* [pthread_cond_wait()](https://www.cnblogs.com/diyingyun/archive/2011/11/25/2263164.html)
* [pthread_cond_wait()用法分析](https://blog.csdn.net/hairetz/article/details/4535920)
