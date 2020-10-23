---
layout: post
title:  "程序变量内存分布（Linux）"
categories: Linux
tags: system Linux memory distribution
author: wenfh2020
---

系统通过虚拟内存方式管理进程内存，我们测试一下程序中的变量分别分布在虚拟内存哪些区域。



* content
{:toc}

## 1. 进程虚拟内存

系统通过虚拟内存方式管理进程内存。

![进程地址空间](/images/2020-02-20-14-22-08.png){: data-action="zoom"}

> 图片来源 《深入理解计算机系统》8.2.3 私有地址空间

---

## 2. 内存分布

程序源码通过编译，产生可执行的 elf 文件。源码对应的变量，有的在执行前已经在虚拟内存中分配好内存空间，有的需要在程序运行起来才会分配。

* 数据分区

  | 区域            | 描述       | 变量类型               |
  | :-------------- | :--------- | :--------------------- |
  | `stack`         | 栈区       | 临时变量               |
  | `heap`          | 堆区       | malloc  分配空间的变量 |
  | `.data`，`.bss` | 全局数据区 | 全局变量/静态变量      |
  | `.rodata`       | 文字常量区 | 只读数据，常量等       |
  | `.text`         | 程序代码区 | 程序代码               |

---

* 内存分布特点：
  
  1. 内存从低地址到高地址分配情况：`.text`，`.rodata`，`.data`，`.bss`，`heap`，`stack`。
  2. 全局数据初始化的放在 `.data` 区，没有初始化的放在 `.bss`。
  3. 栈空间从高地址向低地址分配。
  4. 堆空间从低地址到高地址分配。

---

## 3. 测试

### 3.1. 系统

CentOS Linux release 7.4.1708 (Core)  

---

### 3.2. 源码

