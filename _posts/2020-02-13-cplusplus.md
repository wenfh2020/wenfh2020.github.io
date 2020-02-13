---
layout: post
title:  "c++ 语言基础知识"
categories: c/c++
tags: c++
author: wenfh2020
note: 1
---

c++ 基础知识回顾。



## 基础知识

### const 常量

const 可以修饰常量，引用，函数。

```c
// 常量指针，指针指向的是常量，(*p)内容不能变。
const char* p = "123";

// 指针常量，(p)指针不能变。
char* const p = "123";

// 不允许修改类数据成员的值。
char* get_count() const;

// 不允许修改返回指针的内容。
const char* get_data();
```

---
### inline
inline 是 C++ 关键字，在函数声明或定义中。在函数返回类型前加上关键字 inline，即可把函数指定为内联函数，这样可以解决一些频繁调用的函数，大量消耗栈空间。
> 可以对比宏函数

1. 优点：
   作为函数定义的关键字，说明该函数是内联函数。内联函数会将代码块嵌入到每个调用该函数的地方，内联函数减少了函数的调用，使代码执行的效率提高。
2. 缺点：
   内联是以代码膨胀复制为代价，仅仅省去了函数调用的开销，从而提高函数的执行效率。如果执行函数体内代码的时间，相比于函数调用的开销较大，那么效率的收获会很少。另一方面，每一处内联函数的调用都要复制代码, 将使程序的总代码量增大，消耗更多的内存空间。以下情况不宜使用内联:
   1）如果函数体内的代码比较长，使用内联将导致内存消耗代价较高。
   2）如果函数体内出现循环，那么执行函数体内代码的时间要比函数调用的开销大。（递归）

---
### C++ 三大特性
封装，继承，多态

---
#### 封装
将处理的数据抽象成类，操作执行抽象成方法。例如 file.

---
#### 继承
```c++
#include <iostream>
#include <string>

class Base {
   public:
    Base() { std::cout << "base construct" << std::endl; }
    ~Base() { func(); }
    virtual void func() { std::cout << "base destruct" << std::endl; }
    virtual void func2() { std::cout << "base func2" << std::endl; }
};

class Child : public Base {
   public:
    Child() { std::cout << "child construct" << std::endl; }
    ~Child() { func(); }
    virtual void func() { std::cout << "child destruct" << std::endl; }
    virtual void func2() { std::cout << "child func2" << std::endl; }
};

class Child2 : public Child {
   public:
    Child2() { std::cout << "Child2 construct" << std::endl; }
    ~Child2() { func(); }
    virtual void func() { std::cout << "Child2 destruct" << std::endl; }
    virtual void func2() { std::cout << "Child2 func2" << std::endl; }
};

int main() {
    Child2 c;
    c.func2();
    return 0;
}
```
这里考察的是析构函数，多态功能。在析构函数中调用虚函数

结果
```shell
base construct
child construct
Child2 construct
Child2 func2
Child2 destruct
child destruct
base destruct
```

---
#### 多态
```c++
#include <iostream>
#include <string>

class Base {
   public:
    Base() { std::cout << "base construct" << std::endl; }
    ~Base() { func(); }
    virtual void func() { std::cout << "base destruct" << std::endl; }
    virtual void func2() { std::cout << "base func2" << std::endl; }
};

class Child : public Base {
   public:
    Child() { std::cout << "child construct" << std::endl; }
    ~Child() { func(); }
    virtual void func() { std::cout << "child destruct" << std::endl; }
    virtual void func2() { std::cout << "child func2" << std::endl; }
};

class Child2 : public Child {
   public:
    Child2() { std::cout << "Child2 construct" << std::endl; }
    ~Child2() { func(); }
    virtual void func() { std::cout << "Child2 destruct" << std::endl; }
    virtual void func2() { std::cout << "Child2 func2" << std::endl; }
};

int main() {
    Base* b = new Child2;
    b->func2();
    delete b;
    return 0;
}
```
结果
```shell
base construct
child construct
Child2 construct
Child2 func2
base destruct
```

---
- delete 强制转换指针对象和不强制转换效果不一样。

```c++
int main() {
    Base* b = new Child2;
    b->func2();
    delete (Child2*)b;
    return 0;
}
```
```shell
base construct
child construct
Child2 construct
Child2 func2
Child2 destruct
child destruct
base destruct
```

---
- 虚析构函数，会调用父类的析构函数，避免内存泄漏

