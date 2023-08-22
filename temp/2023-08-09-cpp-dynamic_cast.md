---
layout: post
title:  "[c++] dynamic_cast"
categories: c/c++
tags: stl sort
author: wenfh2020
---




* content
{:toc}

---

## 1. type_info

```cpp
class type_info {
    ...
   protected:
    const char* __name;
};

typedef long int ptrdiff_t;

template <typename T>
inline const T *
adjust_pointer(const void *base, ptrdiff_t offset) {
    return reinterpret_cast<const T *>(reinterpret_cast<const char *>(base) + offset);
}

// Initial part of a vtable, this structure is used with offsetof, so we don't
// have to keep alignments consistent manually.
struct vtable_prefix {
    // Offset to most derived object.
    ptrdiff_t whole_object;

    // Additional padding if necessary.
#ifdef _GLIBCXX_VTABLE_PADDING
    ptrdiff_t padding1;
#endif

    // Pointer to most derived type_info.
    const __class_type_info *whole_type;

    // Additional padding if necessary.
#ifdef _GLIBCXX_VTABLE_PADDING
    ptrdiff_t padding2;
#endif

    // What a class's vptr points to.
    const void *origin;
};
```

---

## 2. __class_type_info

```cpp
// Type information for a class.
class __class_type_info : public std::type_info {
   public:
    explicit __class_type_info(const char* __n) : type_info(__n) {}

    virtual ~__class_type_info();

    // Implementation defined types.
    // The type sub_kind tells us about how a base object is contained
    // within a derived object. We often do this lazily, hence the
    // UNKNOWN value. At other times we may use NOT_CONTAINED to mean
    // not publicly contained.
    enum __sub_kind {
        // We have no idea.
        __unknown = 0,

        // Not contained within us (in some circumstances this might
        // mean not contained publicly)
        __not_contained,

        // Contained ambiguously.
        __contained_ambig,

        // Via a virtual path.
        __contained_virtual_mask = __base_class_type_info::__virtual_mask,

        // Via a public path.
        __contained_public_mask = __base_class_type_info::__public_mask,

        // Contained within us.
        __contained_mask = 1 << __base_class_type_info::__hwm_bit,

        __contained_private = __contained_mask,
        __contained_public = __contained_mask | __contained_public_mask
    };

    struct __upcast_result;
    struct __dyncast_result;

   protected:
    // Implementation defined member functions.
    virtual bool
    __do_upcast(const __class_type_info* __dst_type, void** __obj_ptr) const;

    virtual bool
    __do_catch(const type_info* __thr_type, void** __thr_obj,
               unsigned __outer) const;

   public:
    // Helper for upcast. See if DST is us, or one of our bases.
    // Return false if not found, true if found.
    virtual bool
    __do_upcast(const __class_type_info* __dst, const void* __obj,
                __upcast_result& __restrict __result) const;

    // Indicate whether SRC_PTR of type SRC_TYPE is contained publicly
    // within OBJ_PTR. OBJ_PTR points to a base object of our type,
    // which is the destination type. SRC2DST indicates how SRC
    // objects might be contained within this type.  If SRC_PTR is one
    // of our SRC_TYPE bases, indicate the virtuality. Returns
    // not_contained for non containment or private containment.
    inline __sub_kind
    __find_public_src(ptrdiff_t __src2dst, const void* __obj_ptr,
                      const __class_type_info* __src_type,
                      const void* __src_ptr) const;

    // Helper for dynamic cast. ACCESS_PATH gives the access from the
    // most derived object to this base. DST_TYPE indicates the
    // desired type we want. OBJ_PTR points to a base of our type
    // within the complete object. SRC_TYPE indicates the static type
    // started from and SRC_PTR points to that base within the most
    // derived object. Fill in RESULT with what we find. Return true
    // if we have located an ambiguous match.
    virtual bool
    __do_dyncast(ptrdiff_t __src2dst, __sub_kind __access_path,
                 const __class_type_info* __dst_type, const void* __obj_ptr,
                 const __class_type_info* __src_type, const void* __src_ptr,
                 __dyncast_result& __result) const;

    // Helper for find_public_subobj. SRC2DST indicates how SRC_TYPE
    // bases are inherited by the type started from -- which is not
    // necessarily the current type. The current type will be a base
    // of the destination type.  OBJ_PTR points to the current base.
    virtual __sub_kind
    __do_find_public_src(ptrdiff_t __src2dst, const void* __obj_ptr,
                         const __class_type_info* __src_type,
                         const void* __src_ptr) const;
};
```

