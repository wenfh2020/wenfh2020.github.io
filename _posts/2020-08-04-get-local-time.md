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

---

## 4. 性能

### 4.1. 问题

高并发系统里，从火焰图里看到：平平无奇的 `mstime()` 接口，却是资源吃货！

<div align=center><img src="/images/2021-03-01-13-10-57.png" data-action="zoom"/></div>

> 火焰图参考：[软件性能检测--火焰图🔥](https://wenfh2020.com/2020/07/30/flame-diagram/)

---

### 4.2. 优化

一般业务，对时间精度要求不高。可以按照两个方面优化：

* 放在时钟里定时设置。
* 根据使用频率设置。

```c++
class Network {
    ...
protected:
    int m_time_index = 0;
    uint64_t m_now_time = 0;

    void on_repeat_timer() {
         m_now_time = mstime();
    }

    uint64_t now() {
        if ((++m_time_index % 10) == 0) {
            m_now_time = mstime();
        }
        return m_now_time;
    }
    ...
};
```

---

有空的同学，可以阅读一下 `libev` 的源码，看看它是怎么获取当前时间的。

```c
ev_tstamp ev_now (struct ev_loop *loop) {
  return ((loop)->ev_rt_now);
}
```
