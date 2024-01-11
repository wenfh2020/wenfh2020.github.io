---
layout: post
title:  "[stl 源码分析] 浅析 std::vector::emplace_back"
categories: c/c++
tags: stl emplace
author: wenfh2020
---

本文通过测试和结合 [std::vector::emplace_back](https://cplusplus.com/reference/vector/vector/emplace_back/) 实现源码，去理解它的功能和作用。

* content
{:toc}

---

## 1. 概念

`std::vector::emplace_back` 主要作用是在 vector 末尾直接构造一个新元素，而不需要先创建临时对象然后再将其复制或移动到 vector 中，这样可以提高程序的效率。

---

## 2. push_back 与 emplace_back 区别

都是 vector 追加元素接口，emplace_back 与 push_back 有什么区别呢？

通过测试实例，可以看到它们的工作结果：

1. 参数都支持左值引用，外部对象通过左值引用参数类型，传入 vector 内部进行**复制保存**。
2. 参数都支持右值引用，A 临时对象通过右值引用参数类型，传入 vector 内部进行**资源转移**。
3. push_back 的字符串实参隐形转换为 A 临时对象，传入 vector 内部再进行资源转移，而 emplace_back 将参数传入 std::vector 内部进行构造对象 A，减少了临时对象的创建。

小结：接口都支持左值引用和右值引用，emplace_back 接口支持参数传递到 vector 进行构造，避免临时对象的创建开销。

|序号|push_back| 结果| emplace_back|结果|
|:--:|:--|:--|:--|:--|
|1|A a1("a1");<br> datas.push_back(a1);|A(const char*): a1<br>A(const A&): a1|A a2("a2");<br>datas.emplace_back(a2);|A(const char*): a2<br>A(const A&): a2|
|2|datas.push_back(A("b1"));|A(const char*): b1<br>A(A&&): b1|datas.emplace_back(A("b2"));|A(const char*): b2<br>A(A&&): b2|
|3|datas.push_back("c1");|A(const char*): c1<br>A(A&&): c1|datas.emplace_back("c2");|A(const char*): c2|

```cpp
/* g++ -O0 -std=c++11 test.cpp -o t && ./t */
#include <iostream>
#include <vector>

class A {
   public:
    A(const char* s) : m_str(s) {
        std::cout << "A(const char*): "
                  << m_str << "\n";
    }

    A(const A& d) : m_str(d.m_str) {
        std::cout << "A(const A&): "
                  << m_str << "\n";
    }

    A(A&& d) : m_str(std::move(d.m_str)) {
        std::cout << "A(A&&): "
                  << m_str << "\n";
    }

   private:
    std::string m_str;
};

int main() {
    std::vector<A> datas;
    datas.reserve(16);

    A a1("a1");
    datas.push_back(a1);
    datas.push_back(A("b1"));
    datas.push_back("c1");

    std::cout << "---\n";

    A a2("a2");
    datas.emplace_back(a2);
    datas.emplace_back(A("b2"));
    datas.emplace_back("c2");
    return 0;
}

// 输出：
// A(const char*): a1
// A(const A&): a1
// A(const char*): b1
// A(A&&): b1
// A(const char*): c1
// A(A&&): c1
// ---
// A(const char*): a2
// A(const A&): a2
// A(const char*): b2
// A(A&&): b2
// A(const char*): c2
```

---

### 2.1. 源码剖析

我们可以从内部实现源码观察：

1. emplace_back 形参是个万能引用：它可以是左值引用，也可以是右值引用，这样可以减少接口的重载。
2. push_back 则重载了右值引用参数，它内部调用了 emplace_back。
3. C++11 引入了右值引用，结合移动语义，可以实现对象间资源的转移而非复制，减少了复制带来的性能开销。
4. 两者参数作为引用类型进行传递，可以减少复制。
5. 容器元素对象可以在内部直接构造，不需要外部创建，减少复制和转移的开销。
6. emplace_back 内部将传入参数完美转发传递到其它函数处理，可以实现更多优化。

   1. 使用连续内存空间，可以有效减少内存碎片。
   2. 减少 new 操作次数，不需要每个元素对象都 new 一次。
   3. 各个元素对象内存在连续内存空间上存储，系统访问连续内存空间要比访问离散的更高效。(重载的 new 操作符，在自由存储区（连续内存空间）上构造元素对象)。

* 内部接口。

```cpp
void push_back(const _Tp& __x) {
    ...
}

template <typename _Up = _Tp>
typename __gnu_cxx::__enable_if<
    !std::__are_same<_Up, bool>::__value, void>::__type
push_back(_Tp&& __x) {
    emplace_back(std::move(__x));
}

void emplace_back(_Args&&... __args) {
    ...
    _Base::emplace_back(std::forward<_Args>(__args)...);
    ...
}
```

* emplace_back 参数传递和对象构造流程。

```shell
|-- main
  |-- std::vector
    |-- emplace_back(_Args&&... __args)
      # std::forward 完美转发参数
      |-- _Base::emplace_back(std::forward<_Args>(__args)...);
        # 内部构造对象
        |-- _Alloc_traits::construct(this->_M_impl, this->_M_impl._M_finish,
                                    std::forward<_Args>(__args)...);
          |-- __a.construct(__p, std::forward<_Args>(__args)...);
            # 结合传递的参数，通过 new 构造对象
            |-- ::new((void *)__p) _Up(std::forward<_Args>(__args)...);
              # 根据传递的参数，在指定的（自由存储区）内存空间 __p 上构造对象
              |-- operator new(std::size_t, void* __p)
                |-- return _p;
```

* emplace_back 内部详细实现源码。

```cpp
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

## 3. 注意

上面测试用例调用了 `std::vector::reserve` 预分配了动态数组空间，如果没有这一行源码，我们将会看到不一样的结果，多了很多复制操作。

```shell
# 输出：
A(const char*): a1
A(const A&): a1
A(const char*): b1
A(A&&): b1
A(const A&): a1
A(const char*): c1
A(A&&): c1
A(const A&): a1
A(const A&): b1
---
A(const char*): a2
A(const A&): a2
A(const char*): b2
A(A&&): b2
A(const A&): a1
A(const A&): b1
A(const A&): c1
A(const A&): a2
A(const char*): c2
```

因为动态数组，使用的是连续的内存空间，当增加对象超出容器内部的存储空间时，会触发内存的动态扩展，这个过程中可能产生数据复制。

那么上面测试例子的元素对象为什么不是转移而是复制构造呢？事实上我们应该为移动构造函数添加 `noexcept` 标识，这样才会确保执行移动语义。

> noexcept 的一个重要用途是在移动语义和异常安全性中。
>
> 例如，如果一个对象的移动构造函数被标记为 noexcept，那么在需要重新分配内存的情况下，标准库容器可以安全地将对象移动而不是复制。

---

## 4. 引用

* 《Effective Modern C++》
* [std::vector::emplace_back](https://cplusplus.com/reference/vector/vector/emplace_back/)
* [std::move_if_noexcept](https://www.apiref.com/cpp-zh/cpp/utility/move_if_noexcept.html)
