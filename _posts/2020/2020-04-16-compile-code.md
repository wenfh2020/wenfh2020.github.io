---
layout: post
title:  "gcc/make/Makefile 源码编译"
categories: c/c++
tags: make Makefile gcc compile
author: wenfh2020
---

本章主要说 c 语言。

源码工作流程：程序员编写代码 -> 编译 -> 产生二进制执行文件 -> 文件加载到系统运行。

编译这个环节，其实是一个高级语言翻译成低级语言过程：高级语言 -> 汇编 -> 机器语言。



* content
{:toc}

---

## 1. 概述

* 随着时代变迁，人类根据不同应用场景，创造了很多应用级别的高级语言，例如 c 语言，然而这些都是高级语言，机器不懂啊，机器就是一堆硬件，它只懂（0 1）二进制机器码。用二进制机器码编写代码对人类非常不友好，那怎么办，后面工程师创造了汇编语言，比二进制机器码高级一点，它封装了二进制命令。后来在这个基础上，人们又创造出很多对人类友好的高级语言，只要将这些高级语言翻译成汇编就好了。

* 高级语言转汇编过程中，需要编译器进行“翻译”。例如 `gcc` 编译器套件，它是一个程序集合。编译器对高级语言通过：预编译 -> 编译 -> 汇编 -> 链接，产生可以被系统加载运行的二进制文件。

<div align=center><img src="/images/2021/2021-05-06-11-18-19.png" data-action="zoom"/></div>

* 编译器可以对源码进行翻译，一个复杂的项目，往往不是一个简单的文件就能实现的，它通过很多文件实现不同功能，组合起来完成一个项目。这其实是模块化，不同的小功能模块，当你需要哪个小功能模块时就添加进来构成一个整体。但是编译器没那么智能，它不懂文件之间的依赖关系是怎么样的。所以 `make` 自动化构建命令工具应运而生，研发人员通过编写 `Makefile` 文件，将源码文件之间的依赖关系通过一定规则建立起来。make 工具读取 Makefile 文件规则，调用编译器套件（gcc）编译链接这些文件，最终这些小模块组织起来编译成预期的可执行文件。

---

## 2. gcc

GCC（GNU Compiler Collection，GNU编译器套件）是由GNU开发的编程语言译器。GNU编译器套件包括C、C++、 Objective-C、Fortran、Java 和 Go 语言等，也包括了这些语言的库（如libstdc++，libgcj等）。

<style> table th:first-of-type { width: 70px; } </style>

* 常用参数。

|  参数   | 描述                                                                                                                         |
| :-----: | ---------------------------------------------------------------------------------------------------------------------------- |
|   -E    | 只运行 C 预编译器。                                                                                                          |
|   -S    | 告诉编译器产生汇编语言文件（.s 文件）后停止编译。                                                                            |
|   -c    | 只编译，不链接成为可执行文件，编译器只是由输入的.c等源代码文件生成.o为后缀的目标文件，通常用于编译不包含主程序的子程序文件。 |
|   -o    | -o \<file_name> 确定输出文件 file_name。                                                                                     |
|   -g    | 在目标文件中嵌入调试信息，方便调试工具对源码进行调试。                                                                       |
|   -O    | -On (n=0,1,2,3) 设置编译器优化等级，O0为不优化，O3为最高等级优化，O1为默认优化等级。                                         |
|  -Wall  | 使 gcc 对源文件的代码有问题的地方发出警告。                                                                                  |
|   -D    | 宏编译。                                                                                                                     |
|   -I    | -I\<dir> 将 dir 目录加入搜索头文件的目录路径。                                                                               |
|   -L    | -L\<dir> 将 dir 目录加入搜索库的目录路径。                                                                                   |
|   -l    | -l\<lib> 链接库。                                                                                                            |
| -static | 禁止使用动态库，所以编译出来的目标文件很大。                                                                                 |
| -share  | 尽量使用动态库，生成的文件很小，但是需要系统已经安装有动态库。                                                               |
|   -w    | 不显示任何警告。                                                                                                             |
|   -W    | 显示默认的警告。                                                                                                             |
|  -Wall  | 显示所有的警告。                                                                                                             |

* 测试源码。

```c
// hello.c
#include <stdio.h>

int main(int argc, char** argv) {
    printf("hello world\n");
    return 0;
}
```

* gcc 编译运行结果。

```shell
# gcc -O0 -g hello.c -o hello && ./hello
hello world
```

---

## 3. make/Makefile

### 3.1. make 工作流程

1. 读入所有的 Makefile。
2. 读入被 include 的其它 Makefile。
3. 初始化文件中的变量。
4. 推导隐晦规则，并分析所有规则。
5. 为所有的目标文件创建依赖关系链。
6. 根据依赖关系，决定哪些目标要重新生成。
7. 执行生成命令。

> 参考：《跟我一起学 Makefile》-- 五、make 的工作方式

---

### 3.2. Makefile 规则

```shell
target ... : prerequisites ...
(tab)command
```

* 关键字。

|    关键字     | 描述                                                                 |
| :-----------: | :------------------------------------------------------------------- |
|    target     | 目标文件，可以是 Object File (*.o) ，也可以是执行文件。              |
| prerequisites | 要生成 target 所需要依赖的文件或是目标，也可以不写，代表不需要依赖。 |
|    command    | make 需要执行的（shell）命令。                                       |

---

* 语法。

