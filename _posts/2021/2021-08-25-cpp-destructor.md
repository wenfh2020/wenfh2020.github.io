---
layout: post
title:  "深入探索 C++ 多态 - 析构函数（进行中）"
categories: c/c++
author: wenfh2020
---

本章主要探索 C++ 具有多态特性的类的析构函数工作原理。




---

* content
{:toc}

---

## 1. 概述

要理解 C++ 虚析构函数，我们需要了解一些概念，编译器会根据不同的场景，生成不同的析构函数供程序进行调用。这些概念下面实例将会提到。

* base object destructor of a class T
  
  A function that runs the destructors for non-static data members of T and non-virtual direct base classes of T.

* complete object destructor of a class T
  
  A function that, in addition to the actions required of a base object destructor, runs the destructors for the virtual base classes of T.

* deleting destructor of a class T
  
  A function that, in addition to the actions required of a complete object destructor, calls the appropriate deallocation function (i.e,. operator delete) for T.

> 文字来源：[Itanium C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi.html)

---

* [base object destructor]：它销毁对象本身，以及数据成员和非虚基类。

* [complete object destructor]：除了执行 [base object destructor]，它还会销毁虚拟基类。

* [deleting object destructor]：除了执行 [deleting object destructor]，它还调用 operator delete 来实际释放内存。

