---
layout: post
title:  "C++ 日志宏定义"
categories: c/c++
tags: log format
author: wenfh2020
---

项目中，无论客户端还是服务端，日志都是必不可少的，一般的日志格式具备下面几个要素：

时间，日志等级，源码文件，源码行数，日志字符串格式化内容。



* content
{:toc}

---

## 1. 日志事例

* 事例代码：

```shell
LOG_ERR("check file failed, task id = %d, error = %d", iTaskID, iErrCode);
```

* 内容：

```shell
[2017-10-28 19:40:01][ERROR][uploadclient.cpp][380] check file failed, task id = 6, error = 23
```

---

## 2. 日志宏定义

字符串格式化数据如何作为参数传递，研究了不少时间~ 为啥要将日志函数定义为宏呢，主要是因为 __FILE__ 和 __LINE__ 这两个参数，只有通过宏，才能正确记录哪个文件，哪一行的日志。

---

### 2.1. windows

* 宏

```c++
#define LOG_TRACE(x, ...)     LogTrace(__FILE__, __LINE__, x, ##__VA_ARGS__);
#define LOG_DEBUG(x, ...)     LogDebug(__FILE__, __LINE__, x, ##__VA_ARGS__);
#define LOG_INFO(x, ...)      LogInfo(__FILE__, __LINE__, x, ##__VA_ARGS__);
#define LOG_IMPORTANT(x, ...) LogImportant(__FILE__, __LINE__, x, ##__VA_ARGS__);
#define LOG_ERR(x, ...)       LogError(__FILE__, __LINE__, x, ##__VA_ARGS__);  
```

* 函数

```c++
void LogData(LPCTSTR pFile, int iLine, int iType, LPCTSTR lpInfo);
void LogTrace(LPCTSTR pFile, int iLine, LPCTSTR lpszFormat, ...);
void LogDebug(LPCTSTR pFile, int iLine, LPCTSTR lpszFormat, ...);
void LogInfo(LPCTSTR pFile, int iLine, LPCTSTR lpszFormat, ...);
void LogImportant(LPCTSTR pFile, int iLine, LPCTSTR lpszFormat, ...);
void LogError(LPCTSTR pFile, int iLine, LPCTSTR lpszFormat, ...);
```

---

### 2.2. linux

* log4cplus

```c++
#define LOG4_FATAL(args...) LOG4CPLUS_FATAL_FMT(GetLogger(), ##args)
#define LOG4_ERROR(args...) LOG4CPLUS_ERROR_FMT(GetLogger(), ##args)
#define LOG4_WARN(args...)  LOG4CPLUS_WARN_FMT(GetLogger(), ##args)
#define LOG4_INFO(args...)  LOG4CPLUS_INFO_FMT(GetLogger(), ##args)
#define LOG4_DEBUG(args...) LOG4CPLUS_DEBUG_FMT(GetLogger(), ##args)
#define LOG4_TRACE(args...) LOG4CPLUS_TRACE_FMT(GetLogger(), ##args)
```

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
