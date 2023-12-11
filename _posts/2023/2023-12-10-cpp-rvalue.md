---
layout: post
title:  "[c++] 右值引用"
categories: c++
author: wenfh2020
---

右值引用/万能引用/引用折叠/移动语义/完美转发。

这一串关键字很容易把人整晕~，要理解它们需要寻找突破口：`右值引用`。




---

* content
{:toc}



---

## 1. 右值引用

### 1.1. 概念

C++11 引入了一种新的引用类型：右值引用，它主要用于优化临时对象的资源管理。

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

void f(const A&& a) {
    std::cout << "f(A&&)" << std::endl;
}

void f(const A& a) {
    std::cout << "f(A&)" << std::endl;
}

int main() {
    // 字面量：k 右值引用。
    int&& k = 1;
    std::cout << "k is rvalue? "
              << std::is_same<decltype(k), int&&>::value
              << std::endl;

    // 临时变量：右值引用。
    f(A());

    // 强制转换：右值引用。
    A a;
    f(std::move(a));

    // 强制转换：b 是右值引用。
    A b;
    A&& c = std::move(b);
    std::cout << "c is rvalue? "
              << std::is_same<decltype(c), A&&>::value
              << std::endl;
    return 0;
}

// 输出：
// k is rvalue? 1
// f(A&&)
// f(A&&)
// c is rvalue? 1
```

---

### 1.2. 注意

要注意某些场景，右值引用作为左值使用。

1. 右值引用变量作为函数的实参传递。
2. 函数的形参是左值。

* 源码。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <iostream>
#include <type_traits>

class A {
};

void f(const A& a) {
    std::cout << "f(A&)" << std::endl;
}

void f(const A&& a) {
    std::cout << "f(A&&)" << std::endl;
}

void f2(const A& a) {
    std::cout << "f2(A&) arg is rvalue? "
              << std::is_same<decltype(a), A&&>::value
              << std::endl;
}

void f2(const A&& a) {
    std::cout << "f2(A&&) arg is rvalue? "
              << std::is_same<decltype(a), A&&>::value
              << std::endl;
}

int main() {
    // 强制转换：b 是右值引用。
    A b;
    A&& c = std::move(b);
    std::cout << "c is rvalue? "
              << std::is_same<decltype(c), A&&>::value
              << std::endl;
    // 虽然 b 的变量类型是右值引用，
    // 但是 b 作为 f 函数的实参，以左值方式给 f 函数传值。
    f(c);

    // f2 的形参类型 A&& 虽然是右值引用，
    // 但是在函数内部，形参作为左值使用~~~~~
    f2(A());
    return 0;
}

// 输出：
// c is rvalue? 1
// f(A&)
// f2(A&&) arg is rvalue? 0
```

---

## 2. 万能引用

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

## 3. 引用折叠

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

## 4. 移动语义

### 4.1. 概念

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
            delete m_data;
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

### 4.2. 注意

上面移动语义测试例子，对象间的资源转移主要做了三件事：

1. 重置目标对象 b 的内部资源。
2. 将源对象 a 的资源转移给 b。
3. 重置源对象 a 的内部资源。

因为资源移动涉及到对象资源重置，有一定危险性，特别是源对象被移动处理后，如果被再次使用是非常危险的（参考上述测试例程）。

---

### 4.3. std::move

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
            delete m_data;
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

## 5. 完美转发

### 5.1. 概念

完美转发 - std::forward，正常的使用方式是结合万能引用使用，将模板函数的参数类型：万能引用转换为对应的左值引用或右值引用。

```cpp
// g++ -std=c++11 test.cpp -o test && ./test
#include <iostream>

class A {
};

void f2(const A& a) {
    std::cout << "lvalue" << std::endl;
}

void f2(const A&& a) {
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

### 5.2. std::forward

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

void f2(const A&& a) {
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
    f2(static_cast<const A&&>(forward<A>(t)));
}
```

---

## 6. 引用

* 《Effective Modern C++》
* 《C++ Primer》- 第五版
