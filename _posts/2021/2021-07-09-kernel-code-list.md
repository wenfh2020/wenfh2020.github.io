---
layout: post
title:  "[内核源码走读] list 链表"
categories: kernel
tags: kernel list epoll
author: wenfh2020
---

链表（双向链表/环形链表）是 Linux 内核的一个基础数据结构（内核源码目录 ./include/linux/list.h），看看它是如何实现和应用的。

> 走读的源码版本是 5.0.1。




* content
{:toc}



---

## 1. 链表接口

链表节点关系，主要是当前节点，前一个节点 (prev)，后一个节点（next），三个节点的关系。

---

### 1.1. 链表结构

```c
/* ./include/linux/types.h */
struct list_head {
    struct list_head *next, *prev;
};
```

---

### 1.2. 初始化

链表初始化链表时，把节点的 prev, next 指针都指向自己。

```c
static inline void INIT_LIST_HEAD(struct list_head *list) {
    /* 为了避免编译器优化，从内存写数据。 */
    WRITE_ONCE(list->next, list);
    list->prev = list;
}

/* ./include/linux/compile.h */
#define WRITE_ONCE(x, val) \
({                            \
    union { typeof(x) __val; char __c[1]; } __u =    \
        { .__val = (__force typeof(x)) (val) }; \
    __write_once_size(&(x), __u.__c, sizeof(x));    \
    __u.__val;                    \
})

/* ./include/linux/compiler.h */
static __always_inline void __write_once_size(volatile void *p, void *res, int size) {
    switch (size) {
    case 1: *(volatile __u8 *)p = *(__u8 *)res; break;
    case 2: *(volatile __u16 *)p = *(__u16 *)res; break;
    case 4: *(volatile __u32 *)p = *(__u32 *)res; break;
    case 8: *(volatile __u64 *)p = *(__u64 *)res; break;
    default:
        barrier();
        __builtin_memcpy((void *)p, (const void *)res, size);
        barrier();
    }
}
```

---

### 1.3. 检查链表是否为空

当它的 next 指针还是指向自己就认为是空。

> 这个链表的设计，难道 head 节点是不参与真实数据处理的(O_O)?。

```c
/* ./include/linux/list.h
 * list_empty - tests whether a list is empty
 * @head: the list to test.
 */
static inline int list_empty(const struct list_head *head) {
    return READ_ONCE(head->next) == head;
}
```

---

### 1.4. 添加

添加节点，函数设计三个参数的思路：新节点（new），往两个节点（prev, next）中间插入。

```c
/* ./include/linux/list.h
 * Insert a new entry between two known consecutive entries.
 *
 * This is only for internal list manipulation where we know
 * the prev/next entries already!
 */
static inline void __list_add(struct list_head *new,
                  struct list_head *prev,
                  struct list_head *next) {
    if (!__list_add_valid(new, prev, next))
        return;

    next->prev = new;
    new->next = next;
    new->prev = prev;
    WRITE_ONCE(prev->next, new);
}
```

* list_add，将新节点添加到 head 节点后面。

```c
/** ./include/linux/list.h
 * list_add - add a new entry
 * @new: new entry to be added
 * @head: list head to add it after
 *
 * Insert a new entry after the specified head.
 * This is good for implementing stacks.
 */
static inline void list_add(struct list_head *new, struct list_head *head) {
    __list_add(new, head, head->next);
}
```

* list_add_tail，将新节点添加到 head 节点前面。（这是环形链表吧~）

```c
/** ./include/linux/list.h
 * list_add_tail - add a new entry
 * @new: new entry to be added
 * @head: list head to add it before
 *
 * Insert a new entry before the specified head.
 * This is useful for implementing queues.
 */
static inline void list_add_tail(struct list_head *new, struct list_head *head) {
    __list_add(new, head->prev, head);
}
```

---

### 1.5. 删除

```c
/* ./include/linux/list.h
 * Delete a list entry by making the prev/next entries
 * point to each other.
 *
 * This is only for internal list manipulation where we know
 * the prev/next entries already!
 */
static inline void __list_del(struct list_head * prev, struct list_head * next) {
    next->prev = prev;
    WRITE_ONCE(prev->next, next);
}
```

从链表中删除节点，被删除的节点 prev，next 指针指向自己。

```c
/**
 * list_del_init - deletes entry from list and reinitialize it.
 * @entry: the element to delete from the list.
 */
static inline void list_del_init(struct list_head *entry) {
    __list_del_entry(entry);
    INIT_LIST_HEAD(entry);
}

/* ./include/linux/list.h
 * list_del - deletes entry from list.
 * @entry: the element to delete from the list.
 * Note: list_empty() on entry does not return true after this, the entry is
 * in an undefined state.
 */
static inline void __list_del_entry(struct list_head *entry) {
    if (!__list_del_entry_valid(entry))
        return;

    __list_del(entry->prev, entry->next);
}
```

---

### 1.6. 获取

list_head 数据结构，在应用过程中，作为某个数据结构的成员出现，例如下面的 rdllink 是一个 struct list_head 结构。

使用过程中，通过 rdllink 这个成员将 epitem 关联进链表，但是链表里保存的是 rdllink 指针，它不是 struct epitem 的第一个成员，那么如何从 rdllink 位置，找到 epitem 的指针呢？

我们可以知道 rdllink 内存指针，也可以知道 rdllink 在 epitem 的相对偏移位置。这样：

> 理解一下 struct 数据结构数据在内存的布局。

