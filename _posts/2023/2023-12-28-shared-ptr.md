---
layout: post
title:  "[C++] 浅析 std::share_ptr"
categories: redis
author: wenfh2020
---

本文可能不适合入门的朋友阅读。



* content
{:toc}



---

## 1. 概念

* 线程安全。
* 元素对象是什么时候析构，销毁的。
* 

---

## 2. std::shared_ptr

### 2.1. 概念

std::shared_ptr 是 C++11 中引入的一种智能指针，它可以用来自动管理对象的生命周期，以防止内存泄漏。

它的工作原理是引用计数：每当一个新的 shared_ptr 指向一个对象，该对象的引用计数就会增加；当一个 shared_ptr 被销毁或者指向另一个对象，原来的对象的引用计数就会减少。当引用计数变为 0 时，对象就会被自动删除。

> 部分文字来源：ChatGPT

---

### 2.2. 内部结构

<div align=center><img src="/images/2023/2024-01-04-06-45-50.png" data-action="zoom"></div>

#### 2.2.1. 常规创建

```cpp
auto a = std::shared_ptr<A>(new A("hello"));
```

```shell
|-- shared_ptr 
  |-- element_type* _M_ptr;            # 数据块指针。
  |-- __shared_count<_Lp> _M_refcount; # 引用计数对象。
    |-- _Sp_counted_base<_Lp>* _M_pi;  # 控制块指针。
      |-- _Atomic_word _M_use_count;   # 对象引用计数。
      |-- _Atomic_word _M_weak_count;  # 对象弱引用计数。
```

---

#### 2.2.2. make_shared 创建

```cpp
auto a = std::make_shared<A>("hello");
```

使用 std::make_shared 创建 std::shared_ptr 效率更高：

