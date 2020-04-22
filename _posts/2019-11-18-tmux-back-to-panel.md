---
layout: post
title:  "tmux 返回前一个 panel 快捷键"
categories: tool
tags: tmux prev pannel
author: wenfh2020
---

tmux 在同一个 session 里分割了多个 panel ， panel 间的切换方法很多种：左右前后，prefix + q 选数字等。

返回前一个窗口的快捷键比较难找，tmux 也提供了这个功能。需要进行设置进行绑定。



* content
{:toc}

---

## 设置

* 修改 tmux 配置，绑定 prefix + b。

```shell
# vim ~/.tmux.conf
bind-key b select-pane -l
```

* 在 tmux 窗口里执行命令：

```shell
prefix + ：
source-file ~/.tmux.conf
```

* 新建 session 生效。

---

## 参考

* [How to switch to the previous pane by any shortcut in tmux?](https://stackoverflow.com/questions/31980036/how-to-switch-to-the-previous-pane-by-any-shortcut-in-tmux)

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/)
