---
layout: post
title:  "strncpy 安全吗? "
categories: c/c++
tags: strcpy strncpy snprintf
author: wenfh2020
---

测试一下看看，Linux 环境下，这三个函数（`strcpy`, `strncpy`, `snprintf`）哪个比较安全。



* content
{:toc}

---

## 测试代码

数据拷贝，当目标内存很小，源数据很大时，从测试结果看：

* `snprintf` 结果正常，达到预期。
* `strcpy` 拷贝的数据打印出来有点问题，不知道是否正常。
* `strncpy` 崩溃了。

```c
// test.c
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
    char test[2];
    const char* p = "hello world";

    printf("%s", "snprintf: ");
    snprintf(test, sizeof(test), "%s", p);
    printf("%s\n", test);

    printf("%s", "strcpy: ");
    strcpy(test, p);
    printf("%s\n", test);

    printf("%s", "strncpy: ");
    strncpy(test, p, sizeof(test));
    printf("%s\n", test);
}
```

---

```shell
# gcc -g test.c -o test && ./test
snprintf: h
strcpy: hello world
[1]    18785 segmentation fault (core dumped)  ./test
```

---

## 看源码，探究原因

* strcpy
  
  从源码看，字符串拷贝是寻找 '\0' 结束符，上面的测试场景看，这个函数是不安全的。

```c
// https://github.com/torvalds/linux/blob/master/lib/string.c
char *strcpy(char *dest, const char *src) {
    char *tmp = dest;
    while ((*dest++ = *src++) != '\0')
        /* nothing */;
    return tmp;
}
```

* strncpy

  从源码看，字符串拷贝也是寻找 '\0' 结束符，而且有数据大小限制。上面测试场景，数据拷贝是安全的，但是 printf 出问题了，因为 printf 在打印字符串时，也是在找字符串的 '\0' 结束符。而 strncpy 不会自动在末自己补 '\0'。

  > 关于 printf，详细可以参考下我的帖子 [printf 从现象到本质](https://wenfh2020.com/2020/03/01/c-printf/)

```c
// https://github.com/torvalds/linux/blob/master/lib/string.c
char *strncpy(char *dest, const char *src, size_t count) {
    char *tmp = dest;

    while (count) {
        if ((*tmp = *src) != 0)
            src++;
        tmp++;
        count--;
    }
    return dest;
}
```

* sprintf
  
  代码有点长，没仔细看完，从测试场景上看，是正常的。。。

```c
// https://github.com/torvalds/linux/blob/master/lib/vsprintf.c
int snprintf(char *buf, size_t size, const char *fmt, ...) {
    va_list args;
    int i;

    va_start(args, fmt);
    i = vsnprintf(buf, size, fmt, args);
    va_end(args);

    return i;
}

int vsnprintf(char *buf, size_t size, const char *fmt, va_list args) {
    ...
}
```

---

## 总结

从测试结果看：

* `snprintf` 比较安全。
* `strcpy` 不安全。
* `strncpy` 当目标内存很小时，拷贝完成后不会在末位添加 '\0' ，拷贝操作后，目标字符串在使用中可能会有问题。

---

内存越界是 c/c++ 一个坑，有时候要解决这类型的偶发问题，只能看缘分。所以平时使用，须要形成良好的编码习惯。

---

* 更精彩内容，可以关注我的博客：[wenfh2020.com](https://wenfh2020.com/)
