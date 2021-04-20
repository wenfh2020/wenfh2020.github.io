---
layout: post
title:  "[stl 源码分析] std::vector::push_back 内存扩充"
categories: c/c++
tags: stl vector expand memory
author: wenfh2020
---

std::vector::push_back 内存是如何动态增长的：增加新元素，如果超过当时的容量，则容量会扩充至原来的两倍。




* content
{:toc}

---

## 1. 概述

std::vecotr 有自己的动态内存分配策略，策略有优点也有缺点，只有充分理解它们才能更好地使用。

* 优点：避免频繁向底层分配空间，增加开销。
* 缺点：内存动态增长幅度比较大（2 倍），可能会浪费空间。而且数组是连续的内存空间，内存空间增长需要创建新的连续空间，涉及到内容拷贝，某些场景会增加系统开销。

<div align=center><img src="/images/2021-04-20-10-45-24.png" data-action="zoom"/></div>

> 图片来源：《STL 源码剖析》-- 侯捷 -- 第四章 - 序列式容器 - 4.2 vector

---

## 2. 源码分析

我们通过 C++11 的 `std::vecotr::push_back` 接口源码，看看 std::vecotr 是怎么扩充内存的，空间分配大小核心在接口 `_M_check_len`。

```cpp
/* stl_vector.h */
template <typename _Tp, typename _Alloc>
struct _Vector_base {
    typedef typename __gnu_cxx::__alloc_traits<_Alloc>::template rebind<_Tp>::other _Tp_alloc_type;
    typedef typename __gnu_cxx::__alloc_traits<_Tp_alloc_type>::pointer pointer;

    struct _Vector_impl : public _Tp_alloc_type {
        pointer _M_start;         /* 目前使用空间头部位置。 */
        pointer _M_finish;        /* 当前使用空间尾部位置。 */
        pointer _M_end_of_storage;/* 目前可用空间尾部位置。 */
    }
    ...
};

/* 追加元素。 */
template <typename _Tp, typename _Alloc = std::allocator<_Tp> >
class vector : protected _Vector_base<_Tp, _Alloc> {
    ...
    /* 追加元素，如果还有空间继续追加内容，否则分配新的空间，处理内容。 */
    void push_back(const value_type& __x) {
        if (this->_M_impl._M_finish != this->_M_impl._M_end_of_storage) {
            _Alloc_traits::construct(this->_M_impl, this->_M_impl._M_finish, __x);
            ++this->_M_impl._M_finish;
        } else {
#if __cplusplus >= 201103L
            /* c++11 */
            _M_emplace_back_aux(__x);
#else
            _M_insert_aux(end(), __x);
        }
#endif
    }
    ...
    size_type _M_check_len(size_type __n, const char* __s) const {
        if (max_size() - size() < __n)
            __throw_length_error(__N(__s));

        /* 一般情况下就是两倍空间。 */
        const size_type __len = size() + std::max(size(), __n);
        return (__len < size() || __len > max_size()) ? max_size() : __len;
    }
};

/* vector.tcc */
#if __cplusplus >= 201103L
    template <typename _Tp, typename _Alloc>
    template <typename... _Args>
    void vector<_Tp, _Alloc>::_M_emplace_back_aux(_Args&&... __args) {
        /* 检查空间长度，返回合适的长度。 */
        const size_type __len = _M_check_len(size_type(1), "vector::_M_emplace_back_aux");
        pointer __new_start(this->_M_allocate(__len));
        pointer __new_finish(__new_start);
        __try {
            /* 创建新空间，将数据写入新空间，旧空间内容复制到新空间。 */
            _Alloc_traits::construct(this->_M_impl, __new_start + size(), std::forward<_Args>(__args)...);
            __new_finish = 0;
            __new_finish = std::__uninitialized_move_if_noexcept_a(
                this->_M_impl._M_start, this->_M_impl._M_finish, __new_start, _M_get_Tp_allocator());
            ++__new_finish;
        }
        __catch(...) {
            if (!__new_finish) {
                _Alloc_traits::destroy(this->_M_impl, __new_start + size());
            }
            else {
                std::_Destroy(__new_start, __new_finish, _M_get_Tp_allocator());
            }
            _M_deallocate(__new_start, __len);
            __throw_exception_again;
        }
        /* 释放旧空间。 */
        std::_Destroy(this->_M_impl._M_start, this->_M_impl._M_finish, _M_get_Tp_allocator());
        _M_deallocate(this->_M_impl._M_start, this->_M_impl._M_end_of_storage - this->_M_impl._M_start);
        /* 位置指向新空间。 */
        this->_M_impl._M_start = __new_start;
        this->_M_impl._M_finish = __new_finish;
        this->_M_impl._M_end_of_storage = __new_start + __len;
    }
#endif
```

---

## 3. 小结

* 「源码面前，了无秘密。」 ———— 向侯捷先生学习。
* 从源码可以看到，std::vector 追加元素，会动态扩展空间。如果我们使用 std::vector 添加大量元素，会涉及内存频繁地扩展，内容频繁地拷贝。如果增加的内容可以预期的，我们可以考虑通过 `resize` 接口一次性给 std::vector 分配预期的内存空间，避免逐步扩展带来的性能开销。

---

## 4. 参考

* 《STL 源码剖析》
* [序列容器之vector](https://www.kancloud.cn/digest/stl-sources/177267)
