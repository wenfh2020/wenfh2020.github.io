---
layout: post
title:  "gettimeofday 获取本地时间"
categories: c/c++
tags: gettimeofday local time
author: wenfh2020
---

获取本地时间是比较常用的操作，通过函数 `gettimeofday` 可获取本地时间，然后根据需要转化为毫秒，微秒，dobule 精度的时间。



* content
{:toc}

---

## 1. gettimeofday

```c
#include <sys/time.h>

int
gettimeofday(struct timeval *tp, struct timezone *tzp);

struct timeval {
    time_t       tv_sec;   /* seconds since Jan. 1, 1970 */
    suseconds_t  tv_usec;  /* and microseconds */
};
```

---

## 2. 毫秒

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

## 3. 微秒

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

## 4. 秒（double）

```c
double time_now() {
    struct timeval tv;
    gettimeofday(&tv, 0);
    return ((tv).tv_sec + (tv).tv_usec * 1e-6);
}
```

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/2020/08/04/get-local-time/)
