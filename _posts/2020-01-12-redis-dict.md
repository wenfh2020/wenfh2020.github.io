---
layout: post
title:  "[redis 源码走读] 字典(dict)"
categories: redis
tags: redis dict 字典
author: wenfh2020
mathjax: true
---

redis 是 key-value 的 NoSQL 数据库，dict 是基本数据结构，dict 总体来说是一个`哈希表`，哈希表 $O(1)$ 的时间复杂度，能高效进行数据读取。dict 还有动态扩容/缩容的功能，能灵活有效地使用机器内存。因为 redis 是单进程服务，所以当数据量很大的时候，扩容/缩容这些内存操作，涉及到新内存重新分配，数据拷贝。当数据量大的时候，会导致系统卡顿，必然会影响服务质量，redis 作者采用了渐进式的方式，将一次性操作，分散到 dict 对应的各个增删改查操作中。每个操作触发有限制数量的数据进行迁移。所以 dict 会有两个哈希表（`dictht ht[2];`），相应的 `rehashidx` 迁移位置，方便数据迁移操作。

![结构](/images/2020-02-20-16-49-43.png)



* content
{:toc}

---

## 数据结构

```c
//字典
typedef struct dict {
    dictType *type;
    void *privdata;
    dictht ht[2];
    long rehashidx;/* rehashing not in progress if rehashidx == -1 */
    int iterators; /* number of iterators currently running */
} dict;

// 哈希表
typedef struct dictht {
    dictEntry **table;
    unsigned long size;
    unsigned long sizemask;
    unsigned long used;
} dictht;

// 链表数据结点
typedef struct dictEntry {
    void *key;
    union {
        void *val;
        uint64_t u64;
        int64_t s64;
        double d;
    } v;
    struct dictEntry *next;
} dictEntry;

// 数据类型，不同应用实现是不同的，所以用指针函数抽象出通用的接口，方便调用。
typedef struct dictType {
    unsigned int (*hashFunction)(const void *key);
    void *(*keyDup)(void *privdata, const void *key);
    void *(*valDup)(void *privdata, const void *obj);
    int (*keyCompare)(void *privdata, const void *key1, const void *key2);
    void (*keyDestructor)(void *privdata, void *key);
    void (*valDestructor)(void *privdata, void *obj);
} dictType;
```

## 时间复杂度（读数据）

查找数据，哈希表 $O(1)$ 时间复杂度，但是哈希表也会存在碰撞问题，所以哈希索引指向的列表长度也会影响效率。

```c
#define dictHashKey(d, key) (d)->type->hashFunction(key)

dictEntry *dictFind(dict *d, const void *key) {
    dictEntry *he;
    uint64_t h, idx, table;

    if (d->ht[0].used + d->ht[1].used == 0) return NULL; /* dict is empty */
    if (dictIsRehashing(d)) _dictRehashStep(d);
    h = dictHashKey(d, key);
    for (table = 0; table <= 1; table++) {
        idx = h & d->ht[table].sizemask;
        he = d->ht[table].table[idx];
        while(he) {
            // 如果 key 已经存在则返回错误。
            if (key==he->key || dictCompareKeys(d, key, he->key))
                return he;
            he = he->next;
        }

        // 如果数据正在迁移，从第二张表上查找。
        if (!dictIsRehashing(d)) return NULL;
    }
    return NULL;
}
```

## 工作流程

* 堆栈调用流程，下面会通过这个堆栈函数调用时序，看以下写操作的源码流程：

