---
layout: post
title:  "tmux 返回前一个 panel 快捷键"
categories: tool
tags: tmux prev pannel
author: wenfh2020
---

tmux 在同一个 session 里分割了多个 panel ， panel 间的切换方法很多种：左右前后，prefix + q 选数字等。

返回前一个窗口的快捷键比较难找，tmux 也提供了这个功能，需要进行设置进行绑定。



* content
{:toc}

---

## 1. tmux 文档

用 `man tmux` 查看文档，有详细资料。

```shell
# man tmux
DEFAULT KEY BINDINGS
     tmux may be controlled from an attached client by using a key combination of a prefix
     key, `C-b' (Ctrl-b) by default, followed by a command key.

     The default command key bindings are:

           C-b         Send the prefix key (C-b) through to the application.
           C-o         Rotate the panes in the current window forwards.
           C-z         Suspend the tmux client.
           !           Break the current pane out of the window.
           ...
           # 这个就是返回上一个窗口。
           l           Move to the previously selected window.
```

---

## 2. 绑定设置

* 修改 tmux 配置，绑定 `prefix + b` 快捷键。

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

## 3. 参考

* [tmux 常用快捷键](https://wenfh2020.com/2020/11/05/tmux/)
* [How to switch to the previous pane by any shortcut in tmux?](https://stackoverflow.com/questions/31980036/how-to-switch-to-the-previous-pane-by-any-shortcut-in-tmux)
