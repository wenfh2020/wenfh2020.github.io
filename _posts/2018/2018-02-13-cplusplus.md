---
layout: post
title:  "c++ 语言基础知识"
categories: c/c++
tags: c++
author: wenfh2020
note: 1
---

c++ 基础知识回顾。



* content
{:toc}

## 1. 基础知识

### 1.1. const 常量

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

### 1.2. inline

inline 是 C++ 关键字，在函数声明或定义中。在函数返回类型前加上关键字 inline，即可把函数指定为内联函数，这样可以解决一些频繁调用的函数，大量消耗栈空间。
> 可以对比 [宏函数](https://wenfh2020.com/2020/02/15/c-asm/)

1. 优点：
   作为函数定义的关键字，说明该函数是内联函数。内联函数会将代码块嵌入到每个调用该函数的地方，内联函数减少了函数的调用，使代码执行的效率提高。
2. 缺点：
   内联是以代码膨胀复制为代价，仅仅省去了函数调用的开销，从而提高函数的执行效率。如果执行函数体内代码的时间，相比于函数调用的开销较大，那么效率的收获会很少。另一方面，每一处内联函数的调用都要复制代码, 将使程序的总代码量增大，消耗更多的内存空间。以下情况不宜使用内联:

   1）如果函数体内的代码比较长，使用内联将导致内存消耗代价较高。

   2）如果函数体内出现循环，那么执行函数体内代码的时间要比函数调用的开销大。（递归）

---

### 1.3. C++ 三大特性

封装，继承，多态。看看下面 demo 的输出，理解三者关系。

* demo。

```cpp
#include <iostream>

class A {
   public:
    A() {
        std::cout << "A::A()" << std::endl;
        func();
    }
    virtual ~A() { std::cout << "A::~A()" << std::endl; }
    virtual void func() { std::cout << "A::func" << std::endl; }
    virtual void func2() { std::cout << "A::func2" << std::endl; }
};

class B : public A {
   public:
    B() { std::cout << "B::B()" << std::endl; }
    ~B() { std::cout << "B::~B()" << std::endl; }
    virtual void func() { std::cout << "B::func" << std::endl; }
    virtual void func2() { std::cout << "B::func2" << std::endl; }
};

class K {
   public:
    K() { std::cout << "K::K()" << std::endl; }
    virtual ~K() { std::cout << "K::~K()" << std::endl; }
    virtual void func() { std::cout << "K::func" << std::endl; }
    virtual void func2() { std::cout << "K::func2" << std::endl; }
};

class C : public B, public K {
   public:
    C() { std::cout << "C::C()" << std::endl; }
    virtual ~C() { std::cout << "C::~C()" << std::endl; }
    virtual void func() { std::cout << "C::func" << std::endl; }
    virtual void func2() { std::cout << "C::func" << std::endl; }
};

int main(int argc, char** argv) {
    std::cout << "sizeof(C): " << sizeof(C) << std::endl;
    A* p = new C;
    p->func();
    delete p;
    return 0;
}
```

* 结果。

```shell
sizeof(C): 16
A::A()
A::func
B::B()
K::K()
C::C()
C::func
C::~C()
K::~K()
B::~B()
A::~A()
```

* 分析。

1. C 类被 new 实例化后，是先调用基类进行构造，然后才到派生类。如果有多个基类，那么按继承的基类顺序进行构造，类析构顺序刚好与类构造相反。
2. C 类对象实例在 64 位机器上的占的空间是 16 字节，因为继承了两个基类 B，K，它们有各自的虚函数指针，分别占 8 个字节
3. func 函数多态特性，虽然基类指针指向了派生类对象地址，但是基类指针调用多态的 func 函数是 C 对象实例的。
4. `注意`，基类的析构函数需要添加上 virtual 关键字，避免对象实例销毁时，只调用了基类析构函数，没有调用派生类的析构函数，这可能导致内存泄漏。
5. 基类构造函数调用虚函数，并没有发生多态现象，原因：派生类构造，先构造基类，vptr 先指向基类的虚函数表，然后到了派生类的构造函数，vptr 才指向派生类的虚函数表。

---

### 1.4. 字符串类

#### 1.4.1. demo1

* demo1

```cpp
#include <iostream>
#define MAX_DATA_LEN 64

class Test {
   public:
    Test() : m_data(NULL) {}

    Test(const char* p) : m_data(NULL) {
        copy_data(p);
    }

    Test(const Test& t) : m_data(NULL) {
        if (t.m_data != NULL) {
            copy_data(t.m_data);
        }
    }

    Test& operator=(const Test& t) {
        if (this != &t) {
            copy_data(t.m_data);
        }
        return *this;
    }

    virtual ~Test() {
        release();
    }

    const char* data() { return m_data; }
    bool set_data(const char* p) {
        return copy_data(p) == NULL;
    }

   protected:
    void release() {
        if (m_data != NULL) {
            delete[] m_data;
            m_data = NULL;
        }
    }

    const char* copy_data(const char* p) {
        if (p == NULL) {
            return NULL;
        }
        release();
        int len = strlen(p);
        if (len <= MAX_DATA_LEN - 1) {
            m_data = new char[MAX_DATA_LEN];
            strcpy(m_data, p);
        }
        return m_data;
    }

   private:
    char* m_data;
};

int main() {
    Test t;
    t.set_data("123");
    Test tt("456");
    Test ttt(tt);
    Test* p = &tt;
    *p = tt;
    *p = ttt;
    std::cout << t.data() << std::endl
              << tt.data() << std::endl
              << ttt.data() << std::endl
              << p->data() << std::endl;
    return 0;
}
```

* 输出。

```shell
123
456
456
456
```

---

#### 1.4.2. demo2

```cpp
struct A {
    std::string s;
    A(std::string str) : s(std::move(str))  { std::cout << " constructed\n"; }
    A(const A& o) : s(o.s) { std::cout << " copy constructed\n"; }
    A(A&& o) : s(std::move(o.s)) { std::cout << " move constructed\n"; }
    A& operator=(const A& other) {
        s = other.s;
        std::cout << " copy assigned\n";
        return *this;
    }
    A& operator=(A&& other) {
        s = std::move(other.s);
        std::cout << " move assigned\n";
        return *this;
    }
};
```

---

## 2. 常用函数

```cpp
/* 字符串转整型。 */
std::stoi
/* 字符串转长整型。 */
std::stol
/* 字符串转 64 位长整型。 */
std::stoll
/* 整型转字符串。 */
std::to_string
```

---

## 3. 其它

### 3.1. malloc 和 new 区别

1. 属性：new/delete 是 C++ 关键字，需要编译器支持。malloc/free 是库函数，需要头文件支持。
2. 参数：使用 new 操作符申请内存分配时无须指定内存块的大小，编译器会根据类型信息自行计算。而 malloc 则需要显式地指出所需内存的尺寸。
3. 返回类型：new 操作符内存分配成功时，返回的是对象类型的指针，类型严格与对象匹配，无须进行类型转换，故 new 是符合类型安全性的操作符。而 malloc 内存分配成功则是返回 void*，需要通过强制类型转换将 void* 指针转换成我们需要的类型。
4. 分配失败：new 内存分配失败时，会抛出 bac_alloc 异常。malloc 分配内存失败时返回 NULL。
5. 自定义类型：new 会先调用 operator new 函数，申请足够的内存（通常底层使用 malloc 实现）。然后调用类型的构造函数，初始化成员变量，最后返回自定义类型指针。delete 先调用析构函数，然后调用 operator delete 函数释放内存（通常底层使用 free 实现）。 malloc/free 是库函数，只能动态的申请和释放内存，无法强制要求其做自定义类型对象构造和析构工作。
6. 重载：C++ 允许重载 new/delete 操作符，特别的，布局new的就不需要为对象分配内存，而是指定了一个地址作为内存起始区域，new 在这段内存上为对象调用构造函数完成初始化工作，并返回此地址。而 malloc 不允许重载。

---

### 3.2. 空类

空类大小为 1 个字节。

```cpp
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

## 4. 字符串处理

### 4.1. 分离字符串

```cpp
/* g++ -std=c++11 test.cpp -o test && ./test */
#include <iostream>
#include <string>
#include <vector>

bool get_words(const std::string& s, const std::string& split, std::vector<std::string>& words) {
    std::size_t pre = 0, cur = 0;
    while ((pre = s.find_first_not_of(split, cur)) != std::string::npos) {
        cur = s.find(split, pre);
        if (cur != std::string::npos) {
            words.push_back(s.substr(pre, cur - pre));
        } else {
            words.push_back(s.substr(pre, s.length() - pre));
        }
    }
    return words.size() != 0;
}

int main() {
    char s[] = "1 2 3 4 5 6 ";
    std::vector<std::string> words;
    if (get_words(s, " ", words)) {
        for (auto v : words) {
            std::cout << v << std::endl;
        }
    }
    return 0;
}
```

---

## 5. 参考

* [c++ 官网](http://www.cplusplus.com/reference/)
* [C++ 多态的实现原理分析](https://blog.csdn.net/afei__/article/details/82142775)
