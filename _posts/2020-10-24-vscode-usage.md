---
layout: post
title:  "vscode 快捷键执行脚本命令"
categories: tool
tags: vscode usage
author: wenfh2020
---

我写代码习惯了一边写一边编译，以前用 `vistual studio` 系列，有编译、调试、运行快捷键；现在使用 `vscode` 却没发现这些快捷键，在很长一段时间里，经常在 `terminal` 窗口执行脚本编译，窗口来回切换，思路很容易被打断。

最近查了一下，需要自己设置 `vscode` 的一些脚本，绑定快捷键。




* content
{:toc}

---

## 1. 原理

快捷键和脚本绑定，主要编辑两个文件 `keybindings.json` + `tasks.json`。详细可以参考[官方文档](https://code.visualstudio.com/docs/editor/tasks#_binding-keyboard-shortcuts-to-tasks)。

现在看看如何绑定快捷键 `ctrl+h` 和下面这个脚本命令。

```shell
~/src/other/kimserver/run.sh compile all
```

---

## 2. 设置快捷键

1. `F1` 快捷键查找：`short`。
2. 选中 `Preferences: Open Keyboard Shortcuts (JSON)` 选项。
3. 步骤 1 随即会打开快捷键 json 文件：`keybindings.json`。
4. 添加要绑定的快捷键信息。

![快捷键设置](/images/2020-10-24-17-25-43.png){:data-action="zoom"}

| key     | value                                                              |
| :------ | :----------------------------------------------------------------- |
| key     | 快捷键。注意不要与系统的重复，冲突。                               |
| command | 运行 task.json 脚本。                                              |
| args    | 对应 task.json 里的 'lablel' 选项。                                |
| when    | 焦点在源码编辑窗口上快捷键才会生效，这个地方可以根据自己需要修改。 |

```json
    {
        "key": "ctrl+h",
        "command": "workbench.action.tasks.runTask",
        "args": "kimserver",
        "when": "editorTextFocus"
    }
```

---

## 3. 编辑编译任务

修改 `tasks.json`，绑定执行命令。

1. `F1` 快捷键查找：`tasks`。
2. 选中 `Tasks: Open User Tasks` 选项。
3. 根据自己脚本的需要选择对应的类型，笔者选择了 `Others`。
4. 步骤 3 后就可以编辑 `tasks.json` 文件即可。

![编辑 tasks.json](/images/2020-10-24-17-55-14.png){:data-action="zoom"}

![编辑 tasks.json](/images/2020-10-24-17-57-16.png){:data-action="zoom"}

| key     | value                                  |
| :------ | :------------------------------------- |
| label   | 对应 keybindings.json 的 "args" 参数。 |
| type    | 脚本类型。                             |
| command | 需要执行的脚本命令。                   |

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "kimserver",
            "type": "shell",
            "command": "~/src/other/kimserver/run.sh compile all"
        }
    ]
}
```

---

## 4. 参考

* [Integrate with External Tools via Tasks](https://code.visualstudio.com/docs/editor/tasks#_binding-keyboard-shortcuts-to-tasks)

---

> 🔥 文章来源：[《vscode 实用功能实用》](https://wenfh2020.com/2020/10/24/vscode-usage/)
>
> 👍 大家觉得文章对你有些作用！ 如果想 <font color=green>赞赏</font>，可以用微信扫描下面的二维码，感谢!
<div align=center><img src="/images/2020-08-06-15-49-47.png" width="120"/></div>
