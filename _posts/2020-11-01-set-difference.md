---
layout: post
title:  "计算两个集合差集（C++）"
categories: c/c++
tags: set_difference
author: wenfh2020
---

标准库里有这个函数：`set_difference`，它可以计算两个集合的差集。

它的算法实现并不复杂，但是要求传进来的两个参数数组集合数据都是有序的（从小到大排列）。

> [cppreference.com](https://zh.cppreference.com/w/cpp/algorithm/set_difference) 有详细文档和测试用例。




* content
{:toc}

---

## 1. 源码

我封装了一个比较通用的模板函数 diff_cmp：

```cpp
template <typename T>
std::vector<T> diff_cmp(std::vector<T>& first, std::vector<T>& second) {
    std::vector<T> diff;
    /* 排序 */
    std::sort(first.begin(), first.end(), std::less<T>());
    std::sort(second.begin(), second.end(), std::less<T>());
    /* 求两个集合差集 */
    std::set_difference(first.begin(), first.end(), second.begin(),
                        second.end(), std::inserter(diff, diff.begin()));
    /* 返回差集结果。*/
    return diff;
}
```

---

## 2. 测试

* 测试源码 [github](https://github.com/wenfh2020/c_test/blob/master/algorithms/test_set_difference.cpp)。

```cpp
#include <algorithm>
#include <iostream>
#include <vector>

/* 求差集数组模板。 */
template <typename T>
std::vector<T> diff_cmp(std::vector<T>& first, std::vector<T>& second) {
    std::vector<T> diff;
    /* 排序 */
    std::sort(first.begin(), first.end(), std::less<T>());
    std::sort(second.begin(), second.end(), std::less<T>());
    /* 求两个集合差集 */
    std::set_difference(first.begin(), first.end(), second.begin(),
                        second.end(), std::inserter(diff, diff.begin()));
    return diff;
}

void diff_int() {
    ...
    std::vector<int> diff;
    std::vector<int> first{9, 2, 3, 7, 5, 4, 1};
    std::vector<int> second{10, 2, 8, 5, 6, 3, 1};
    ...
    diff = diff_cmp(first, second);
    ...
    diff = diff_cmp(second, first);
    ...
}

void diff_string(bool turn = false) {
    ...
    std::vector<std::string> diff;
    std::vector<std::string> first{"192.168.0.1:1122.1", "192.168.0.1:1122.3", "192.168.0.1:1133.1", "192.168.0.1:1133.2"};
    std::vector<std::string> second{"192.168.0.1:1122.1", "192.168.0.1:1122.2", "192.168.0.1:1133.1", "192.168.0.1:1133.3"};
    ...
    diff = diff_cmp(first, second);
    ...
    diff = diff_cmp(second, first);
    ...
}

int main() {
    diff_int();
    diff_string();
}
```

* 测试结果。

```shell
-------
first: 9, 2, 3, 7, 5, 4, 1,
second: 10, 2, 8, 5, 6, 3, 1,
turn: 0, diff: 4, 7, 9,
turn: 1, diff: 6, 8, 10,
-------
first: 192.168.0.1:1122.1, 192.168.0.1:1122.3, 192.168.0.1:1133.1, 192.168.0.1:1133.2,
second: 192.168.0.1:1122.1, 192.168.0.1:1122.2, 192.168.0.1:1133.1, 192.168.0.1:1133.3,
turn: 0, diff: 192.168.0.1:1122.3, 192.168.0.1:1133.2,
turn: 1, diff: 192.168.0.1:1122.2, 192.168.0.1:1133.3,
```

---

## 3. 参考

* [set_difference()](https://blog.csdn.net/querdaizhi/article/details/6712519)
* [cppreference.com](https://zh.cppreference.com/w/cpp/algorithm/set_difference)
