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

## 文件

>adlist.h, adlist.c

## 数据结构

### 链表结点

```c
typedef struct listNode {
    struct listNode *prev;
    struct listNode *next;
    void *value;
} listNode;
```

### 链表迭代器

```c
typedef struct listIter {
    listNode *next;
    int direction;
} listIter;
```

### 链表

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