> 调试方法，可以参考视频：
>
> * bilibili: [Debug Redis in VsCode with Gdb](https://www.bilibili.com/video/av83070640)
> * youtube: [Debug Redis in VsCode with Gdb](https://youtu.be/QltK3vV5Slw)

```shell
#0  dictAdd (d=0x100529310, key=0x1018000b1, val=0x101800090) at dict.c:324
#1  0x000000010002bb9c in dbAdd (db=0x101005800, key=0x101800070, val=0x101800090) at db.c:159
#2  0x000000010002bd5c in setKey (db=0x101005800, key=0x101800070, val=0x101800090) at db.c:186
#3  0x000000010003abad in setGenericCommand (c=0x101015400, flags=0, key=0x101800070, val=0x101800090, expire=0x0, unit=0, ok_reply=0x0, abort_reply=0x0) at t_string.c:86
#4  0x000000010003afdd in setCommand (c=0x101015400) at t_string.c:139
#5  0x000000010001052d in call (c=0x101015400, flags=15) at server.c:2252
#6  0x00000001000112ac in processCommand (c=0x101015400) at server.c:2531
#7  0x0000000100025619 in processInputBuffer (c=0x101015400) at networking.c:1299
#8  0x0000000100021cb8 in readQueryFromClient (el=0x100528ba0, fd=5, privdata=0x101015400, mask=1) at networking.c:1363
#9  0x000000010000583c in aeProcessEvents (eventLoop=0x100528ba0, flags=3) at ae.c:412
#10 0x0000000100005ede in aeMain (eventLoop=0x100528ba0) at ae.c:455
#11 0x00000001000159d7 in main (argc=2, argv=0x7ffeefbff8c8) at server.c:4114
```

## 写数据

### 保存数据

数据库保存数据时，先检查这个键是否已经存在，从而分开添加，删除逻辑。

```c
/* High level Set operation. This function can be used in order to set
 * a key, whatever it was existing or not, to a new object.
 *
 * 1) The ref count of the value object is incremented.
 * 2) clients WATCHing for the destination key notified.
 * 3) The expire time of the key is reset (the key is made persistent). */
void setKey(redisDb *db, robj *key, robj *val) {
    if (lookupKeyWrite(db,key) == NULL) {
        dbAdd(db,key,val);
    } else {
        dbOverwrite(db,key,val);
    }
    incrRefCount(val);
    removeExpire(db,key);
    signalModifiedKey(db,key);
}
```

### 添加数据

要添加一个元素，首先需要申请一个空间，申请空间涉及到是否需要扩容，key 是否已经存在了。

```c
/* Add an element to the target hash table */
int dictAdd(dict *d, void *key, void *val) {
    dictEntry *entry = dictAddRaw(d,key);

    if (!entry) return DICT_ERR;
    dictSetVal(d, entry, val);
    return DICT_OK;
}
```

### 增加数据结点

```c
/* Low level add. This function adds the entry but instead of setting
 * a value returns the dictEntry structure to the user, that will make
 * sure to fill the value field as he wishes.
 *
 * This function is also directly exposed to the user API to be called
 * mainly in order to store non-pointers inside the hash value, example:
 *
 * entry = dictAddRaw(dict,mykey);
 * if (entry != NULL) dictSetSignedIntegerVal(entry,1000);
 *
 * Return values:
 *
 * If key already exists NULL is returned.
 * If key was added, the hash entry is returned to be manipulated by the caller.
 */
dictEntry *dictAddRaw(dict *d, void *key) {
    int index;
    dictEntry *entry;
    dictht *ht;

    if (dictIsRehashing(d)) _dictRehashStep(d);

    /* Get the index of the new element, or -1 if
     * the element already exists. */
    // 检查 key 是否存在，避免重复添加。
    if ((index = _dictKeyIndex(d, key)) == -1)
        return NULL;

    /* Allocate the memory and store the new entry.
     * Insert the element in top, with the assumption that in a database
     * system it is more likely that recently added entries are accessed
     * more frequently. */
    // 如果哈希表正在迁移数据，操作哈希表2.
    ht = dictIsRehashing(d) ? &d->ht[1] : &d->ht[0];
    entry = zmalloc(sizeof(*entry));
    entry->next = ht->table[index];
    ht->table[index] = entry;
    ht->used++;

    /* Set the hash entry fields. */
    dictSetKey(d, entry, key);
    return entry;
}
```

### 哈希索引

```c
/* Returns the index of a free slot that can be populated with
 * a hash entry for the given 'key'.
 * If the key already exists, -1 is returned.
 *
 * Note that if we are in the process of rehashing the hash table, the
 * index is always returned in the context of the second (new) hash table. */
static int _dictKeyIndex(dict *d, const void *key) {
    unsigned int h, idx, table;
    dictEntry *he;

    /* Expand the hash table if needed */
    if (_dictExpandIfNeeded(d) == DICT_ERR)
        return -1;
    /* Compute the key hash value */
    h = dictHashKey(d, key);
    for (table = 0; table <= 1; table++) {
        idx = h & d->ht[table].sizemask;
        /* Search if this slot does not already contain the given key */
        he = d->ht[table].table[idx];
        while(he) {
            // 如果 key 已经存在则返回错误。
            if (key==he->key || dictCompareKeys(d, key, he->key))
                return -1;
            he = he->next;
        }

        // 如果哈希表处在数据迁移状态，从第二张表上查找。
        if (!dictIsRehashing(d)) break;
    }
    return idx;
}
```

## 数据迁移

### 哈希表数据迁移

避免数据量大，一次性迁移需要耗费大量资源。每次只迁移部分数据。

```c
/* This function performs just a step of rehashing, and only if there are
 * no safe iterators bound to our hash table. When we have iterators in the
 * middle of a rehashing we can't mess with the two hash tables otherwise
 * some element can be missed or duplicated.
 *
 * This function is called by common lookup or update operations in the
 * dictionary so that the hash table automatically migrates from H1 to H2
 * while it is actively used. */
static void _dictRehashStep(dict *d) {
    if (d->iterators == 0) dictRehash(d,1);
}

/* Performs N steps of incremental rehashing. Returns 1 if there are still
 * keys to move from the old to the new hash table, otherwise 0 is returned.
 *
 * Note that a rehashing step consists in moving a bucket (that may have more
 * than one key as we use chaining) from the old to the new hash table, however
 * since part of the hash table may be composed of empty spaces, it is not
 * guaranteed that this function will rehash even a single bucket, since it
 * will visit at max N*10 empty buckets in total, otherwise the amount of
 * work it does would be unbound and the function may block for a long time. */
int dictRehash(dict *d, int n) {
    // empty_visits 记录哈希表最大遍历空桶个数。
    int empty_visits = n*10; /* Max number of empty buckets to visit. */
    if (!dictIsRehashing(d)) return 0;

    // 从 ht[0] rehashidx 位置开始遍历 n 个桶进行数据迁移。
    while(n-- && d->ht[0].used != 0) {
        dictEntry *de, *nextde;

        /* Note that rehashidx can't overflow as we are sure there are more
         * elements because ht[0].used != 0 */
        assert(d->ht[0].size > (unsigned long)d->rehashidx);
        while(d->ht[0].table[d->rehashidx] == NULL) {
            d->rehashidx++;
            // 当遍历限制的空桶数量后，返回。
            if (--empty_visits == 0) return 1;
        }

        // 获取桶上的数据链表
        de = d->ht[0].table[d->rehashidx];
        /* Move all the keys in this bucket from the old to the new hash HT */
        while(de) {
            unsigned int h;

            nextde = de->next;
            /* Get the index in the new hash table */
            h = dictHashKey(d, de->key) & d->ht[1].sizemask;
            // 旧的数据链表插入新的数据链表前面。
            de->next = d->ht[1].table[h];
            d->ht[1].table[h] = de;
            d->ht[0].used--;
            d->ht[1].used++;
            de = nextde;
        }
        d->ht[0].table[d->rehashidx] = NULL;
        d->rehashidx++;
    }

    // 数据迁移完毕，重置哈希表两个 table。
    /* Check if we already rehashed the whole table... */
    if (d->ht[0].used == 0) {
        zfree(d->ht[0].table);
        d->ht[0] = d->ht[1];
        _dictReset(&d->ht[1]);
        d->rehashidx = -1;
        return 0;
    }

    /* More to rehash... */
    return 1;
}
```

### 定时执行任务

```c
/* Rehash for an amount of time between ms milliseconds and ms+1 milliseconds */
int dictRehashMilliseconds(dict *d, int ms) {
    long long start = timeInMilliseconds();
    int rehashes = 0;

    while(dictRehash(d,100)) {
        rehashes += 100;
        if (timeInMilliseconds()-start > ms) break;
    }
    return rehashes;
}
```

## 扩容缩容

`dict` 是 redis 使用对基础数据之一，该数据结构有动态扩容和缩容功能。

### 是否需要扩容

```c
/* Expand the hash table if needed */
static int _dictExpandIfNeeded(dict *d) {
    /* Incremental rehashing already in progress. Return. */
    if (dictIsRehashing(d)) return DICT_OK;

    /* If the hash table is empty expand it to the initial size. */
    if (d->ht[0].size == 0) return dictExpand(d, DICT_HT_INITIAL_SIZE);

    /* If we reached the 1:1 ratio, and we are allowed to resize the hash
     * table (global setting) or we should avoid it but the ratio between
     * elements/buckets is over the "safe" threshold, we resize doubling
     * the number of buckets. */
    // 当使用的数据大于哈希表大小就可以扩展了。当`dict_can_resize` 不允许扩展时，数据的使用与哈希表的大小对比，超出一个比率强制扩展内存。
    if (d->ht[0].used >= d->ht[0].size &&
        (dict_can_resize ||
         d->ht[0].used/d->ht[0].size > dict_force_resize_ratio)) {
        // 使用数据大小的两倍增长
        return dictExpand(d, d->ht[0].used*2);
    }
    return DICT_OK;
}
```

### 扩容容量大小

```c
/* Our hash table capability is a power of two */
static unsigned long _dictNextPower(unsigned long size) {
    unsigned long i = DICT_HT_INITIAL_SIZE;

    // 新容量大小是 2 的 n 次方，并且这个数值是第一个大于 2 * 原长度 的值。
    if (size >= LONG_MAX) return LONG_MAX;
    while(1) {
        if (i >= size)
            return i;
        i *= 2;
    }
}
```

### 扩容

```c
/* Expand or create the hash table */
int dictExpand(dict *d, unsigned long size) {
    dictht n; /* the new hash table */
    unsigned long realsize = _dictNextPower(size);

    /* the size is invalid if it is smaller than the number of
     * elements already inside the hash table */
    if (dictIsRehashing(d) || d->ht[0].used > size)
        return DICT_ERR;

    /* Rehashing to the same table size is not useful. */
    if (realsize == d->ht[0].size) return DICT_ERR;

    /* Allocate the new hash table and initialize all pointers to NULL */
    n.size = realsize;
    n.sizemask = realsize-1;
    n.table = zcalloc(realsize*sizeof(dictEntry*));
    n.used = 0;

    /* Is this the first initialization? If so it's not really a rehashing
     * we just set the first hash table so that it can accept keys. */
    // 如果哈希表还是空的，给表1分配空间，否则空间分配给表2
    if (d->ht[0].table == NULL) {
        d->ht[0] = n;
        return DICT_OK;
    }

    /* Prepare a second hash table for incremental rehashing */
    d->ht[1] = n;
    d->rehashidx = 0;
    return DICT_OK;
}
```

### 缩容

* 缩容，部分删除操作，会触发重新分配内存进行存储。

```c
#define HASHTABLE_MIN_FILL        10      /* Minimal hash table fill 10% */

int zsetDel(robj *zobj, sds ele) {
    ...
    if (htNeedsResize(zs->dict)) dictResize(zs->dict);
    ...
}

int htNeedsResize(dict *dict) {
    long long size, used;

    size = dictSlots(dict);
    used = dictSize(dict);
    return (size > DICT_HT_INITIAL_SIZE &&
            (used*100/size < HASHTABLE_MIN_FILL));
}

/* Resize the table to the minimal size that contains all the elements,
 * but with the invariant of a USED/BUCKETS ratio near to <= 1 */
int dictResize(dict *d) {
    int minimal;

    if (!dict_can_resize || dictIsRehashing(d)) return DICT_ERR;
    minimal = d->ht[0].used;
    if (minimal < DICT_HT_INITIAL_SIZE)
        minimal = DICT_HT_INITIAL_SIZE;
    return dictExpand(d, minimal);
}
```

---

## 参考

* [Redis源码剖析和注释（三）--- Redis 字典结构](https://blog.csdn.net/men_wen/article/details/69787532)
* 《redis 设计与实现》
* [Redis源码学习简记（三）dict哈希原理与个人理解](https://blog.csdn.net/qq_30085733/article/details/79843175)
* [Redis源码剖析和注释](https://blog.csdn.net/men_wen/article/details/69787532)

---

* 更精彩内容，请关注作者博客：[wenfh2020.com](https://wenfh2020.com/)

---

## 问题

1. iterator 作用是啥。
2. [scan 的用法](麥路人/articles/1410.html)。

> * [让人爱恨交加的Redis Scan遍历操作原理](麥路人/articles/1410.html)
> * [Redis Scan迭代器遍历操作原理（二）–dictScan反向二进制迭代器](http://chenzhenianqing.com/articles/1101.html)
