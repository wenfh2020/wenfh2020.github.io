---
layout: post
title:  "[libco] 协程调度"
categories: libco
tags: libco dispatch
author: wenfh2020
---

一般情况下，主协程与其它子协程通过 `co_resume` 和 `co_yield` 交替调度工作。






* content
{:toc}

---

## 1. 协程调度

<div align=center><img src="/images/2020-12-28-15-23-42.png" data-action="zoom"/></div>

### 1.1. 协程数组

pCallStack 协程数组，保存当前正在执行协程（<font color=red>注意</font>：并不是所有协程）。

pCallStack[0] 是主协程，`env->pCallStack[env->iCallStackSize - 1]` 是当前协程。
  
一般情况下数组大小为 2，子协程在主协程里创建。除非在子协程里嵌套创建唤醒新的协程，这个协程数组大小才会一直被累加 `env->iCallStackSize++`，直到嵌套深度达到 `128` 才会出现堆栈溢出，这种应用场景嵌应该不常见。

```c++
struct stCoRoutineEnv_t {
    stCoRoutine_t *pCallStack[128]; /* 协程数组。 */
    int iCallStackSize;             /* 协程数组元素个数。 */
    ...
};
```

---

### 1.2. 启动协程 co_resume

```c
void co_resume(stCoRoutine_t *co) {
    stCoRoutineEnv_t *env = co->env;
    stCoRoutine_t *lpCurrRoutine = env->pCallStack[env->iCallStackSize - 1];
    ...
    env->pCallStack[env->iCallStackSize++] = co;
    co_swap(lpCurrRoutine, co);
}
```

---

### 1.3. 挂起协程 co_yield

```c++
void co_yield_env(stCoRoutineEnv_t *env) {
    stCoRoutine_t *last = env->pCallStack[env->iCallStackSize - 2];
    stCoRoutine_t *curr = env->pCallStack[env->iCallStackSize - 1];
    env->iCallStackSize--;
    co_swap(curr, last);
}
```

---

### 1.4. 协程执行函数

```c
static int CoRoutineFunc(stCoRoutine_t *co,void *) {
    if (co->pfn) {
        /* pfn 协程执行函数。 */
        co->pfn(co->arg);
    }
    co->cEnd = 1;
    stCoRoutineEnv_t *env = co->env;
    co_yield_env(env);
    return 0;
}
```

---

## 2. 参考

* [万字长文\|漫谈libco协程设计及实现](https://zhuanlan.zhihu.com/p/73679393)
