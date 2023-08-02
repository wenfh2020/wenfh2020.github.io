---
layout: post
title:  "[c++] 浅析 std::vector::emplace_back"
categories: c/c++
author: wenfh2020
---

本文通过测试和走读 `std::vector::emplace_back` 源码，理解 C++11 引入的 emplace 新特性。

原理相对简单：emplace_back 函数的参数类型是 `万能引用`，参数通过 `完美转发` 到 std::vector 内部进行对象创建构造，可以有效减少临时对象的产生，避免对象的移动和拷贝。


* content
{:toc}



---

## 1. 概述

std::vector::emplace_back 是 C++ 中 std::vector 类的成员函数之一。

它用于在 std::vector 的末尾插入一个新元素，`而不需要进行额外的拷贝或移动操作`。具体来说，std::vector::emplace_back 函数接受可变数量的参数，并使用这些参数构造一个新元素，然后将其插入到 std::vector 的末尾。这个函数的优点是可以避免额外的拷贝或移动操作，从而提高性能。

> 文字来源：ChatGPT

---

## 2. 测试源码

* 系统。

```shell
g++ --version                                 
g++ (GCC) 4.8.5 20150623 (Red Hat 4.8.5-44)
Copyright (C) 2015 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

* 测试源码。

<div align=center><img src="/images/2023/2023-08-01-23-18-17.png" data-action="zoom"></div>

```cpp
/* g++ -O0 -std=c++11 test.cpp -o test && ./test */
#include <iostream>
#include <vector>

class Data {
   public:
    Data(const std::string& str) {
        m_str = str;
        std::cout << m_str << " constructed" << std::endl;
    }
    Data(const Data& d) : m_str(d.m_str) {
        std::cout << m_str << " copy constructed"
                  << std::endl;
    }
    Data(Data&& d) : m_str(std::move(d.m_str)) {
        std::cout << m_str << " moved constructed" << std::endl;
    }
    Data& operator=(const Data& rhs) {
        if (this != &rhs) {
            m_str = rhs.m_str;
            std::cout << m_str << " copy assigned" << std::endl;
        }
        return *this;
    }
    Data& operator=(Data&& rhs) {
        if (this != &rhs) {
            m_str = std::move(rhs.m_str);
            std::cout << m_str << " move assigned" << std::endl;
        }
        return *this;
    }

   private:
    std::string m_str;
};

int main() {
    std::vector<Data> datas;
    datas.reserve(16);

    Data a("aa");
    datas.push_back(a);
    std::cout << std::endl;

    datas.push_back(Data("bb"));
    std::cout << std::endl;

    Data c("cc");
    datas.emplace_back(c);
    std::cout << std::endl;

    datas.emplace_back(Data("dd"));
    std::cout << std::endl;

    datas.emplace_back("ee");
    return 0;
}
```

---

* 结果。

```shell
# g++ -O0 -std=c++11 test.cpp -o test && ./test 
aa constructed
aa copy constructed
-------------
bb constructed
bb moved constructed
-------------
cc constructed
cc copy constructed
-------------
dd constructed
dd moved constructed
-------------
ee constructed
-------------
```

---

## 3. 源码剖析

上面的测试结果反馈了一些有趣的信息：在对象元素的插入过程中，有的触发拷贝构造，有的触发移动构造，有的两者都没触发。为什么会这样呢？通过查看 emplace_back 的内部源码实现，我们将会找到答案。

---

通过走读源码：

1. 我们可以发现 emplace_back 的输入参数类型是 `万能引用`，入参通过 `完美转发` 给内部 ::new 实现对象构造，并将其追加到数组对应的位置。

2. 测试例程里 `datas.emplace_back("ee");`，它插入对象元素，并没有触发拷贝构造和移动构造。因为 emplace_back 接口传递的是字符串常量，而真正的对象构造是在内部实现的：`::new ((void*)__p) _Up(std::forward<_Args>(__args)...);` ，在插入对象元素的整个过程中，并未产生须要拷贝和移动的任何 `临时对象`。

* 万能引用参数类型 + 完美转发。

> 详细知识请查看《Effective Modern C++》- 第五章：右值引用、移动语义和完美转发。

```cpp
/* /usr/include/c++/4.8.2/debug/vector */
template <typename _Tp, typename _Allocator = std::allocator<_Tp> >
class vector : public _GLIBCXX_STD_C::vector<_Tp, _Allocator>,
               public __gnu_debug::_Safe_sequence<vector<_Tp, _Allocator> > {
    ...
    // emplace_back 参数是万能引用。
    template <typename... _Args>
    void emplace_back(_Args&&... __args) {
        bool __realloc = _M_requires_reallocation(this->size() + 1);
        // 完美转发传递参数。
        _Base::emplace_back(std::forward<_Args>(__args)...);
        ...
    }
#endif
    ...
};
```

* 参数转发到内部进行对象构造。

```cpp
/* /usr/include/c++/4.8.2/bits/vector.tcc */
#if __cplusplus >= 201103L
template <typename _Tp, typename _Alloc>
template <typename... _Args>
void vector<_Tp, _Alloc>::emplace_back(_Args&&... __args) {
    if (this->_M_impl._M_finish != this->_M_impl._M_end_of_storage) {
        _Alloc_traits::construct(this->_M_impl, this->_M_impl._M_finish,
                                 std::forward<_Args>(__args)...);
        ++this->_M_impl._M_finish;
    } else {
        _M_emplace_back_aux(std::forward<_Args>(__args)...);
    }
}
#endif

/* /usr/include/c++/4.8.2/bits/alloc_traits.h */
template <typename _Tp, typename... _Args>
static typename enable_if<__construct_helper<_Tp, _Args...>::value, void>::type
_S_construct(_Alloc& __a, _Tp* __p, _Args&&... __args) {
    __a.construct(__p, std::forward<_Args>(__args)...);
}

template <typename _Tp, typename... _Args>
static auto construct(_Alloc& __a, _Tp* __p, _Args&&... __args)
    -> decltype(_S_construct(__a, __p, std::forward<_Args>(__args)...)) {
    _S_construct(__a, __p, std::forward<_Args>(__args)...);
}

/* /usr/include/c++/4.8.2/ext/new_allocator.h */
template <typename _Tp>
class new_allocator {
#if __cplusplus >= 201103L
    template <typename _Up, typename... _Args>
    void construct(_Up* __p, _Args&&... __args) {
        // 新建构造对象，并通过完美转发给对象传递对应的参数。
        ::new ((void*)__p) _Up(std::forward<_Args>(__args)...);
    }
#endif
};
```

---

## 4. 注意

本文测试用例调用了 `std::vector::reserve` 预分配了动态数组空间，如果没有这一行源码，我们将会看到不一样的结果。

因为动态数组，使用的是连续的内存空间，一些操作可能会触发内存的动态扩展，这个过程中将会产生数据拷贝。所以当我们不了解容器内部具体实现时，最好不要往容器里保存类/结构对象这样的元素，保存 `对象指针` 是个不错的选择，这样即使容器内部发生数据拷贝，成本也比较低。

```cpp
aa constructed
aa copy constructed
-------------
bb constructed
bb moved constructed
aa copy constructed
-------------
cc constructed
cc copy constructed
aa copy constructed
bb copy constructed
-------------
dd constructed
dd moved constructed
-------------
ee constructed
aa copy constructed
bb copy constructed
cc copy constructed
dd copy constructed
-------------
```

---

## 5. 引用

* 《Effective Modern C++》
