---
layout: post
title:  "[redis 源码走读] 整数集合(inset)"
categories: redis
tags: redis c
author: wenfh2020
---

整数集合，是一个有序的数值数组对象，存储的数值不允许重复。源码在 `intset.c`



* content
{:toc}

---

## 数据结构

```c
/* Note that these encodings are ordered, so:
 * INTSET_ENC_INT16 < INTSET_ENC_INT32 < INTSET_ENC_INT64. */
#define INTSET_ENC_INT16 (sizeof(int16_t))
#define INTSET_ENC_INT32 (sizeof(int32_t))
#define INTSET_ENC_INT64 (sizeof(int64_t))

typedef struct intset {
    uint32_t encoding; // 编码。
    uint32_t length;   // 数组长度。
    int8_t contents[]; // 整数值数值。
} intset;
```

根据插入数值大小，决定 `contents` 数组的`encoding`格式。编码格式分别有 `int16_t`，`int32_t`，`int64_t`。以最大的数值为准，如果最大的数值是 `int64_t` 那么数组的每个 `item` 都是 `int64_t`，优点是统一简单，提高数组查找效率——源码实现是通过二分法查找。如果数组不同数值用不同的编码存储，就很难用二分法查找了。
但是这样做一方面提高了查找效率，另一方面也会导致内存浪费，如果所有数据中，只有一个数据是 `int64_t`，其它数据都是 `int16_t`，整个数组 `item` 都以 `int64_t` 存储，显然会造成内存浪费。
当然 redis 的数据结构是丰富的，连续内存上的数据管理有：字符串对象（sds），压缩列表（ziplist），这里有整数集合（intset），都分别针对不同的应用场景进行应用。

---

## 接口

### 数值编码

```c
#define INT8_MAX         127
#define INT16_MAX        32767
#define INT32_MAX        2147483647
#define INT64_MAX        9223372036854775807LL

#define INT8_MIN          -128
#define INT16_MIN         -32768

/* Return the required encoding for the provided value. */
static uint8_t _intsetValueEncoding(int64_t v) {
    if (v < INT32_MIN || v > INT32_MAX)
        return INTSET_ENC_INT64;
    else if (v < INT16_MIN || v > INT16_MAX)
        return INTSET_ENC_INT32;
    else
        return INTSET_ENC_INT16;
}

```

### 插入数据

检查插入数据是否大于当前编码格式，决定是否需要升级

```c
/* Insert an integer in the intset */
intset *intsetAdd(intset *is, int64_t value, uint8_t *success) {
    uint8_t valenc = _intsetValueEncoding(value);
    uint32_t pos;
    if (success) *success = 1;

    /* Upgrade encoding if necessary. If we need to upgrade, we know that
     * this value should be either appended (if > 0) or prepended (if < 0),
     * because it lies outside the range of existing values. */
    // 如果插入数值大于当前编码，那么需要升级数组
    if (valenc > intrev32ifbe(is->encoding)) {
        /* This always succeeds, so we don't need to curry *success. */
        return intsetUpgradeAndAdd(is,value);
    } else {
        /* Abort if the value is already present in the set.
         * This call will populate "pos" with the right position to insert
         * the value when it cannot be found. */
        // 如果数值已经存在，就不需要插入数据了。*success = 0;
        if (intsetSearch(is,value,&pos)) {
            if (success) *success = 0;
            return is;
        }

        // 数据增长，重新申请内存。
        is = intsetResize(is,intrev32ifbe(is->length)+1);
        if (pos < intrev32ifbe(is->length)) intsetMoveTail(is,pos,pos+1);
    }

    _intsetSet(is,pos,value);
    is->length = intrev32ifbe(intrev32ifbe(is->length)+1);
    return is;
}
```

### 升级

```c
/* Upgrades the intset to a larger encoding and inserts the given integer. */
static intset *intsetUpgradeAndAdd(intset *is, int64_t value) {
    uint8_t curenc = intrev32ifbe(is->encoding);
    uint8_t newenc = _intsetValueEncoding(value);
    int length = intrev32ifbe(is->length);

    // 因为插入新的数据，而且数据超出了当前数组所有数值的范围才会升级。
    // 超出了负数，或者超出了正数。正数在数组末添加，负数在数组前面添加。
    int prepend = value < 0 ? 1 : 0;

    /* First set new encoding and resize */
    is->encoding = intrev32ifbe(newenc);
    is = intsetResize(is,intrev32ifbe(is->length)+1);

    /* Upgrade back-to-front so we don't overwrite values.
     * Note that the "prepend" variable is used to make sure we have an empty
     * space at either the beginning or the end of the intset. */
    // 扩充内存后，迁移数据。
    while(length--)
        _intsetSet(is,length+prepend,_intsetGetEncoded(is,length,curenc));

    /* Set the value at the beginning or the end. */
    if (prepend)
        _intsetSet(is,0,value);
    else
        _intsetSet(is,intrev32ifbe(is->length),value);
    is->length = intrev32ifbe(intrev32ifbe(is->length)+1);
    return is;
}
```

![升级](https://raw.githubusercontent.com/wenfh2020/imgs_for_blog/master/md20200215164106.png)

### 搜索

二分法搜索数组数据。

```c
/* Search for the position of "value". Return 1 when the value was found and
 * sets "pos" to the position of the value within the intset. Return 0 when
 * the value is not present in the intset and sets "pos" to the position
 * where "value" can be inserted. */
static uint8_t intsetSearch(intset *is, int64_t value, uint32_t *pos) {
    int min = 0, max = intrev32ifbe(is->length)-1, mid = -1;
    int64_t cur = -1;

    /* The value can never be found when the set is empty */
    if (intrev32ifbe(is->length) == 0) {
        if (pos) *pos = 0;
        return 0;
    } else {
        // 检查数值是否大于或小于数组里的所有数值。
        /* Check for the case where we know we cannot find the value,
         * but do know the insert position. */
        if (value > _intsetGet(is,max)) {
            if (pos) *pos = intrev32ifbe(is->length);
            return 0;
        } else if (value < _intsetGet(is,0)) {
            if (pos) *pos = 0;
            return 0;
        }
    }

    // 数值如果在存储的数据中间，用二分法查找。
    while(max >= min) {
        mid = ((unsigned int)min + (unsigned int)max) >> 1;
        cur = _intsetGet(is,mid);
        if (value > cur) {
            min = mid+1;
        } else if (value < cur) {
            max = mid-1;
        } else {
            break;
        }
    }

    if (value == cur) {
        if (pos) *pos = mid;
        return 1;
    } else {
        if (pos) *pos = min;
        return 0;
    }
}
```