|    语法    | 描述                                                                                                                                                                                                                                                                                                                                                                                                |
| :--------: | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|    all     | 这个伪目标是所有目标的目标，其功能一般是编译所有的目标。                                                                                                                                                                                                                                                                                                                                            |
|  wildcard  | \$ (wildcard $(dir)/*.cpp) 为了找出目录和指定目录下所有后缀为 cpp 的文件。                                                                                                                                                                                                                                                                                                                          |
|  foreach   | 循环。\$(foreach \<var>, \<list>, \<text>)，把参数 \<list> 中的单词逐一取出放到参数\<var>所指定的变量中， 然后再执行\<text>所包含的表达式。每一次\<text>会返回一个字符串，循环过程中，\<text> 的所返回的每个字符串会以空格分隔，最后当整个循环结束时，\<text>所返回的每个字符串 所组成的整个字符串(以空格分隔)将会是 foreach 函数的返回值。CPP_SRCS = $ (foreach dir, ., $ (wildcard $(dir)/*.cpp)) |
|   vpath    | 告诉 make 搜索制定的源码目录。                                                                                                                                                                                                                                                                                                                                                                      |
|  patsubst  | 替代字符串<br/> SRCS = \$(wildcard ./*.c) <br/> OBJS = \$(patsubst %.c, %.o, $(SRCS))  <br/> 将 *c 文件替换成 *.o 文件。                                                                                                                                                                                                                                                                            |
|   .PHONY   | ".PHONY" 用来显式地指明一个目标是“伪目标”，向 make 说明，不管是否有这个文件，这个目标就是“伪目标”。“伪目标”并不是一个文件，只是一个标签，由于“伪目标”不是文件，所以 make 无法生成它的依赖关系和决定它是否要执行。我们只有通过显式地指明这个“目标”才能让其生效。当然，“伪目标”的取名不能和文件名重名，不然其就失去了“伪目标”的意义了。<br/>.PHONY: clean <br/>clean: <br/>rm *.o temp                |
| .SECONDARY | 阻止 make 自动删除中间目标。                                                                                                                                                                                                                                                                                                                                                                        |
|     %      | 我们的“目标模式”或是“依赖模式”中都应该有“%”这个字符<br/>$(objects): %.o: %.c                                                                                                                                                                                                                                                                                                                        |
|     $      | 可以定义变量<br/>TARGETS = main<br/>$(TARGETS)                                                                                                                                                                                                                                                                                                                                                      |
|    \$<     | 依赖目标中的第一个目标名字。                                                                                                                                                                                                                                                                                                                                                                        |
|    \$^     | 所有依赖目标集合，以空格分隔。                                                                                                                                                                                                                                                                                                                                                                      |
|    \$@     | 表示目标集(也就是“foo.o bar.o”)<br/>$(CC) -c \$(CFLAGS) \$< -o \$@                                                                                                                                                                                                                                                                                                                                  |

### 3.3. Makefile 实例

* 编译前。

```shell
# ls
Makefile     ae.h         ae_kqueue.c  anet.h       networking.c server.c
ae.c         ae_epoll.c   anet.c       config.h     server.h
```

* Makefile 文件内容。

```make
CC = gcc
CFLAGS = -g -O0

SRCS = $(wildcard ./*.c)
OBJS = $(patsubst %.c, %.o, $(SRCS))
SERVER_NAME = my-redis-server

.PHONY: clean

$(SERVER_NAME): $(OBJS)
	$(CC) $(CFLAGS) $^ -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS)
	rm -f $(SERVER_NAME)
```

* 编译。

```shell
# make clean; make
rm -f  ./ae.o  ./ae_epoll.o  ./ae_kqueue.o  ./anet.o  ./networking.o  ./server.o
rm -f my-redis-server
gcc -g -O0 -c ae.c -o ae.o
gcc -g -O0 -c ae_epoll.c -o ae_epoll.o
gcc -g -O0 -c ae_kqueue.c -o ae_kqueue.o
gcc -g -O0 -c anet.c -o anet.o
gcc -g -O0 -c networking.c -o networking.o
gcc -g -O0 -c server.c -o server.o
gcc -g -O0 ae.o ae_epoll.o ae_kqueue.o anet.o networking.o server.o -o my-redis-server
```

* 编译结果。

```shell
# ls
Makefile        ae_epoll.c      anet.c          my-redis-server server.c
ae.c            ae_epoll.o      anet.h          networking.c    server.h
ae.h            ae_kqueue.c     anet.o          networking.o    server.o
ae.o            ae_kqueue.o     config.h
```

---

## 4. 编译子文件夹

参考 [test_libco](https://github.com/wenfh2020/test_libco) Makefile 配置。

### 4.1. 目录

```shell
# tree -L 2
.
├── Makefile
├── Makefile.test
├── libco
│   ├── CMakeLists.txt
│   ├── LICENSE.txt
│   ├── Makefile
│ ...
└── ...
```

---

### 4.2. Makefile 文件内容

```make
LIBCO_DIR = libco
TEST_DIR = $(shell pwd)

.PHONY : build

build:
	cd $(LIBCO_DIR) && make -f Makefile
	cd $(TEST_DIR) && make -f Makefile.test

clean:
	cd $(LIBCO_DIR) && make clean -f Makefile
	cd $(TEST_DIR) && make clean -f Makefile.test
```

---

## 5. 参考

* 《跟我一起学 Makefile》
* [Make 命令教程](http://www.ruanyifeng.com/blog/2015/02/make.html)
* [进程内存分布（Linux）](https://wenfh2020.com/2020/02/17/mem-distribution/)
* [编译器 cc、gcc、g++、CC 的区别](https://www.cnblogs.com/52php/p/5681725.html)
* [wiki Makefile](https://en.wikipedia.org/wiki/Makefile)
* [gcc （GNU编译器套件）](https://baike.baidu.com/item/gcc/17570?fr=aladdin)
* [GCC 参数详解](https://www.runoob.com/w3cnote/gcc-parameter-detail.html)
* [Make (software)](https://en.wikipedia.org/wiki/Make_(software))
* [gcc-Link-Options](https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html)
