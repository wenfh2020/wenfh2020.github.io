---
layout: post
title:  "深入探索 C++ 多态 ④ - 模板静态多态"
categories: c/c++
author: wenfh2020
---

动态多态虽然使用灵活，但在某些性能要求极高的嵌入式系统，虚函数调用的性能开销往往显得不那么友好。



---



* content
{:toc}

---

## 1. 动态多态

### 1.1. 缺点

虚指针 -> 虚表 -> 虚函数，这是动态多态虚函数调用原理。

[反汇编查看源码](https://wenfh2020.com/2022/12/27/deep-cpp/)，与普通函数调用对比，虚函数调用咋一看似乎多了几条额外的指令，其实它隐藏了一些性能开销缺点。

动态多态缺点：

1. 内存：虚指针，虚表的出现使得程序对内存产生额外开销。
2. 内联：虚函数通过虚指针链路寻址，函数代码不能享受编译器内联的优化。
3. Cache miss：虚函数通过虚指针链路寻址，地址的跳转（非连续内存空间寻址）破坏了程序的局部性原理；虚函数的调用额外导致非连续连续内存空间的访问，增加了处理器高速缓存未命中的几率和发生流水线停顿的几率。

> 详细请参考：《C++ 性能优化指南》-P127 - 虚函数的性能开销

---

### 1.2. 实例

<div align=center><img src="/images/2023/2023-03-07-13-00-36.png" data-action="zoom"/></div>

> 详细请参考：[深入探索 C++ 多态 ① - 虚函数调用链路](https://wenfh2020.com/2022/12/27/deep-cpp/)

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

---

## 2. 模板静态多态

为避免动态多态的缺点，静态多态应运而生，例如模板。

---

### 2.1. 实例

通过模板实例化，也可以达到类似动态多态的效果。

> 参考上面动态多态的实例，改写的静态多态代码。

```cpp
/* g++ -std='c++11' test.cpp -o t && ./t */
#include <iostream>
#include <memory>

template <class T>
class Model {
   public:
    void show() {
        T* p = static_cast<T*>(this);
        p->face();
    }
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
    Gril girl;
    takePhoto(girl);
    Man man;
    takePhoto(man);
    Boy boy;
    takePhoto(boy);
    return 0;
}

// 输出：
// girl's face!
// man's face!
// boy's face!
```

---

### 2.2. 工作原理

静态多态实现原理：模板实例会在编译时生成一份实例化代码，根据对应的实例调用对应的函数。

模板的实例化源码：

```cpp
template <>
class Model<Gril> {
   public:
    inline void show() {
        Gril *p = static_cast<Gril *>(this);
        p->face();
    }
};

template <>
class Model<Man> {
   public:
    inline void show() {
        Man *p = static_cast<Man *>(this);
        p->face();
    }
};

template <>
class Model<Boy> {
   public:
    inline void show() {
        Boy *p = static_cast<Boy *>(this);
        p->face();
    }
};

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
