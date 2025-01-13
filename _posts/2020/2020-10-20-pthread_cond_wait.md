---
layout: post
title:  "[C++] 理解 C++ 多线程条件变量 pthread_cond_wait 使用"
categories: c/c++
tags: 多线程 条件变量
author: wenfh2020
---

pthread_cond_wait 是 POSIX 线程库中用于条件变量等待的函数。

它的作用是让线程在条件变量上等待，并在等待期间释放与之关联的互斥锁。当条件变量被通知（通过 pthread_cond_signal 或 pthread_cond_broadcast）时，线程会被唤醒并重新获取互斥锁。




* content
{:toc}

---

## 1. pthread_cond_wait

The pthread_cond_wait() function atomically blocks the current thread waiting on the condition variable specified by cond, and releases the mutex specified by mutex. The waiting thread unblocks only after another thread calls pthread_cond_signal(3), or pthread_cond_broadcast(3) with the same condition variable, and the current thread reac-
quires the lock on mutex.

---

pthread_cond_wait 的主要功能是：

1. 释放互斥锁：线程在等待条件变量之前，必须释放与之关联的互斥锁。
2. 等待条件变量：线程进入等待状态，直到条件变量被通知（通过 pthread_cond_signal 或 pthread_cond_broadcast）。
3. 重新获取互斥锁：线程被唤醒后，重新获取互斥锁。

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
    pthread_mutex_unlock(&m_mutex);

    /* 发“信号”唤醒正在睡眠的一个线程。*/
    pthread_cond_signal(&m_cond);
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

`pthread_cond_wait` 工作流程：

1. 解锁。
2. 阻塞等待唤醒（如果不满足条件唤醒条件，阻塞等待）。
3. 被唤醒（pthread_cond_signal / pthread_cond_broadcast）。
4. 重新上锁。

<div align=center><img src="/images/2024/2025-01-13-11-10-42.png" width="90%" data-action="zoom"></div>

---

## 4. glibc 源码

要了解条件变量各个接口的工作原理，可以参考 glibc 源码的实现：

[pthread_cond_signal](https://codebrowser.dev/glibc/glibc/nptl/pthread_cond_signal.c.html) / [pthread_cond_broadcast](https://codebrowser.dev/glibc/glibc/nptl/pthread_cond_broadcast.c.html) / [pthread_cond_wait](https://codebrowser.dev/glibc/glibc/nptl/pthread_cond_wait.c.html)


```c
// https://codebrowser.dev/glibc/glibc/nptl/pthread_cond_signal.c.html
int ___pthread_cond_signal(pthread_cond_t* cond) {
    ...
    // 唤醒
    if (do_futex_wake)
        futex_wake(cond->__data.__g_signals + g1, 1, private);
    return 0;
}

// https://codebrowser.dev/glibc/glibc/nptl/pthread_cond_broadcast.c.html
int ___pthread_cond_broadcast(pthread_cond_t* cond) {
    ...
    // 唤醒
    if (do_futex_wake)
        futex_wake(cond->__data.__g_signals + g1, INT_MAX, private);
    return 0;
}

// https://codebrowser.dev/glibc/glibc/nptl/pthread_cond_wait.c.html
static __always_inline int
__pthread_cond_wait_common(pthread_cond_t *cond, pthread_mutex_t *mutex,
                           clockid_t clockid, const struct __timespec64 *abstime) {
    ...
    // 解锁
    err = __pthread_mutex_unlock_usercnt(mutex, 0);
    ...
    unsigned int signals = atomic_load_acquire(cond->__data.__g_signals + g);
    do {
        while (1) {
            ...
            // 等待唤醒
            err = __futex_abstimed_wait_cancelable64(
                cond->__data.__g_signals + g, 0, clockid, abstime, private);
            ...
        }
    }
    ...
done:
    ...
    // 加锁
    err = __pthread_mutex_cond_lock(mutex);
 ...
}
```

---

## 5. 条件变量 demo

```cpp
// g++ -g -O0 -std=c++17 test.cpp  -lpthread -o test && ./test

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <iostream>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

std::queue<int> g_queue;          // 共享队列
std::mutex g_mutex;               // 互斥锁
std::condition_variable g_cv;     // 条件变量
std::atomic<bool> g_done{false};  // 使用原子变量替代普通 bool

// 生产者
void producer() {
    for (int i = 0; i < 10; ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));

        {
            std::lock_guard<std::mutex> lock(g_mutex);
            g_queue.push(i);
        }

        printf("Produced: %d\n", i);
        g_cv.notify_one();
    }

    g_done = true;
    g_cv.notify_all();
}

// 消费者
void consumer(int id) {
    while (true) {
        int item = -1;

        {
            std::unique_lock<std::mutex> lock(g_mutex);
            g_cv.wait(lock, [&] { return !g_queue.empty() || g_done; });
            if (g_done) {
                break;
            }

            if (!g_queue.empty()) {
                item = g_queue.front();
                g_queue.pop();
            }
        }

        if (item != -1) {
            printf("Consumer %d consumed: %d\n", id, item);
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
        }
    }
}

int main() {
    std::thread prod(producer);

    std::vector<std::thread> consumers;
    for (int i = 0; i < 10; ++i) {
        consumers.emplace_back(consumer, i + 1);
    }

    if (prod.joinable()) {
        prod.join();
    }

    for (auto& cons : consumers) {
        if (cons.joinable()) {
            cons.join();
        }
    }

    printf("Main thread finished.\n");
    return 0;
}
```

---

## 6. 参考

* [pthread_cond_wait函数实现](https://www.cnblogs.com/kuikuitage/p/12907904.html)
* [Linux Futex浅析](http://blog.sina.com.cn/s/blog_e59371cc0102v29b.html)
* [pthread_cond_wait()](https://www.cnblogs.com/diyingyun/archive/2011/11/25/2263164.html)
* [pthread_cond_wait()用法分析](https://blog.csdn.net/hairetz/article/details/4535920)
