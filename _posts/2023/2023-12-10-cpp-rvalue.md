---
layout: post
title:  "[C++] 右值引用"
categories: c/c++
author: wenfh2020
---

右值引用/万能引用/引用折叠/移动语义/完美转发。

这一串关键字很容易把人整晕~，要理解它们需要寻找突破口：`右值引用`。

所有这些概念的最终目标只有一个：性能。

1. 资源使用过程中减少复制。
2. 将那些准备销毁的资源进行转移，重复利用。



---

* content
{:toc}



---

## 1. 引用

什么是引用？

引用可以看作是变量的一个 `别名`，它与原变量共享同一块内存地址；这意味着对引用的修改会直接反映在原变量上。

接下来通过测试代码和反汇编去观察它的工作流程。

* 测试代码。b 是 a 的引用，改变了 b 的值，也相当于改变了 a 的值。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <iostream>

int main() {
    int a = 1;
    int& b = a;
    b = 2;
    std::cout << "a: " << a << ", b: " << b << std::endl;
    return 0;
}

// 输出：
// a: 2, b: 2
```

* 汇编。反汇编可以查看到引用其实也是一个变量，有自己的地址空间，只不过它保存了被引用对象的地址，当需要读写时，它会通过保存的地址，跳转到被引用对象上去使用。—— 这个逻辑咋看起来有点像指针啊 ^_^！。

```shell
# objdump -CdStT test > asm.log
# a 变量的地址：-0x1c(%rbp)
# b 变量的地址：-0x18(%rbp) 

000000000040081d <main>:
...
# 将 1 数值，赋值给 a 变量。
400828: c7 45 e4 01 00 00 00  movl   $0x1,-0x1c(%rbp)
# b 变量地址空间保存了 a 变量的地址。
40082f: 48 8d 45 e4           lea    -0x1c(%rbp),%rax
400833: 48 89 45 e8           mov    %rax,-0x18(%rbp)
# 将数值 2 赋值给引用 b，
# 事实上通过 b 变量保存的 a 地址，跳转到 a 空间，进行存储。
400837: 48 8b 45 e8           mov    -0x18(%rbp),%rax
40083b: c7 00 02 00 00 00     movl   $0x2,(%rax)
400841: 48 8b 45 e8           mov    -0x18(%rbp),%rax
...
```

<div align=center><img src="/images/2023/2023-12-12-12-51-01.png" data-action="zoom"></div>

---

## 2. 右值引用

### 2.1. 概念

C++11 引入了一种新的引用类型：右值引用，**它主要用于优化临时对象的资源管理**。

右值是临时的，它不具有明确的内存地址，例如：字面量、临时对象或者返回值。

右值引用的声明方式：在类型后面使用两个 & 符号（type&&），例如：int&&。

---

概念比较抽象，我们通过测试源码，先简单地去了解它使用。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <iostream>
#include <type_traits>

class A {
};

A makeObj() {
    A a;
    return a;
}

void f(A&& a) {
    std::cout << "f(A&&)" << std::endl;
}

void f(const A& a) {
    std::cout << "f(A&)" << std::endl;
}

int main() {
    // 字面量：k 右值引用。
    int&& a = 1;
    std::cout << "a is rvalue? "
              << std::is_same<decltype(a), int&&>::value
              << std::endl;

    // 临时变量作为右值引用在函数中传递。
    f(A());

    // 延长函数返回值的生命周期。
    auto&& b = makeObj();
    std::cout << "b is rvalue? "
              << std::is_same<decltype(b), A&&>::value
              << std::endl;

    A c;
    // 强制转换左值 c 为右值引用 d。
    A&& d = std::move(c);
    std::cout << "d is rvalue? "
              << std::is_same<decltype(d), A&&>::value
              << std::endl;
    return 0;
}

// 输出：
// a is rvalue? 1
// f(A&&)
// b is rvalue? 1
// d is rvalue? 1
```

---

### 2.2. 注意

要注意某些场景，右值引用作为左值使用。

1. 右值引用变量作为函数的实参传递。
2. 函数的形参是左值。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <iostream>
#include <type_traits>

class A {
public:
    A() = default;
    A(const A& a) {
        std::cout <<"A(const A& a)" << std::endl;
    }

    A(A&& a) {
        std::cout <<"A(A&& a)" << std::endl;
    }