1. 因为 std::make_shared 参数是个 [万能引用](https://wenfh2020.com/2023/12/10/cpp-rvalue/)，可以有效防止数据拷贝。
2. 元素对象 A，可以在 std::shared_ptr 内部进行构造，可以实现更多的优化，例如 std::shared_ptr 内部可以创建一块 `连续的内存空间`，将 `控制块内存`和 `数据块内存` 连接在一起，系统访问连续的内存空间要比访问离散的内存空间效率更高。(std::shared_ptr 内部重载 new 操作符，在自由存储区（连续的内存空间）上进行构造对象 A。)

```shell
|-- shared_ptr 
  |-- element_type* _M_ptr; ---------------------------------------+
  |-- __shared_count<_Lp> _M_refcount;                             |
    |-- _Sp_counted_base<_Lp>* _M_pi; --------------------------+  |
                                                                |  |
# 引用控制块实例                                                 |  |
|-- _Sp_counted_ptr_inplace : public _Sp_counted_base<_Lp> <----+  |
  |-- _Sp_counted_base<_Lp>* _M_pi;                             |  |
    |-- _Atomic_word _M_use_count;                              |  |
    |-- _Atomic_word _M_weak_count;                             |  |
  |-- _Impl _M_impl                                             |  |
    |-- __gnu_cxx::__aligned_buffer<_Tp> _M_storage;            |  |
      |-- unsigned char __data[_Len];  <---------------------------+
```

<div align=center><img src="/images/2023/2024-01-04-06-57-09.png" data-action="zoom"></div>

---

* 内部实现源码。

```cpp
// 智能指针结构。
template <typename _Tp>
class shared_ptr : public __shared_ptr<_Tp> {
   public:
    using element_type = typename remove_extent<_Tp>::type;
   ...
   private:
    element_type* _M_ptr;             // Contained pointer.
    __shared_count<_Lp> _M_refcount;  // Reference counter.
};

// 共享对象引用计数控制块。
template <_Lock_policy _Lp>
class __shared_count {
   public:
    _Sp_counted_base() noexcept
        : _M_use_count(1), _M_weak_count(1) {}
   ...
   private:
    _Sp_counted_base<_Lp>* _M_pi;
};

// 引用计数控制块。
template <_Lock_policy _Lp = __default_lock_policy>
class _Sp_counted_base : public _Mutex_base<_Lp> {
    ...
   private:
    _Atomic_word _M_use_count;
    _Atomic_word _M_weak_count;
};

// 智能指针保存的 “元素” 对象内存。
template <std::size_t _Len, std::size_t _Align =
    __alignof__(typename __aligned_storage_msa<_Len>::__type)>
struct aligned_storage {
    union type {
        unsigned char __data[_Len];
        struct __attribute__((__aligned__((_Align)))) {
        } __align;
    };
};

// 智能指针保存的 “元素” 对象内存。
template <typename _Tp>
struct __aligned_buffer
    : std::aligned_storage<sizeof(_Tp), __alignof__(_Tp)> {
    typename std::aligned_storage<sizeof(_Tp), __alignof__(_Tp)>::type _M_storage;

   public:
    // ...
    void* _M_addr() noexcept {
        return static_cast<void*>(&_M_storage);
    }
    const void* _M_addr() const noexcept {
        return static_cast<const void*>(&_M_storage);
    }
    _Tp* _M_ptr() noexcept {
        return static_cast<_Tp*>(_M_addr());
    }
    const _Tp* _M_ptr() const noexcept {
        return static_cast<const _Tp*>(_M_addr());
    }
};

// 共享对象实体控制块。
template <typename _Tp, typename _Alloc, _Lock_policy _Lp>
class _Sp_counted_ptr_inplace final : public _Sp_counted_base<_Lp> {
    class _Impl : _Sp_ebo_helper<0, _Alloc> {
        typedef _Sp_ebo_helper<0, _Alloc> _A_base;

       public:
       ...
        __gnu_cxx::__aligned_buffer<_Tp> _M_storage;
    };

   public:
    // Alloc parameter is not a reference so doesn't alias anything in __args
    template <typename... _Args>
    _Sp_counted_ptr_inplace(_Alloc __a, _Args&&... __args)
        : _M_impl(__a) {
        allocator_traits<_Alloc>::construct(
            __a, _M_ptr(), std::forward<_Args>(__args)...);
    }
   ...
   private:
   ...
    _Tp* _M_ptr() noexcept { return _M_impl._M_storage._M_ptr(); }

    _Impl _M_impl;
};
```

* 内存分配。智能指针共享内存在 __shared_count 里进行分配，shared_ptr 对象成员指向共享控制块对应内容。

```cpp
template <typename _Tp, typename _Alloc, typename... _Args>
__shared_count(_Tp*& __p, _Sp_alloc_shared_tag<_Alloc> __a,
               _Args&&... __args) {
    typedef _Sp_counted_ptr_inplace<_Tp, _Alloc, _Lp> _Sp_cp_type;
    typename _Sp_cp_type::__allocator_type __a2(__a._M_a);
    auto __guard = std::__allocate_guarded(__a2);
    _Sp_cp_type* __mem = __guard.get();
    // 给共享对象实体 _Sp_counted_ptr_inplace 分配内存。
    auto __pi = ::new (__mem)
        _Sp_cp_type(__a._M_a, std::forward<_Args>(__args)...);
    __guard = nullptr;
    // __shared_count::_M_pi 指向引用计数控制块。
    _M_pi = __pi;
    // shared_ptr::_M_ptr 指向控制块的创建的元素对象。
    __p = __pi->_M_ptr();
}
```

---

### 2.3. 引用计数

std::shared_ptr 通过引用计数维护共享对象实体的生命周期。

每当一个新的 shared_ptr 指向一个对象，该对象的引用计数就会增加；当一个 shared_ptr 被销毁或者指向另一个对象，原来的对象的引用计数就会减少。当引用计数变为 0 时，对象就会被自动删除。

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
    auto a = std::make_shared<A>();
    std::cout << "a's use_cnt: " << a.use_count()
              << "\n-----\n";
    // b 对象指向 a 对象后，引用计数加一。
    auto b = a;
    std::cout << "a's use_cnt: " << a.use_count()
              << "\nb's use_cnt: " << b.use_count()
              << "\n";
    return 0;
}

