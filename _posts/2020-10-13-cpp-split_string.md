---
layout: post
title:  "c++ 分割字符串函数"
categories: c/c++
tags: split string
author: wenfh2020
---

字符串分割是比较常用的功能，python 和 golang 都有这样的函数。c++ 好像没有，基于 stl 自己实现了一个（[github](https://github.com/wenfh2020/c_test/blob/master/normal/test_split_strings.cpp)），测试基本能用。



* content
{:toc}

---

```c++
/* g++ -std='c++11' test_split_strings.cpp -o test_split_strings && ./test_split_strings */
#include <iostream>
#include <sstream>
#include <vector>

void string_splits(const char* in, const char* sep, std::vector<std::string>& out, bool no_blank = true) {
    if (in == nullptr || sep == nullptr || strlen(sep) > strlen(in)) {
        return;
    }

    std::size_t pos;
    std::string str(in);

    while (1) {
        pos = str.find(sep);
        if (pos != std::string::npos) {
            if (pos != 0) {
                out.push_back(str.substr(0, pos));
            }
            if (str.length() == pos + 1) {
                break;
            }
            str = str.substr(pos + 1);
        } else {
            out.push_back(str);
            break;
        }
    }

    /* trim blank. */
    if (no_blank) {
        auto it = out.begin();
        while (it != out.end()) {
            it->erase(0, it->find_first_not_of(" "));
            it->erase(it->find_last_not_of(" ") + 1);
            if (!it->empty()) {
                it++;
            } else {
                it = out.erase(it);
            }
        }
    }
}

int main() {
    std::vector<std::string> items;
    const char* test = "   ,127.0.0.1:6379, 127.0.0.1:6378, 127.0.0.1:6377, ";
    string_splits(test, ",", items);
    for (auto& s : items) {
        std::cout << s << std::endl;
    }
    return 0;
}
```

---

> 🔥 文章来源：[wenfh2020.com](https://wenfh2020.com/2020/08/04/get-local-time/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
