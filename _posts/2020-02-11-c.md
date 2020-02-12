# C语言 

---
## 基础知识

---
### 变量字节数
| 有符号  | 无符号         | 32位字节数 | 64位字节数 |
| :------ | :------------- | :--------- | :--------- |
| char    | unsigned char  | 1          | 1          |
| short   | unsigned short | 2          | 2          |
| int     | unsigned int   | 4          | 4          |
| long    | unsigned long  | 4          | 8          |
| int32_t | uint32_t       | 4          | 4          |
| int64_t | uint64_t       | 8          | 8          |
| char*   |                | 4          | 8          |
| float   |                | 4          | 4          |
| double  |                | 8          | 8          |

---
### [位运算](https://www.runoob.com/cprogramming/c-operators.html)
  | 符号 | 描述                                                            | 应用                                                         |
  | :--- | :-------------------------------------------------------------- | :----------------------------------------------------------- |
  | &    | 与运算（两个 1 是 1，否则为 0），可以截取一个尾数的后面几位数字 | idx = h & d->ht[table].sizemask; <br/> flags &= ~O_NONBLOCK; |
  | \|   | 或运算（有一个为 1，为 1）                                      | flags \| = O_NONBLOCK;                                       |
  | ^    | 异域运算（相同的两个位是 0，不同 1）                            |                                                              |
  | ~    | 取反运算                                                        | flags &= ~O_NONBLOCK;                                        |
  | <<   | 左移运算（左移一位相当于 * 2）                                  | #define ZIP_INT_32B (0xc0 \| 1<<4)                           |
  | >>   | 右移运算（右移一位相当于 除以 2）                               | ret = i32>>8;                                                |

```c
// 可以灵活运用位运算，将多项属性存储在一个变量里。
// 二进制，每一位 1 表示一个选项。 ｜ 操作表示添加一项。 & ～ 结合使用去掉一项。
bool set_module_key(const string& value) {
    if (value.size() > 90) {
        m_ull_has_bit &= ~0x00000020;
        m_ui_error = 0;
        return false;
    }
    m_str_module_key = value;
    m_ull_has_bit |= 0x00000020;
    return true;
}
```

---
### 大小端
**小端**
特征：数据的低字节保存在内存低地址，高字节保存在内存高地址。
注意：数据类型 char 和 unsigned char 类型是没有大小端之分的。

---
网络通信中，终端与服务器的通信需要保证大小端一致才能正常工作。终端和服务端约定一种方式，进行通信即可。

例如约定小端模式。那么终端在数据传输前，要将数据类型进行检测处理。
```c
int little = 1;
if (*(char*)(&little) == 0) {
    printf("big endian\n");
} else {
    printf("little endian\n");
}
```