    A& operator=(A& a) {
        std::cout << "operator=(A& a)" << std::endl;
        return *this;
    }

    A& operator=(A&& a) noexcept {
        std::cout << "operator=(A&& a)" << std::endl;
        return *this;
    }
};

void f(const A& a) {
    std::cout << "f(A&)" << std::endl;
}

void f(A&& a) {
    std::cout << "f(A&&)" << std::endl;
}

void f2(const A& a) {
    std::cout << "f2(A&) arg is rvalue? "
              << std::is_same<decltype(a), A&&>::value
              << std::endl;
}

void f2(A&& a) {
    std::cout << "f2(A&&) arg is rvalue? "
              << std::is_same<decltype(a), A&&>::value
              << std::endl;
    A b(a);
    // 完美转发可以将 a 转化为原来的变量类型（晕了吧~~~~~~）
    // b = std::forward<A>(a); 
}

int main() {
    A a;
    // 强制转换左值 a 为右值引用。
    A&& b = std::move(a);
    std::cout << "b is rvalue? "
              << std::is_same<decltype(b), A&&>::value
              << std::endl;
    // 虽然 b 的变量类型是右值引用，
    // 但是 b 作为 f 函数的实参，以左值方式给 f 函数传值。
    f(b);

    // f2 的形参类型 A&& 虽然是右值引用，
    // 但是在函数内部，形参作为左值使用~~~~~
    f2(A());
    return 0;
}

// 输出：
// b is rvalue? 1
// f(A&)
// f2(A&&) arg is rvalue? 1
// A(const A& a)
```

---

## 3. 万能引用

万能引用是一种特殊的引用类型，它可以同时接受左值和右值。

它的类型是 T&& 模板变量类型或 auto&&，这些须要 `编译器推导` 的类型它是万能引用；它有可能是右值引用，也可能是右值引用，取决于传递给它的实参类型。

> 右值引用类型是：type&&，type 都是明确的类型，例如：int&& 并不须要编译器进行推导。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <iostream>
#include <type_traits>

class A {
};

template <typename T>
void f(T&& t) {
    // 因为函数形参 t 在函数内作为形参使用，
    // 要获得它的真实类型需要使用 std::forward。
    if (std::is_same<decltype(std::forward<T>(t)), A&>::value) {
        std::cout << "f(A&)" << std::endl;
    } else {
        std::cout << "f(A&&)" << std::endl;
    }
}

int main() {
    A a;
    auto&& b = a;
    std::cout << "b type: A& ? "
              << std::is_same<decltype(b), A&>::value
              << std::endl;
    f(b);

    auto&& c = A();
    std::cout << "c type: A&& ? "
              << std::is_same<decltype(c), A&&>::value
              << std::endl;
    f(A());
    return 0;
}

// 输出
// b type: A& ? 1
// f(A&)
// c type: A&& ? 1
// f(A&&)
```

---

## 4. 引用折叠

引用折叠是一种语言特性，主要用于处理模板和类型推导中的引用类型。

如果模板类型 T = A，那么 'T&' 就是 'A&'，'T&&' 就是 'A&&' 这是正确的，然而 T = A&，那么 'T&&' 就是 'A& &&'，显然这种类型是错误的，它需要编译器进行 `引用折叠`，将 'A& &&' 折叠成 'A&' 才能正确使用。

> 其它引用类型折叠场景，详细请参考下面图表。

* 模板代码。

```cpp
class A {};

template <typename T>
void f(T& t) {
}

template <typename T>
void f2(T&& t) {
}
```

* 引用折叠场景。

|T 实际类型|类型模板|折叠后类型|
|:----:|:---:|:---:|
|A|T&|A&|
|A&|T&|A&|
|A&&|T&|A&|
|A|T&&|A&&|
|A&|T&&|A&|
|A&&|T&&|A&&|

---

## 5. 移动语义

### 5.1. 概念

在 C++11 之前，我们通常通过复制构造函数来复制对象，但这种方式可能会导致资源浪费。

通过使用右值引用的移动语义，我们可以将资源从一个对象移动到另一个对象，无需复制，从而提高了效率。

例如下面的测试代码，创建 b 对象：

1. a 对象被强制转移为右值引用作为实参。
2. 右值引用实参触发 class A 的移动构造函数（移动语义）。
3. 在移动构造函数内，对象 a 的资源被转移给对象 b。

