---
layout: post
title:  "[C++] 浅析 C++11 移动语义"
categories: c/c++
tags: stl move
author: wenfh2020
---

本文将会结合测试例子走读 `std::string` 和 `std::vector` 源码，观察 C++11 `移动语义` 是如何影响程序性能的。



* content
{:toc}

---

## 1. 简述

### 1.1. 概念

移动语义是 C++11 引入的新特性，它使得开发者有更好的方式实现对象资源的 **转移** 而不是复制，从而减少复制，提升程序性能。

**移动语义** 与 **右值引用** 有着千丝万缕的关系。请看下面 A 类伪代码，移动语义操作，多了一个 `A&&` 右值引用参数。右值引用与左值引用同样是引用，而右值引用指向的对象一般是 **临时对象** 或 **即将销毁** 的对象（标识该对象可以进行资源转移）。

> 移动语义涉及到其它一些 C++11 概念，详细请参考：[《[C++] 右值引用》](https://wenfh2020.com/2023/12/10/cpp-rvalue/)

```cpp
class A {
   public:
    // 默认构造
    A() {...}
    // 带参构造
    A(const char* s) {...}
    // 拷贝构造
    A(const A& a) {...}
    // 拷贝赋值
    A& operator=(const A& a) {...}

    // 移动构造
    A(A&& a) {...}
    // 移动赋值
    A& operator=(A&& a) {...}

   private:
    // 移动数据
    char* moveData(A&& a) {...}
};

int main() {
    // 默认构造
    A a;
    // 带参构造
    A b("hello");
    // 拷贝构造
    A c(b);
    // 拷贝赋值
    a = c;

    // 移动构造，A("haha") 是临时对象
    A d(A("haha"));
    // 移动赋值，std::move 强制转换左值 d 为右值引用
    a = std::move(d);
    return 0;
}
```

---

### 1.2. 实例

原理不复杂，但是概念有点抽象，还是上测试实例吧。下面实例展示了数据拷贝和移动语义的工作方式。

（B--->A）对象间资源移动主要有三步：

1. A 重置自己的资源。
2. A 移动 B 的资源给自己。
3. A 重置 B 的资源。

`【注意】` B 的资源已经转移给 A 后，如果某些地方再次使用 B 的资源，这是危险行为，得谨慎使用。

> 实例代码，有些代码编译器会实行 RVO 返回值优化，为了达到测试效果，这里编译项添加了 `-fno-elide-constructors` 禁止 RVO 优化）。

```cpp
// g++ -std=c++11 -fno-elide-constructors test.cpp -o t && ./t
#include <string.h>

#include <iostream>

class A {
   public:
    // 默认构造
    A() {
        std::cout << "A()\n";
    }

    // 带参构造
    A(const char* s) {
        if (s != nullptr) {
            copyData(s, strlen(s) + 1);
            std::cout << "A(const char*): "
                      << m_data << "\n";
        }
    }

    // 拷贝构造
    A(const A& a) {
        if (copyData(a.m_data, a.m_data_len)) {
            std::cout << "A(const A&): "
                      << m_data << "\n";
        }
    }

    // 移动构造
    A(A&& a) {
        // 右值引用 a 作为实参传递给函数 moveData，
        // 这时它是个左值，需要对其完美转发，保持它原来的右值属性。
        if (moveData(std::forward<A>(a))) {
            std::cout << "A(A&&): " << m_data << "\n";
        }
    }

    // 拷贝赋值
    A& operator=(const A& a) {
        if (this != &a) {
            if (copyData(a.m_data, a.m_data_len)) {
                std::cout << "operator=(const A&): "
                          << m_data << "\n";
            }
        }
        return *this;
    }

    // 移动赋值
    A& operator=(A&& a) {
        if (this != &a) {
            if (moveData(std::forward<A>(a))) {
                std::cout << "operator=(const A&&): "
                          << m_data << "\n";
            }
        }
        return *this;
    }

    ~A() { release(); }

   private:
    // 释放数据
    void release() {
        if (m_data != nullptr) {
            delete[] m_data;
            m_data = nullptr;
            m_data_len = 0;
        }
    }

    // 拷贝数据
    char* copyData(const char* p, int len) {
        if (p != nullptr && len != 0) {
            release();
            m_data = new char[len];
            memcpy(m_data, p, len);
            m_data_len = len;
            return m_data;
        }
        return nullptr;
    }

    // 移动数据
    char* moveData(A&& a) {
        // 先释放自己
        release();
        // 浅拷贝对方数据
        m_data = a.m_data;
        m_data_len = a.m_data_len;
        // 重置对方成员数据
        a.m_data = nullptr;
        a.m_data_len = 0;
        return m_data;
    }

   private:
    char* m_data = nullptr;  // 数据指针
    int m_data_len = 0;      // 数据长度
};

int main() {
    std::cout << "> copy ---\n";
    // 默认构造
    A a;
    // 带参构造
    A b("hello");
    // 拷贝构造
    A c(b);
    // 拷贝赋值
    a = c;

    std::cout << "> move ---\n";
    // 移动构造
    A d(A("world"));
    // 移动构造
    A e(std::move(d));
    // 移动复制
    a = std::move(e);
    return 0;
}

// 输出：
// > copy ---
// A()
// A(const char*): hello
// A(const A&): hello
// operator=(const A&): hello
// > move ---
// A(const char*): world
// A(A&&): world
// A(A&&): world
// operator=(const A&&): world
```

---

## 2. stl 源码分析

下面将阅读 C++ 标准库源码，看看内部是如何移动语义的。

> 复制和移动有点像深拷贝和浅拷贝的之间区别。

---

### 2.1. std::string

<div align=center><img src="/images/2022/2022-04-09-12-58-38.png" data-action="zoom"/></div>

---

#### 2.1.1. 移动构造

浅拷贝，实现了原对象成员数据转移到目标对象，原对象成员数据被重置。

* 测试源码。

```cpp
// g++ -std=c++11 test.cpp -o t && ./t
#include <iostream>

int main() {
    std::string s("1234567890123456789");
    std::string ss(std::move(s));
    std::cout << (s.empty() ? "empty" : s) << "\n"
              << ss << "\n";
    return 0;
}

// 输出：
// empty
// 1234567890123456789
```

* stl 源码，移动构造逻辑简单，当数据量比较大时，可以避免深拷贝数据带来的开销。

```cpp
/* bits/basic_string.h */
template <typename _CharT, typename _Traits, typename _Alloc>
class basic_string {
    ...
    /* 移动构造函数。*/
    basic_string(basic_string&& __str) noexcept
        : _M_dataplus(_M_local_data(),
          std::move(__str._M_get_allocator())) {
        if (__str._M_is_local()) {
            /* 参考：enum { _S_local_capacity = 15 / sizeof(_CharT) };
               当原对象数据长度 <= 15，程序会跑到这里来。*/
            traits_type::copy(_M_local_buf,
                __str._M_local_buf, _S_local_capacity + 1);
        } else {
            /* 字符串指针浅拷贝。*/
            _M_data(__str._M_data());
            _M_capacity(__str._M_allocated_capacity);
        }

        /* 设置当前字符串长度。 */
        _M_length(__str.length());
        /* 重置原数据。 */
        __str._M_data(__str._M_local_data());
        __str._M_set_length(0);
    }
}
```

---

#### 2.1.2. 复制构造

复制构造，申请新的空间，深拷贝数据。

* 测试源码。

```cpp
// g++ -std=c++11 test.cpp -o t && ./t
#include <iostream>

int main() {
    std::string s("1234567890123456789");
    std::string ss(s); /* 复制构造，深拷贝数据。*/
    std::cout << s << "\n" << ss << "\n";
    return 0;
}

// 输出：
// 1234567890123456789
// 1234567890123456789
```

* stl 源码。

```cpp
/* bits/basic_string.h */

template <typename _CharT, typename _Traits, typename _Alloc>
class basic_string {
    ...
    basic_string(const basic_string& __str)
        : _M_dataplus(_M_local_data(),
          _Alloc_traits::_S_select_on_copy(__str._M_get_allocator())) {
        /* 构造分配空间，深拷贝数据。*/
        _M_construct(__str._M_data(), __str._M_data() + __str.length());
    }

    template <typename _InIterator>
    void
    _M_construct(_InIterator __beg, _InIterator __end) {
        typedef typename std::__is_integer<_InIterator>::__type _Integral;
        _M_construct_aux(__beg, __end, _Integral());
    }

    template <typename _InIterator>
    void
    _M_construct_aux(_InIterator __beg,
        _InIterator __end, std::__false_type) {
        typedef typename iterator_traits<_InIterator>::iterator_category _Tag;
        _M_construct(__beg, __end, _Tag());
    }
}

/* bits/basic_string.tcc */

template <typename _CharT, typename _Traits, typename _Alloc>
template <typename _InIterator>
void basic_string<_CharT, _Traits, _Alloc>::
    _M_construct(_InIterator __beg, _InIterator __end,
                 std::forward_iterator_tag) {
    ...
    size_type __dnew = static_cast<size_type>(std::distance(__beg, __end));

    if (__dnew > size_type(_S_local_capacity)) {
        /* 申请新的空间。*/
        _M_data(_M_create(__dnew, size_type(0)));
        _M_capacity(__dnew);
    }

    // Check for out_of_range and length_error exceptions.
    __try {
        /* 深拷贝数据。*/
        this->_S_copy_chars(_M_data(), __beg, __end);
    }
    ...
    _M_set_length(__dnew);
}

template <typename _CharT, typename _Traits, typename _Alloc>
typename basic_string<_CharT, _Traits, _Alloc>::pointer
basic_string<_CharT, _Traits, _Alloc>::
    _M_create(size_type& __capacity, size_type __old_capacity) {
        ...
        /* 计算动态空间。*/
        if (__capacity > __old_capacity && __capacity < 2 * __old_capacity) {
        __capacity = 2 * __old_capacity;
        // Never allocate a string bigger than max_size.
        if (__capacity > max_size())
            __capacity = max_size();
    }

    /* 申请空间。*/
    return _Alloc_traits::allocate(_M_get_allocator(), __capacity + 1);
}
```

---

### 2.2. std::vector

接下来再来看看动态数组容器是如何通过移动方式减少拷贝的。

* 测试源码。

```cpp
// g++ -std=c++11 test.cpp -o t && ./t
#include <iostream>
#include <vector>

int main() {
    std::vector<std::string> a;
    for (int i = 0; i < 5; i++) {
        a.emplace_back(std::to_string(i));
    }

    std::cout << "--- no move ---" << "\n";
    std::vector<std::string> b = a;
    std::cout << "a   size: " << a.size() << "\n";
    std::cout << "b   size: " << b.size() << "\n";

    std::cout << "--- move ---" << "\n";
    std::vector<std::string> c = std::move(a);
    std::cout << "a   size: " << a.size() << "\n";
    std::cout << "c   size: " << c.size() << "\n";
    return 0;
}

// 输出：
// --- no move ---
// a   size: 5
// b   size: 5
// --- move ---
// a   size: 0
// c   size: 5
```

* stl 源码，通过 gdb 调试方式，看看关键部分代码的处理。

<div align=center><img src="/images/2022/2022-04-09-12-36-04.png" data-action="zoom"/></div>

```cpp
/* /usr/include/c++/9/debug/vector */
template <typename _Tp, typename _Allocator = std::allocator<_Tp> >
class vector
    : public __gnu_debug::_Safe_container<
          vector<_Tp, _Allocator>, _Allocator, __gnu_debug::_Safe_sequence>,
      public _GLIBCXX_STD_C::vector<_Tp, _Allocator>,
      public __gnu_debug::_Safe_vector<
          vector<_Tp, _Allocator>, _GLIBCXX_STD_C::vector<_Tp, _Allocator> > {
    ...
#if __cplusplus >= 201103L
    ...
    vector(vector&&) noexcept = default;
    ...
#endif
    ...
}

/* /usr/include/c++/9/bits/stl_vector.h */
template <typename _Tp, typename _Alloc>
struct _Vector_base {
    ...
#if __cplusplus >= 201103L
    _Vector_base(_Vector_base&&) = default;
#endif
    ...
    struct _Vector_impl_data {
        pointer _M_start;          /* 目前使用空间头部位置。 */
        pointer _M_finish;         /* 当前使用空间尾部位置。 */
        pointer _M_end_of_storage; /* 目前可用空间尾部位置。 */

#if __cplusplus >= 201103L
        _Vector_impl_data(_Vector_impl_data&& __x) noexcept
            /* 转移被转移对象的关键成员数据到当前对象。 */
            : _M_start(__x._M_start),
              _M_finish(__x._M_finish),
              _M_end_of_storage(__x._M_end_of_storage) {
            /* 被转移对象，关键成员数据被重置。 */
            __x._M_start = __x._M_finish = __x._M_end_of_storage = pointer();
        }
#endif
    };
    ...
}
```

---

## 3. 参考

* 《Effective Modern C++》-- 第五章
* [(ubuntu) vscode + gdb 调试 c++](https://wenfh2020.com/2022/02/19/vscode-gdb-cpp/)
* [C++17剖析：string在Modern C++中的实现](https://www.cnblogs.com/bigben0123/p/14043586.html)