// 输出：
// A()
// a's use_cnt: 1
// ----
// a's use_cnt: 2
// b's use_cnt: 2
// ~A()
```

---

#### 2.3.1. 引用计数增加

每当一个新的 shared_ptr 指向一个对象，该对象的引用计数就会增加。

内部通过原子操作维护 _M_use_count 引用计数，保证引用计数在多线程环境下安全工作。

* 参考上面 demo，共享智能指针引用计数增加流程。

```shell
|-- main
  |-- shared_ptr(const shared_ptr&) noexcept = default;
    |-- __shared_count(const __shared_count& __r)
      |-- _M_pi->_M_add_ref_copy();
        |-- __gnu_cxx::__atomic_add_dispatch(&_M_use_count, 1)
          |-- __atomic_add(__mem, __val);
```

* 内部实现源码。

```cpp
template <typename _Tp>
class shared_ptr : public __shared_ptr<_Tp> {
   ...
   public:
    shared_ptr(const shared_ptr&) noexcept = default;
   ...
   private:
    element_type* _M_ptr;
    __shared_count<_Lp> _M_refcount;
};

template <_Lock_policy _Lp>
class __shared_count {
    template <typename _Tp, typename _Del>
    explicit __shared_count(std::unique_ptr<_Tp, _Del>&& __r) : _M_pi(0) {
       ...
       public:
        __shared_count(const __shared_count& __r) noexcept : _M_pi(__r._M_pi) {
            if (_M_pi != 0)
                // 增加引用计数。
                _M_pi->_M_add_ref_copy();
        }
    }
    ...
   private:
    _Sp_counted_base<_Lp>* _M_pi;
};

// 对象控制块添加引用计数。
template <_Lock_policy _Lp = __default_lock_policy>
class _Sp_counted_base : public _Mutex_base<_Lp> {
   public:
    _Sp_counted_base() noexcept
        : _M_use_count(1), _M_weak_count(1) {}
    // ...
    void _M_add_ref_copy() {
        __gnu_cxx::__atomic_add_dispatch(&_M_use_count, 1);
    }
    ...
   private:
    _Atomic_word _M_use_count;
    _Atomic_word _M_weak_count;
};

// 原子操作。
static inline void
    __attribute__((__unused__))
    __atomic_add_dispatch(_Atomic_word* __mem, int __val) {
#ifdef __GTHREADS
    if (__gthread_active_p())
        __atomic_add(__mem, __val);
    else
        __atomic_add_single(__mem, __val);
#else
    __atomic_add_single(__mem, __val);
#endif
}
```

---

#### 2.3.2. 引用计数减少

std::shared_ptr 对象生命期结束时，引用计数为零，销毁元素对象。

* _M_use_count == 0 引用计数销毁 `元素对象`，这里对象销毁只是调用对象的析构函数。
* <font color=red>_M_weak_count == 0 弱引用计数销毁 `共享对象控制块`。</font>

> 关于 弱引用 下文将会详细讲述。

* 析构流程。

```shell
|-- main
  |-- ~__shared_ptr() = default;
    |-- _M_pi->_M_release();
      |-- if (__gnu_cxx::__exchange_and_add_dispatch(&_M_use_count, -1) == 1)
        |-- _Sp_counted_base::_M_dispose(); # 销毁元素对象 A。(只是析构，并未 delete)
        |-- if (__gnu_cxx::__exchange_and_add_dispatch(&_M_weak_count, -1) == 1)
          |-- _Sp_counted_base::_M_destroy(); # 销毁共享对象控制块。（delete）