* 测试源码 ([github](https://github.com/wenfh2020/c_test/tree/master/normal/address.cpp))

```c
// 测试静态变量
void test_static();
// 测试全局变量
void test_global();
// 测试堆栈
void test_stack();
// 测试堆
void test_heap();
// 测试函数源码
void test_code();
// 从低地址到高地址打印地址对应的变量
void print_sort_ret();

...

int main() {
    test_code();
    test_static();
    test_global();
    test_stack();
    test_heap();
    print_sort_ret();
    return 0;
}
```

* 源码运行结果

```shell
# g++ -g address.cpp -o address
# file address
address: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked (uses shared libs)

# ./address
           stack_int_not_init : 0x7ffc7e778a8c
                  stack_int_0 : 0x7ffc7e778a88
                  stack_int_1 : 0x7ffc7e778a84
                  stack_int_2 : 0x7ffc7e778a80
                  stack_int_3 : 0x7ffc7e778a7c
                        heap3 :      0x222a670
                        heap2 :      0x222a260
                        heap1 :      0x2229e50
           static_stack_int_0 :       0x6061c0
    static_stack_int_not_init :       0x6061bc
          global_static_int_0 :       0x6061b8
   global_static_int_not_init :       0x6061b4
                 global_int_0 :       0x606164
          global_int_not_init :       0x606160
           static_stack_int_4 :       0x606134
           static_stack_int_3 :       0x606130
           static_stack_int_2 :       0x60612c
           static_stack_int_1 :       0x606128
          global_static_int_2 :       0x606110
          global_static_int_1 :       0x60610c
                 global_int_3 :       0x606108
                 global_int_2 :       0x606104
                 global_int_1 :       0x606100
        global_const_string_2 :       0x403cb8
        global_const_string_1 :       0x403cb0
                         main :       0x402d0b
               print_sort_ret :       0x402c5f
                   test_stack :       0x40279b
                    test_heap :       0x4024a0
                  test_static :       0x401b89
                  test_global :       0x40143d
                    test_code :       0x400ded
      global_pointer_not_init :          (nil)
```

* 测试源码变量内存分布情况（上面是高地址，下面是低地址）：

| 虚拟内存分布 | 变量                       |
| :----------- | :------------------------- |
| stack        | stack_int_not_init         |
| stack        | stack_int_init_0           |
| stack        | stack_int_1                |
| stack        | stack_int_2                |
| stack        | stack_int_3                |
| heap         | heap3                      |
| heap         | heap2                      |
| heap         | heap1                      |
| .bss         | global_static_int_0        |
| .bss         | global_static_int_not_init |
| .bss         | static_stack_int_0         |
| .bss         | static_stack_int_not_init  |
| .bss         | global_int_init_0          |
| .bss         | global_int_not_init        |
| .data        | global_pointer_not_init    |
| .data        | global_static_int_2        |
| .data        | global_static_int_1        |
| .data        | static_stack_int_4         |
| .data        | static_stack_int_3         |
| .data        | static_stack_int_2         |
| .data        | static_stack_int_1         |
| .data        | global_int_3               |
| .data        | global_int_2               |
| .data        | global_int_1               |
| .rodata      | global_const_string_2      |
| .rodata      | global_const_string_1      |
| .text        | print_sort_ret             |
| .text        | test_heap                  |
| .text        | test_stack                 |
| .text        | test_global                |
| .text        | test_static                |
| .text        | main                       |
| .text        | test_code                  |
{:.table-striped}

---

## 4. elf 格式头

`.text`， `.data`，`bss`，`.rodata` 数据区是程序运行前，编译器分配好的，并不是程序载入内存后进行分配的，可以通过 `objdump` 工具查询。

ELF 可重定位目标文件的格式头：

| 头      | 描述                       |
| :------ | :------------------------- |
| .bss    | 未初始化段全局和静态变量。 |
| .rodata | 只读数据，常量等。         |
| .data   | 已初始化段全局和静态变量。 |
| .text   | 已编译程序段机器代码。     |

> 《深入理解计算机系统》7.4 可重定位目标文件

---

## 5. objdump 工具

* 通过 objdump 工具查询程序部分变量在 elf 文件中分配在虚拟内存哪个区。
  
```shell
# objdump -j .rodata -S address
```

```shell
address:     file format elf64-x86-64


Disassembly of section .rodata:

0000000000403ca0 <_IO_stdin_used>:
  403ca0:       01 00 02 00 00 00 00 00                             ........

0000000000403ca8 <__dso_handle>:
        ...
  403cb0:       68 65 6c 6c 6f 5f 31 00 68 65 6c 6c 6f 5f 32 00     hello_1.hello_2.
  403cc0:       63 6f 64 65 20 6c 6f 63 61 74 69 6f 6e 3a 0a 2d     code location:.-
  403cd0:       2d 2d 2d 0a 6d 61 69 6e 20 20 20 20 20 20 20 20     ---.main
  403ce0:       3a 20 25 70 0a 74 65 73 74 5f 73 74 61 74 69 63     : %p.test_static
  403cf0:       20 3a 20 25 70 0a 74 65 73 74 5f 67 6c 6f 62 61      : %p.test_globa
  403d00:       6c 20 3a 20 25 70 0a 74 65 73 74 5f 73 74 61 63     l : %p.test_stac
  403d10:       6b 20 20 3a 20 25 70 0a 74 65 73 74 5f 68 65 61     k  : %p.test_hea
  403d20:       70 20 20 20 3a 20 25 70 0a 74 65 73 74 5f 63 6f     p   : %p.test_co
  403d30:       64 65 20 20 20 3a 20 25 70 0a 70 72 69 6e 74 5f     de   : %p.print_
  403d40:       73 6f 72 74 5f 72 65 74 20 20 20 3a 20 25 70 0a     sort_ret   : %p.
```

可见常量字符串 "hello" 和 printf(...) 里面的字符串都是保存在 `.rodata` 这个区。

---

```shell
# objdump -x address | grep '\.bss'
```

```shell
0000000000606140 l     d .bss   0000000000000000              .bss
0000000000606140 l     O .bss   0000000000000001              completed.6354
00000000006061b0 l     O .bss   0000000000000001              _ZStL8__ioinit
00000000006061b4 l     O .bss   0000000000000004              _ZL26global_static_int_not_init
00000000006061b8 l     O .bss   0000000000000004              _ZL19global_static_int_0
00000000006061c0 l     O .bss   0000000000000004              _ZZ11test_staticvE18static_stack_int_0
00000000006061bc l     O .bss   0000000000000004              _ZZ11test_staticvE25static_stack_int_not_init
0000000000606168 g     O .bss   0000000000000008              global_pointer_not_init
0000000000606130 g       .bss   0000000000000000              __bss_start
0000000000606160 g     O .bss   0000000000000004              global_int_not_init
00000000006061c8 g       .bss   0000000000000000              _end
0000000000606180 g     O .bss   0000000000000030              g_map
0000000000606164 g     O .bss   0000000000000004              global_int_0
```

* 工具使用参数

```shell
# objdump --help

Usage: objdump <option(s)> <file(s)>
 Display information from object <file(s)>.
 At least one of the following switches must be given:
  -a, --archive-headers    Display archive header information
  -f, --file-headers       Display the contents of the overall file header
  -p, --private-headers    Display object format specific file header contents
  -P, --private=OPT,OPT... Display object format specific contents
  -h, --[section-]headers  Display the contents of the section headers
  -x, --all-headers        Display the contents of all headers
  -d, --disassemble        Display assembler contents of executable sections
  -D, --disassemble-all    Display assembler contents of all sections
  -S, --source             Intermix source code with disassembly
  -s, --full-contents      Display the full contents of all sections requested
  -g, --debugging          Display debug information in object file
  -e, --debugging-tags     Display debug information using ctags style
  -G, --stabs              Display (in raw form) any STABS info in the file
  -W[lLiaprmfFsoRt] or
  --dwarf[=rawline,=decodedline,=info,=abbrev,=pubnames,=aranges,=macro,=frames,
          =frames-interp,=str,=loc,=Ranges,=pubtypes,
          =gdb_index,=trace_info,=trace_abbrev,=trace_aranges,
          =addr,=cu_index]
                           Display DWARF info in the file
  -t, --syms               Display the contents of the symbol table(s)
  -T, --dynamic-syms       Display the contents of the dynamic symbol table
  -r, --reloc              Display the relocation entries in the file
  -R, --dynamic-reloc      Display the dynamic relocation entries in the file
  @<file>                  Read options from <file>
  -v, --version            Display this program's version number
  -i, --info               List object formats and architectures supported
  -H, --help               Display this information

The following switches are optional:
  -b, --target=BFDNAME           Specify the target object format as BFDNAME
  -m, --architecture=MACHINE     Specify the target architecture as MACHINE
  -j, --section=NAME             Only display information for section NAME
  -M, --disassembler-options=OPT Pass text OPT on to the disassembler
  ...
```

---

## 6. 参考

* [进程内存分配](https://www.cnblogs.com/coolYuan/p/9228739.html)
* 《深入理解计算机系统》
* 《UNIX 环境高级编程》
* 《程序员的自我修养》
* [C语言中的static 详细分析](https://blog.csdn.net/keyeagle/article/details/6708077)

---

> 🔥 文章来源：[《程序变量内存分布（Linux）》](https://wenfh2020.com/2020/02/17/mem-distribution/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
