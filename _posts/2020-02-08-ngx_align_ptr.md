---
layout: post
title:  "nginx 地址对齐(ngx_align_ptr)"
categories: nginx
tags: nginx c align
author: wenfh2020
mathjax: 1
---
内存池，要在大块连续内存上，分配小块内存，指向小内存块的地址是否对齐，对系统性能有一定影响：因为 cpu 从主存上读取数据很慢的，合理的地址对齐可以减少访问次数，提高访问效率。



* content
{:toc}

## 1. 对齐操作

看看 nginx 的内存池地址对齐操作：

```c
// p 是内存指针，a 是对齐字节数
#define ngx_align_ptr(p, a)                                                   \
    (u_char *) (((uintptr_t) (p) + ((uintptr_t) a - 1)) & ~((uintptr_t) a - 1))
```

> 该宏的原理详细证明，请参考 《高效算法的奥秘》（第二版）第三章 2 的幂边界

---

- 当 $ a = 2^n $ 时，`~((uintptr_t) a - 1))`  的 64 位二进制数，最右边 $n$ 位数是 0。所以 `x &  ~((uintptr_t) a - 1)) ` 能被 $2^n$ 整除。

| a 对齐字节数 | 2 的幂 | 64位二进制                                                       |
| :----------- | :----- | :--------------------------------------------------------------- |
| 1            | $2^0$  | 1111111111111111111111111111111111111111111111111111111111111111 |
| 2            | $2^1$  | 1111111111111111111111111111111111111111111111111111111111111110 |
| 4            | $2^2$  | 1111111111111111111111111111111111111111111111111111111111111100 |
| 8            | $2^3$  | 1111111111111111111111111111111111111111111111111111111111111000 |
| 16           | $2^4$  | 1111111111111111111111111111111111111111111111111111111111110000 |
| 32           | $2^5$  | 1111111111111111111111111111111111111111111111111111111111100000 |
| 64           | $2^6$  | 1111111111111111111111111111111111111111111111111111111111000000 |

---

## 2. 测试

