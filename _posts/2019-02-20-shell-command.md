---
layout: post
title:  "shell 常用语法"
categories: Linux
tags: shell command
author: wenfh2020
--- 

shell 常用语法，整理方便查阅。



* content
{:toc}

---

## 1. 语法

### 1.1. for

```shell
for p in $paths
do
done
```

---

### 1.2. if

```shell
# 判断目录是否存在
if [ ! -d "$dir" ]; then
else
fi

# 判断字符串是否相等
[ "a" != "b" ] && command
[ $1 == "kill" ] && command
```

---

### 1.3. 数组

```shell
array=(1, 2, 4, 8, 16, 32,64)

for x in ${array[*]}
do
    # do something.
done
```

---

### 1.4. 文件

| 参数 | 描述               |
| ---- | ------------------ |
| -d   | 文件夹是否存在     |
| -x   | 文件是否有执行权限 |
| -f   | 文件是否存在       |

---

### 1.5. 数值比较

| 参数 | 描述     |
| ---- | -------- |
| -eq  | 等于     |
| -ne  | 不等于   |
| -gt  | 大于     |
| -ge  | 大于等于 |
| -lt  | 小于     |
| -le  | 小于等于 |

---

### 1.6. 字符串

| 参数 | 描述              |
| ---- | ----------------- |
| =    | 等于              |
| !=   | 等于              |
| -z   | 字符串的长度为0   |
| -n   | 字符串的长度不为0 |

---

### 1.7. 特殊字符

| 参数 | 描述                                                          |
| :--- | :------------------------------------------------------------ |
| $#   | 传递到脚本的参数个数                                          |
| $*   | 显示所有向脚本传递的参数。                                    |
| $$   | 脚本运行的当前进程ID号                                        |
| $!   | 后台运行的最后一个进程的ID号                                  |
| $@   | 与$*相同，但是使用时加引号<br/>git commit -m "\$(echo "\$@")" |
| $-   | 显示Shell使用的当前选项，与set命令功能相同。                  |
| $?   | 显示最后命令的退出状态。0表示没有错误，其他任何值表明有错误。 |

---

### 1.8. 函数

```shell
function main()
{
    # do something.
}

main $@
```

---

```shell
function func_check_path()
{
    if [ ! -d "${ROOT_PATH}" ]; then
        echo "invalid root path."${ROOT_PATH}
        return 1
    elif [ ! -d "${TOOLS_PATH}" ]; then
        echo "invalid tools path."${TOOLS_PATH}
        return 2
    elif [ ! -d "${PROTO_PATH}" ]; then
        echo "invalid proto path."${PROTO_PATH}
        return 3
    fi

    return 0
}
```

---

```shell
function kill_process()
{
    for process_name in ${PN_ARRAY[@]}
    do
        #echo ${process_name}
        process=`ps -ef|grep ${process_name}|grep -v grep|grep -v vim|grep -v PPID|awk '{ print $2}'`
        for i in $process
        do
            #echo "Kill the process [ $i ]"
            kill $i
        done
    done
}
```

---

### 1.9. 注释

单行 '#'，多行：

```shell
#: '
echo ${WORK_PATH}
echo ${TOOLS_PATH}
echo ${PROTO_PATH}
#'
```

---

## 2. 读文件

```shell
while c1 c2 c3
do
    # do something.
done < ${file}
```

---

## 3. 算术

```shell
SUCCESS=0
let SUCCESS++
echo $SUCCESS
```

---

## 4. 时间

```shell
BUILD_BEGIN_TIME=`date +"%Y-%m-%d %H:%M:%S"`
local begin_time=${BUILD_BEGIN_TIME}
local end_time=`date +"%Y-%m-%d %H:%M:%S"`

begin_time_data=`date -d "$begin_time" +%s`
end_time_data=`date -d "$end_time" +%s`
interval=`expr $end_time_data - $begin_time_data`
```

```shell
end_time=`date +"%Y-%m-%d %H:%M:%S"`
printf "%-10s %-11s" "end:" $end_time
```

---

## 5. 参考

* [Shell 传递参数](https://www.runoob.com/linux/linux-shell-passing-arguments.html
)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)