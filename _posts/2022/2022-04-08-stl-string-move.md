---
layout: post
title:  "[stl 源码分析] 移动语义是如何影响程序性能的（C++11）"
categories: c/c++
tags: stl sort
author: wenfh2020
---

本文将结合测试例子走读 `std::string` 和 `std::vector` 源码，观察程序是如何通过 `移动语义` 影响程序性能的。

> 右值引用，移动语义，等详细知识可以参考：《Effective Modern C++》-- 第五章



* content
{:toc}

---

## 1. 概念

这里借助 ChatGPT 的回答来借花献佛。

### 1.1. 移动语义

C++ 移动语义是一种在 C++11 中引入的特性，它允许对象的资源（如堆内存）在移动时被转移而不是复制。

传统上，当对象被赋值或传递给函数时，会进行复制操作，这可能会导致性能损失，移动语义通过使用 `右值引用` 和 `移动构造函数` 来解决这个问题。`右值引用` 允许我们标识出临时对象或即将销毁的对象，而移动构造函数则允许我们将资源从一个对象转移到另一个对象，而不进行复制。

这样可以避免不必要的内存分配和释放，提高程序的性能。

> 文字来源：ChatGPT

---

### 1.2. std::move

C++11 中的 std::move 是一个函数模板，用于将对象转换为右值引用。

它的作用是告诉编译器，我们希望将对象的资源转移到另一个对象，而不是进行复制操作。std::move 实际上只是将对象的类型转换为右值引用类型，并不会真正移动对象的资源。

移动操作的实际发生是由对象的移动构造函数或移动赋值运算符来完成的。使用 std::move 可以显式地指示编译器进行移动操作，从而提高代码的性能。

> 文字来源：ChatGPT

---

```cpp
/* bits/move.h */

template <typename _Tp>
constexpr typename std::remove_reference<_Tp>::type&&
move(_Tp&& __t) noexcept {
    return static_cast<typename std::remove_reference<_Tp>::type&&>(__t);
}
```

---

## 2. 源码分析

### 2.1. std::string

<div align=center><img src="/images/2022/2022-04-09-12-58-38.png" data-action="zoom"/></div>

---

#### 2.1.1. 移动构造

浅拷贝，实现了原对象成员数据转移到目标对象，原对象成员数据被重置。

* 测试源码。

```cpp
/* g++ -g -O0 -W -std=c++11 test.cpp -o test -D_GLIBCXX_DEBUG && ./test */
#include <iostream>

int main() {
    std::string s("1234567890123456789");
    std::string ss(std::move(s)); /* 右值引用。*/
    std::cout << s << " " << ss << std::endl;
    return 0;
}
```

* stl 源码，移动构造逻辑简单，当数据量比较大时，可以避免深拷贝数据带来的开销。

```cpp
/* bits/basic_string.h */
template <typename _CharT, typename _Traits, typename _Alloc>
class basic_string {
    ...
    /* 移动构造函数。*/
    basic_string(basic_string&& __str) noexcept
        : _M_dataplus(_M_local_data(), std::move(__str._M_get_allocator())) {
        if (__str._M_is_local()) {
            /* 参考：enum { _S_local_capacity = 15 / sizeof(_CharT) };
               当原对象数据长度 <= 15，程序会跑到这里来。*/
            traits_type::copy(_M_local_buf, __str._M_local_buf, _S_local_capacity + 1);
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
/* g++ -g -O0 -W -std=c++11 test.cpp -o test -D_GLIBCXX_DEBUG && ./test */
#include <iostream>

int main() {
    std::string s("1234567890123456789");
    std::string ss(s); /* 复制构造，深拷贝数据。*/
    std::cout << s << " " << ss << std::endl;
    return 0;
}
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
    _M_construct_aux(_InIterator __beg, _InIterator __end,
                     std::__false_type) {
        typedef typename iterator_traits<_InIterator>::iterator_category _Tag;
        _M_construct(__beg, __end, _Tag());
    }
}

/* bits/basic_string.tcc */

template <typename _CharT, typename _Traits, typename _Alloc>
template <typename _InIterator>
void basic_string<_CharT, _Traits, _Alloc>::
    _M_construct(_InIterator __beg, _InIterator __end, std::forward_iterator_tag) {
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

接下来分析一下，动态数组容器是如何通过移动方式减少拷贝的。

* 测试源码。

```cpp
/* g++ -g -O0 -std=c++11 test.cpp -o test -D_GLIBCXX_DEBUG && ./test */
#include <iostream>
#include <vector>

int main() {
    std::vector<std::string> v;
    for (int i = 0; i < 5; i++) {
        v.emplace_back(std::to_string(i));
    }

    std::cout << "--- no move ---" << std::endl;
    std::vector<std::string> vv = v;
    std::cout << "v   size: " << v.size() << std::endl;
    std::cout << "vv  size: " << vv.size() << std::endl;
    std::cout << "--- no move ---" << std::endl;

    std::cout << "--- move ---" << std::endl;
    std::vector<std::string> vvv = std::move(v); /* 右值引用。*/
    std::cout << "v   size: " << v.size() << std::endl;
    std::cout << "vv  size: " << vv.size() << std::endl;
    std::cout << "vvv size: " << vvv.size() << std::endl;
    std::cout << "--- move ---" << std::endl;
    return 0;
}
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

* 其它。有兴趣的朋友可以观测一下下面自定义结构的程序运行结果。

```cpp
#include <iostream>
#include <vector>

struct A {
    std::string s;
    A(std::string str) : s(std::move(str)) { std::cout << "constructed\n"; }
    A(const A& o) : s(o.s) { std::cout << "copy constructed\n"; }
    A(A&& o) : s(std::move(o.s)) { std::cout << "move constructed\n"; }
    ~A() { std::cout << "destructed\n"; }
    A& operator=(const A& rhs) {
        if (&rhs != this) {
            s = rhs.s;
            std::cout << " copy assigned\n";
        }
        return *this;
    }
    A& operator=(A&& rhs) {
        if (&rhs != this) {
            s = std::move(rhs.s);
            std::cout << " move assigned\n";
        }
        return *this;
    }
};

int main() {
    std::vector<A> v;
    for (int i = 0; i < 5; i++) {
        std::cout << i << " ---" << std::endl;
        // v.push_back(std::to_string(i));
        v.emplace_back(std::to_string(i));
    }

    std::cout << "--- no move ---" << std::endl;
    std::vector<A> vv = v;
    std::cout << "v size: " << v.size() << std::endl;
    std::cout << "vv size: " << vv.size() << std::endl;
    std::cout << "--- no move ---" << std::endl;

    std::cout << "--- move ---" << std::endl;
    /* 右值引用。*/
    std::vector<A> vvv = std::move(vv);
    std::cout << "v size: " << vv.size() << std::endl;
    std::cout << "vv size: " << vv.size() << std::endl;
    std::cout << "vvv size: " << vvv.size() << std::endl;
    std::cout << "--- move ---" << std::endl;
    return 0;
}
```

---

## 3. 小结

* 通过调试和走读 stl 源码，可以看到 std::string / std::vector 移动语义的实现，它们是如何影响程序性能的。
* 自定义的类实体对象，轻易不要传到 stl 容器里，因为你不知道里面有啥拷贝操作，反之应该传递对象指针，这样内部拷贝的成本就会比较低。

---

## 4. 参考

* 《Effective Modern C++》
* [(ubuntu) vscode + gdb 调试 c++](https://wenfh2020.com/2022/02/19/vscode-gdb-cpp/)
* [C++17剖析：string在Modern C++中的实现](https://www.cnblogs.com/bigben0123/p/14043586.html)
