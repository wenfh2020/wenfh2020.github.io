---
layout: post
title:  "[libco] 协程切换理解思路"
categories: libco
tags: libco swap coroutines
author: wenfh2020
---

协程切换，可以理解为函数运行时上下文的切换。





* content
{:toc}

---

## 1. 协程切换

正常情况下，函数代码从头到尾串行执行，直到函数生命期结束。而协程切换却能将当前运行的函数，切换到另外一个函数运行，这是协程的神奇之处。

<div align=center><img src="/images/2020-12-23-12-01-52.png" data-action="zoom"/></div>

---

## 2. 画重点

* 理解协程切换原理，首先需要理解函数的运行原理。（[《x86-64 下函数调用及栈帧原理》](https://zhuanlan.zhihu.com/p/27339191)）
* 协程是啥？它本质上就是一个函数体，与普通函数相比，它只是特殊一点而已。
* 协程函数上下文：寄存器数据 + 内存数据。
* 协程切换（yield/resume）本质是函数运行时上下文切换。
* 系统默认为函数运行时分配堆栈内存，而 libco 为协程函数分配堆空间（独立栈/共享栈）使其工作。
* libco 切换核心源码在 `co_routine.cpp/co_swap()/coctx_swap()`，`coctx_swap` 通过汇编实现。
* 汇编源码的理解，关键对 `call/ret` 这两个汇编指令理解：call 调用函数，ret 返回函数运行地址；当执行这两个指令时寄存器和程序是如何在内存上压栈出栈的。
* 用 lldb / gdb 走一下 `coctx_swap` 这段汇编源码逻辑，观察寄存器与内存数据的变化。

---

## 3. 协程上下文

协程上下文：寄存器数据 + 内存数据。

---

### 3.1. 协程拓扑结构

```c
struct stCoRoutine_t {
    ...
    coctx_t ctx; /* 协程上下文。 */
    ...
    stStackMem_t *stack_mem; /* 函数在这个内存块上工作。 */
    ...
};
```

<div align=center><img src="/images/2020-12-23-10-00-40.png" data-action="zoom"/></div>


---

### 3.2. 内存分配

* 协程函数运行的内存空间。

```c
struct stStackMem_t {
    stCoRoutine_t *occupy_co; /* 使用该内存块的协程。 */
    int stack_size;           /* 栈大小。 */
    char *stack_bp;           /* 栈底指针。 */
    char *stack_buffer;       /* 栈顶指针。 */
};
```

* 协程上下文。

```c
struct coctx_t {
    void *regs[14]; /* 寄存器数组。 */
    size_t ss_size; /* 内存大小。 */
    char *ss_sp;    /* 内存块起始地址。 */
};
```

* 协程函数运行时内存空间。

<div align=center><img src="/images/2020-12-23-15-53-33.png" data-action="zoom"/></div>

* 协程运行时内存布局。

<div align=center><img src="/images/2020-12-23-10-07-13.png" data-action="zoom"/></div>

---

## 4. 协程切换汇编实现功能

`co_routine.cpp/co_swap()/coctx_swap()` 汇编工作流程。

```shell
    ; 将当前协程寄存器数据保存到 curr->ctx->regs
    leaq (%rsp),%rax
    movq %rax, 104(%rdi) ; rsp --> regs[13]
    movq %rbx, 96(%rdi)  ; rbx --> regs[12]
    movq %rcx, 88(%rdi)  ; rcx --> regs[11]
    movq %rdx, 80(%rdi)  ; rdx --> regs[10]
    movq 0(%rax), %rax   ; rax 寄存器指向函数返回地址。 
    movq %rax, 72(%rdi)  ; rax --> regs[9] 
    movq %rsi, 64(%rdi)  ; rsi --> regs[8]
    movq %rdi, 56(%rdi)  ; rdi --> regs[7]
    movq %rbp, 48(%rdi)  ; rbp --> regs[6]
    movq %r8, 40(%rdi)   ; r8  --> regs[5]
    movq %r9, 32(%rdi)   ; r9  --> regs[4]
    movq %r12, 24(%rdi)  ; r12 --> regs[3]
    movq %r13, 16(%rdi)  ; r13 --> regs[2]
    movq %r14, 8(%rdi)   ; r14 --> regs[1]
    movq %r15, (%rdi)    ; r15 --> regs[0]
    xorq %rax, %rax      ; rax = 0x0000000000000000

    ; 将 pending_co->ctx->regs 数据，写入对应寄存器。
    movq 48(%rsi), %rbp  ; regs[6]  --> rbp
    movq 104(%rsi), %rsp ; regs[13] --> rsp
    movq (%rsi), %r15    ; regs[0]  --> r15
    movq 8(%rsi), %r14   ; regs[1]  --> r14
    movq 16(%rsi), %r13  ; regs[2]  --> r13
    movq 24(%rsi), %r12  ; regs[3]  --> r12
    movq 32(%rsi), %r9   ; regs[4]  --> r9
    movq 40(%rsi), %r8   ; regs[5]  --> r8
    movq 56(%rsi), %rdi  ; regs[7]  --> rdi
    movq 80(%rsi), %rdx  ; regs[10] --> rdx
    movq 88(%rsi), %rcx  ; regs[11] --> rcx
    movq 96(%rsi), %rbx  ; regs[12] --> rbx
    leaq 8(%rsp), %rsp   ; rsp 上移 8 个字节。
    pushq 72(%rsi)       ; 将 regs[9] 返回地址压栈。
    movq 64(%rsi), %rsi  ; regs[8]  --> rsi
    ret
```

<div align=center><img src="/images/2020-12-23-11-44-39.png" data-action="zoom"/></div>

---

## 5. lldb 调试

调试测试程序（[github](https://github.com/wenfh2020/test_libco)），观察协程切换寄存器数据和内存数据的变化。

```shell
[root:.../other/coroutine/test_libco]# lldb test_libco -- 1 1                                          (main✱) 
Current executable set to 'test_libco' (x86_64).
(lldb) b co_routine.cpp : 664
Breakpoint 1: where = test_libco`co_swap(stCoRoutine_t*, stCoRoutine_t*) + 182 at co_routine.cpp:664, address = 0x0000000000402eb4
(lldb) r
Process 30842 launched: '/home/other/coroutine/test_libco/test_libco' (x86_64)
Process 30842 stopped
* thread #1: tid = 30842, 0x0000000000402eb4 test_libco`co_swap(curr=0x00000000020de590, pending_co=0x00000000020e0730) + 182 at co_routine.cpp:664, name = 'test_libco', stop reason = breakpoint 1.1
    frame #0: 0x0000000000402eb4 test_libco`co_swap(curr=0x00000000020de590, pending_co=0x00000000020e0730) + 182 at co_routine.cpp:664
   661          }
   662 
   663          //swap context
-> 664          coctx_swap(&(curr->ctx),&(pending_co->ctx) );
   665 
   666          //stack buffer may be overwrite, so get again;
   667          stCoRoutineEnv_t* curr_env = co_get_curr_thread_env();
di -l 
test_libco`co_swap(stCoRoutine_t*, stCoRoutine_t*) + 182 at co_routine.cpp:664
   663          //swap context
-> 664          coctx_swap(&(curr->ctx),&(pending_co->ctx) );
   665 
-> 0x402eb4:  movq   -0x40(%rbp), %rax
   0x402eb8:  leaq   0x18(%rax), %rdx
   0x402ebc:  movq   -0x38(%rbp), %rax
   0x402ec0:  addq   $0x18, %rax
   0x402ec4:  movq   %rdx, %rsi
   0x402ec7:  movq   %rax, %rdi
   0x402eca:  callq  0x407fca                  ; coctx_swap
...
# 设置调试打印数据，每执行一步，打印当前汇编编码和寄存器数据。
(lldb) target stop-hook add
Enter your stop hook command(s).  Type 'DONE' to end.
> di -p
> re r rbp rsp rax rsi rdi
> DONE
Stop hook #1 added.
(lldb) si
...
test_libco`co_swap(stCoRoutine_t*, stCoRoutine_t*) + 204 at co_routine.cpp:664:
-> 0x402eca:  callq  0x407fca                  ; coctx_swap
   0x402ecf:  callq  0x403133                  ; co_get_curr_thread_env() at co_routine.cpp:762
   0x402ed4:  movq   %rax, -0x18(%rbp)
   0x402ed8:  movq   -0x18(%rbp), %rax
     rbp = 0x00007ffdcfc18050
     rsp = 0x00007ffdcfc18010
     rax = 0x00000000020de5a8
     rsi = 0x00000000020e0748
     rdi = 0x00000000020de5a8
...
(lldb) si
Process 30842 stopped
* thread #1: tid = 30842, 0x0000000000407fca test_libco`coctx_swap, name = 'test_libco', stop reason = instruction step into
    frame #0: 0x0000000000407fca test_libco`coctx_swap
# 进入 coctx_swap 函数。
test_libco`coctx_swap:
-> 0x407fca:  leaq   (%rsp), %rax
   0x407fce:  movq   %rax, 0x68(%rdi)
   0x407fd2:  movq   %rbx, 0x60(%rdi)
   0x407fd6:  movq   %rcx, 0x58(%rdi)
test_libco`coctx_swap:
-> 0x407fca:  leaq   (%rsp), %rax
   0x407fce:  movq   %rax, 0x68(%rdi)
   0x407fd2:  movq   %rbx, 0x60(%rdi)
   0x407fd6:  movq   %rcx, 0x58(%rdi)
     rbp = 0x00007ffdcfc18050
     rsp = 0x00007ffdcfc18008
     rax = 0x00000000020de5a8
     rsi = 0x00000000020e0748
     rdi = 0x00000000020de5a8
# 查看 rsp 内存内容。
(lldb) me read -fx -s8 -c1 0x00007ffdcfc18008
0x7ffdcfc18008: 0x0000000000402ecf

# 查看该地址的汇编内容，刚好是紧接 coctx_swap 函数下面的代码。
(lldb) di -s 0x0000000000402ecf
test_libco`co_swap(stCoRoutine_t*, stCoRoutine_t*) + 209 at co_routine.cpp:667:
   0x402ecf:  callq  0x403133                  ; co_get_curr_thread_env() at co_routine.cpp:762
   0x402ed4:  movq   %rax, -0x18(%rbp)
   0x402ed8:  movq   -0x18(%rbp), %rax
   0x402edc:  movq   0x418(%rax), %rax
   0x402ee3:  movq   %rax, -0x20(%rbp)
   0x402ee7:  movq   -0x18(%rbp), %rax
(lldb) bt
* thread #1: tid = 30842, 0x0000000000407fca test_libco`coctx_swap, name = 'test_libco', stop reason = instruction step into
  * frame #0: 0x0000000000407fca test_libco`coctx_swap
    frame #1: 0x0000000000402ecf test_libco`co_swap(curr=0x00000000020de590, pending_co=0x00000000020e0730) + 209 at co_routine.cpp:664
    frame #2: 0x0000000000402bf5 test_libco`co_resume(co=0x00000000020e0730) + 165 at co_routine.cpp:568
    frame #3: 0x00000000004022de test_libco`main(argc=3, argv=0x00007ffdcfc181e8) + 458 at test_libco.cpp:145
    frame #4: 0x00007fc67f4ee505 libc.so.6`__libc_start_main + 245
(lldb) f 1
frame #1: 0x0000000000402ecf test_libco`co_swap(curr=0x00000000020de590, pending_co=0x00000000020e0730) + 209 at co_routine.cpp:664
   661          }
   662 
   663          //swap context
