---
layout: post
title:  "[知乎回答] 程序员都是怎么记笔记的？"
categories: 知乎 随笔
tags: working
author: wenfh2020
---

[**知乎问题**](https://www.zhihu.com/question/26229037/answer/2261258741)：

程序员编码过程中总会碰到很多 bug，这些 bug 都应该算是我们的一种阅历，非常想把这些犯过的错误记录下来，所以说大家都是用什么来做 bug 笔记的呢？

现在个人在用 Evernote 做一些记录，但是碰到了一下问题：
1. Evernote 没有好的代码编辑器。
2. 公司有安全的考虑，不建议用外部软件记录业务数据。
3. 还没设计出好的规则来进行管理。




* content
{:toc}

---

## 1. 概述

* 语雀
* markdown + vscode
* git + github (github 有公开或私人目录)
* processon（也可以用 xmind）
* 博客 wiki（可以部署本地/局域网/公网）

---

## 2. 方式

### 2.1. 语雀

语雀，是蚂蚁集团旗下的在线文档编辑与协同工具，软件支持跨平台，文档编辑相对友好，是个不错的个人/团队的知识库平台。

<div align=center><img src="/images/2023/2023-02-16-12-37-07.png" data-action="zoom" width="40%"/></div>

---

### 2.2. markdown + vscode

markdown 通过简单的语法写出精简条理的文档，vscode 功能强大，有很多插件支持 markdown.

| vsocde 插件               | 插件描述           |
| :------------------------ | :----------------- |
| Markdown All in Once      | 文档编写基本插件。 |
| Markdown Preview Enhanced | 预览。             |
| markdownlint              | 语法检查。         |
| Markdown TOC              | 自动生成目录。     |
| Paste Image               | 在编辑器贴图。     |

<div align=center><img src="/images/2021/2021-12-31-10-16-46.png" data-action="zoom"/></div>

---

### 2.3. git + github

笔记文章通过 git 进行版本管理，git 数据上传 [github](https://github.com/wenfh2020/wenfh2020.github.io/tree/master/_posts) 进行可视化管理。（github + jekyll 还能搭建自己的博客。）

<div align=center><img src="/images/2021/2021-12-31-10-17-46.png" data-action="zoom"/></div>

---

### 2.4. processon

* [processon](https://processon.com/u/56e76de5e4b05387d036f99e/profile) 思维导图将复杂的业务要点分类。

<div align=center><img src="/images/2021/2021-12-31-10-18-34.png" data-action="zoom"/></div>

---

* 逻辑时序图，将复杂的源码工作流程落地。

<div align=center><img src="/images/2021/2021-12-31-12-44-05.png" data-action="zoom"/></div>

> 图片来源：[tcp + epoll 内核睡眠唤醒工作流程](https://wenfh2020.com/2021/12/16/tcp-epoll-wakeup/)

---

### 2.5. 博客 wiki

可以自己[搭建博客](https://wenfh2020.com/2020/02/17/make-blog/)，博客页面排版更人性化，可以同步 markdown 文件内容，博客可以部署在本地或局域网浏览，也可以部署到公网。

<div align=center><img src="/images/2021/2021-12-31-10-20-53.png" data-action="zoom"/></div>
