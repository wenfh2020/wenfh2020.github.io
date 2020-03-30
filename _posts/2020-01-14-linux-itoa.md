---
layout: post
title:  "linux 下实现 itoa 转二进制"
categories: c/c++
tags: c/c++
author: wenfh2020
--- 

`linux` 下，需要将整数转化为二进制，很自然想到 `itoa`，发现这函数竟然编译不通过。标准库中貌似有这个[实现](http://www.cplusplus.com/reference/cstdlib/itoa/
)，不明白了~ 网上参考了[帖子](https://stackoverflow.com/questions/190229/where-is-the-itoa-function-in-linux)，下面实现代码：



* content
{:toc}

---

## 方法一

感觉这方法有点费脑，不是很直观。

> 取模的方法一般都是从低位到高位，所以保存的字符串结果一般会跟需要的结果相反，需要倒转，要解决这个问题，可以从字符串数组后面开始往前保存。

```c
#include <stdio.h>
#include <string.h>

#define BUF_LEN 64

char* i2bin(unsigned long long v, char* buf, int len) {
    if (0 == v) {
        memcpy(buf, "0", 2);
        return buf;
    }

    char* dst = buf + len - 1;
    *dst = '\0';

    while (v) {
        if (dst - buf <= 0) return NULL;
        *--dst = (v & 1) + '0';
        v = v >> 1;
    }
    memcpy(buf, dst, buf + len - dst);
    return buf;
}

int main() {
    unsigned long long v;
    scanf("%llu", &v);
    char buf[BUF_LEN] = {0};
    char* res = i2bin(v, buf, BUF_LEN);
    res ? printf("data: %s, len: %lu\n", i2bin(v, buf, BUF_LEN), strlen(buf))
        : printf("fail\n");
}
```

---

## 方法二

参考 redis sds.c 源码，把下面源码的 10 改为 2 即可。

```c
int sdsll2str(char *s, long long value) {
    char *p, aux;
    unsigned long long v;
    size_t l;

    /* Generate the string representation, this method produces
     * an reversed string. */
    v = (value < 0) ? -value : value;
    p = s;
    do {
        *p++ = '0' + (v % 10); // 2 
        v /= 10; // 2
    } while (v);
    if (value < 0) *p++ = '-';

    /* Compute length and add null term. */
    l = p - s;
    *p = '\0';

    /* Reverse the string. */
    p--;
    while (s < p) {
        aux = *s;
        *s = *p;
        *p = aux;
        s++;
        p--;
    }
    return l;
}
```

---

### 方法三

可以参考下 linux 源码，看看 printf 是怎么格式化字符串的。参考 [github 源码](https://github.com/torvalds/linux/blob/master/arch/x86/boot/printf.c)

---

* 更精彩内容，可以关注我的博客：[wenfh2020.com](https://wenfh2020.com/)