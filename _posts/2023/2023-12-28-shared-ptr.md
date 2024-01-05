---
layout: post
title:  "[C++] 浅析 std::share_ptr 内部结构"
categories: redis
author: wenfh2020
---

最近阅读了 C++ 智能指针的部分实现源码，简单总结和记录一下 std::share_ptr/std::weak_ptr 内部结构和工作原理。



* content
{:toc}


---

## 1. std::shared_ptr

### 1.1. 概念

std::shared_ptr 是 C++11 中引入的一种智能指针，它可以用来自动管理对象的生命周期，以防止内存泄漏。

---

### 1.2. 结构

<div align=center><img src="/images/2023/2024-01-04-06-45-50.png" data-action="zoom"></div>

#### 1.2.1. 常规创建对象

```cpp
class A {
   public:
    std::string m_str;
    A(const char* s) : m_str(s) {}
    ~A() {}
};

auto a = std::shared_ptr<A>(new A("hello"));
```

std::shared_ptr 的内部结构并不复杂，关键的两个成员指针：

1. _M_ptr：数据块指针。
2. _M_pi：控制块指针，控制块里面有 `引用计数` 和 `弱引用计数`。

```shell
|-- shared_ptr 
  |-- element_type* _M_ptr;            # 数据块指针。
  |-- __shared_count<_Lp> _M_refcount; # 引用计数对象。
    |-- _Sp_counted_base<_Lp>* _M_pi;  # 控制块指针。
      |-- _Atomic_word _M_use_count;   # 引用计数。
      |-- _Atomic_word _M_weak_count;  # 弱引用计数。
```

---

#### 1.2.2. make_shared 创建对象

```cpp
auto a = std::make_shared<A>("hello");
```

使用 std::make_shared 创建 std::shared_ptr 对象效率更高：