```

* 内部实现源码。

```cpp
template <typename _Tp>
class shared_ptr : public __shared_ptr<_Tp> {
   public:
    using element_type = typename remove_extent<_Tp>::type;
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
        _GLIBCXX_SYNCHRONIZATION_HAPPENS_BEFORE(&_M_use_count);
        if (__gnu_cxx::__exchange_and_add_dispatch(&_M_use_count, -1) == 1) {
            _GLIBCXX_SYNCHRONIZATION_HAPPENS_AFTER(&_M_use_count);
            // 销毁元素对象。
            _M_dispose();
            if (_Mutex_base<_Lp>::_S_need_barriers) {
                __atomic_thread_fence(__ATOMIC_ACQ_REL);
            }

            _GLIBCXX_SYNCHRONIZATION_HAPPENS_BEFORE(&_M_weak_count);
            if (__gnu_cxx::__exchange_and_add_dispatch(&_M_weak_count, -1) == 1) {
                _GLIBCXX_SYNCHRONIZATION_HAPPENS_AFTER(&_M_weak_count);
                // 销毁共享对象控制块。
                _M_destroy();
            }
        }
    }
    ...
};
```

---

## 3. std::weak_ptr

### 3.1. 概念

std::weak_ptr 是 C++11 中引入的另一种智能指针。

* 它的主要用途是防止 std::shared_ptr 的 `循环引用问题`，生命期结束后，没有自动销毁元素对象。

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

* std::weak_ptr 不会增加 std::shared_ptr 所指向对象的引用计数。如果所有的 std::shared_ptr 都已经被销毁，那么即使还有 std::weak_ptr 指向该对象，该对象也会被销毁。

* std::weak_ptr 通常用于观察 std::shared_ptr。如果 std::weak_ptr 所指向的对象还存在的话，可以通过 std::weak_ptr::lock() 来创建一个新的 std::shared_ptr，否则这个新的 std::shared_ptr 就会是空的。

---

### 3.2. 内部结构

std::weak_ptr 与 std::shared_ptr 有着极为相似的内部结构，它也有成员指针：_M_ptr（元素对象指针）和 _M_pi（共享对象实体控制块指针），分别指向 `共享对象控制块` 对应的内容。

> _M_ptr/_M_pi 从 std::shared_ptr 对象浅拷贝过来的。

```cpp
// std::weak_ptr 对象构造时，浅拷贝 std::shared_ptr 对象成员。
template <typename _Yp, typename = _Compatible<_Yp>>
__weak_ptr(const __shared_ptr<_Yp, _Lp>& __r) noexcept
    : _M_ptr(__r._M_ptr), _M_refcount(__r._M_refcount) {}

template <_Lock_policy _Lp>
class __weak_count {
   public:
   // __shared_count 是 std::shared_ptr 的引用控制块。
    __weak_count(const __shared_count<_Lp>& __r) noexcept
        : _M_pi(__r._M_pi) {
        if (_M_pi != nullptr)
            // 弱引用计数增加一。
            _M_pi->_M_weak_add_ref();
    }
};
```

* 对象结构。

<div align=center><img src="/images/2023/2024-01-04-17-04-27.png" data-action="zoom"></div>

* 共享模型。std::weak_ptr 对象和 std::shared_ptr 对象指向相同的 `共享对象实体控制块`。

<div align=center><img src="/images/2023/2024-01-04-13-17-35.png" data-action="zoom"></div>

* 源码实现。

```cpp
// 引用计数控制块。
template <_Lock_policy _Lp = __default_lock_policy>
class _Sp_counted_base : public _Mutex_base<_Lp> {
    //...
   private:
    _Atomic_word _M_use_count;
    _Atomic_word _M_weak_count;
};

template <_Lock_policy _Lp>
class __weak_count {
    ...
   private:
    _Sp_counted_base<_Lp>* _M_pi;
};

template <typename _Tp, _Lock_policy _Lp>
class __weak_ptr {
    ...
   private:
    _Tp* _M_ptr;                    // Contained pointer.
    __weak_count<_Lp> _M_refcount;  // Reference counter.
};

template <typename _Tp>
class weak_ptr : public __weak_ptr<_Tp> {
};
```

---

#### 3.2.1. 弱引用计数



---

## 4. 小结

1. 共享智能指针对象通过引用计数，保证对象元素能被多个共享指针共享。智能指针被其它智能指针共享一次，引用计数加一；共享智能指针对象结束生命期进行销毁时，会查看对象的引用计数，如果只有 1，就会销毁整个对象，否则引用计数减一，并不会销毁共享内存。
2. 单线程环境，共享智能指针对象安全，多线程不安全，需要添加同步原语保证其安全。
