---
layout: post
title:  "[知乎回答] C++ 有什么好用的线程池？"
categories: 知乎 c/c++
author: wenfh2020
---

[**知乎问题**](https://www.zhihu.com/question/397916107/answer/2848415125)：

生产环境有什么推荐的线程池库吗？...

* content
{:toc}



---

## 1. 概述

Github 上有个[轻量级线程池](https://github.com/mtrebi/thread-pool)，核心源码不超过百行^_^，简单易用，README 也写得很详细；

缺点是数据拷贝有点多，一般对性能不是特别苛刻的应用场景使用应该没啥问题。

<div align=center><img src="/images/2023/2023-02-13-23-39-27.png"/></div>

---

## 2. 源码

考虑到有些同学上不了 Github，所以把源码贴到下面来了。能上的同学，直接通过链接访问 [Github](https://github.com/mtrebi/thread-pool) 即可。

* 安全队列。

```cpp
#pragma once

#include <mutex>
#include <queue>

// Thread safe implementation of a Queue using an std::queue
template <typename T>
class SafeQueue {
 private:
    std::queue<T> m_queue;
    std::mutex m_mutex;

 public:
    SafeQueue() {}
    SafeQueue(SafeQueue& other) {}
    ~SafeQueue() {}

    bool empty() {
        std::unique_lock<std::mutex> lock(m_mutex);
        return m_queue.empty();
    }

    int size() {
        std::unique_lock<std::mutex> lock(m_mutex);
        return m_queue.size();
    }

    void enqueue(T& t) {
        std::unique_lock<std::mutex> lock(m_mutex);
        m_queue.push(t);
    }

    bool dequeue(T& t) {
        std::unique_lock<std::mutex> lock(m_mutex);

        if (m_queue.empty()) {
            return false;
        }
        t = std::move(m_queue.front());

        m_queue.pop();
        return true;
    }
};
```

* 线程池。

```cpp
#pragma once

#include <functional>
#include <future>
#include <mutex>
#include <queue>
#include <thread>
#include <utility>
#include <vector>

#include "SafeQueue.h"

class ThreadPool {
 private:
    class ThreadWorker {
     private:
        int m_id;
        ThreadPool* m_pool;

     public:
        ThreadWorker(ThreadPool* pool, const int id) : m_pool(pool), m_id(id) {}

        void operator()() {
            std::function<void()> func;
            bool dequeued;
            while (!m_pool->m_shutdown) {
                {
                    std::unique_lock<std::mutex> lock(
                        m_pool->m_conditional_mutex);
                    if (m_pool->m_queue.empty()) {
                        m_pool->m_conditional_lock.wait(lock);
                    }
                    dequeued = m_pool->m_queue.dequeue(func);
                }
                if (dequeued) {
                    func();
                }
            }
        }
    };

    bool m_shutdown;
    SafeQueue<std::function<void()>> m_queue;
    std::vector<std::thread> m_threads;
    std::mutex m_conditional_mutex;
    std::condition_variable m_conditional_lock;

 public:
    ThreadPool(const int n_threads)
        : m_threads(std::vector<std::thread>(n_threads)), m_shutdown(false) {}

    ThreadPool(const ThreadPool&) = delete;
    ThreadPool(ThreadPool&&) = delete;

    ThreadPool& operator=(const ThreadPool&) = delete;
    ThreadPool& operator=(ThreadPool&&) = delete;

    // Inits thread pool
    void init() {
        for (int i = 0; i < m_threads.size(); ++i) {
            m_threads[i] = std::thread(ThreadWorker(this, i));
        }
    }

    // Waits until threads finish their current task and shutdowns the pool
    void shutdown() {
        m_shutdown = true;
        m_conditional_lock.notify_all();

        for (int i = 0; i < m_threads.size(); ++i) {
            if (m_threads[i].joinable()) {
                m_threads[i].join();
            }
        }
    }

    // Submit a function to be executed asynchronously by the pool
    template <typename F, typename... Args>
    auto submit(F&& f, Args&&... args) -> std::future<decltype(f(args...))> {
        // Create a function with bounded parameters ready to execute
        std::function<decltype(f(args...))()> func =
            std::bind(std::forward<F>(f), std::forward<Args>(args)...);
        // Encapsulate it into a shared ptr in order to be able to copy
        // construct / assign
        auto task_ptr =
            std::make_shared<std::packaged_task<decltype(f(args...))()>>(func);

        // Wrap packaged task into void function
        std::function<void()> wrapper_func = [task_ptr]() { (*task_ptr)(); };

        // Enqueue generic wrapper function
        m_queue.enqueue(wrapper_func);

        // Wake up one thread if its waiting
        m_conditional_lock.notify_one();

        // Return future from promise
        return task_ptr->get_future();
    }
};
```

---

* 测试源码。

```cpp
#include <iostream>
#include <random>

#include "../include/ThreadPool.h"

std::random_device rd;
std::mt19937 mt(rd());
std::uniform_int_distribution<int> dist(-1000, 1000);
auto rnd = std::bind(dist, mt);

void simulate_hard_computation() {
    std::this_thread::sleep_for(std::chrono::milliseconds(2000 + rnd()));
}

// Simple function that adds multiplies two numbers and prints the result
void multiply(const int a, const int b) {
    simulate_hard_computation();
    const int res = a * b;
    std::cout << a << " * " << b << " = " << res << std::endl;
}

// Same as before but now we have an output parameter
void multiply_output(int& out, const int a, const int b) {
    simulate_hard_computation();
    out = a * b;
    std::cout << a << " * " << b << " = " << out << std::endl;
}

// Same as before but now we have an output parameter
int multiply_return(const int a, const int b) {
    simulate_hard_computation();
    const int res = a * b;
    std::cout << a << " * " << b << " = " << res << std::endl;
    return res;
}

int main(int argc, char* argv[]) {
    // Create pool with 3 threads
    ThreadPool pool(3);

    // Initialize pool
    pool.init();

    // Submit (partial) multiplication table
    for (int i = 1; i < 3; ++i) {
        for (int j = 1; j < 10; ++j) {
            pool.submit(multiply, i, j);
        }
    }

    // Submit function with output parameter passed by ref
    int output_ref;
    auto future1 = pool.submit(multiply_output, std::ref(output_ref), 5, 6);

    // Wait for multiplication output to finish
    future1.get();
    std::cout << "Last operation result is equals to " << output_ref
              << std::endl;

    // Submit function with return parameter
    auto future2 = pool.submit(multiply_return, 5, 3);

    // Wait for multiplication output to finish
    int res = future2.get();
    std::cout << "Last operation result is equals to " << res << std::endl;

    pool.shutdown();

    return 0;
}
```

---

## 3. 缺点

### 3.1. 问题

缺点非常明显，实际应用中，线程执行函数的参数拷贝次数有点多。

```cpp
// g++ -g -O0 -std=c++11 test.cpp -lpthread -o t && ./t
#include <iostream>

#include "thread_pool.h"

class A {
   public:
    A() {
        std::cout << "A()\n";
    }
    A(const A&) {
        std::cout << "A(const A&)\n";
    }
    A(A&&) {
        std::cout << "A(A&&)\n";
    }
    void f() const {
        std::cout << "thread work\n";
    }
};

void test(ThreadPool& pool, const A& a) {
    std::cout << "submit\n";
    auto r = pool.submit([=]() {
        a.f();
    });
    r.get();
}

int main(int argc, char* argv[]) {
    ThreadPool pool(1);
    pool.init();
    A a;
    test(pool, a);
    pool.shutdown();
    return 0;
}

// 输出：
// A()
// submit
// A(const A&)
// A(const A&)
// A(const A&)
// A(const A&)
// thread work
```

如果执行函数传参为引用，效果要好很多，但是把引用传到多线程中去，貌似不安全啊~~~。

> 下面源码，如果调用了 submit 后，不调用 `r.get` 进行等待，那么函数生命期结束后，引用指向的变量实体就会被销毁，而在线程内，引用变量可能继续被使用，这是危险的。

```cpp
void test(ThreadPool& pool, const A& a) {
    std::cout << "submit\n";
    // 修改 ‘=’ 为 ‘&a’
    auto r = pool.submit([&a]() {
        a.f();
    });
    r.get();
}

// 输出：
// A()
// submit
// thread work
```

---

### 3.2. 问题分析

现在把 submit 函数影响拷贝的地方抽取出来，定位问题。

通过工具 [cppinsights](https://cppinsights.io/) 查看 lambda 的模板实例化源码：

lambda 匿名类对象（__lambda_32_12）成员 `const A a;`，在程序传递过程中不停地发生拷贝。

<div align=center><img src="/images/2023/2023-12-15-14-21-21.png" data-action="zoom"></div>

拷贝具体位置：

1. 创建 lambada 匿名函数对象。
2. 调用 std::bind。
3. std::bind 返回变量赋值给左值变量。
4. 创建回调任务：std::packaged_task 内部实现有 std::bind 调用。

* 测试源码。

```cpp
// g++ -g -O0 -std=c++11 test.cpp -lpthread -o t && ./t
#include <functional>
#include <future>
#include <iostream>
#include <thread>

class A {
   public:
    A() {
        std::cout << "A()\n";
    }
    A(const A&) {
        std::cout << "A(const A&)\n";
    }
    A(A&&) {
        std::cout << "A(A&&)\n";
    }
    void f() const {}
};

template <typename F, typename... Args>
auto submit(F&& f, Args&&... args) -> void {
    // std::bind 拷贝参数。
    // std::bind 返回赋值给 func，产生二次拷贝。
    std::function<decltype(f(args...))()> func =
        std::bind(std::forward<F>(f), std::forward<Args>(args)...);
    // 创建 std::packaged_task 回调对象，内部封装有 std::bind，再次拷贝参数 ^_^！。
    auto task_ptr =
        std::make_shared<std::packaged_task<decltype(f(args...))()>>(func);
    std::function<void()> wrapper_func = [task_ptr]() { (*task_ptr)(); };
}

void f2(const A& a) {
    submit([=]() {
        a.f();
    });
}

int main(int argc, char* argv[]) {
    A a;
    f2(a);
    return 0;
}

// 输出：
// A()
// A(const A&)
// A(const A&)
// A(const A&)
// A(const A&)
```

* 模板实例化代码。

```cpp
void f2(const A& a) {
    class __lambda_32_12 {
       public:
        inline /*constexpr */ void operator()() const {
            a.f();
        }

       private:
        const A a;

       public:
        __lambda_32_12(const A& _a)
            : a{_a} {}
    };

    submit(__lambda_32_12{a});
}
```

---

* 如果匿名函数改为 `引用` 情况就不一样了，匿名函数对象的成员变成了引用 `const A& a;`，**引用变量在程序内部传递不会产生拷贝**。

```cpp
void f2(const A& a) {
    submit([&a]() {
        a.f();
    });
}

// 输出：
// A()
```

* 模板实例化代码。

```cpp
void f2(const A& a) {
    class __lambda_35_12 {
       public:
        inline /*constexpr */ void operator()() const {
            a.f();
        }

       private:
        const A& a;

       public:
        __lambda_35_12(const A& _a)
            : a{_a} {}
    };

    submit(__lambda_35_12{a});
}
```

---

## 4. 小结

1. C++11 实现的线程池实现非常精巧优雅，虽然有缺点，瑕不掩瑜。
2. 线程池内部直接间接地使用 std::bind，使得任务执行函数的参数可能会被多次拷贝，这也是性能与代码简洁之间的一种妥协。
