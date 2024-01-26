---
layout: post
title:  "[stl 源码分析] std::list::size 时间复杂度"
categories: c/c++
tags: stl list
author: wenfh2020
---

项目在 Centos 上压测，很多性能问题都暴露了出来，没想到 std::list::size 接口，时间复杂度竟然是 O(N)。

看了 Centos 的 stl 源码，发现确实是循环遍历实现的，为啥每次都要循环计算大小呢？感觉这里是个坑啊。





* content
{:toc}

---

## 1. 现象

功能测试完成后，发现 cpu 一直很高，所以就上火焰图，看到 std::list::size 占满了负载。

<div align=center><img src="/images/2021/2021-04-09-09-13-49.png" data-action="zoom"/></div>

> 火焰图参考：[如何生成火焰图🔥](https://wenfh2020.com/2020/07/30/flame-diagram/)

---

## 2. 原因

g++ 低版本的坑，为了兼容某些功能，列表通过遍历节点获取列表大小。

出现问题的 g++ 版本是：4.8.5。

* g++ 版本。

```shell
# g++ --version
g++ (GCC) 4.8.5 20150623 (Red Hat 4.8.5-44)
```

* 测试用例。判断列表为空，谨慎使用 std::list::size()，最好使用 std::list::empty()。

```cpp
#include <iostream>
#include <list>

int main() {
    std::list<int> lst;
    for (int i = 0; i < 10; i++) {
        lst.push_back(i);
    }

    if (!lst.empty()) {
        std::cout << "list is not empty 1.\n";
    }

    // 【警告】避免使用
    if (lst.size() != 0) {
        std::cout << "list is not empty 2.\n";
    }
    return 0;
}
```

---

## 3. 源码分析

std::list 通过遍历列表，获取列表大小。

### 3.1. 低版本 STL 源码

* 源码调用逻辑。

```shell
|-- main
  |-- std::list::size
    |-- std::list::_M_node_count
      |-- std::distance
        |-- std::__distance
```

* 源码。

```cpp
template <typename _Tp, typename _Alloc = std::allocator<_Tp>>
    class list : protected _List_base<_Tp, _Alloc> {
    ...
    /**  Returns the number of elements in the %list.  */
    size_type size() const _GLIBCXX_NOEXCEPT { 
        return std::distance(begin(), end()); 
    }
    ...
}

template<typename _InputIterator>
inline typename iterator_traits<_InputIterator>::difference_type
distance(_InputIterator __first, _InputIterator __last) {
    // concept requirements -- taken care of in __distance
    return std::__distance(
        __first, __last, std::__iterator_category(__first));
}

template <typename _InputIterator>
inline typename iterator_traits<_InputIterator>::difference_type
__distance(_InputIterator __first, 
          _InputIterator __last, input_iterator_tag) {
    // concept requirements
    __glibcxx_function_requires(
        _InputIteratorConcept<_InputIterator>)

    /* 遍历列表获取 __n。*/
    typename iterator_traits<_InputIterator>::difference_type __n = 0;
    while (__first != __last) {
        ++__first;
        ++__n;
    }
    return __n;
}
```

---

### 3.2. 高版本 STL 源码

`_List_node_header` 结构添加了 `_M_size` 成员保存列表大小。

> 引入了 `_GLIBCXX_USE_CXX11_ABI` 宏，主要是为了处理 std::string 的 copy-on-write 问题和 std::list::size 时间复杂度问题。

* g++ 版本。

```shell
# g++ --version
g++ (GCC) 9.3.1 20200408 (Red Hat 9.3.1-2)
```

* 源码调用逻辑。

```shell
|-- main
  |-- std::list::size
    |-- std::list::_M_node_count
      |-- std::list::_M_get_size
        |-- return _M_impl._M_node._M_size;
```

* 内部源码。

```cpp
// 增加了 _M_size 列表大小成员
struct _List_node_header : public _List_node_base {
#if _GLIBCXX_USE_CXX11_ABI
    std::size_t _M_size;
#endif
}

template <typename _Tp, typename _Alloc = std::allocator<_Tp> >
class list : protected _List_base<_Tp, _Alloc> {
    //...
    size_type
    size() const _GLIBCXX_NOEXCEPT {
        return _M_node_count();
    }

#if _GLIBCXX_USE_CXX11_ABI
    static size_t
    _S_distance(const_iterator __first, const_iterator __last) {
        return std::distance(__first, __last);
    }

    // return the stored size
    size_t _M_node_count() const {
        return this->_M_get_size();
    }
#else
    // dummy implementations used when the size is not stored
    static size_t
    _S_distance(const_iterator, const_iterator) {
        return 0;
    }

    // count the number of nodes
    size_t _M_node_count() const {
        return std::distance(begin(), end());
    }
#endif

#if _GLIBCXX_USE_CXX11_ABI
    size_t _M_get_size() const {
        return _M_impl._M_node._M_size;
    }
#endif
};
```