测试[源码](https://github.com/wenfh2020/c_test/blob/master/normal/align.cpp)

---

### 2.1. 测试 ~((uintptr_t)a - 1))

```c
// 测试 ~((uintptr_t)a - 1))
void test_a() {
    int i, len;
    uintptr_t l;
    char* p;
    char test[128];

    int aligns[] = {1, 2, 4, 8, 16, 32, 64};
    len = sizeof(aligns) / sizeof(int);

    for (i = 0; i < len; i++) {
        l = ~((uintptr_t)aligns[i] - 1);
        p = i2bin(l, test, 128);
        printf("a: %2d,  d: %s\n", aligns[i], p);
    }
}
```

结果：

```shell
a:  1,  d: 1111111111111111111111111111111111111111111111111111111111111111
a:  2,  d: 1111111111111111111111111111111111111111111111111111111111111110
a:  4,  d: 1111111111111111111111111111111111111111111111111111111111111100
a:  8,  d: 1111111111111111111111111111111111111111111111111111111111111000
a: 16,  d: 1111111111111111111111111111111111111111111111111111111111110000
a: 32,  d: 1111111111111111111111111111111111111111111111111111111111100000
a: 64,  d: 1111111111111111111111111111111111111111111111111111111111000000
```

---

### 2.2. 地址添加随机数，测试不同的对齐方式

```c
// 测试数值是否对齐
void test_align_mod() {
    char bin[128];
    u_char *p, *a, *r;
    int i, len, alignment;
    int aligns[] = {1, 2, 4, 8, 16, 32, 64};

    len = sizeof(aligns) / sizeof(int);
    srand(time(NULL));

    p = (u_char*)malloc(1024 * sizeof(u_char));
    printf("p: %p\n", p);

    r = p;

    for (i = 0; i < len; i++) {
        alignment = aligns[i];
        r = p + rand() % 64;
        a = ngx_align_ptr(r, alignment);
        printf("a: %2d, r: %p, align: %p, abin: %s, mod: %lu\n", alignment, r,
               a, i2bin((unsigned long long)a, bin, 128),
               (uintptr_t)a % alignment);
    }
    free(p);
}
```

结果：

```shell
p: 0x7fd035800600
a:  1, r: 0x7fd03580062f, align: 0x7fd03580062f, abin: 11111111101000000110101100000000000011000101111, mod: 0
a:  2, r: 0x7fd03580061a, align: 0x7fd03580061a, abin: 11111111101000000110101100000000000011000011010, mod: 0
a:  4, r: 0x7fd035800635, align: 0x7fd035800638, abin: 11111111101000000110101100000000000011000111000, mod: 0
a:  8, r: 0x7fd035800613, align: 0x7fd035800618, abin: 11111111101000000110101100000000000011000011000, mod: 0
a: 16, r: 0x7fd035800633, align: 0x7fd035800640, abin: 11111111101000000110101100000000000011001000000, mod: 0
a: 32, r: 0x7fd035800602, align: 0x7fd035800620, abin: 11111111101000000110101100000000000011000100000, mod: 0
a: 64, r: 0x7fd03580061b, align: 0x7fd035800640, abin: 11111111101000000110101100000000000011001000000, mod: 0
```

---

### 2.3. 测试对齐效率

申请两块内存，一块内存是对齐处理，另外一块不对齐查看效率（[测试代码](https://github.com/wenfh2020/c_test/blob/master/normal/align.cpp)）。

```c
#define ALIGN 1
#define UN_ALIGN 0
#define READ 0
#define WRITE 1
#define ALIGN_COUNT (1024 * 1024 * 64)
#define UN_ALIGN_COUNT ALIGN_COUNT

typedef int type_t;
#define ngx_align_ptr(p, a) \
    (u_char*)(((uintptr_t)(p) + ((uintptr_t)a - 1)) & ~((uintptr_t)a - 1))

// 申请两块内存，一块内存是对齐处理，另外一块不对齐。
void test_align(u_char* p, int size, int alignment, int is_align,
                int is_write) {
    u_char* end;
    long long start, stop;
    type_t *wirte, read;
    int count;

    count = 0;
    srand(time(NULL));

    end = p + size;
    p = (u_char*)ngx_align_ptr(p, alignment);
    p += is_align ? 0 : 1;  //制造不对齐地址

    start = mstime();
    while (p + sizeof(type_t) < end) {
        if (is_write) {
            wirte = (type_t*)p;
            *wirte = (type_t)rand();
        } else {
            read = (type_t)rand();
        }
        p += sizeof(type_t);

        count++;
    }
    stop = mstime();

    printf(
        "is_align: %d, is_write: %d, alignment: %d, count: %d, cost: %lld ms,"
        " avg: %lf ms\n",
        is_align, is_write, alignment, count, stop - start,
        (float)(stop - start) / count);
}

void test_alloc_mem(int argc, char** argv, int alignment, int is_align) {
    u_char *aligns, *ualigns;
    int alen, ualen;

    alen = ALIGN_COUNT * sizeof(type_t);
    aligns = (u_char*)malloc(alen);
    ualen = UN_ALIGN_COUNT * sizeof(type_t);
    ualigns = (u_char*)malloc(ualen);

    if (is_align) {
        test_align(aligns, alen, alignment, ALIGN, WRITE);
        test_align(aligns, alen, alignment, ALIGN, READ);
    } else {
        test_align(ualigns, ualen, alignment, UN_ALIGN, WRITE);
        test_align(ualigns, ualen, alignment, UN_ALIGN, READ);
    }

    free(aligns);
    free(ualigns);
    return;
}

int main(int argc, char* argv[]) {
    int alignment, is_align;

    alignment = (argc >= 2) ? atoi(argv[1]) : 4;
    is_align = (argc == 3 && !strcasecmp(argv[2], "1")) ? 1 : 0;
    test_alloc_mem(argc, argv, alignment, is_align);
    return 0;
}
```

结果：

```shell
# ./test_align.sh

is_align: 1, is_write: 1, alignment: 16, count: 67108862, cost: 1016 ms, avg: 0.000015 ms
is_align: 1, is_write: 0, alignment: 16, count: 67108862, cost: 214 ms, avg: 0.000003 ms

real    0m1.244s
user    0m1.177s
sys     0m0.066s
-------
is_align: 0, is_write: 1, alignment: 16, count: 67108862, cost: 919 ms, avg: 0.000014 ms
is_align: 0, is_write: 0, alignment: 16, count: 67108862, cost: 223 ms, avg: 0.000003 ms

real    0m1.159s
user    0m1.084s
sys     0m0.075s
```

---

## 3. 总结

从测试例子中，对齐和不对齐效率没有明显差距（`cost` 耗费时间），反而对齐的地址有时候花的时间还多，实践和理论对不上啊！——不知道问题出在哪里，能力有限，欢迎指正。

---

## 4. 参考

[[nginx 源码走读] 内存池](https://www.jianshu.com/p/7bf77adc17be)

[NGINX 内存池 — 对齐](https://blog.virbox.com/?p=63)

[Nginx - CPU Cacheline 深思](https://oopschen.github.io/posts/2013/cpu-cacheline/)

[C语言字节对齐问题详解](https://www.cnblogs.com/clover-toeic/p/3853132.html)

[谈谈内存对齐一](http://www.openedv.com/thread-277386-1-1.html)

---

> 🔥 文章来源：[《nginx 地址对齐(ngx_align_ptr)》](https://wenfh2020.com/2020/02/08/ngx_align_ptr/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
