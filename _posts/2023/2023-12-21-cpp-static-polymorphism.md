---
layout: post
title:  "[C++] 深入探索 C++ 多态 ④ - 模板静态多态"
categories: c/c++
author: wenfh2020
---

动态多态虽然使用灵活，但在某些性能要求极高的嵌入式系统，虚函数调用的性能开销往往显得不那么友好。

所以为了实现多态功能，除了动态多态，我们也可以考虑 `静态多态`，通过模板方式实现类似多态的功能。

* [深入探索 C++ 多态 ① - 虚函数调用链路](https://wenfh2020.com/2022/12/27/deep-cpp/)
* [深入探索 C++ 多态 ② - 继承关系](https://wenfh2020.com/2023/08/22/cpp-inheritance/)
* [深入探索 C++ 多态 ③ - 虚析构](https://www.wenfh2020.com/2023/08/25/cpp-destructor/)
* [深入探索 C++ 多态 ④ - 模板静态多态](https://wenfh2020.com/2023/12/21/cpp-static-polymorphism/)

---



* content
{:toc}



---

## 1. 动态多态

### 1.1. 虚函数调用原理

虚指针 -> 虚函数表 -> 虚函数，这是动态多态虚函数调用原理。

* 虚函数调用的内存布局。

<div align=center><img src="/images/2023/2023-08-16-12-15-41.png" data-action="zoom"/></div>

* 虚函数汇编解析。

```shell
int main(int argc, char** argv) {
  ;...
    A* a = new A;
  ;...
  ; 将 a 的对象（this）指针压栈到 -0x18(%rbp)。
  400722: mov %rbx,-0x18(%rbp)
    a->vfuncA2();
  ; 找到虚指针。
  400726: mov -0x18(%rbp),%rax
  ; 通过虚指针，找到虚表保存虚函数的起始位置。
  40072a: mov (%rax),%rax
  ; 通过上面起始位置进行偏移，找到虚表存放某个虚函数的地址。
  40072d: add $0x8,%rax
  ; 找到对应的虚函数地址。
  400731: mov (%rax),%rax
  ; 通过寄存器传递 a 指针作为参数，传给虚函数使用
  400734: mov -0x18(%rbp),%rdx
  400738: mov %rdx,%rdi
  ; 调用虚函数
  40073b: callq *%rax
    return 0;
  ;...
}
```

> 参考：[深入探索 C++ 多态 ① - 虚函数调用链路](https://wenfh2020.com/2022/12/27/deep-cpp/)

---

### 1.2. 主要缺点

[反汇编查看源码](https://wenfh2020.com/2022/12/27/deep-cpp/)，虚函数与普通函数调用比较，虚函数调用咋一看似乎多了几条额外指令，其实它隐藏了一些性能开销缺点。

<div align=center><img src="/images/2023/2023-12-22-10-28-16.png" width="85%" data-action="zoom"></div>

1. 占用内存：虚指针，虚函数表的出现使得程序运行占用了额外的内存空间。
2. 内联问题：虚函数通过虚指针链路寻址，虚函数代码不能享受编译器内联的优化。
3. Cache miss：虚函数通过虚指针链路寻址，额外的地址跳转（非连续内存空间寻址）破坏了程序的局部性原理；虚函数调用，增加额外非连续内存空间的访问，增加了处理器高速缓存未命中的几率和发生流水线停顿的几率。

> 详细请参考：《C++ 性能优化指南》-P127 - 虚函数的性能开销。

---

## 2. 模板静态多态

为避免动态多态的缺点，静态多态应运而生，例如模板。

### 2.1. 实例

<div align=center><img src="/images/2023/2023-03-07-13-00-36.png" data-action="zoom"/></div>

> 参考：[深入探索 C++ 多态 ① - 虚函数调用链路](https://wenfh2020.com/2022/12/27/deep-cpp/)

* 动态多态。派生类重写基类虚函数。

```cpp
/* g++ -std='c++11' test.cpp -o t && ./t */
#include <iostream>
#include <memory>

class Model {
   public:
    virtual void face() {
        std::cout << "model's face!\n";
    }
};

class Gril : public Model {
   public:
    virtual void face() {
        std::cout << "girl's face!\n";
    }
};

class Man : public Model {
   public:
    virtual void face() {
        std::cout << "man's face!\n";
    }
};

class Boy : public Model {
   public:
    virtual void face() {
        std::cout << "boy's face!\n";
    }
};

void take_photo(const std::unique_ptr<Model>& m) {
    m->face();
}

int main() {
    auto model = std::unique_ptr<Model>(new Model);
    auto girl = std::unique_ptr<Model>(new Gril);
    auto man = std::unique_ptr<Model>(new Man);
    auto boy = std::unique_ptr<Model>(new Boy);
    take_photo(model);
    take_photo(girl);
    take_photo(man);
    take_photo(boy);
    return 0;
}

// 输出：
// model's face!
// girl's face!
// man's face!
// boy's face!
```

* 静态多态。通过派生类对基类模板实例化，也可以实现类似动态多态的效果。

```cpp
// g++ -std='c++11' test.cpp -o t && ./t
#include <iostream>
#include <memory>

template <class T>
class Model {
   public:
    void show() {
        T* p = static_cast<T*>(this);
        p->face();
    }

    void face() {
        std::cout << "model's face!\n";
    }
};

class Who : public Model<Who> {
};

class Gril : public Model<Gril> {
   public:
    void face() {
        std::cout << "girl's face!\n";
    }
};

class Man : public Model<Man> {
   public:
    void face() {
        std::cout << "man's face!\n";
    }
};

class Boy : public Model<Boy> {
   public:
    void face() {
        std::cout << "boy's face!\n";
    }
};

template <typename T>
void takePhoto(Model<T>& m) {
    m.show();
}

int main() {
    Who who;
    Gril girl;
    Man man;
    Boy boy;
    takePhoto(who);
    takePhoto(girl);
    takePhoto(man);
    takePhoto(boy);
    return 0;
}

// 输出：
// model's face!
// girl's face!
// man's face!
// boy's face!
```

---

### 2.2. 工作原理

静态多态实现原理：编译时编译器会为模板生成一份实例化代码，根据对应实例调用对应函数。

模板的实例化源码：

```cpp
template <>
class Model<Who> {
   public:
    inline void show() {
        Who *p = static_cast<Who *>(this);
        static_cast<Model<Who> *>(p)->face();
    }

    inline void face() {
        std::operator<<(std::cout, "model's face!\n");
    }
};

template <>
class Model<Gril> {
   public:
    inline void show() {
        Gril *p = static_cast<Gril *>(this);
        p->face();
    }

    inline void face();
};

template <>
class Model<Man> {
   public:
    inline void show() {
        Man *p = static_cast<Man *>(this);
        p->face();
    }

    inline void face();
};

template <>
class Model<Boy> {
   public:
    inline void show() {
        Boy *p = static_cast<Boy *>(this);
        p->face();
    }

    inline void face();
};

template <>
void takePhoto<Who>(Model<Who> &m) {
    m.show();
}

template <>
void takePhoto<Gril>(Model<Gril> &m) {
    m.show();
}

template <>
void takePhoto<Man>(Model<Man> &m) {
    m.show();
}

template <>
void takePhoto<Boy>(Model<Boy> &m) {
    m.show();
}
```

---

### 2.3. 缺点

天下没有十全十美的东西，虽然静态多态避免了动态多态的性能开销问题。

但是每个模板实例会在编译时生成一份实例化代码，如果使用大量的模板可能会导致 `代码膨胀`。

---

## 3. 参考

* 《C++ 性能优化指南》
* [深入探索 C++ 多态 ① - 虚函数调用链路](https://wenfh2020.com/2022/12/27/deep-cpp/)
