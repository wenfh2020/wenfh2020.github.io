---
layout: post
title:  "类型强制转换异常跟踪"
categories: c/c++
tags: type cast exception
author: wenfh2020
---

最近发现文件服务客户端 sdk 异常：上传文件，文件数据经常只传一部分就进入完成状态，经过跟踪调试，原来类型强制转换错误，程序没有抛异常。



* content
{:toc}

---

## 1. 问题

进度逻辑里，`pTask` 指针对象原来是 `CUploadTask` 类型的，被强制转换成 `CDownloadTask`，程序正常运行，没有抛异常。

```c++
// 下载任务
class CDownloadTask : public CTask {
public:
    CDownloadTask() : m_ullDownloadedSize(0) {}
    virtual ~CDownloadTask() {}

public:
    unsigned __int64 m_ullDownloadedSize; //已下载文件大小
    ...
};

// 上传任务
class CUploadTask : public CTask {
public:
    CUploadTask() : m_bPicResample(false), m_ullUploadedSize(0) {}
    virtual ~CUploadTask() {}

public:
    bool m_bPicResample;                     //是否有压缩图片
    std::string m_strFileType;               //文件类型
    unsigned __int64 m_ullUploadedSize;      //已上传文件大小
    ...
};

// 进度更新逻辑
bool CTaskMgr::UpdateTaskProgress(int iTaskID, 
               unsigned __int64 ullFileSize, unsigned __int64 ullNowSize) {
    CTask* pTask = NULL;
    if (m_mapTask.Lookup(iTaskID, pTask) && pTask != NULL) {
        CDownloadTask* pDLoadTask = (CDownloadTask*)pTask; // 出现问题语句。
        pDLoadTask->m_oFileInfo.m_ullFilesize = ullFileSize;
        pDLoadTask->m_ullDownloadedSize = ullNowSize;
        return true;
    }

    return false;
}
```

---

## 2. 解决方案

用安全的强制转换 `dynamic_cast`，它会在运行期对可疑的转型操作进行安全检查，类型不匹配会返回 NULL。

```c++
CDownloadTask* pDLoadTask = dynamic_cast<CDownloadTask*>(pTask);
```

---

## 3. 调试手段

如果不清楚变量是在哪里发生改变的，VS 系列，可以用“数据断点”功能，监控某个变量的改变。类似于 gdb 的 watch 功能。

![调试手段 watch](/images/2020-06-29-17-17-10.png){:data-action="zoom"}

---

## 4. 参考

* [static_cast, dynamic_cast, const_cast 三种类型转化的区别](https://www.cnblogs.com/xj626852095/p/3648099.html)
* [C++四种类型转换运算符](http://c.biancheng.net/cpp/biancheng/view/3297.html)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/2018/07/03/type-cast-exception/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
