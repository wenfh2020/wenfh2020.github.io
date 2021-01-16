---
layout: post
title:  "gettimeofday 获取本地时间"
categories: c/c++
tags: gettimeofday local time
author: wenfh2020
---

获取本地时间是比较常用的操作，可通过 `gettimeofday` 函数获取本地时间，然后根据需要转化成对应的时间单位：毫秒，微秒，秒。



* content
{:toc}

---

## 1. gettimeofday

```c
#include <sys/time.h>

int gettimeofday(struct timeval *tp, struct timezone *tzp);

struct timeval {
    time_t       tv_sec;   /* seconds since Jan. 1, 1970 */
    suseconds_t  tv_usec;  /* and microseconds */
};
```

---

## 2. 单位

### 2.1. 毫秒

```c
long long mstime() {
    struct timeval tv;
    long long mst;

    gettimeofday(&tv, NULL);
    mst = ((long long)tv.tv_sec) * 1000;
    mst += tv.tv_usec / 1000;
    return mst;
}
```

---

### 2.2. 微秒

```c
long long ustime() {
    struct timeval tv;
    long long ust;

    gettimeofday(&tv, NULL);
    ust = ((long)tv.tv_sec) * 1000000;
    ust += tv.tv_usec;
    return ust;
}

```

---

### 2.3. 秒（double）

```c
double time_now() {
    struct timeval tv;
    gettimeofday(&tv, 0);
    return ((tv).tv_sec + (tv).tv_usec * 1e-6);
}
```

---

## 3. 格式化

[年]-[月]-[日] [时]-[分]-[秒].[毫秒]

```c++
#include <sys/time.h>
#include <unistd.h>
#include <iostream>

void format() {
    int off;
    time_t t;
    char buf[64];
    struct tm* tm;
    struct timeval tv;

    t = time(NULL);
    tm = localtime(&t);
    gettimeofday(&tv, NULL);
    off = strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", tm);
    std::cout << "[" << buf << "]" << std::endl;

    snprintf(buf + off, sizeof(buf) - off, ".%03d", (int)tv.tv_usec / 1000);
    std::cout << "[" << buf << "]" << std::endl;
}

int main() {
    format();
    return 0;
}
```

```shell
# g++ test_time.cpp -o test_time && ./test_time
[2020-10-16 10:07:22]
[2020-10-16 10:07:22.916]
```
