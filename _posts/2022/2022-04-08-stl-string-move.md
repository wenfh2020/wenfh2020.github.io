---
layout: post
title:  "[stl 源码分析] 通过 std::string 分析 std::move 作用（C++11）"
categories: c/c++
tags: stl sort
author: wenfh2020
---

std::move 顾名思义：`移动`。

本章将通过走读 C++11 的 std::string 源码，分析移动语义的作用：避免数据拷贝，提高程序性能。



* content
{:toc}

---

## 1. 概述

通过 gdb 调试方式走读 stl 源码。

* g++ 版本。

```shell
# g++ --version                                                             
g++ (Ubuntu 9.4.0-1ubuntu1~20.04.1) 9.4.0
```

* 测试源码。

```cpp
/* g++ -g -O0 -W -std=c++11 test.cpp -o test -D_GLIBCXX_DEBUG && ./test */
#include <iostream>

int main() {
    std::string s("1234567890123456789");
    std::string ss(s);
    std::string sss(std::move(s));
    return 0;
}
```

* stl 源码。

<div align=center><img src="/images/2022-04-08-18-52-02.png" data-action="zoom"/></div>

---

## 2. 源码分析

### 2.1. 复制构造

复制构造，申请新的空间，深拷贝数据。

* 测试源码。

```cpp
/* g++ -g -O0 -W -std=c++11 test_smptr.cpp -o test -D_GLIBCXX_DEBUG && ./test */
#include <iostream>

int main() {
    std::string s("1234567890123456789");
    std::string ss(s); /* 复制构造，深拷贝数据。*/
    return 0;
}
```

* stl 源码。

```cpp
/* bits/basic_string.h */
template<typename _CharT, typename _Traits, typename _Alloc>
class basic_string {
    ...
    basic_string(const basic_string& __str)
      : _M_dataplus(_M_local_data(),
            _Alloc_traits::_S_select_on_copy(__str._M_get_allocator())) {
        /* 构造分配空间，深拷贝数据。*/
        _M_construct(__str._M_data(), __str._M_data() + __str.length());
    }

    template<typename _InIterator>
    void
    _M_construct(_InIterator __beg, _InIterator __end) {
      typedef typename std::__is_integer<_InIterator>::__type _Integral;
      _M_construct_aux(__beg, __end, _Integral());
    }

    template<typename _InIterator>
    void
    _M_construct_aux(_InIterator __beg, _InIterator __end,
             std::__false_type) {
        typedef typename iterator_traits<_InIterator>::iterator_category _Tag;
        _M_construct(__beg, __end, _Tag());
    }
}

/* bits/basic_string.tcc */

template<typename _CharT, typename _Traits, typename _Alloc>
template<typename _InIterator>
void
basic_string<_CharT, _Traits, _Alloc>::
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
    } __catch(...) {
        _M_dispose();
        __throw_exception_again;
    }
    _M_set_length(__dnew);
}

template<typename _CharT, typename _Traits, typename _Alloc>
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

### 2.2. 移动构造

通过浅拷贝的方式，实现了原对象内存数据的转移，但是原对象数据被重置。

* 测试源码。

```cpp
/* g++ -g -O0 -W -std=c++11 test.cpp -o test -D_GLIBCXX_DEBUG && ./test */
#include <iostream>

int main() {
    std::string s("1234567890123456789");
    std::string sss(std::move(s));
    return 0;
}
```

* stl 源码，可见移动构造逻辑简单，当数据量比较大时，可以避免数据深拷贝。

```cpp
/* bits/basic_string.h */
template<typename _CharT, typename _Traits, typename _Alloc>
class basic_string {
    ...
    basic_string(basic_string&& __str) noexcept
        : _M_dataplus(_M_local_data(), std::move(__str._M_get_allocator())) {
        if (__str._M_is_local()) {
            /* 参考：enum { _S_local_capacity = 15 / sizeof(_CharT) }; 
               当原对象数据长度 <= 15，会跑到这里来。
             */
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

## 3. 小结

通过 stl 源码走读，可以看到移动语义，在 std::string 的复制构造和移动构造实现，对原对象数据进行深浅拷贝的处理逻辑，这样对程序性能影响就应该有比较直观的认知了。

---

## 4. 参考

* [C++17剖析：string在Modern C++中的实现](https://www.cnblogs.com/bigben0123/p/14043586.html)
