---
layout: post
title:  "[redis 源码走读] 链表"
categories: redis
tags: redis list
author: wenfh2020
---

redis 的链表实现不是很复杂，从 `listNode` 可以知道，`list` 是一个双向链表，支持从链表首尾两边开始遍历结点。同时提供了 `listIter` 迭代器，方便前后方向迭代遍历。其它应该就是链表增删改查的一些常规操作了。



* content
{:toc}

---

## 1. 文件

>adlist.h, adlist.c

## 2. 数据结构

### 2.1. 链表结点

```c
typedef struct listNode {
    struct listNode *prev;
    struct listNode *next;
    void *value;
} listNode;
```

### 2.2. 链表迭代器

```c
typedef struct listIter {
    listNode *next;
    int direction;
} listIter;
```

### 2.3. 链表

```c
typedef struct list {
    listNode *head;
    listNode *tail;
    void *(*dup)(void *ptr);
    void (*free)(void *ptr);
    int (*match)(void *ptr, void *key);
    unsigned long len;
} list;
```

---

> 🔥 文章来源：[《[redis 源码走读] 链表》](https://wenfh2020.com/2020/01/21/redis-list/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