```c
#include <iostream.h>
#include <string>

class Base {
   public:
    Base() { std::cout << "base construct" << std::endl; }
    virtual ~Base() { func(); }
    virtual void func() { std::cout << "base destruct" << std::endl; }
    virtual void func2() { std::cout << "base func2" << std::endl; }
};

class Child : public Base {
   public:
    Child() { std::cout << "child construct" << std::endl; }
    ~Child() { func(); }
    virtual void func() { std::cout << "child destruct" << std::endl; }
    virtual void func2() { std::cout << "child func2" << std::endl; }
};

class Child2 : public Child {
   public:
    Child2() { std::cout << "Child2 construct" << std::endl; }
    ~Child2() { func(); }
    virtual void func() { std::cout << "Child2 destruct" << std::endl; }
    virtual void func2() { std::cout << "Child2 func2" << std::endl; }
};

int main() {
    Base* b = new Child2;
    b->func2();
    delete b;
    return 0;
}
```
结果
```shell
base construct
child construct
Child2 construct
Child2 func2
Child2 destruct
child destruct
base destruct
```

---
### 数组长度，指针长度
```c
#include <iostream>
#include <string>

class C {
    public:
    static void func() {}
    virtual void func2() {}
    void func3() {}
};

int main() {
    std::cout << "class size: " << sizeof(C) << std::endl;
    char szArray[] = "1234567890";
    const char* pArray = "1234567890";
    std::cout << "ptr size:" << sizeof(pArray)
            << ", ptr len: " << strlen(pArray) << std::endl;
    std::cout << "array size: " << sizeof(szArray)
            << ", array len: " << strlen(szArray) << std::endl;
    return 0;
}
```
结果：
```shell
class size: 8
ptr size:8, ptr len: 10
array size: 11, array len: 10
```
> class 有虚函数，所以有虚函数指针，普通函数内存被分配到代码区，static 函数被分配到全局数据区，所以 sizeof 大小只有 virtual 的虚函数指针，64位机器，指针长度 8 个字节。数组除了字符串，还有结束符‘\0’

---
## 其它
### malloc 和 new 区别
1. 属性：new/delete是C++关键字，需要编译器支持。malloc/free是库函数，需要头文件支持。
2. 参数：使用new操作符申请内存分配时无须指定内存块的大小，编译器会根据类型信息自行计算。而malloc则需要显式地指出所需内存的尺寸。
3. 返回类型：new操作符内存分配成功时，返回的是对象类型的指针，类型严格与对象匹配，无须进行类型转换，故new是符合类型安全性的操作符。而malloc内存分配成功则是返回 void*，需要通过强制类型转换将void* 指针转换成我们需要的类型。
4. 分配失败：new内存分配失败时，会抛出bac_alloc异常。malloc分配内存失败时返回NULL。
5. 自定义类型：new会先调用operator new函数，申请足够的内存（通常底层使用malloc实现）。然后调用类型的构造函数，初始化成员变量，最后返回自定义类型指针。delete先调用析构函数，然后调用operator delete函数释放内存（通常底层使用free实现）。 malloc/free是库函数，只能动态的申请和释放内存，无法强制要求其做自定义类型对象构造和析构工作。
6. 重载：C++允许重载new/delete操作符，特别的，布局new的就不需要为对象分配内存，而是指定了一个地址作为内存起始区域，new在这段内存上为对象调用构造函数完成初始化工作，并返回此地址。而malloc不允许重载。
7. 内存区域：new操作符从**自由存储区（free store）上为对象动态分配内存空间**，而malloc函数从堆上动态分配内存。自由存储区是C++基于new操作符的一个抽象概念，凡是通过new操作符进行内存申请，该内存即为自由存储区。而堆是操作系统中的术语，是操作系统所维护的一块特殊内存，用于程序的内存动态分配，C语言使用malloc从堆上分配内存，使用free释放已分配的对应内存。自由存储区不等于堆，如上所述，布局new就可以不位于堆中。

---
### 空类
空类大小为 1
```c++
#include <iostream>

class C {};

int main() {
    std::cout << "class size: " << sizeof(C) << std::endl;
    return 0;
}
```
结果：
```shell
class size: 1
```
这就是实例化的原因（空类同样可以被实例化），每个实例在内存中都有一个独一无二的地址，为了达到这个目的，编译器往往会给一个空类隐含的加一个字节，这样空类在实例化后在内存得到了独一无二的地址，所以空类所占的内存大小是1个字节。

---
## 参考
[c++ 官网](http://www.cplusplus.com/reference/)