> 其它的移动语义使用场景可以参考：[[stl 源码分析] 移动语义是如何影响程序性能的（C++11）](https://www.wenfh2020.com/2022/04/08/stl-string-move/)

* 测试代码。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <string.h>
#include <iostream>

class A {
   public:
    explicit A(const char* s) {
        if (s != nullptr) {
            release();
            int len = strlen(s);
            m_data = new char[len + 1];
            memcpy(m_data, s, len + 1);
            std::cout << "A(const char*)" << std::endl;
        }
    }
    // 移动构造函数（移动语义）。
    A(A&& a) {
        release();
        m_data = a.m_data;
        a.m_data = nullptr;
        std::cout << "A(A&&)" << std::endl;
    }
    ~A() {
        release();
    }

    const char* get() const { return m_data; }

   private:
    void release() {
        if (m_data != nullptr) {
            delete[] m_data;
            m_data = nullptr;
        }
    }

   private:
    char* m_data = nullptr;
};

int main() {
    A a("hello world!");
    // 对象 a 被强制转换为右值引用。
    // 通过移动语义将 a 的资源转移给 b。
    A b(std::move(a));
    std::cout << b.get() << std::endl;
    // 危险！！！！
    // std::cout << a.get() << std::endl;
    return 0;
}

// 输出：
// A(const char*)
// A(A&&)
// hello world!
```

---

### 5.2. 注意

上面移动语义测试例子，对象间的资源转移主要做了三件事：

1. 重置目标对象 b 的内部资源。
2. 将源对象 a 的资源转移给 b。
3. 重置源对象 a 的内部资源。

因为资源移动涉及到对象资源重置，有一定危险性，特别是源对象被移动处理后，如果被再次使用是非常危险的（参考上述测试例程）。

---

### 5.3. std::move

`std::move` 是 C++ 标准库中的一个函数模板，它可以将其参数转换为右值引用，从而可以触发移动语义。

* 从实现源码可见：函数强制返回右值引用（`typename std::remove_reference<_Tp>::type&&`）。

```cpp
/* bits/move.h */
template <typename _Tp>
constexpr typename std::remove_reference<_Tp>::type&&
move(_Tp&& __t) noexcept {
    return static_cast<typename std::remove_reference<_Tp>::type&&>(__t);
}
```

* 测试源码。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <string.h>
#include <iostream>

class A {
   public:
    explicit A(const char* s) {
        if (s != nullptr) {
            release();
            int len = strlen(s);
            m_data = new char[len + 1];
            memcpy(m_data, s, len + 1);
            std::cout << "A(const char*)" << std::endl;
        }
    }
    // 移动语义
    A(A&& a) {
        release();
        m_data = a.m_data;
        a.m_data = nullptr;
        std::cout << "A(A&&)" << std::endl;
    }
    ~A() {
        release();
    }

    const char* get() const { return m_data; }

   private:
    void release() {
        if (m_data != nullptr) {
            delete[] m_data;
            m_data = nullptr;
        }
    }

   private:
    char* m_data = nullptr;
};

// 提取标准库内部源码，方便查看模板实例化源码。
template <typename _Tp>
constexpr typename std::remove_reference<_Tp>::type&&
move(_Tp&& __t) noexcept {
    return static_cast<typename std::remove_reference<_Tp>::type&&>(__t);
}

int main() {
    A a("hello world!");
    A b(move(a));
    std::cout << b.get() << std::endl;
    return 0;
}
```

* std::move 模板实例化源码，编译器将 std::move 模板类型 T 推导出为：T = A&。（工具：[cppinsights](https://cppinsights.io/)）

```cpp
// std::move 类型推导 T = A&。
template <>
inline constexpr typename std::remove_reference<A&>::type&&
move<A&>(A& __t) noexcept {
    return static_cast<typename std::remove_reference<A&>::type&&>(__t);
}

// 简化上面的类型推导。
inline constexpr A&&
move<A&>(A& __t) noexcept {
    return static_cast<A&&>(__t);
}
```

---

## 6. 完美转发

### 6.1. 概念

`std::forward` 完美转发，通常与 右值引用（T&&）一起使用，主要用于保持参数的原始值类别，在将其传递给其他函数时能够正确处理左值和右值。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <iostream>

class A {
};

void f2(const A& a) {
    std::cout << "lvalue" << std::endl;
}

void f2(A&& a) {
    std::cout << "rvalue" << std::endl;
}

// 万能引用。
template <typename T>
void f(T&& t) {
    // 完美转发。
    // 形参 t，在函数内部作为左值使用，
    // 需要通过 std::forward 将形参转换为实参原来的类型。
    f2(std::forward<T>(t));
}

int main() {
    A a;
    // 左值引用。
    f(a);
    // 右值引用。
    f(std::move(a));
    return 0;
}

// 输出：
// lvalue
// rvalue
```

---

### 6.2. std::forward

从 std::forward 的实现源码来看，并不复杂，结合上面的 `引用折叠` 来理解，就能推导出对应的引用返回类型。

* 实现源码。

```cpp
template <typename _Tp>
constexpr _Tp&&
forward(typename std::remove_reference<_Tp>::type& __t) noexcept {
    return static_cast<_Tp&&>(__t);
}
```

* T&& 引用折叠使用场景。

|T 实际类型|类型模板|折叠后类型|
|:----:|:---:|:---:|
|A|T&&|A&&|
|A&|T&&|A&|
|A&&|T&&|A&&|

* 将 std::forward 实现源码提取出来，并查看模板实例化后的代码（工具：[cppinsights](https://cppinsights.io/)）。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <iostream>

class A {
};

void f2(const A& a) {
    std::cout << "lvalue" << std::endl;
}

void f2(A&& a) {
    std::cout << "rvalue" << std::endl;
}

// 从标准库里提取出来，方便查看实例化代码。
template <typename _Tp>
constexpr _Tp&&
forward(typename std::remove_reference<_Tp>::type& __t) noexcept {
    return static_cast<_Tp&&>(__t);
}

template <typename T>
void f(T&& t) {
    f2(forward<T>(t));
}

int main() {
    A a;
    f(a);
    f(std::move(a));
    return 0;
}

// 输出：
// lvalue
// rvalue
```

* 具体的类型推导参考下面模板实例化源码。
  1. 左值引用实参传给 f 函数后，模板函数类型 T 被推导为 T = A&。
  2. 右值引用实参传给 f 函数后，模板函数类型 T 被推导为 T = A。

```cpp
// 1. 左值引用的模板推导: T = A&。
template <>
inline constexpr A&
forward<A&>(typename std::remove_reference<A&>::type& __t) noexcept {
    return static_cast<A&>(__t);
}

// 简化上面 forward 的类型推导，forward<A&> 返回 A& 左值引用。
template <>
inline constexpr A&
forward<A&>(A& __t) noexcept {
    return static_cast<A&>(__t);
}

template <>
void f<A&>(A& t) {
    f2(forward<A&>(t));
}

// ------------------------------------------

// 2. 右值引用的模板推导 T = A。
template <>
inline constexpr A&&
forward<A>(typename std::remove_reference<A>::type& __t) noexcept {
    return static_cast<A&&>(__t);
}

// 简化上面 forward 的类型推导，forward<AA&> 返回 A&& 右值引用。
template <>
inline constexpr A&&
forward<A>(A& __t) noexcept {
    return static_cast<A&&>(__t);
}

template <>
void f<A>(A&& t) {
    f2(static_cast<A&&>(forward<A>(t)));
}
```

---

## 7. 小结

* 无论是左值引用还是右值引用，首先它得是个引用，是源对象的别名。
* 右值引用对象某种程度上是将亡值的别名。将亡对象是将要被销毁的，但即便要死亡也要死得其所：移动语义，将即将销毁的源对象资源转移给目标对象，实现资源的重复利用。
* 当然引用的出现也为性能优化提供了条件，避免变量在代码逻辑里传递产生拷贝，所以万能引用（既可以是左值引用，又可以是右值引用），完美转发这种简洁的代码表达方式应运而生。

---

## 8. 引用

* 《Effective Modern C++》
* 《C++ Primer》- 第五版

---

## 9. 后记

最近遇到职业生涯最硬核的（C++）笔试：指定时间内完成 50 道选择题。

面试可以复盘知识，也帮我挑出了薄弱环节，例如 右值引用 等等，因此有了此文。

—— 既来之，则安之。感恩挑战~
