---
layout: post
title:  "c++ 分割字符串函数"
categories: c/c++
tags: split string
author: wenfh2020
---

分割字符串是比较常用的功能，自己基于 stl 实现了一个，也可以参考一下 QT 原生的字符串分割实现逻辑。



* content
{:toc}

---

## 1. 轮子

* 源码。

```cpp
// g++ -std='c++11' test_split_strings.cpp -o t && ./t
#include <iostream>
#include <string>
#include <list>

// 分割子串
std::list<std::string> split(const std::string& src, const std::string& sep) {
    std::list<std::string> subs;
    std::size_t pre = 0, cur = 0;

    while ((pre = src.find_first_not_of(sep, cur)) != std::string::npos) {
        cur = src.find(sep, pre);
        if (cur == std::string::npos) {
            subs.push_back(src.substr(pre, src.length() - pre));
            break;
        }
        subs.push_back(src.substr(pre, cur - pre));
    }
    return subs;
}

// 去掉子串的前后空白符
void trim_empty_parts(std::list<std::string>& datas) {
    for (auto it = datas.begin(); it != datas.end();) {
        it->erase(0, it->find_first_not_of(" "));
        it->erase(it->find_last_not_of(" ") + 1);
        it = it->empty() ? datas.erase(it) : ++it;
    }
}

int main() {
    auto data = "  ,127.0.0.1:6379,  127.0.0.1:6378 ,  127.0.0.1:6377 ,3 ";
    auto subs = split(data, ",");
    for (auto& s : subs) {
        std::cout << "len: " << s.length() << ", value: " << s << std::endl;
    }

    std::cout << "--------------" << std::endl;

    trim_empty_parts(subs);
    for (auto& s : subs) {
        std::cout << "len: " << s.length() << ", value: " << s << std::endl;
    }
    return 0;
}
```

* 结果。

```shell
len: 1, value:  
len: 14, value: 127.0.0.1:6379
len: 17, value:   127.0.0.1:6378 
len: 17, value:   127.0.0.1:6377 
len: 2, value: 3 
--------------
len: 14, value: 127.0.0.1:6379
len: 14, value: 127.0.0.1:6378
len: 14, value: 127.0.0.1:6377
len: 1, value: 3
```

---

## 2. QT 原生

QT 原生字符串分割实现逻辑。

```cpp
// C:\Qt\Qt5.14.2\5.14.2\Src\qtbase\src\corelib\text\qstring.cpp
QStringList QString::split(const QString& sep, SplitBehavior behavior,
                           Qt::CaseSensitivity cs) const {
    return splitString<QStringList>(*this, sep.constData(), behavior, cs, sep.size());
}

namespace {
template <class ResultList, class StringSource>
static ResultList splitString(const StringSource& source, const QChar* sep,
                              QString::SplitBehavior behavior,
                              Qt::CaseSensitivity cs, const int separatorSize) {
    ResultList list;
    typename StringSource::size_type start = 0;
    typename StringSource::size_type end;
    typename StringSource::size_type extra = 0;

    while ((end = QtPrivate::findString(
                QStringView(source.constData(), source.size()), start + extra,
                QStringView(sep, separatorSize), cs)) != -1) {
        if (start != end || behavior == QString::KeepEmptyParts)
            list.append(source.mid(start, end - start));
        start = end + separatorSize;
        extra = (separatorSize == 0 ? 1 : 0);
    }

    if (start != source.size() || behavior == QString::KeepEmptyParts)
        list.append(source.mid(start, -1));
    return list;
}

}  // namespace
```

---

## 3. 参考

* [HOW TO SPLIT A STRING IN C++](http://www.martinbroadhurst.com/how-to-split-a-string-in-c.html)