**epitem 指针 = rdllink 指针  -  rdllink 在 epitem 的相对偏移位置。**

* epoll 管理的 fd 节点 epitem。

```c
/* ./fs/eventpoll.c */
struct epitem {
    union {
        /* RB tree node links this structure to the eventpoll RB tree */
        struct rb_node rbn;
        /* Used to free the struct epitem */
        struct rcu_head rcu;
    };
    ...
    struct list_head rdllink;
    ...
};
```

* list 节点内容。

```c
/* ./include/linux/list.h
 * list_entry - get the struct for this entry
 * @ptr:     the &struct list_head pointer.
 * @type:    the type of the struct this is embedded in.
 * @member:  the name of the list_head within the struct.
 */
#define list_entry(ptr, type, member) \
    container_of(ptr, type, member)

/* ./include/linux/list.h
 * Returns a pointer to the container of this list element.
 *
 * Example:
 * struct foo* f;
 * f = container_of(&foo->entry, struct foo, entry);
 * assert(f == foo);
 *
 * @param ptr Pointer to the struct list_head.
 * @param type Data type of the list element.
 * @param member Member name of the struct list_head field in the list element.
 * @return A pointer to the data struct containing the list head.
 */
/* 获得数据结构成员的相对位置，那么往前便宜相对位置，就是数据结构指针的首地址。 */
#ifndef container_of
#define container_of(ptr, type, member) \
    (type *)((char *)(ptr) - (char *) &((type *)0)->member)
#endif
```

---

### 1.7. 遍历

list_first_entry 从 head 节点的下一个节点开始...

```c
/**
 * list_for_each_entry_safe - iterate over list of given type safe against removal of list entry
 * @pos:    the type * to use as a loop cursor.
 * @n:      another type * to use as temporary storage
 * @head:   the head for your list.
 * @member: the name of the list_head within the struct.
 */
#define list_for_each_entry_safe(pos, n, head, member)            \
    for (pos = list_first_entry(head, typeof(*pos), member),    \
        n = list_next_entry(pos, member);            \
         &pos->member != (head);                     \
         pos = n, n = list_next_entry(n, member))

/**
 * list_first_entry - get the first element from a list
 * @ptr:    the list head to take the element from.
 * @type:   the type of the struct this is embedded in.
 * @member: the name of the list_head within the struct.
 *
 * Note, that list is expected to be not empty.
 */
#define list_first_entry(ptr, type, member) \
    list_entry((ptr)->next, type, member)
```

---

## 2. epoll 应用

epoll 的就绪队列，结合上面的代码，理解一下这个队列的应用。

---

### 2.1. 初始化

epoll 数据结构对象 eventpoll 在创建时，会初始化就绪链表，就是 ep->rdllist (list_head) 指针 prev 和 next，指向自己。

```c
/* ./fs/eventpoll.c */

struct eventpoll {
    ...
    /* List of ready file descriptors */
    struct list_head rdllist;
    ...
}

/* 初始化链表。 */
static int ep_alloc(struct eventpoll **pep) {
    ...
    struct eventpoll *ep;
    ep = kzalloc(sizeof(*ep), GFP_KERNEL);
    INIT_LIST_HEAD(&ep->rdllist);
    ...
}
```

---

### 2.2. 添加就绪事件

当用户关注的就绪事件发生时，软中断，将 fd 节点（epi），添加进就绪队列。

```c
/* ./fs/eventpoll.c */
static int ep_poll_callback(wait_queue_entry_t *wait, unsigned mode, int sync, void *key) {
    ...
    struct epitem *epi = ep_item_from_wait(wait);
    struct eventpoll *ep = epi->ep;
    ...
    /* If this file is already in the ready list we exit soon */
    if (!ep_is_linked(epi)) {
        list_add_tail(&epi->rdllink, &ep->rdllist);
        ep_pm_stay_awake_rcu(epi);
    }
    ...
}
```

---

### 2.3. 删除就绪事件

内核遍历就绪链表，向用户态拷贝数据，先将就绪事件删除（list_del_init），如果是 LT 模式再就 epi 添加回就绪链表，等待下次处理。

```c
/* ./fs/eventpoll.c */
static __poll_t ep_send_events_proc(struct eventpoll *ep, struct list_head *head,
                   void *priv) {
    ...
    /* 感觉 list_for_each_entry_safe 这个遍历有点奇葩，取的是 head 节点的下一个，
     * 内核的封装会把人绕晕。 */
    list_for_each_entry_safe(epi, tmp, head, rdllink) {
        ...
        list_del_init(&epi->rdllink);
        ...
        revents = ep_item_poll(epi, &pt, 1);
        if (!revents)
            continue;
        ...
        if (__put_user(revents, &uevent->events) ||
            __put_user(epi->event.data, &uevent->data)) {
            /* 拷贝数据失败，将 epi 节点，添加到 head 节点后面，退出遍历。 */
            list_add(&epi->rdllink, head);
            ep_pm_stay_awake(epi);
            if (!esed->res)
                esed->res = -EFAULT;
            return 0;
        }
        ...
        else if (!(epi->event.events & EPOLLET)) {
            ...
            /* LT 模式，将 epi 节点，重新添加回就绪队列。*/
            list_add_tail(&epi->rdllink, &ep->rdllist);
            ...
        }
    }

    return 0;
}
```

---

## 3. 参考

* 《Linux 内核源代码情景分析》
* [linux deepin内核头文件解析（二）——WRITE_ONCE函数和list.h](https://blog.csdn.net/weixin_40771793/article/details/95013445)