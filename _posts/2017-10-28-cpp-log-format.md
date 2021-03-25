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

## 1. 日志示例

* 示例代码：

```shell
LOG_ERR("check file failed, task id = %d, error = %d", iTaskID, iErrCode);
```

* 内容：

```shell
[2017-10-28 19:40:01][ERROR][uploadclient.cpp][380] check file failed, task id = 6, error = 23
```

---

## 2. 日志宏定义

字符串格式化数据如何作为参数传递，研究了不少时间~ 为啥要将日志函数定义为宏呢，主要是因为 \__FILE__ 和 \__LINE__ 这两个参数，只有通过宏，才能正确记录哪个文件，哪一行的日志。

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

### 2.2. Linux

* log4cplus

```c++
#define LOG4_FATAL(args...) LOG4CPLUS_FATAL_FMT(GetLogger(), ##args)
#define LOG4_ERROR(args...) LOG4CPLUS_ERROR_FMT(GetLogger(), ##args)
#define LOG4_WARN(args...)  LOG4CPLUS_WARN_FMT(GetLogger(), ##args)
#define LOG4_INFO(args...)  LOG4CPLUS_INFO_FMT(GetLogger(), ##args)
#define LOG4_DEBUG(args...) LOG4CPLUS_DEBUG_FMT(GetLogger(), ##args)
#define LOG4_TRACE(args...) LOG4CPLUS_TRACE_FMT(GetLogger(), ##args)
```

* 自定义（[github 源码](https://github.com/wenfh2020/kimserver/blob/master/src/core/server.h)）

```c++
#define LOG_FORMAT(level, args...)                                           \
    if (m_logger != nullptr) {                                               \
        m_logger->log_data(__FILE__, __LINE__, __FUNCTION__, level, ##args); \
    }

#define LOG_EMERG(args...) LOG_FORMAT((Log::LL_EMERG), ##args)
#define LOG_ALERT(args...) LOG_FORMAT((Log::LL_ALERT), ##args)
#define LOG_CRIT(args...) LOG_FORMAT((Log::LL_CRIT), ##args)
#define LOG_ERROR(args...) LOG_FORMAT((Log::LL_ERR), ##args)
#define LOG_WARN(args...) LOG_FORMAT((Log::LL_WARNING), ##args)
#define LOG_NOTICE(args...) LOG_FORMAT((Log::LL_NOTICE), ##args)
#define LOG_INFO(args...) LOG_FORMAT((Log::LL_INFO), ##args)
#define LOG_DEBUG(args...) LOG_FORMAT((Log::LL_DEBUG), ##args)
```

* 源码实现（[github 源码](https://github.com/wenfh2020/kimserver/blob/master/src/core/util/log.h)）

```c++
class Log {
   public:
    enum {
        LL_EMERG = 0, /* system is unusable */
        LL_ALERT,     /* action must be taken immediately */
        LL_CRIT,      /* critical conditions */
        LL_ERR,       /* error conditions */
        LL_WARNING,   /* warning conditions */
        LL_NOTICE,    /* normal but significant condition */
        LL_INFO,      /* informational */
        LL_DEBUG,     /* debug-level messages */
        LL_COUNT
    };

    Log();
    virtual ~Log() {}

   public:
    bool set_level(int level);
    bool set_level(const char* level);
    bool set_log_path(const char* path);
    bool log_data(const char* file_name, int file_line, const char* func_name, int level, const char* fmt, ...);

   private:
    bool log_raw(const char* file_name, int file_line, const char* func_name, int level, const char* msg);

   private:
    int m_cur_level;
    std::string m_path;
};
```

---

## 3. 跨平台

跨平台日志处理，详细请参考 [zookeeper-client-c](https://github.com/apache/zookeeper/tree/master/zookeeper-client/zookeeper-client-c)。

```c
/* zookeeper_log.h */
#ifndef ZK_LOG_H_
#define ZK_LOG_H_

#include <zookeeper.h>

#ifdef __cplusplus
extern "C" {
#endif

extern ZOOAPI ZooLogLevel logLevel;
#define LOGCALLBACK(_zh) zoo_get_log_callback(_zh)
#define LOGSTREAM NULL

#define LOG_ERROR(_cb, ...) if(logLevel>=ZOO_LOG_LEVEL_ERROR) \
    log_message(_cb, ZOO_LOG_LEVEL_ERROR, __LINE__, __func__, __VA_ARGS__)
#define LOG_WARN(_cb, ...) if(logLevel>=ZOO_LOG_LEVEL_WARN) \
    log_message(_cb, ZOO_LOG_LEVEL_WARN, __LINE__, __func__, __VA_ARGS__)
#define LOG_INFO(_cb, ...) if(logLevel>=ZOO_LOG_LEVEL_INFO) \
    log_message(_cb, ZOO_LOG_LEVEL_INFO, __LINE__, __func__, __VA_ARGS__)
#define LOG_DEBUG(_cb, ...) if(logLevel==ZOO_LOG_LEVEL_DEBUG) \
    log_message(_cb, ZOO_LOG_LEVEL_DEBUG, __LINE__, __func__, __VA_ARGS__)

ZOOAPI void log_message(log_callback_fn callback, ZooLogLevel curLevel,
    int line, const char* funcName, const char* format, ...);

FILE* zoo_get_log_stream();

#ifdef __cplusplus
}
#endif

#endif /*ZK_LOG_H_*/
```

---

## 4. fprintf 线程安全吗

因为 [redis 的日志实现](https://github.com/redis/redis/blob/1f5a73a530915f6f6326047effc796218af22cf6/src/server.c#L1079) 是用 `fprintf` 将文件内容序列化的，不知道对于多线程它是否安全，查了一下 glibc 的实现源码，发现有上锁和解锁的逻辑。

```c
/* https://github.com/lattera/glibc/blob/master/stdio-common/fprintf.c */

/* Write formatted output to STREAM from the format string FORMAT.  */
/* VARARGS2 */
int
__fprintf (FILE *stream, const char *format, ...)
{
  va_list arg;
  int done;

  va_start (arg, format);
  done = vfprintf (stream, format, arg);
  va_end (arg);

  return done;
}
ldbl_hidden_def (__fprintf, fprintf)
ldbl_strong_alias (__fprintf, fprintf)

/* We define the function with the real name here.  But deep down in
   libio the original function _IO_fprintf is also needed.  So make
   an alias.  */
ldbl_weak_alias (__fprintf, _IO_fprintf)
```

```c
/* https://github.com/lattera/glibc/blob/master/stdio-common/vfprintf.c */

/* The function itself.  */
int
vfprintf (FILE *s, const CHAR_T *format, va_list ap)
{
    ...
  /* Lock stream.  */
#ifdef USE_IN_LIBIO
  __libc_cleanup_region_start ((void (*) (void *)) &_IO_funlockfile, s);
  _IO_flockfile (s);
#else
  __libc_cleanup_region_start ((void (*) (void *)) &__funlockfile, s);
  __flockfile (s);
#endif
    ...
all_done:
  /* Unlock the stream.  */
  __libc_cleanup_region_end (1);

  return done;
}
```

---

## 5. 参考

* [多线程下的fwrite和write](https://cloud.tencent.com/developer/article/1412015)