---

## 3. dynamic_cast

```cpp
namespace __cxxabiv1 {

// this is the external interface to the dynamic cast machinery
/* sub: source address to be adjusted; nonnull, and since the
 *      source object is polymorphic, *(void**)sub is a virtual pointer.
 * src: static type of the source object.
 * dst: destination type (the "T" in "dynamic_cast<T>(v)").
 * src2dst_offset: a static hint about the location of the
 *    source subobject with respect to the complete object;
 *    special negative values are:
 *       -1: no hint
 *       -2: src is not a public base of dst
 *       -3: src is a multiple public base type but never a
 *           virtual base type
 *    otherwise, the src type is a unique public nonvirtual
 *    base type of dst at offset src2dst_offset from the
 *    origin of dst.  */
extern "C" void *
__dynamic_cast(const void *src_ptr,                // object started from
               const __class_type_info *src_type,  // type of the starting object
               const __class_type_info *dst_type,  // desired target type
               ptrdiff_t src2dst)                  // how src and dst are related
{
    const void *vtable = *static_cast<const void *const *>(src_ptr);
    const vtable_prefix *prefix =
        adjust_pointer<vtable_prefix>(vtable,
                                      -offsetof(vtable_prefix, origin));
    const void *whole_ptr =
        adjust_pointer<void>(src_ptr, prefix->whole_object);
    const __class_type_info *whole_type = prefix->whole_type;
    __class_type_info::__dyncast_result result;

    // If the whole object vptr doesn't refer to the whole object type, we're
    // in the middle of constructing a primary base, and src is a separate
    // base.  This has undefined behavior and we can't find anything outside
    // of the base we're actually constructing, so fail now rather than
    // segfault later trying to use a vbase offset that doesn't exist.
    const void *whole_vtable = *static_cast<const void *const *>(whole_ptr);
    const vtable_prefix *whole_prefix =
        adjust_pointer<vtable_prefix>(whole_vtable,
                                      -offsetof(vtable_prefix, origin));
    if (whole_prefix->whole_type != whole_type)
        return NULL;

    whole_type->__do_dyncast(src2dst, __class_type_info::__contained_public,
                             dst_type, whole_ptr, src_type, src_ptr, result);
    if (!result.dst_ptr)
        return NULL;
    if (contained_public_p(result.dst2src))
        // Src is known to be a public base of dst.
        return const_cast<void *>(result.dst_ptr);
    if (contained_public_p(__class_type_info::__sub_kind(result.whole2src & result.whole2dst)))
        // Both src and dst are known to be public bases of whole. Found a valid
        // cross cast.
        return const_cast<void *>(result.dst_ptr);
    if (contained_nonvirtual_p(result.whole2src))
        // Src is known to be a non-public nonvirtual base of whole, and not a
        // base of dst. Found an invalid cross cast, which cannot also be a down
        // cast
        return NULL;
    if (result.dst2src == __class_type_info::__unknown)
        result.dst2src = dst_type->__find_public_src(src2dst, result.dst_ptr,
                                                     src_type, src_ptr);
    if (contained_public_p(result.dst2src))
        // Found a valid down cast
        return const_cast<void *>(result.dst_ptr);
    // Must be an invalid down cast, or the cross cast wasn't bettered
    return NULL;
}

}  // namespace __cxxabiv1
```

---

```cpp
/* g++ -O0 -std=c++11 test.cpp -o test && ./test */
#include <iostream>
#include <vector>

class Base {
   public:
    virtual void vBaseFunc() {}
    virtual void vBaseFunc2() {}
};

class Drived : public Base {
   public:
    virtual void vBaseFunc2() {}
    virtual void vDrivedFunc() {}
};

int main() {
    Base *b = new Drived;
    auto d = dynamic_cast<Drived *>(b);
    if (d) {
        d->vBaseFunc2();
    }
    return 0;
}
```

---

```shell
00000000004007bd <main>:
  4007ef:    b9 00 00 00 00           mov    $0x0,%ecx
  4007f4:    ba 10 0a 40 00           mov    $0x400a10,%edx
  4007f9:    be 30 0a 40 00           mov    $0x400a30,%esi
  4007fe:    48 89 c7                 mov    %rax,%rdi
  400801:    e8 aa fe ff ff           callq  4006b0 <__dynamic_cast@plt>
```

## 4. 引用

* [C++ 对象的内存布局(上)](https://haoel.blog.csdn.net/article/details/3081328)
* [C++ 对象的内存布局（下）](https://blog.csdn.net/haoel/article/details/3081385)