-> 664          coctx_swap(&(curr->ctx),&(pending_co->ctx) );
   665 
   666          //stack buffer may be overwrite, so get again;
   # 0x0000000000402ecf 代码。
   667          stCoRoutineEnv_t* curr_env = co_get_curr_thread_env();
(lldb) 
```

---

## 6. 后记

* 写了一通，感觉没有把协程切换原理描述清楚，这里只整理了我自己看源码时的思路，很多细节没有补充进来，也可能有些地方没理解正确。
* 虽然写了多年代码，但是汇编知识早已还给了老师，操作系统知识也是模糊的，都是边看边查，边写日志。
* 通过 Libco 的源码学习，感觉终于比较深入理解协程是啥玩意了。
* 协程的工作流程，感觉这东西实在太抽象了，不是三言两语能描述清楚，只看源码和资料也是不够的，还是动手画图，写测试例子，上调试器观察寄存器和内存数据吧。

---

## 7. 参考

* [《x86_64 函数运行时栈帧内存布局》](https://wenfh2020.com/2020/12/17/stack/)
* [《x86-64 下函数调用及栈帧原理》](https://zhuanlan.zhihu.com/p/27339191)
* [最近都流行实现 Coroutine 么？](https://zhuanlan.zhihu.com/p/32431200)
* [libco协程库上下文切换原理详解](https://zhuanlan.zhihu.com/p/27409164)
* [微信开源C++协程库Libco—原理与应用](https://blog.didiyun.com/index.php/2018/11/23/libco/)
* [漫谈微信libco协程设计及实现（万字长文）](https://runzhiwang.github.io/2019/06/21/libco/)