---
测试[源码](https://github.com/wenfh2020/c_test/blob/master/network/endian.cpp)
```c
#include <stdio.h>

unsigned char is_little_endian() {
    static int little = 1;
    return (*(char*)(&little) == 1);
}

void swap(void* data, int n) {
    if (is_little_endian()) return;

    int i;
    unsigned char *p, temp;

    p = (unsigned char*)data;
    for (i = 0; i < n / 2; i++) {
        temp = p[i];
        p[i] = p[n - 1 - i];
        p[n - 1 - i] = temp;
    }
}

int main(int argc, char** argv) {
    int a = 0x12345678;
    swap(&a, sizeof(a));
    printf("a: %x\n", a);
    return 0;
}
```

---
### [printf](http://www.cplusplus.com/reference/cstdio/printf/?kw=printf)

| 选项 | 描述                               |
| :--- | :--------------------------------- |
| p    | 打印指针 printf("ptr: %p\n", ptr); |


---
### static
static 全局变量和全局变量，static 局部变量和局部变量，static 函数和普通函数区别：
1. 全局静态变量 ：
   1. 在全局数据区内分配内存。
   2. 如果没有初始化，其默认值为0。
   3. 该变量在本文件内从定义开始到文件结束可见。
2. 局部静态变量：
   1. 该变量在全局数据区分配内存。
   2. 如果不显示初始化，那么将被隐式初始化为0。
   3. 它始终驻留在全局数据区，直到程序运行结束。
   4. 其作用域为局部作用域，当定义它的函数或语句块结束时，其作用域随之结束。
3. 静态函数：
   1. 静态函数只能在本源文件中使用。
   2. 在文件作用域中声明的inline函数默认为static。
      > 说明：静态函数只是一个普通的全局函数，只不过受static限制，他只能在文件所在的编译单位内使用，不能在其他编译单位内使用。

---
### union 共同体
https://www.runoob.com/cprogramming/c-unions.html
一个数据结构有多个成员数据，但是只能保存一个成员数据。共同体结构的大小，是最大的成员的大小。

```c
union Data {
    int i;
    float f;
    char str[20];
} data;
```

---
### 字节对齐
参考引用文章，理解对齐的规律。
![理解](https://raw.githubusercontent.com/wenfh2020/imgs_for_blog/master/md20200210222217.png)
[字节对齐你真明白了么](https://baijiahao.baidu.com/s?id=1626141749557181338&wfr=spider&for=pc)
[谈谈内存对齐](http://www.openedv.com/thread-277386-1-1.html)
[C语言字节对齐问题详解](https://www.cnblogs.com/clover-toeic/p/3853132.html)
[谈谈内存对齐一](http://www.openedv.com/thread-277386-1-1.html)

---
nginx 对齐操作
```c
typedef unsigned char u_char;
 
#define NGX_POOL_ALIGNMENT 16
#define ngx_align_ptr(p, a)                                                   \
    (u_char *) (((uintptr_t) (p) + ((uintptr_t) a - 1)) & ~((uintptr_t) a - 1))
 
int main(int argc, char *argv[]) {
    ...
    char *p = (char *)malloc(1024);
    u_char *p10 = ngx_align_ptr(p, 4);
    u_char *p11 = ngx_align_ptr(p+1, 4);
    ...
}
```

---
### 内存种类，堆，栈，全局数据区...

---
### 宏
- 宏的作用和展开
1. C 语言一般用 #define 宏作为常变量；C++里用 const 修饰常变量。
2. 宏定义只是做字符替换，不分配内存空间。
3. 预编译，编译，汇编器，链接；预编译的时候编译器将宏对应的值替换到代码中去。
4. 宏一般只是替换对应的值，对定义不做正确性检查，有一定危险性。

- C 语言编程中以空间换时间(**宏**)
计算机程序中最大的矛盾是空间和时间的矛盾，那么，从这个角度出发逆向思维来考虑程序的效率问题，我们就有可以利用C语言编程中以空间换时间，使用的时候可以直接用指针来操作。同时我们也可以使用宏函数而不是函数。

- ‘#’ 和 ‘##’ 作用
使用 # 把宏参数变为一个字符串，用 ## 把两个宏参数贴合在一起

```c++
#include <iostream>
#include <string>

#define STR(s) #s
#define CONV(a, b) (a##e##b)

int main() {
    std::cout << STR(12345) << std::endl;
    std::cout << CONV(2, 3) << std::endl;
    return 0;
}
```
结果：
```shell
12345
2000
```

- 宏函数
函数和宏函数的区别就在于，宏函数占用了大量的空间，而函数占用了时间。大家要知道的是，**函数调用是要使用系统的栈来保存数据的**，如果编译器里有栈检查选项，一般在函数的头会嵌入一些汇编语句对当前栈进行检查；同时，CPU也要在函数调用时保存和恢复当前的现场，进行压栈和弹栈操作，所以，函数调用需要一些CPU时间。而宏函数不存在这个问题。宏函数仅仅作为预先写好的代码嵌入到当前程序，不会产生函数调用，所以仅仅是占用了空间，在频繁调用同一个宏函数的时候，该现象尤其突出。

下面从实例结果可以证明，如果深入研究，可以看看汇编执行流程。

```c
#include <stdlib.h>
#include <time.h>
#include <iostream>
using namespace std;

#define MAX(x, y) (x) < (y) ? (x) : (y)
int _max(int x, int y) { return x y ? (x) : (y); }

int main(int argc, char* argv[]) {
    string cmd(argv[1]);
    int count = atoi(argv[2]);
    clock_t begin_time = clock();
    srand((unsigned)time(NULL));
  
    for (int i = 0; i < count; i++) {
        int v1 = rand();
        int v2 = rand();
        (cmd == "0") ? _max(v1, v2) : MAX(v1, v2);
    }

    clock_t end_time = clock();
    double cost = (double)(end_time - begin_time) / CLOCKS_PER_SEC;
    printf("cmd: %s, cost time: %lf secs\n", cmd == "1" ? "marco" : "func",
           cost);
    return 0;
}
```
结果
```shell
$ g++ -g main.cpp -o main;./main  1 1000000000
cmd: marco, cost time: 31.766957 secs
$ g++ -g main.cpp -o main;./main  0 1000000000
cmd: func, cost time: 32.241336 secs
```
---
```c
#include <stdio.h>

#define max(x, y) (x) > (y) ? (x) : (y)
#define sum(x)    \
    do {          \
        (x) += 1; \
    } while ((x) < 10)

int main(int argc, char** argv) {
    int a, b;

#ifdef TEST
    a = 1;
    b = 2;
#else
    a = 2;
    b = 3;
#endif
    sum(b);
    printf("max: %d, %d\n", max(a, b), b);
    return 0;
}
```

可以预编译看看编译出来的东西，原来的宏已经将字符串替换了。

```shell
gcc -E test.cpp -o test.i 
```

```c
int main(int argc, char** argv) {
    int a, b;





    a = 2;
    b = 3;

    do { (b) += 1; } while ((b) < 10);
    printf("max: %d, %d\n", (a) > (b) ? (a) : (b), b);
    return 0;
}

```

---
但是 max(++a, b) 这样的操作会隐藏了错误。例如下面这个例子：
举例：
```c
#define max(x, y) (x) > (y) ? (x) : (y)
void func(int a) { printf("%d\n", a); }
func(max(a, ++b));
```
==>
```c
func((a) > (++b) ? (a) : (++b));
```

---
### volatile
volatile关键字是一种限定符用来声明一个对象在程序中可以被语句外的东西修改，比如操作系统、硬件或并发执行线程。遇到该关键字，编译器不再对该变量的代码进行优化，不再从寄存器中读取变量的值，而是直接从它所在的内存中读取值，即使它前面的指令刚刚从该处读取过数据。而且读取的数据立刻被保存。好，说完了。一句话总结一下，volatile到底有什么用。它的作用就是叫编译器不要偷懒，去内存中去取值。

1. 易变性。 在汇编层面观察，两条语句，下一条语句不会直接使用上一条语句对应的volatile变量的寄存器内容，而是直接从内存中读取。
2. 不可优化性。volatile告诉编译器，不要对我这个变量进行各种激进的优化，甚至将变量直接消除，保证程序员写在代码中的指令，一定会被执行。相对于前面提到的第一个特性：”易变”性，”不可优化”特性可能知晓的人会相对少一些。
3. 顺序性。C/C++ Volatile关键词前面提到的两个特性，让Volatile经常被解读为一个为多线程而生的关键词：一个全局变量，会被多线程同时访问/修改，那么线程内部，就不能假设此变量的不变性，并且基于此假设，来做一些程序设计。当然，这样的假设，本身并没有什么问题，多线程编程，并发访问/修改的全局变量，通常都会建议加上Volatile关键词修饰，来防止C/C++编译器进行不必要的优化。变量赋值的时序性在多线程中是很重要的，一般全局变量设置成 Volatile 防止编译器的优化，解决方案，全局共享的数据，在多线程环境下的逻辑需要加锁。

---
[volatile 关键字](https://blog.csdn.net/wenqiang1208/article/details/71117818)
[volatile关键字与竞态条件和sigchild信号](https://blog.51cto.com/10541559/1771025)
[Volatile关键词深度剖析](https://www.cnblogs.com/god-of-death/p/7852394.html)

可以用 gdb 查看发汇编或者 
```shell
layout split
```

或者输出汇编代码查看
```shell
gcc -S test.cpp -o test.s 
```

```c
#include <stdio.h>

volatile int bbbb = 789;
volatile int aaaa = 123;

int main(int argc, char** argv) {
    aaaa += 456;
    bbbb = aaaa;
    return 0;
}
```

---
```shell
gdb server -tui
layout regs
set disassemble-next-line on
```
[GDB 单步调试汇编](https://juejin.im/entry/5b3111e151882574d1345496)
[lldb 命令](https://www.dllhook.com/post/51.html)


---
## gcc
GCC（GNU Compiler Collection，GNU编译器套件）是由GNU开发的编程语言译器。GNU编译器套件包括C、C++、 Objective-C、 Fortran、Java、Ada和Go语言前端，也包括了这些语言的库（如libstdc++，libgcj等）。[解析](https://baike.baidu.com/item/gcc/17570?fr=aladdin)， [菜鸟](https://www.runoob.com/w3cnote/gcc-parameter-detail.html)

| 选项    | 描述                                                                               |
| ------- | ---------------------------------------------------------------------------------- |
| -o      | 生成目标（ `.i` 、 `.s` 、 `.o` 、可执行文件等）                                   |
| -c      | 通知 gcc 取消链接步骤，即编译源码并在最后生成目标文件。                            |
| -E      | 只运行 C 预编译器                                                                  |
| -S      | 告诉编译器产生汇编语言文件后停止编译，产生的汇编语言文件扩展名为 `.s`              |
| -Wall   | 使 gcc 对源文件的代码有问题的地方发出警告                                          |
| -I      | -I\<dir> 将 dir 目录加入搜索头文件的目录路径                                       |
| -L      | -L\<dir> 将 dir 目录加入搜索库的目录路径                                           |
| -l      | -l\<lib> 链接库                                                                    |
| -g      | 在目标文件中嵌入调试信息，以便gdb之类的调试程序调试                                |
| -O      | -On (n=0,1,2,3) 设置编译器优化等级，O0为不优化，O3为最高等级优化，O1为默认优化等级 |
| -static | 禁止使用动态库，所以编译出来的目标文件很大                                         |
| -share  | 尽量使用动态库，生成的文件很小，但是需要系统已经安装有动态库。                     |
| -D      | 宏编译                                                                             |

---
## makefile
- make 工作流程
  1. 读入所有的Makefile
  2. 读入被include 的其他 Makefile
  3. 初始化文件中的变量。
  4. 推导隐晦规则，并分析所有规则。
  5. 为所有目标文件创建依赖关系链。
  6. 根据依赖关系，决定哪些目标要重新生成。
  7. 执行生成命令。

- makefile

  《跟我一起学 makefile》

  makefile带来的好 处就是——“自动化编译”，一旦写好，只需要一个 make 命令，整个工程完全自动编译，make 是一个命令工具，是一个解释 makefile 中指令的命令 工具。这里所默认的编译器是 UNIX 下的 GCC 和 CC。（elf 文件编译流程：预编译，编译，汇编，链接）make 命令执行时，需要一个 Makefile 文件，以告诉 make 命令需要怎么样的去编译和链接程序。

  **语法：**
  
   target ... : prerequisites ... 

   (tab)command
  
  > target 也就是一个目标文件，可以是 Object File，也可以是执行文件。还可以是一个 标签(Label)，对于标签这种特性，在后续的“伪目标”章节中会有叙述。prerequisites 就是，要生成那个 target 所需要的文件或是目标。command 也就是 make 需要执行的命令。(任意的 Shell 命令)
  
  ---
  
  **关键字:**
  
  | 关键字    | 描述                                                                                                                                                                                                                                                                                                                                                                                                                      |
  | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | -I        | 有“-I”或“--include-dir”参数，那么 make 就会在这个参数 所指定的目录下去寻找。<br/>LIB3RD_PATH = ../../l3oss<br/ƒ>INC := -I \$(LIB3RD_PATH)/src                                                                                                                                                                                                                                                                             |
  | -L        | 链接第三方库<br/>LDFLAGS := -L\$(LIB3RD_PATH)/lib -lhiredis -lev                                                                                                                                                                                                                                                                                                                                                          |
  | wildcard  | \$(wildcard $(dir)/*.cpp)为了找出目录和指定目录下所有后缀为cpp的文件                                                                                                                                                                                                                                                                                                                                                      |
  | foreach   | 循环。\$(foreach <var>,<list>,<text>)，把参数<list>中的单词逐一取出放到参数<var>所指定的变量中， 然后再执行<text>所包含的表达式。每一次<text>会返回一个字符串，循环过程中，<text> 的所返回的每个字符串会以空格分隔，最后当整个循环结束时，<text>所返回的每个字符串 所组成的整个字符串(以空格分隔)将会是 foreach 函数的返回值。CPP_SRCS = \$(foreach dir, ., \$(wildcard $(dir)/*.cpp))                                    |
  | vpath     | 告诉 make 搜索制定的源码目录。                                                                                                                                                                                                                                                                                                                                                                                            |
  | .PHONY    | “.PHONY”来显 示地指明一个目标是“伪目标”，向 make 说明，不管是否有这个文件，这个目标就是“伪 目标”。因为，我们并不生成“clean”这个文件。“伪目标”并不是一个文件，只是一个标签， 由于“伪目标”不是文件，所以 make 无法生成它的依赖关系和决定它是否要执行。我们只 有通过显示地指明这个“目标”才能让其生效。当然，“伪目标”的取名不能和文件名重名， 不然其就失去了“伪目标”的意义了。<br/>.PHONY: clean <br/>clean: <br/>rm *.o temp |
  | %         | 我们的“目标模式”或是“依赖模式”中都应该有“%”这个字符<br/>$(objects): %.o: %.c                                                                                                                                                                                                                                                                                                                                              |
  | \$<       | 自动化变量，表示所有的依赖目标集(也就是“foo.c bar.c”)<br/>$(CC) -c \$(CFLAGS) \$< -o \$@                                                                                                                                                                                                                                                                                                                                  |
  | \$@       | 表示目标集(也就是“foo.o bar.o”)<br/>$(CC) -c \$(CFLAGS) \$< -o \$@                                                                                                                                                                                                                                                                                                                                                        |
  | patsubst  | 代替字符串<br/> \$(patsubst <pattern>, <replacement>,<text>)<br/>CPP_SRCS = \$(foreach dir, ., \$(wildcard \$(dir)/*.cpp))<br/>OBJS = \$(patsubst %.cpp, %.o, \$(CPP_SRCS))                                                                                                                                                                                                                                               |
  | $         | 可以定义变量<br/>TARGETS = main<br/>$(TARGETS)                                                                                                                                                                                                                                                                                                                                                                            |
  | ifeq/else | ifeq (\$(CC),gcc) 条件比较。                                                                                                                                                                                                                                                                                                                                                                                              |
---
```shell
# redis-benchmark
# 编译项，依赖，输出，
$(REDIS_BENCHMARK_NAME): $(REDIS_BENCHMARK_OBJ)
	$(REDIS_LD) -o $@ $^ ../deps/hiredis/libhiredis.a $(FINAL_LIBS)

# redis-server
$(REDIS_SERVER_NAME): $(REDIS_SERVER_OBJ)
	$(REDIS_LD) -o $@ $^ ../deps/hiredis/libhiredis.a ../deps/lua/src/liblua.a $(FINAL_LIBS)
```
  
---
## 其它

---
### 数字转二进制
- 参考 [问题](https://stackoverflow.com/questions/190229/where-is-the-itoa-function-in-linux)
```c
#include <stdio.h>
#include <string.h>

#define BUF_LEN 64

char* i2bin(unsigned long long v, char* buf, int len) {
    if (0 == v) {
        memcpy(buf, "0", 2);
        return buf;
    }

    char* dst = buf + len - 1;
    *dst = '\0';

    while (v) {
        if (dst - buf <= 0) return NULL;
        *--dst = (v & 1) + '0';
        v = v >> 1;
    }
    memcpy(buf, dst, buf + len - dst);
    return buf;
}

int main() {
    char buf[BUF_LEN];
    unsigned long long v;
    scanf("%llu", &v);
    char* res = i2bin(v, buf, BUF_LEN);
    res ? printf("data: %s, len: %lu\n", i2bin(v, buf, BUF_LEN), strlen(buf))
        : printf("fail\n");
}
```

- 参考 redis 源码
```c
int sdsll2str(char *s, long long value) {
    char *p, aux;
    unsigned long long v;
    size_t l;

    /* Generate the string representation, this method produces
     * an reversed string. */
    v = (value < 0) ? -value : value;
    p = s;
    do {
        *p++ = '0' + (v % 10); // 2 
        v /= 10; // 2
    } while (v);
    if (value < 0) *p++ = '-';

    /* Compute length and add null term. */
    l = p - s;
    *p = '\0';

    /* Reverse the string. */
    p--;
    while (s < p) {
        aux = *s;
        *s = *p;
        *p = aux;
        s++;
        p--;
    }
    return l;
}
```

- 不用任何系统函数，写出 strcpy 的实现。

```c
int StrCpy(const char* pSrc, char* pDest) {
    if (NULL == pSrc || NULL == pDest) {
        return -1;
    }

    int i = 0;
    while (pSrc[i] != '\0') {
        pDest[i] = pSrc[i];
        i++;
    }
    pDest[i] = '\0';
    return i;
}

int main() {
    char szDest[100] = {0};
    char szSrc[] = "1234567890";
    int iLen = StrCpy(szSrc, szDest);
    std::cout << "src: " << szSrc << " dest: " << szDest << " len: " << iLen
            << std::endl;
    return 0;
}
```

结果：
```c
src: 1234567890 dest: 1234567890 len: 10
```

---
### glibc 如何管理内存
> slab 内存管理机制理解
> 《深入理解计算机系统》第九章 虚拟内存，9.9 动态内存分配
> nignx 内存池

glibc 是GNU发布的libc库，即c运行库。glibc是linux系统中最底层的api，几乎其它任何运行库都会依赖于glibc。glibc除了封装linux操作系统所提供的系统服务外，它本身也提供了许多其它一些必要功能服务的实现。由于 glibc 囊括了几乎所有的 UNIX 通行的标准。

glibc 通过预分配大块内存来解决内存申请效率，大块内存切成小块方式进行分配，小块内存回收后，空闲链表维护空闲内存块供后续的内存申请，空闲内存块或被合并空闲块。
问题：glibc 内存管理容易造成内存碎片，导致内存泄漏。