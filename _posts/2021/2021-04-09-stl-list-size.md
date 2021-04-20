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

<div align=center><img src="/images/2021-04-09-09-13-49.png" data-action="zoom"/></div>

---

## 2. 源码分析

std::list 通过遍历列表，获取列表大小。

> /usr/include/c++/4.8.2

```cpp
/* stl_list.h */
template <typename _Tp, typename _Alloc = std::allocator<_Tp>>
    class list : protected _List_base<_Tp, _Alloc> {
    ...
    /**  Returns the number of elements in the %list.  */
    size_type size() const _GLIBCXX_NOEXCEPT { 
        return std::distance(begin(), end()); 
    }
    ...
}

/* bits/stl_iterator_base_funcs.h */
template<typename _InputIterator>
inline typename iterator_traits<_InputIterator>::difference_type
distance(_InputIterator __first, _InputIterator __last) {
    // concept requirements -- taken care of in __distance
    return std::__distance(__first, __last, std::__iterator_category(__first));
}

/* bits/stl_iterator_base_funcs.h */
template <typename _InputIterator>
inline typename iterator_traits<_InputIterator>::difference_type
__distance(_InputIterator __first, _InputIterator __last, input_iterator_tag) {
    // concept requirements
    __glibcxx_function_requires(_InputIteratorConcept<_InputIterator>)

    /* 遍历列表获取 __n。*/
    typename iterator_traits<_InputIterator>::difference_type __n = 0;
    while (__first != __last) {
        ++__first;
        ++__n;
    }
    return __n;
}
```
