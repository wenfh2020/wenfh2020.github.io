---
layout: post
title:  "深入探索 C++ 多态 ③ - 虚析构"
categories: c/c++
author: wenfh2020
---

前两章探索了 C++ 多态的 [虚函数调用链路](https://www.wenfh2020.com/2022/12/27/deep-cpp/) 和 [继承关系](https://www.wenfh2020.com/2023/08/22/cpp-inheritance/)，本章将探索 `虚析构` 的工作原理。

具有虚析构多态特征的类对象，被释放时：

* 有继承关系的多态类，会先析构派生类，再析构基类，与它的构造顺序刚好相反。
* 类的析构函数被调用时，对象的 this 指针和虚指针会在对应的类内部被重新设置，this 指针指向当前类对象对应的内存位置，虚指针也会被重置指向当前类对应的虚表。
* 释放当前派生类对象内存。



---

* content
{:toc}

---

## 1. 概述

### 1.1. 概念

C++ 虚析构函数是在 C++ 中用于处理继承关系的特殊函数。它允许在基类中定义一个虚析构函数，以便在派生类对象被删除时正确地释放资源。虚析构函数的声明方式是在基类的析构函数前面加上关键字 "virtual"。

当释放基类指针指向派生类的对象时，如果基类中的析构函数不是虚函数，那么只会调用基类的析构函数，而不会调用派生类的析构函数。这可能导致资源泄漏或未定义的行为。

通过将基类的析构函数声明为虚函数，可以确保在删除派生类对象时，会首先调用派生类的析构函数，然后再调用基类的析构函数，从而正确地释放所有相关资源。

> 部分文字来源：ChatGPT

---

### 1.2. 析构函数类型

要理解 C++ 虚析构函数，我们需要了解一些概念，编译器会根据不同的场景，生成不同类型的析构函数供程序进行调用。这些概念下面实例将会提到。

* base object destructor of a class T
  
  A function that runs the destructors for non-static data members of T and non-virtual direct base classes of T.

* complete object destructor of a class T
  
  A function that, in addition to the actions required of a base object destructor, runs the destructors for the virtual base classes of T.

* deleting destructor of a class T
  
  A function that, in addition to the actions required of a complete object destructor, calls the appropriate deallocation function (i.e,. operator delete) for T.

> 文字来源：[Itanium C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi.html)

---

* **[base object destructor]**：它销毁对象本身，以及数据成员和非虚基类。

* **[complete object destructor]**：除了执行 [base object destructor]，它还会销毁虚拟基类。

* **[deleting object destructor]**：除了执行 [deleting object destructor]，它还调用 operator delete 来实际释放内存。

> 【注意】如果没有虚拟基类，[complete object destructor] 和 [base object destructor] 基本是相同的。部分文字来源：[GNU GCC (g++): Why does it generate multiple dtors?](https://stackoverflow.com/questions/6613870/gnu-gcc-g-why-does-it-generate-multiple-dtors/6614369#6614369)

---

## 2. 单一继承

通过单一继承，我们来观察一下普通析构和虚析构代码产生的结果。

### 2.1. 非虚析构

#### 2.1.1. 测试源码

下面测试代码，Derived 类的析构函数没有执行。

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

// 输出：
// ~Base2
// ~Base
```

---

#### 2.1.2. 析构流程

接下来，我们使用工具（[Compiler Explorer](https://godbolt.org/)），查看源码的汇编实现，这样可以清晰地看到 C++ 源码的内部逻辑：编译器并没有为 Derived 类生成任何关于 ~Derived 析构函数的逻辑。

* 析构流程。

```shell
|-- main
    |-- ...
    |-- delete b
        |-- Base2::~Base2() [complete object destructor]
            |-- Base::~Base() [base object destructor]
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

// 输出：
// ~Derived
// ~Base2
// ~Base
```

---

#### 2.2.2. 析构流程

* 流程。

```shell
|-- main
    |-- ...
    |-- delete b;
        |-- Derived::~Derived() [deleting destructor] # 程序调用虚表上的虚析构函数。
            |-- Derived::~Derived() [complete object destructor] # 调用 Derived 析构函数。
                |-- Base2::~Base2() [base object destructor] # 调用 Base2 析构函数。
                    |-- Base::~Base() [base object destructor] # 调用 Base 析构函数。
            |-- operator delete(void*) # delete 释放对象。
```

1. 程序通过虚指针找到虚表，虚指针指向虚表的位置向高位偏移 8 个字节，找到对应的虚函数：Derived::~Derived() [deleting destructor] 进行调用，接着调用 Derived::~Derived() [complete object destructor] 开始析构对象。
2. Derived::~Derived() [complete object destructor] 内部调用 Base2::~Base2() [base object destructor] 对 Base2 类进行析构，并将虚指针指向 Base2 虚表。
3. Base2::~Base2() [base object destructor] 内部调用 Base::~Base() [base object destructor] 对 Base 类进行析构，并将虚指针指向 Base 虚表。
4. 各个类的析构函数都调用完毕后，程序调用 delete 操作符，释放 Derived 对象。

> 这里的 [complete object destructor] 和 [base object destructor] 类型的析构函数，没有区别，都指向了相同的函数。

<div align=center><img src="/images/2023/2023-09-05-09-51-14.png" data-action="zoom"/></div>

* 汇编源码。

```shell
main:
        ...
        call    operator new(unsigned long)
        ...
        call    Derived::Derived() [complete object constructor]
        ...
        # 对象内存首位保存了虚指针。
        movq    -32(%rbp), %rax
        # 虚指针指向虚表。
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
        # 调用 delete 释放对象。
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

---

## 3. 多重继承

### 3.1. 测试代码

```cpp
/* g++ -O0 -std=c++11 -fdump-class-hierarchy test.cpp -o test */
#include <iostream>

class Base {
   public:
    virtual ~Base() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base_data = 0x11;
};

class Base2 {
   public:
    virtual ~Base2() { std::cout << __FUNCTION__ << std::endl; }

    long long m_base2_data = 0x21;
};

class Derived : public Base, public Base2 {
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

// 输出：
// ~Derived
// ~Base2
// ~Base
```

---

### 3.2. 析构流程

* 析构流程。详细逻辑，结合汇编源码和图片去理解吧。

```shell
|-- main
    |-- ...
    |-- delete b
        |-- non-virtual thunk to Derived::~Derived() [deleting destructor]
        |-- Derived::~Derived() [deleting destructor]
            |-- Derived::~Derived() [complete object destructor]
                |-- Base2::~Base2() [base object destructor]
                |-- Base::~Base() [base object destructor]
            |-- operator delete(void*)
```

<div align=center><img src="/images/2023/2023-09-05-09-48-30.png" data-action="zoom"/></div>

* 汇编。

```shell
main:
        ...
        # 虚指针 vptr2 指向虚表。
        movq    -32(%rbp), %rax
        movq    (%rax), %rax
        # 在虚表上进行偏移，找到对应的虚析构函数。
        addq    $8, %rax
        movq    (%rax), %rax
        # 将 b 指针指向的地址传递给虚析构函数作为函数参数。
        movq    -32(%rbp), %rdx
        movq    %rdx, %rdi
        # 调用（non-virtual thunk to Derived::~Derived() [deleting destructor]）。
        call    *%rax

# delete 操作符触发调用的虚析构函数，跳转到 Derived::~Derived() [deleting destructor]
non-virtual thunk to Derived::~Derived() [deleting destructor]:
        # 通过偏移，对象内存首地址传给 Derived::~Derived() [deleting destructor]。
        subq    $16, %rdi
        jmp     .LTHUNK1

# delete Derived 虚析构函数。
Derived::~Derived() [deleting destructor]:
        ...
        # 将 Derived 对象的 this 指针作为参数传给 Derived 析构函数。
        movq    -8(%rbp), %rax
        movq    %rax, %rdi
        # 调用 Derived 析构函数。
        call    Derived::~Derived() [complete object destructor]
        # 将 Derived 的 this 指针作为参数传给 delete 操作函数。
        movq    -8(%rbp), %rax
        movq    %rax, %rdi
        # 调用 delete 释放 Derived 对象。
        call    operator delete(void*)
        ...

Derived::~Derived() [base object destructor]:
        ...
        # vptr1 指向 Derived 虚表对应位置。
        movq    %rdi, -8(%rbp)
        movq    -8(%rbp), %rax
        movq    $vtable for Derived+16, (%rax)
        # vptr2 指向 Derived 虚表对应位置。
        movq    -8(%rbp), %rax
        movq    $vtable for Derived+48, 16(%rax)
        movq    -8(%rbp), %rax
        # 将 b 指针指向的地址传给 Base2 析构函数。
        addq    $16, %rax
        movq    %rax, %rdi
        # 调用 Base2 对象析构函数。
        call    Base2::~Base2() [base object destructor]
        # 将 Derived 对象首地址传给 Base 析构函数。
        movq    -8(%rbp), %rax
        movq    %rax, %rdi
        # 调用 Base 对象析构函数。
        call    Base::~Base() [base object destructor]
        ...

Base2::~Base2() [base object destructor]:
        ...
        # vptr2 指向 Base2 虚表。
        movq    %rdi, -8(%rbp)
        movq    -8(%rbp), %rax
        movq    $vtable for Base2+16, (%rax)
        ...

Base::~Base() [base object destructor]:
        ...
        # vptr1 指向 Base 虚表。
        movq    %rdi, -8(%rbp)
        movq    -8(%rbp), %rax
        movq    $vtable for Base+16, (%rax)
        ...

# 类虚表。
vtable for Derived:
        .quad   0
        .quad   typeinfo for Derived
        .quad   Derived::~Derived() [complete object destructor]
        # delete 操作符调用的虚析构函数。
        .quad   Derived::~Derived() [deleting destructor]
        .quad   -16
        .quad   typeinfo for Derived
        .quad   non-virtual thunk to Derived::~Derived() [complete object destructor]
        .quad   non-virtual thunk to Derived::~Derived() [deleting destructor]

vtable for Base2:
        .quad   0
        .quad   typeinfo for Base2
        .quad   Base2::~Base2() [complete object destructor]
        .quad   Base2::~Base2() [deleting destructor]

vtable for Base:
        .quad   0
        .quad   typeinfo for Base
        .quad   Base::~Base() [complete object destructor]
        .quad   Base::~Base() [deleting destructor]
```

---

## 4. 虚拟继承

### 4.1. 测试代码

```cpp
/* g++ -O0 -std=c++11 -fdump-class-hierarchy test.cpp -o test */
#include <iostream>

class Base {
   public:
    virtual ~Base() { std::cout << __FUNCTION__ << std::endl; }
    long long m_base_data = 0x11;
};

class Base2 : virtual public Base {
   public:
    ~Base2() { std::cout << __FUNCTION__ << std::endl; }
    long long m_base2_data = 0x21;
};

class Base3 : virtual public Base {
   public:
    ~Base3() { std::cout << __FUNCTION__ << std::endl; }
    long long m_base2_data = 0x31;
};

class Derived : public Base2, public Base3 {
   public:
    ~Derived() { std::cout << __FUNCTION__ << std::endl; }

    long long m_derived_data = 0x41;
};

int main() {
    auto d = new Derived;
    auto b = static_cast<Base*>(d);
    delete b;
    return 0;
}

// 输出：
// ~Derived
// ~Base3
// ~Base2
// ~Base
```

---

### 4.2. 对象内存布局

我们先来看看 Derived 整体的对象内存布局特点：
  
1. 共享基类的数据存储于对象内存底部。
2. 编译器为虚拟继承增加了一个 VTT (virtual table table)，它协调构造出了 Derived 的虚表（详看下图）。

<div align=center><img src="/images/2023/2023-09-04-20-21-59.png" data-action="zoom"></div>

```shell
# Derived 虚表
vtable for Derived:
        .quad   40
        .quad   0
        .quad   typeinfo for Derived
        .quad   Derived::~Derived() [complete object destructor]
        .quad   Derived::~Derived() [deleting destructor]
        .quad   24
        .quad   -16
        .quad   typeinfo for Derived
        .quad   non-virtual thunk to Derived::~Derived() [complete object destructor]
        .quad   non-virtual thunk to Derived::~Derived() [deleting destructor]
        .quad   -40
        .quad   -40
        .quad   typeinfo for Derived
        .quad   virtual thunk to Derived::~Derived() [complete object destructor]
        .quad   virtual thunk to Derived::~Derived() [deleting destructor]

# virtual table table。
VTT for Derived:
        .quad   vtable for Derived+24
        .quad   construction vtable for Base2-in-Derived+24
        .quad   construction vtable for Base2-in-Derived+64
        .quad   construction vtable for Base3-in-Derived+24
        .quad   construction vtable for Base3-in-Derived+64
        .quad   vtable for Derived+104
        .quad   vtable for Derived+64

construction vtable for Base2-in-Derived:
        .quad   40
        .quad   0
        .quad   typeinfo for Base2
        .quad   Base2::~Base2() [complete object destructor]
        .quad   Base2::~Base2() [deleting destructor]
        .quad   -40
        .quad   -40
        .quad   typeinfo for Base2
        .quad   virtual thunk to Base2::~Base2() [complete object destructor]
        .quad   virtual thunk to Base2::~Base2() [deleting destructor]

construction vtable for Base3-in-Derived:
        .quad   24
        .quad   0
        .quad   typeinfo for Base3
        .quad   Base3::~Base3() [complete object destructor]
        .quad   Base3::~Base3() [deleting destructor]
        .quad   -24
        .quad   -24
        .quad   typeinfo for Base3
        .quad   virtual thunk to Base3::~Base3() [complete object destructor]
        .quad   virtual thunk to Base3::~Base3() [deleting destructor]
```

---

### 4.3. 析构流程

虽然虚拟继承内存布局有一些特殊，但对象的整体析构流程与其它继承关系的对象析构流程并没有多大区别。

```shell
|-- main
    |-- ...
    |-- delete b
        |-- virtual thunk to Derived::~Derived() [deleting destructor]
        |-- Derived::~Derived() [deleting destructor]
            |-- Derived::~Derived() [complete object destructor]
                |-- Base3::~Base3() [base object destructor]
                |-- Base2::~Base2() [base object destructor]
                |-- Base::~Base() [base object destructor]
            |-- operator delete(void*)
```

* 调用 ~Derived() 析构函数。

<div align=center><img src="/images/2023/2023-09-05-10-02-40.png" data-action="zoom"/></div>

```shell
main:
        ...
        # 虚指针 vptr3 指向虚表。
        movq    -32(%rbp), %rax
        movq    (%rax), %rax
        # 在虚表上偏移找到对应虚函数地址：
        # virtual thunk to Derived::~Derived() [deleting destructor]。
        addq    $8, %rax
        movq    (%rax), %rax
        # 将 b 指针，作为参数，传递给将要被调用的虚函数。
        movq    -32(%rbp), %rdx
        movq    %rdx, %rdi
        # 程序调用前面找到的虚函数。
        call    *%rax
        ...

# 主程序 "call *%rax" 指令调用的虚函数。
virtual thunk to Derived::~Derived():
        # 虚指针指向虚表的的位置，该位置向低地址偏移 24 个字节。
        # 获取该地址的内存偏移量 -40，对象 this 指针向低地址偏移 40 个字节。
        mov    (%rdi),%r10
        add    -0x18(%r10),%rdi
        # 调用 Derived::~Derived() [deleting destructor]
        jmp    401488 <Derived::~Derived()>


Derived::~Derived() [deleting destructor]:
        ...
        # 调用 Derived 对象析构函数。
        call    Derived::~Derived() [complete object destructor]
        ...
        # 调用 delete 释放对象。
        call    operator delete(void*)
        leave
        ret 

# Derived 完全对象析构函数，重置对象的 this 指针和虚指针，虚指针指向对应的虚表。
Derived::~Derived() [complete object destructor]:
        ...
        # this 指针指向内存首位。
        movq    %rdi, -8(%rbp)
        # 重置 Derived 对象虚指针，指向 Derived 虚表对应位置。
        movl    $vtable for Derived+24, %edx
        movq    -8(%rbp), %rax
        movq    %rdx, (%rax)
        movl    $40, %edx
        movq    -8(%rbp), %rax
        addq    %rax, %rdx
        movl    $vtable for Derived+104, %eax
        movq    %rax, (%rdx)
        movl    $vtable for Derived+64, %edx
        movq    -8(%rbp), %rax
        movq    %rdx, 16(%rax)

        # 调整 this 指针，从 VTT 中找到保存 Base3 虚函数地址的位置，准备重置 Base3 的虚指针。
        movl    $VTT for Derived+24, %eax
        movq    -8(%rbp), %rdx
        addq    $16, %rdx
        movq    %rax, %rsi
        movq    %rdx, %rdi
        call    Base3::~Base3() [base object destructor]

        # 调整 this 指针，从 VTT 中找到保存 Base2 虚函数地址的位置，准备重置 Base2 的虚指针。
        movl    $VTT for Derived+8, %edx
        movq    -8(%rbp), %rax
        movq    %rdx, %rsi
        movq    %rax, %rdi
        call    Base2::~Base2() [base object destructor]
        ...
        
        # 调整 this 指针，重置 Base 虚指针
        movq    -8(%rbp), %rax
        addq    $40, %rax
        movq    %rax, %rdi
        call    Base::~Base() [base object destructor]
        ...
```

* ~Base3() 析构函数。

<div align=center><img src="/images/2023/2023-09-05-10-12-32.png" data-action="zoom"/></div>

```shell
Derived::~Derived() [complete object destructor]:
        ...
        # 调整 this 指针，从 VTT 中找到保存 Base3 虚函数地址的位置，准备重置 Base3 的虚指针。
        movl    $VTT for Derived+24, %eax
        movq    -8(%rbp), %rdx
        addq    $16, %rdx
        movq    %rax, %rsi
        movq    %rdx, %rdi
        call    Base3::~Base3() [base object destructor]

Base3::~Base3() [base object destructor]:
        ...
        movq    %rdi, -8(%rbp)
        movq    %rsi, -16(%rbp)
        # 虚指针 vptr2 指向虚表对应位置。
        movq    -16(%rbp), %rax
        movq    (%rax), %rdx
        movq    -8(%rbp), %rax
        movq    %rdx, (%rax)

        # 通过虚表偏移找到 vbase_offset
        movq    -8(%rbp), %rax
        movq    (%rax), %rax
        subq    $24, %rax
        movq    (%rax), %rax

        # 虚指针 vptr3 指向虚表对应位置。
        movq    %rax, %rdx
        movq    -8(%rbp), %rax
        addq    %rax, %rdx
        movq    -16(%rbp), %rax
        movq    8(%rax), %rax
        movq    %rax, (%rdx)
        ...
```

* ~Base2() 析构函数。

<div align=center><img src="/images/2023/2023-09-05-10-12-32.png" data-action="zoom"/></div>

```shell
# Derived 完全对象析构函数，重置对象的 this 指针和虚指针，虚指针指向对应的虚表。
Derived::~Derived() [complete object destructor]:
        ...
        # 调整 this 指针，从 VTT 中找到保存 Base2 虚函数地址的位置，准备重置 Base2 的虚指针。
        movl    $VTT for Derived+8, %edx
        movq    -8(%rbp), %rax
        movq    %rdx, %rsi
        movq    %rax, %rdi
        call    Base2::~Base2() [base object destructor]

Base2::~Base2() [base object destructor]:
        ...
        movq    %rdi, -8(%rbp)
        movq    %rsi, -16(%rbp)
        # 虚指针 vptr1 指向虚表（Construction vtable for Base2 in Derived）对应位置。
        movq    -16(%rbp), %rax
        movq    (%rax), %rdx
        movq    -8(%rbp), %rax
        movq    %rdx, (%rax)

        # 通过虚表偏移找到 vbase_offset
        movq    -8(%rbp), %rax
        movq    (%rax), %rax
        subq    $24, %rax
        movq    (%rax), %rax

        # 虚指针 vptr3 指向虚表对应位置。
        movq    %rax, %rdx
        movq    -8(%rbp), %rax
        addq    %rax, %rdx
        movq    -16(%rbp), %rax
        movq    8(%rax), %rax
        movq    %rax, (%rdx)
        ...
```

* ~Base() 析构函数。

<div align=center><img src="/images/2023/2023-09-07-09-22-21.png" data-action="zoom"/></div>

```shell
Derived::~Derived() [complete object destructor]:
        ...
        # 调整 this 指针，重置 Base 虚指针。
        movq    -8(%rbp), %rax
        addq    $40, %rax
        movq    %rax, %rdi
        call    Base::~Base() [base object destructor]
        ...

Base::~Base() [base object destructor]:
        ...
        movq    %rdi, -8(%rbp)
        movq    -8(%rbp), %rax
        movq    $vtable for Base+16, (%rax)
        ...

vtable for Base:
        .quad   0
        .quad   typeinfo for Base
        .quad   Base::~Base() [complete object destructor]
        .quad   Base::~Base() [deleting destructor]
```

---

## 5. 小结

* 虚析构工作原理，还是那几个关键点：虚指针，虚表，虚函数，还有每个类内部 this 指针的变化。
* 虽然多态类的虚函数和虚表是在程序运行前，编译器已经生成，但是多态对象在创建构造的过程中，对象内存数据是按顺序构造出来的（先构造基类，再构造派生类），因此每个构造环节，当前类的 this 指针和 虚指针都可能会出现变化，同理派生类对象的析构，顺序刚好与构造顺序相反（先析构派生类，再析构基类），当然 this 指针和 虚指针，也会像构造那样可能出现相应变化。
* 虚析构虽然使用简单，如果用户忘记使用虚析构，在销毁对象时，可能导致派生类的析构函数不被调用，这是始料未及的。友好的语言应该将复杂的事情变得简单，C++ 这门语言，显然还有很大的优化空间。

---

## 6. 引用

* [Itanium C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi.html)
* [GNU GCC (g++): Why does it generate multiple dtors?](https://stackoverflow.com/questions/6613870/gnu-gcc-g-why-does-it-generate-multiple-dtors/6614369#6614369)