> 【注意】如果没有虚拟基类，[complete object destructor] 和 [base object destructor] 基本是相同的。部分文字来源：[GNU GCC (g++): Why does it generate multiple dtors?](https://stackoverflow.com/questions/6613870/gnu-gcc-g-why-does-it-generate-multiple-dtors/6614369#6614369)

---

## 2. 单一继承

通过单一继承，我们来观察一下普通析构和虚析构代码产生的结果。

### 2.1. 普通析构

#### 2.1.1. 测试源码

下面测试代码，Derived 类的析构函数没有执行。

* 测试代码。

```cpp
/* g++ -O0 -std=c++11 test.cpp -o test */
#include <iostream>

class Base {
   public:
    ~Base() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base_data = 0x11;
};

class Base2 : public Base {
   public:
    ~Base2() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base2_data = 0x21;
};

class Derived : public Base2 {
   public:
    ~Derived() { std::cout << __FUNCTION__ << std::endl; }

    long long m_derived_data = 0x31;
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

接下来，我们使用工具（[Compiler Explorer](https://godbolt.org/)），查看源码的汇编实现，这样可以清晰地看到 C++ 源码的内部逻辑：编译器并没有为 Derived 类生成任何关于 ~Derived 析构函数的逻辑。

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
        ...
        # 析构 Base2 类对象
        call    Base2::~Base2() [complete object destructor]
        ...
        # delete 对象
        call    operator delete(void*, unsigned long)


Base2::~Base2() [base object destructor]:
        ...
        call    Base::~Base() [base object destructor]
        ...


Base::~Base() [base object destructor]:
        ...
```

---

### 2.2. 虚析构

我们在基类 ~Base（或在 ~Base2）析构函数前添加 `virtual` 关键字，程序运行结果符合预期。

#### 2.2.1. 测试源码

* 测试源码。

```cpp
/* g++ -O0 -std=c++11 -fdump-class-hierarchy test.cpp -o test */
#include <iostream>

class Base {
   public:
    virtual ~Base() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base_data = 0x11;
};

class Base2 : public Base {
   public:
    ~Base2() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base2_data = 0x21;
};

class Derived : public Base2 {
   public:
    ~Derived() { std::cout << __FUNCTION__ << std::endl; }

    long long m_derived_data = 0x31;
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

* 汇编源码。我们通过汇编源码可以比较直观地去观察对象析构的流程。

```shell
main:
        ...
        call    operator new(unsigned long)
        ...
        call    Derived::Derived() [complete object constructor]
        ...
        # 对象内存首位保存了虚指针。
        movq    -32(%rbp), %rax
        # 虚指针指向虚表保存虚函数的起始地址。
        movq    (%rax), %rax
        # 程序通过偏移在虚表上找到对应虚函数。
        addq    $8, %rax
        # 保存虚函数地址。
        movq    (%rax), %rax
        # 将对象的 this 指针，写入寄存器，作为参数，传递给虚函数。
        movq    -32(%rbp), %rdx
        movq    %rdx, %rdi
        # 调用析构函数的虚函数（Derived::~Derived() [deleting destructor]）。
        call    *%rax


# 程序通过虚指针找到虚表上的虚函数。
Derived::~Derived() [deleting destructor]:
        ...
        # 调用 Derived 析构函数。
        call    Derived::~Derived() [complete object destructor]
        ...
        # 调用 delete 释放对象
        call    operator delete(void*)
        ...

Derived::~Derived() [base object destructor]:
        ...
        # 虚指针指向 Derived 虚表。
        movq    $vtable for Derived+16, (%rax)
        # 调用 Base2 析构函数。
        call    Base2::~Base2() [base object destructor]
        ...

Base2::~Base2() [base object destructor]:
        ...
        # 虚指针指向 Base2 虚表。
        movq    $vtable for Base2+16, (%rax)
        # 调用 Base 析构函数。
        call    Base::~Base() [base object destructor]
        ...

Base::~Base() [base object destructor]:
        ...
        # 虚指针指向 Base 虚表。
        movq    $vtable for Base+16, (%rax)
        ...

# Derived 虚表。
vtable for Derived:
        .quad   0
        .quad   typeinfo for Derived
        .quad   Derived::~Derived() [complete object destructor]
        # main 函数调用 delete 操作符时，调用 [deleting destructor] 类型的析构函数。
        .quad   Derived::~Derived() [deleting destructor]

# Base2 虚表。
vtable for Base2:
        .quad   0
        .quad   typeinfo for Base2
        .quad   Base2::~Base2() [complete object destructor]
        .quad   Base2::~Base2() [deleting destructor]

# Base 虚表。
vtable for Base:
        .quad   0
        .quad   typeinfo for Base
        .quad   Base::~Base() [complete object destructor]
        .quad   Base::~Base() [deleting destructor]
```

* 析构流程。归纳一下上述汇编的工作流程。

```shell
|-- main
    |-- ...
    |-- delete b;
        |-- Derived::~Derived() [deleting destructor] # 程序调用虚表上的虚析构函数。
            |-- Derived::~Derived() [complete object destructor] # 调用 Derived 析构函数。
                |-- Base2::~Base2() [base object destructor] # 调用 Base2 对象函数。
                    |-- Base::~Base() [base object destructor] # 调用 Base 析构函数。
            |-- operator delete(void*) # delelte 释放对象。
```

1. 程序通过虚指针找到虚表，虚指针指向虚表的位置向高位偏移 8 个字节，找到对应的虚函数：Derived::~Derived() [deleting destructor] 进行调用，接着调用 Derived::~Derived() [complete object destructor] 开始析构对象。
2. Derived::~Derived() [complete object destructor] 内部调用 Base2::~Base2() [base object destructor] 对 Base2 类进行析构，并将虚指针指向 Base2 虚表。
3. Base2::~Base2() [base object destructor] 内部调用 Base::~Base() [base object destructor] 对 Base 类进行析构，并将虚指针指向 Base 虚表。
4. 各个类的析构函数都调用完毕后，程序调用 delete 操作符，释放 Derived 对象。

> 这里的 [complete object destructor] 和 [base object destructor] 类型的析构函数，没有区别，都指向了相同的函数。

<div align=center><img src="/images/2023/2023-08-29-16-37-04.png" data-action="zoom"/></div>

---

## 3. 多重继承

---

## 4. 小结

C++ 多态对象的析构工作机制，使得事情变得复杂，用户稍不留神就会踩坑。个人认为，好的语言应该把复杂的事情变简单，显然 C++ 这门语言，还有很大进步空间。

---

## 5. 引用

* [Itanium C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi.html)
* [GNU GCC (g++): Why does it generate multiple dtors?](https://stackoverflow.com/questions/6613870/gnu-gcc-g-why-does-it-generate-multiple-dtors/6614369#6614369)
