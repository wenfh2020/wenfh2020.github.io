---
layout: post
title:  "[c++] 浅析 std::vector::emplace_back"
categories: c/c++
author: wenfh2020
---

本文通过测试和走读 `std::vector::emplace_back` 源码，理解 C++11 引入的 emplace 新特性。

划重点：右值引用，完美转发。


* content
{:toc}



---

## 1. 概述

std::vector::emplace_back 是 C++ 中 std::vector 类的成员函数之一。

它用于在 std::vector 的末尾插入一个新元素，`而不需要进行额外的拷贝或移动操作`。具体来说，std::vector::emplace_back 函数接受可变数量的参数，并使用这些参数构造一个新元素，然后将其插入到 std::vector 的末尾。这个函数的优点是可以 `避免额外的拷贝或移动操作`，从而提高性能。

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

我们通过上述测试源码去观测相关接口的使用，会发现一些有趣的现象：有的接口触发拷贝构造，有的触发移动构造，有的上述两者都没触发。为什么会这样呢？如何使用才是最简单的呢？通过查看源码，我们将会找到答案。

---

通过走读源码：

1. 我们可以发现 emplace_back 的接口参数类型是右值引用，参数通过完美转发给内部 ::new 实现对象构造，并将其追加到数组对应的位置。

2. 我们也不难理解，测试例程里 `datas.emplace_back("ee");` 这样实现为啥是最简单的了，它确实没有额外的拷贝或移动操作。因为 emplace_back 接口传递的是字符串常量，而真正的对象构造是在内部实现的 `::new ((void*)__p) _Up(std::forward<_Args>(__args)...);` ，并没有产生需要拷贝和移动的任何临时对象。

```cpp
/* /usr/include/c++/4.8.2/debug/vector */
template <typename _Tp, typename _Allocator = std::allocator<_Tp> >
class vector : public _GLIBCXX_STD_C::vector<_Tp, _Allocator>,
               public __gnu_debug::_Safe_sequence<vector<_Tp, _Allocator> > {
    ...
#if __cplusplus >= 201103L
        template <typename _Up = _Tp>
        typename __gnu_cxx::__enable_if<!std::__are_same<_Up, bool>::__value,
                                        void>::__type
        push_back(_Tp&& __x) {
        emplace_back(std::move(__x));
    }

    // emplace_back 参数是右值引用。
    template <typename... _Args>
    void emplace_back(_Args&&... __args) {
        bool __realloc = _M_requires_reallocation(this->size() + 1);
        // 参数的传递使用完美转发。
        _Base::emplace_back(std::forward<_Args>(__args)...);
        ...
    }
#endif
    ...
};

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
        // 新建构造对象，并通过完美转发传递给对象传递对应的参数。
        ::new ((void*)__p) _Up(std::forward<_Args>(__args)...);
    }
#endif
};
```

---

## 4. 注意

上述测试例子调用了 `std::vector::reserve` 预分配了动态数组空间，如果没有这一行源码，我们将会看到下面这样的结果。

因为动态数组，使用的是连续的内存空间，空间可能会根据当前数据量进行动态扩展，在内存扩展过程中将会产生数据拷贝。所以当我们不了解容器内部具体实现时，最好不要往容器里保存类/结构对象这样的数值，可以考虑保存对象指针，这样容器内部即使发生数据拷贝，成本也比较少。

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
