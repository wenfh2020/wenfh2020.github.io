---
layout: post
title:  "c++ 分割字符串函数"
categories: c/c++
tags: split string
author: wenfh2020
---

分割字符串是比较常用的功能，自己基于 stl 实现了一个（[github](https://github.com/wenfh2020/c_test/blob/master/normal/test_split_strings.cpp)）。



* content
{:toc}

---

## 1. 源码

```cpp
/* script: g++ -std='c++11' test_split_strings.cpp -o split && ./split */
void split(const std::string& s, std::vector<std::string>& vec, const std::string& sep = " ", bool trim_blank = true) {
    std::size_t pre = 0, cur = 0;
    while ((pre = s.find_first_not_of(sep, cur)) != std::string::npos) {
        cur = s.find(sep, pre);
        if (cur == std::string::npos) {
            vec.push_back(s.substr(pre, s.length() - pre));
            break;
        }
        vec.push_back(s.substr(pre, cur - pre));
    }

    if (trim_blank && sep != " ") {
        for (auto& v : vec) {
            v.erase(0, v.find_first_not_of(" "));
            v.erase(v.find_last_not_of(" ") + 1);
        }
    }
}
```

---

## 2. 参考

* [HOW TO SPLIT A STRING IN C++](http://www.martinbroadhurst.com/how-to-split-a-string-in-c.html)