1. 因为 std::make_shared 参数是个 [万能引用](https://wenfh2020.com/2023/12/10/cpp-rvalue/)，可以有效防止数据拷贝。
2. 元素对象 A，可以在 std::shared_ptr 内部进行构造，可以实现更多的优化，例如 std::shared_ptr 内部创建了一块连续的内存空间，将 `控制块内存`和 `数据块内存` 连接在一起，系统访问连续的内存空间要比访问离散的内存空间效率更高。(std::shared_ptr 内部重载 new 操作符，在自由存储区（连续的内存空间）上进行构造对象 A。)

* 成员结构。

```shell
|-- shared_ptr 
  |-- element_type* _M_ptr; ---------------------------------------+
  |-- __shared_count<_Lp> _M_refcount;                             |
    |-- _Sp_counted_base<_Lp>* _M_pi; --------------------------+  |
                                                                |  |
# 控制块实例                                                     |  |
|-- _Sp_counted_ptr_inplace : public _Sp_counted_base<_Lp> <----+  |
  |-- _Sp_counted_base<_Lp>* _M_pi;                                |
    |-- _Atomic_word _M_use_count;                                 |
    |-- _Atomic_word _M_weak_count;                                |
  |-- _Impl _M_impl                                                |
    |-- __gnu_cxx::__aligned_buffer<_Tp> _M_storage;               |
      |-- unsigned char __data[_Len];  <---------------------------+
```

* 内部内存分配。（有兴趣的朋友可以研读源码，这里不详细展开了。）

```cpp
template <typename _Tp, typename _Alloc, typename... _Args>
__shared_count(_Tp*& __p, _Sp_alloc_shared_tag<_Alloc> __a,
               _Args&&... __args) {
    typedef _Sp_counted_ptr_inplace<_Tp, _Alloc, _Lp> _Sp_cp_type;
    typename _Sp_cp_type::__allocator_type __a2(__a._M_a);
    auto __guard = std::__allocate_guarded(__a2);
    // 给对象 _Sp_counted_ptr_inplace 分配内存。
    _Sp_cp_type* __mem = __guard.get();
    // 在连续的内存空间 __mem 上构建数据块和控制块。
    auto __pi = ::new (__mem)
        _Sp_cp_type(__a._M_a, std::forward<_Args>(__args)...);
    __guard = nullptr;
    // __shared_count::_M_pi 指向控制块。
    _M_pi = __pi;
    // shared_ptr::_M_ptr 指向数据块。
    __p = __pi->_M_ptr();
}
```

---

### 1.3. 引用计数

std::shared_ptr 通过引用计数维护共享对象实体的生命周期：

* 当一个新的 shared_ptr 指向一个对象，该对象的引用计数就会增加。
* 当一个 shared_ptr 被销毁或者指向另一个对象，原来的对象的引用计数就会减少。
* 当引用计数变为 0 时，对象就会被自动删除。

<div align=center><img src="/images/2023/2024-01-04-12-15-03.png" data-action="zoom"></div>

```cpp
// g++ -std=c++11 test.cpp -o t && ./t
#include <iostream>
#include <memory>

class A {
   public:
    A() { std::cout << "A()\n"; }
    ~A() { std::cout << "~A()\n"; }
};

int main() {
    {
        std::shared_ptr<A> b;
        {
            auto a = std::make_shared<A>();
            std::cout << "a's use_cnt: " << a.use_count()
                      << "\n---\n";
            // b 对象指向 a 对象后，引用计数加一。
            b = a;
            std::cout << "a's use_cnt: " << a.use_count()
                      << "\nb's use_cnt: " << b.use_count()
                      << "\n";
        }
        // a 结束生命期，引用计数减一。
        std::cout << "---\n";
        std::cout << "b's use_cnt: " << b.use_count() << "\n";
    }
    // b 结束生命期，引用计数减一后，引用计数为零，自动销毁对象。
    std::cout << "---\nexit\n";
    return 0;
}

// 输出：
// A()
// a's use_cnt: 1
// ---
// a's use_cnt: 2
// b's use_cnt: 2
// ---
// b's use_cnt: 1
// ~A()
// ---
// exit
```

---

#### 1.3.1. 增加引用计数

每当一个新的 shared_ptr 指向一个对象，该对象的引用计数就会增加。

内部通过原子操作维护 _M_use_count 引用计数，保证引用计数在多线程环境下安全工作。

* 参考上面 demo，增加引用计数流程。

```shell
|-- main
  |-- shared_ptr(const shared_ptr&) noexcept = default;
    |-- __shared_count(const __shared_count& __r)
      |-- _M_pi->_M_add_ref_copy();
        |-- __gnu_cxx::__atomic_add_dispatch(&_M_use_count, 1)
          |-- __atomic_add(__mem, __val);
```

---

#### 1.3.2. 减少引用计数

std::shared_ptr 对象生命期结束时，如果引用计数为零，那么销毁元素对象。

* 引用计数：_M_use_count == 0 销毁 `数据块`。
* 弱引用计数：_M_weak_count == 0，销毁 `控制块`。

> 关于 弱引用 下文将会讲述。

* 析构流程。

```shell
|-- main
  |-- ~__shared_ptr() = default;
    |-- _M_pi->_M_release();
      |-- if (__gnu_cxx::__exchange_and_add_dispatch(&_M_use_count, -1) == 1)
        |-- _Sp_counted_base::_M_dispose(); # 销毁数据块。
        # 【注意】控制块结构要在弱引用计数为 0 才会销毁控制块。
        |-- if (__gnu_cxx::__exchange_and_add_dispatch(&_M_weak_count, -1) == 1)
          |-- _Sp_counted_base::_M_destroy(); # 销毁控制块。
```

* 内部实现源码。

```cpp
template <typename _Tp>
class shared_ptr : public __shared_ptr<_Tp> {
   public:
    ...
   protected:
    ~__shared_count() noexcept {
        if (_M_pi != nullptr)
            _M_pi->_M_release();
    }
    ...
};

template <_Lock_policy _Lp = __default_lock_policy>
class _Sp_counted_base : public _Mutex_base<_Lp> {
    ...
   public:
    void
    _M_release() noexcept {
        // 原子操作。
        _GLIBCXX_SYNCHRONIZATION_HAPPENS_BEFORE(&_M_use_count);
        if (__gnu_cxx::__exchange_and_add_dispatch(&_M_use_count, -1) == 1) {
            _GLIBCXX_SYNCHRONIZATION_HAPPENS_AFTER(&_M_use_count);
            // 销毁数据块。
            _M_dispose();
            ...
            _GLIBCXX_SYNCHRONIZATION_HAPPENS_BEFORE(&_M_weak_count);
            if (__gnu_cxx::__exchange_and_add_dispatch(&_M_weak_count, -1) == 1) {
                _GLIBCXX_SYNCHRONIZATION_HAPPENS_AFTER(&_M_weak_count);
                // 销毁控制块。
                _M_destroy();
            }
        }
    }
    ...
};
```

---

## 2. std::weak_ptr

### 2.1. 概念

std::weak_ptr 是 C++11 中引入的另一种智能指针。

作用：

1. 它的主要用途是防止 std::shared_ptr 的 `循环引用问题`，生命期结束后，没有自动销毁元素对象。
2. std::weak_ptr 不会增加 std::shared_ptr 所指向对象的引用计数。如果所有的 std::shared_ptr 都已经被销毁，那么即使还有 std::weak_ptr 指向该对象，该对象也会被销毁。
3. std::weak_ptr 通常用于观察 std::shared_ptr。如果 std::weak_ptr 所指向的对象还存在的话，可以通过 std::weak_ptr::lock() 来创建一个新的 std::shared_ptr，否则这个新的 std::shared_ptr 就会是空的。

> 参考下面 Demo，循环引用问题导致元素对象没有释放。

```cpp
// g++ -std=c++11 test.cpp -o t && ./t
#include <iostream>
#include <memory>

class B;
class A {
   public:
    A() { std::cout << "A()\n"; }
    ~A() { std::cout << "~A()\n"; }
    std::shared_ptr<B> m_obj;
};

class B {
   public:
    B() { std::cout << "B()\n"; }
    ~B() { std::cout << "~B()\n"; }
    std::shared_ptr<A> m_obj;
};

int main() {
    auto a = std::make_shared<A>();
    auto b = std::make_shared<B>();
    a->m_obj = b;
    b->m_obj = a;
    return 0;
}

// 输出：
// A()
// B()
```

---

### 2.2. 结构

std::weak_ptr 的内部成员结构与 std::shared_ptr 有惊人相似，原理大同小异。

```shell
|-- weak_ptr
  |-- __weak_ptr
    |-- _Tp* _M_ptr;                      # 数据块指针。
    |-- __weak_count<_Lp> _M_refcount;    # 引用计数对象。
      |-- _Sp_counted_base<_Lp>* _M_pi;   # 控制块指针。
        |-- _Atomic_word _M_use_count;    # 引用计数。
        |-- _Atomic_word _M_weak_count;   # 弱引用计数。
```

<div align=center><img src="/images/2023/2024-01-05-10-42-53.png" data-action="zoom"></div>

---

## 3. 线程安全

问：std::shared_ptr 对象是否线程安全？！

答：<font color=red>不安全</font>！

```shell
|-- shared_ptr 
  |-- element_type* _M_ptr;            # 数据块指针。
  |-- __shared_count<_Lp> _M_refcount; # 引用计数对象。
    |-- _Sp_counted_base<_Lp>* _M_pi;  # 控制块指针。
```

* 数据块指针：_M_ptr，std::shared_ptr 内部并没有任何同步原语对它进行保护，多线程环境下读写，不安全！
* 引用计数和弱引用计数是原子操作，它们是安全的；但是原子操作保护的区域有限，多线程环境下引用计数为 0 时，销毁对象不安全。

    请看下图步骤：

    1. A 线程执行步骤一。
    2. B 线程执行骤二：释放 _M_pi 指向的控制块内存。
    3. A 线程执行步骤三还安全吗？！

<div align=center><img src="/images/2023/2024-01-05-11-40-49.png" data-action="zoom"></div>
