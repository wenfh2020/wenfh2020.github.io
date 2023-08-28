---
layout: post
title:  "深入探索 C++ 多态 - 析构函数（进行中）"
categories: c/c++
author: wenfh2020
---

本章主要探索具有多态特性的类的析构函数工作原理。




---

* content
{:toc}

---

## 1. 概述

要理解虚析构函数，我们需要了解一些概念，编译器会根据不同的场景，生成不同的析构函数供程序进行调用。

* [base object destructor]：它销毁对象本身，以及数据成员和非虚基类。

* [complete object destructor]：除了执行 [base object destructor] 的工作，它还会销毁虚拟基类。

* [deleting object destructor]：除了执行 [deleting object destructor] 的工作，它还调用 operator delete 来实际释放内存。

> 部分文字来源：[GNU GCC (g++): Why does it generate multiple dtors?](https://stackoverflow.com/questions/6613870/gnu-gcc-g-why-does-it-generate-multiple-dtors/6614369#6614369)

---

## 2. 单一继承

通过单一继承，我们来观察一下普通析构和虚析构代码产生的结果。

### 2.1. 普通析构

#### 2.1.1. 测试源码

下面测试代码，Derived 类的析构函数没有执行，这并非我们的预期。

* 测试代码。

```cpp
/* g++ -O0 -std=c++11 test.cpp -o test */
#include <iostream>

class Base {
   public:
    ~Base() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base_data = 0x11;
    long long m_base_data2 = 0x12;
};

class Base2 : public Base {
   public:
    ~Base2() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base2_data = 0x21;
    long long m_base2_data2 = 0x22;
};

class Derived : public Base2 {
   public:
    ~Derived() { std::cout << __FUNCTION__ << std::endl; }

    long long m_derived_data = 0x31;
    long long m_derived_data2 = 0x32;
};

int main() {
    auto d = new Derived;
    auto b = static_cast<Base2*>(d);
    delete b;
    return 0;
}
```

* 测试输出结果。

```shell
~Base2
~Base
```

---

#### 2.1.2. 汇编源码

接下来，我们使用工具：[godbolt](https://godbolt.org/) 查看反汇编源码逻辑，可以清晰地看到 C++ 源码的内部逻辑，编译器并没有为 Derived 类生成任何关于 ~Derived 析构函数的逻辑。

* 析构流程。

```shell
|-- main
    |-- ...
    |-- delete b
        |-- Base2::~Base2() [base object destructor]
        |-- operator delete(void*, unsigned long)
```

* 汇编源码。

```shell
main:
        ;...
        ; 析构 Base2 类对象
        call    Base2::~Base2() [complete object destructor]
        ;...
        ; delete 对象
        call    operator delete(void*, unsigned long)


Base2::~Base2() [base object destructor]:
        ;...
        call    Base::~Base() [base object destructor]
        ;...


Base::~Base() [base object destructor]:
        ;...
```

---

### 2.2. 虚析构

在基类 ~Base 析构函数前添加 `virtual` 关键字，程序运行结果符合预期。

> 或在 ~Base2 析构函数前添加 virtual 关键字。

#### 2.2.1. 测试源码

* 测试源码。

```cpp
/* g++ -O0 -std=c++11 -fdump-class-hierarchy test.cpp -o test */
#include <iostream>

class Base {
   public:
    virtual ~Base() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base_data = 0x11;
    long long m_base_data2 = 0x12;
};

class Base2 : public Base {
   public:
    ~Base2() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base2_data = 0x21;
    long long m_base2_data2 = 0x22;
};

class Derived : public Base2 {
   public:
    ~Derived() { std::cout << __FUNCTION__ << std::endl; }

    long long m_derived_data = 0x31;
    long long m_derived_data2 = 0x32;
};

int main() {
    auto d = new Derived;
    auto b = static_cast<Base2*>(d);
    delete b;
    return 0;
}
```

* 运行结果。

```shell
~Derived
~Base2
~Base
```

---

#### 2.2.2. 汇编源码

* 析构流程。

```shell
|-- main
    |-- ...
    |-- delete b;
        |-- Derived::~Derived() [deleting destructor]
            |-- Derived::~Derived() [complete object destructor]
                |-- Base2::~Base2() [complete object destructor]
                    |-- Base::~Base() [base object destructor]
            |-- operator delete(void*)
```

* 汇编源码。

```shell
main:
        ;...
        call    operator new(unsigned long)
        ;...
        call    Derived::Derived() [complete object constructor]
        ;...
        ; 对象内存首位保存了虚指针。
        movq    -32(%rbp), %rax
        ; 虚指针指向虚表保存虚函数起始地址。
        movq    (%rax), %rax
        ; 通过偏移在虚表上找到对应虚函数。
        addq    $8, %rax
        ; 保存虚函数地址。
        movq    (%rax), %rax
        ; 调用析构函数的虚函数。
        call    *%rax


# Derived 虚表。
vtable for Derived:
        .quad   0
        .quad   typeinfo for Derived
        .quad   Derived::~Derived() [complete object destructor]
        ; main 函数调用 delete 时，调用的虚析构函数。
        .quad   Derived::~Derived() [deleting destructor]


Derived::~Derived() [deleting destructor]:
        ;...
        ;... 调用 ~Derived 析构函数。
        call    Derived::~Derived() [complete object destructor]
        ;...
        ; 调用 delete 释放对象
        call    operator delete(void*)
        ;...


Derived::~Derived() [base object destructor]:
        ;...
        call    Base2::~Base2() [base object destructor]
        ;...


Base2::~Base2() [base object destructor]:
        ;...
        call    Base::~Base() [base object destructor]
        ;...


Base::~Base() [base object destructor]:
        ;...
        je      .L1
        ;...
.L1:
        leave
        ret
```

---

## 3. 原理

---

## 4. 小结

* C++ 多态机制下的析构工作机制，使得事情变得复杂，用户稍不留神就会踩坑。站在用户的角度来看，代码越简单越好，显然 C++ 这门语言不符合这样的标准，这样的语言场景我更愿意相信这是历史遗留的问题。

---

## 5. 引用

* [Itanium C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi.html) 
* [GNU GCC (g++): Why does it generate multiple dtors?](https://stackoverflow.com/questions/6613870/gnu-gcc-g-why-does-it-generate-multiple-dtors/6614369#6614369)
