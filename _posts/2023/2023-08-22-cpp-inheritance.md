---
layout: post
title:  "[c++] 深入探索 C++ 多态 - 继承关系"
categories: c/c++
author: wenfh2020
---

上一章《[[c++] 深入探索 C++ 多态 - 虚函数调用链路](https://wenfh2020.com/2022/12/27/deep-cpp/)》讲述了简单的无继承关系的对象是如何调用虚函数的。本章主要探索有继承关系的 C++ 多态对象的内存布局。

C++ 继承特性与多态的实现有着密不可分的关系。有继承关系的对象，被创建时，派生类和基类通过层层构造对对象实例进行初始化，其中对象指针，虚指针，虚表也在这个构造过程中建立关系。




---

* content
{:toc}

---

## 1. 概述

封装，继承，多态是 C++ 的三大特性，其中多态与继承有密切关系。C++ 语言支持三种继承关系：单一继承，多重继承，虚拟继承：

<div align=center><img src="/images/2023/2023-02-25-11-37-39.png" data-action="zoom" width="80%"/></div>

> 图片来源：《多型与虚拟》

<div align=center><img src="/images/2023/2023-08-11-10-36-46.png" data-action="zoom"></div>

---

## 2. 继承关系

### 2.1. 单一继承

C++的单一继承是指一个类只能从一个父类继承属性和方法。

> 文字来源：ChatGPT

单一继承的对象类层次结构比较简单：

1. 对象内存只有一个虚指针，并且在其首位。
2. 虚表上的虚函数，通过层层覆盖，最终得出对象对应的虚函数表，详看下图。

> 部分细节没有写测试，有兴趣的朋友可以自己动手试试。

* 测试代码。

```cpp
/* g++ -O0 -std=c++11 -fdump-class-hierarchy test.cpp -o test */
#include <iostream>

class Base {
   public:
    virtual void vBaseFunc() {}
    virtual void vBaseFunc2() {}
    virtual void vBaseFunc3() {}

    double m_base_data;
    double m_base_data2;
};

class Base2 : public Base {
   public:
    virtual void vBaseFunc() {}
    virtual void vBase2Func() {}
    virtual void vBase2Func2() {}

    double m_base2_data;
    double m_base2_data2;
};

class Drived : public Base2 {
   public:
    virtual void vBaseFunc2() {}
    virtual void vBase2Func() {}
    virtual void vDrivedFunc() {}
    virtual void vDrivedFunc2() {}

    double m_drived_data;
    double m_drived_data2;
};

int main() {
    return 0;
}
```

* 类布局层次。

```shell
# g++ -O0 -std=c++11 -fdump-class-hierarchy test.cpp -o test
# test.cpp.002t.class

Vtable for Base
Base::_ZTV4Base: 5u entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI4Base)
16    (int (*)(...))Base::vBaseFunc
24    (int (*)(...))Base::vBaseFunc2
32    (int (*)(...))Base::vBaseFunc3

Class Base
   size=24 align=8
   base size=24 base align=8
Base (0x0x7fe6a109f180) 0
    # 虚指针指向虚表的这个位置：16    (int (*)(...))Base::vBaseFunc
    vptr=((& Base::_ZTV4Base) + 16u)

Vtable for Base2
Base2::_ZTV5Base2: 7u entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI5Base2)
16    (int (*)(...))Base2::vBaseFunc
24    (int (*)(...))Base::vBaseFunc2
32    (int (*)(...))Base::vBaseFunc3
40    (int (*)(...))Base2::vBase2Func
48    (int (*)(...))Base2::vBase2Func2

Class Base2
   size=40 align=8
   base size=40 base align=8
Base2 (0x0x7fe6a1056f70) 0
    vptr=((& Base2::_ZTV5Base2) + 16u)
  Base (0x0x7fe6a109f1e0) 0
      primary-for Base2 (0x0x7fe6a1056f70)

# 虚表的结构。
Vtable for Drived
Drived::_ZTV6Drived: 9u entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI6Drived)
16    (int (*)(...))Base2::vBaseFunc
24    (int (*)(...))Drived::vBaseFunc2
32    (int (*)(...))Base::vBaseFunc3
40    (int (*)(...))Drived::vBase2Func
48    (int (*)(...))Base2::vBase2Func2
56    (int (*)(...))Drived::vDrivedFunc
64    (int (*)(...))Drived::vDrivedFunc2

# 类的层次结构。
Class Drived
   size=56 align=8
   base size=56 base align=8
Drived (0x0x7fe6a1056478) 0
    vptr=((& Drived::_ZTV6Drived) + 16u)
  Base2 (0x0x7fe6a1056a28) 0
      primary-for Drived (0x0x7fe6a1056478)
    Base (0x0x7fe6a109f240) 0
        primary-for Base2 (0x0x7fe6a1056a28)
```

* 虚表整合。

<div align=center><img src="/images/2023/2023-08-22-15-37-53.png" data-action="zoom"/></div>

* 对象整体对局。

<div align=center><img src="/images/2023/2023-08-22-15-38-09.png" data-action="zoom"/></div>

---

### 2.2. 多重继承

C++ 支持多重继承，这意味着一个类可以从多个父类继承属性和方法，在 C++ 中，可以使用逗号分隔的方式来指定多个父类。

> 文字来源：ChatGPT。

* 测试代码。

```cpp
/* g++ -O0 -std=c++11 -fdump-class-hierarchy test.cpp -o test */
#include <iostream>

class Base {
   public:
    virtual void vBaseFunc() {}
    virtual void vBaseFunc2() {}

    double m_base_data;
    double m_base_data2;
};

class Base2 {
   public:
    virtual void vBase2Func() {}
    virtual void vBase2Func2() {}

    double m_base2_data;
    double m_base2_data2;
};

class Base3 {
   public:
    virtual void vBase3Func() {}
    virtual void vBase3Func2() {}

    double m_base3_data;
    double m_base3_data2;
};

class Drived : public Base, public Base2, public Base3 {
   public:
    virtual void vBaseFunc() {}
    virtual void vBase2Func2() {}
    virtual void vBase3Func2() {}
    virtual void vDrivedFunc() {}
    virtual void vDrivedFunc2() {}

    double m_drived_data;
    double m_drived_data2;
};

int main() {
    return 0;
}
```

* 类内存布局层次。

```shell
# g++ -O0 -std=c++11 -fdump-class-hierarchy test.cpp -o test
# test.cpp.002t.class

Vtable for Base
Base::_ZTV4Base: 4u entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI4Base)
16    (int (*)(...))Base::vBaseFunc
24    (int (*)(...))Base::vBaseFunc2

Class Base
   size=24 align=8
   base size=24 base align=8
Base (0x0x7f8e4bd3da80) 0
    vptr=((& Base::_ZTV4Base) + 16u)

Vtable for Base2
Base2::_ZTV5Base2: 4u entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI5Base2)
16    (int (*)(...))Base2::vBase2Func
24    (int (*)(...))Base2::vBase2Func2

Class Base2
   size=24 align=8
   base size=24 base align=8
Base2 (0x0x7f8e4bd3dae0) 0
    vptr=((& Base2::_ZTV5Base2) + 16u)

Vtable for Base3
Base3::_ZTV5Base3: 4u entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI5Base3)
16    (int (*)(...))Base3::vBase3Func
24    (int (*)(...))Base3::vBase3Func2

Class Base3
   size=24 align=8
   base size=24 base align=8
Base3 (0x0x7f8e4bd3db40) 0
    vptr=((& Base3::_ZTV5Base3) + 16u)

Vtable for Drived
Drived::_ZTV6Drived: 16u entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI6Drived)
16    (int (*)(...))Drived::vBaseFunc
24    (int (*)(...))Base::vBaseFunc2
32    (int (*)(...))Drived::vBase2Func2
40    (int (*)(...))Drived::vBase3Func2
48    (int (*)(...))Drived::vDrivedFunc
56    (int (*)(...))Drived::vDrivedFunc2
64    (int (*)(...))-24
72    (int (*)(...))(& _ZTI6Drived)
80    (int (*)(...))Base2::vBase2Func
88    (int (*)(...))Drived::_ZThn24_N6Drived11vBase2Func2Ev
96    (int (*)(...))-48
104   (int (*)(...))(& _ZTI6Drived)
112   (int (*)(...))Base3::vBase3Func
120   (int (*)(...))Drived::_ZThn48_N6Drived11vBase3Func2Ev

Class Drived
   size=88 align=8
   base size=88 base align=8
Drived (0x0x7f8e4babcd98) 0
    vptr=((& Drived::_ZTV6Drived) + 16u)
  Base (0x0x7f8e4bd3dba0) 0
      primary-for Drived (0x0x7f8e4babcd98)
  Base2 (0x0x7f8e4bd3dc00) 24
      vptr=((& Drived::_ZTV6Drived) + 80u)
  Base3 (0x0x7f8e4bd3dc60) 48
      vptr=((& Drived::_ZTV6Drived) + 112u)
```

* 虚表整合。
  
  1. 首先派生类的虚表与第一个基类的虚表结合成一个虚表单元，并覆盖基类的虚函数。
  2. 其它的基类，作为一个独立虚表单元。当派生类虚函数有重写基类的虚函数时，基类对应虚函数，通过 [thunk 技术](https://zhuanlan.zhihu.com/p/496115833) ，跳转到第一个虚表单元的对应虚函数。

<div align=center><img src="/images/2023/2023-08-22-15-34-28.png" data-action="zoom"/></div>

* 对象整体布局。由下图可见：

  1. 多重继承有多个虚指针，并指向对应的虚表。
  2. 如果派生类有 N 个多重继承单一基类，那么它的对象有 N 多虚指针和虚表。

<div align=center><img src="/images/2023/2023-08-12-14-36-56.png" data-action="zoom"></div>

* 思考，上面多重继承的多态实例，这样操作是否正常。

```cpp
int main() {
    Base2* b = new Drived;
    delete b;
    return 0;
}
```

---

### 2.3. 虚拟继承

多重继承可以让一个类具有多个不同父类的特性，但也可能引发一些问题，比如菱形继承问题。为了解决这个问题，C++ 提供了虚继承和虚基类的概念。虚继承可以解决菱形继承问题，确保只有一个实例的共享基类。

在 C++ 中，虚拟继承（virtual inheritance）是一种特殊的继承方式。它用于解决多重继承中的菱形继承问题。当一个类通过虚拟继承从多个基类继承时，只会保留一个基类的实例，而不会重复继承。这样可以避免菱形继承带来的二义性和冗余。在虚拟继承中，派生类需要使用关键字 "virtual" 来声明基类。

> 文字来源：ChatGPT

---

因为继承关系中有公共基类，为了避免公共基类产生多个对象副本浪费内存，虚拟继承的内存布局，也会与单一继承和多重继承不一样：

1. 公共基类的成员数据，存放于对象内存底部。
2. 虚拟继承引入 VTT（Virtual Table Table）构造虚表。
3. 虚表前缀引入 vbase_offset 偏移量：当前虚表与公共基类虚表的内存偏移量。

> 虚拟继承的类层次关系结构有点复杂，有兴趣的朋友可以看看这个帖子：[What is the VTT for a class](https://stackoverflow.com/questions/6258559/what-is-the-vtt-for-a-class)。

* 测试代码。

```cpp
/* g++ -O0 -std=c++11 -fdump-class-hierarchy test.cpp -o test */
#include <iostream>

class Base {
   public:
    virtual void vBaseFunc() {}
    virtual void vBaseFunc2() {}

    long long m_base_data = 0x11;
    long long m_base_data2 = 0x12;
};

class Base2 : virtual public Base {
   public:
    virtual void vBaseFunc() {}
    virtual void vBase2Func() {}
    virtual void vBase2Func2() {}

    long long m_base2_data = 0x21;
    long long m_base2_data2 = 0x22;
};

class Base3 : virtual public Base {
   public:
    virtual void vBaseFunc2() {}
    virtual void vBase3Func() {}
    virtual void vBase3Func2() {}
    long long m_base3_data = 0x31;
    long long m_base3_data2 = 0x32;
};

class Drived : public Base2, public Base3 {
   public:
    virtual void vBase2Func() {}
    virtual void vBase3Func2() {}
    virtual void vDrivedFunc() {}
    virtual void vDrivedFunc2() {}

    long long m_drived_data = 0x41;
    long long m_drived_data2 = 0x42;
};

int main() {
    return 0;
}
```

* 类内存布局层次。

```shell
Vtable for Base
Base::_ZTV4Base: 4u entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI4Base)
16    (int (*)(...))Base::vBaseFunc
24    (int (*)(...))Base::vBaseFunc2

Class Base
   size=24 align=8
   base size=24 base align=8
Base (0x0x7f45f3a72a80) 0
    vptr=((& Base::_ZTV4Base) + 16u)

Vtable for Base2
Base2::_ZTV5Base2: 12u entries
0     24u
8     (int (*)(...))0
16    (int (*)(...))(& _ZTI5Base2)
24    (int (*)(...))Base2::vBaseFunc
32    (int (*)(...))Base2::vBase2Func
40    (int (*)(...))Base2::vBase2Func2
48    0u
56    18446744073709551592u
64    (int (*)(...))-24
72    (int (*)(...))(& _ZTI5Base2)
80    (int (*)(...))Base2::_ZTv0_n24_N5Base29vBaseFuncEv
88    (int (*)(...))Base::vBaseFunc2

VTT for Base2
Base2::_ZTT5Base2: 2u entries
0     ((& Base2::_ZTV5Base2) + 24u)
8     ((& Base2::_ZTV5Base2) + 80u)

Class Base2
   size=48 align=8
   base size=24 base align=8
Base2 (0x0x7f45f385e750) 0
    vptridx=0u vptr=((& Base2::_ZTV5Base2) + 24u)
  Base (0x0x7f45f3a72ae0) 24 virtual
      vptridx=8u vbaseoffset=-24 vptr=((& Base2::_ZTV5Base2) + 80u)

Vtable for Base3
Base3::_ZTV5Base3: 12u entries
0     24u
8     (int (*)(...))0
16    (int (*)(...))(& _ZTI5Base3)
24    (int (*)(...))Base3::vBaseFunc2
32    (int (*)(...))Base3::vBase3Func
40    (int (*)(...))Base3::vBase3Func2
48    18446744073709551592u
56    0u
64    (int (*)(...))-24
72    (int (*)(...))(& _ZTI5Base3)
80    (int (*)(...))Base::vBaseFunc
88    (int (*)(...))Base3::_ZTv0_n32_N5Base310vBaseFunc2Ev

VTT for Base3
Base3::_ZTT5Base3: 2u entries
0     ((& Base3::_ZTV5Base3) + 24u)
8     ((& Base3::_ZTV5Base3) + 80u)

Class Base3
   size=48 align=8
   base size=24 base align=8
Base3 (0x0x7f45f385e820) 0
    vptridx=0u vptr=((& Base3::_ZTV5Base3) + 24u)
  Base (0x0x7f45f3a72b40) 24 virtual
      vptridx=8u vbaseoffset=-24 vptr=((& Base3::_ZTV5Base3) + 80u)

Vtable for Drived
Drived::_ZTV6Drived: 21u entries
0     64u
8     (int (*)(...))0
16    (int (*)(...))(& _ZTI6Drived)
24    (int (*)(...))Base2::vBaseFunc
32    (int (*)(...))Drived::vBase2Func
40    (int (*)(...))Base2::vBase2Func2
48    (int (*)(...))Drived::vBase3Func2
56    (int (*)(...))Drived::vDrivedFunc
64    (int (*)(...))Drived::vDrivedFunc2
72    40u
80    (int (*)(...))-24
88    (int (*)(...))(& _ZTI6Drived)
96    (int (*)(...))Base3::vBaseFunc2
104   (int (*)(...))Base3::vBase3Func
112   (int (*)(...))Drived::_ZThn24_N6Drived11vBase3Func2Ev
120   18446744073709551576u   # -40
128   18446744073709551552u   # -64
136   (int (*)(...))-64
144   (int (*)(...))(& _ZTI6Drived)
152   (int (*)(...))Base2::_ZTv0_n24_N5Base29vBaseFuncEv
160   (int (*)(...))Base3::_ZTv0_n32_N5Base310vBaseFunc2Ev

Construction vtable for Base2 (0x0x7f45f385e8f0 instance) in Drived
Drived::_ZTC6Drived0_5Base2: 12u entries
0     64u
8     (int (*)(...))0
16    (int (*)(...))(& _ZTI5Base2)
24    (int (*)(...))Base2::vBaseFunc
32    (int (*)(...))Base2::vBase2Func
40    (int (*)(...))Base2::vBase2Func2
48    0u
56    18446744073709551552u
64    (int (*)(...))-64
72    (int (*)(...))(& _ZTI5Base2)
80    (int (*)(...))Base2::_ZTv0_n24_N5Base29vBaseFuncEv
88    (int (*)(...))Base::vBaseFunc2

Construction vtable for Base3 (0x0x7f45f385e958 instance) in Drived
Drived::_ZTC6Drived24_5Base3: 12u entries
0     40u
8     (int (*)(...))0
16    (int (*)(...))(& _ZTI5Base3)
24    (int (*)(...))Base3::vBaseFunc2
32    (int (*)(...))Base3::vBase3Func
40    (int (*)(...))Base3::vBase3Func2
48    18446744073709551576u
56    0u
64    (int (*)(...))-40
72    (int (*)(...))(& _ZTI5Base3)
80    (int (*)(...))Base::vBaseFunc
88    (int (*)(...))Base3::_ZTv0_n32_N5Base310vBaseFunc2Ev

VTT for Drived
Drived::_ZTT6Drived: 7u entries
0     ((& Drived::_ZTV6Drived) + 24u)
8     ((& Drived::_ZTC6Drived0_5Base2) + 24u)
16    ((& Drived::_ZTC6Drived0_5Base2) + 80u)
24    ((& Drived::_ZTC6Drived24_5Base3) + 24u)
32    ((& Drived::_ZTC6Drived24_5Base3) + 80u)
40    ((& Drived::_ZTV6Drived) + 152u)
48    ((& Drived::_ZTV6Drived) + 96u)

Class Drived
   size=88 align=8
   base size=64 base align=8
Drived (0x0x7f45f388d620) 0
    vptridx=0u vptr=((& Drived::_ZTV6Drived) + 24u)
  Base2 (0x0x7f45f385e8f0) 0
      primary-for Drived (0x0x7f45f388d620)
      subvttidx=8u
    Base (0x0x7f45f3a72ba0) 64 virtual
        vptridx=40u vbaseoffset=-24 vptr=((& Drived::_ZTV6Drived) + 152u)
  Base3 (0x0x7f45f385e958) 24
      subvttidx=24u vptridx=48u vptr=((& Drived::_ZTV6Drived) + 96u)
    Base (0x0x7f45f3a72ba0) alternative-path
```

* 对象整体布局。

<div align=center><img src="/images/2023/2023-08-18-18-58-08.png" data-action="zoom"/></div>

* 构造顺序。我们可以通过类的构造顺序去理解，对象的内存布局和虚表是如何一步一步构造出来的。在构造派生类 Drived 时，先构造基类，当基类构造完了，才构造自己：1. Base()，2. Base2()，3. Base3()，4.Drived()。

```shell
0x400b33:    e8 34 02 00 00    callq  0x400d6c <Drived::Drived()>
...
0x400d83:    e8 06 ff ff ff    callq  400c8e <Base::Base()>
...
0x400d97:    e8 20 ff ff ff    callq  400cbc <Base2::Base2()>
...
0x400daf:    e8 60 ff ff ff    callq  400d14 <Base3::Base3()>
```

* 对象内存构建过程。

<div align=center><img src="/images/2023/2023-08-22-15-14-01.jpg" data-action="zoom"/></div>

---

## 3. 后记

* 关于有继承关系的 C++ 多态探索，因为水平有限，以上只作了一些基础简单的 Demo 的分析，可能还有一些应用场景没有涉及。

* 很多技术细节没有在文章中提及，有兴趣的朋友可以动手写写 demo 用 gdb 调试一下，查看对象内存布局上的地址数据，以及反汇编查看对象构造的逻辑，是否与自己的理解一致，这样才能在不断变化的的问题表象里，寻找到答案的本质。

<div align=center><img src="/images/2023/2023-08-22-12-43-37.png" data-action="zoom"/></div>