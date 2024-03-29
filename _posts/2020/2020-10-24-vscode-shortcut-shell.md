---
layout: post
title:  "vscode 一键（快捷键）执行脚本命令"
categories: tool
tags: vscode shell shortcuts
author: wenfh2020
---

写代码习惯了一边写一边编译，以前用 vistual studio 系列，有编译、调试、运行快捷键；现在使用 vscode 却找不到这些快捷键，在很长一段时间里，在 terminal 窗口执行脚本编译，窗口来回切换，麻烦不说，思路也很容易被打断。

最近查了一下，需要自己设置 vscode 的一些配置，绑定快捷键。




* content
{:toc}

---

## 1. 原理

快捷键和脚本绑定，主要编辑两个文件配置： `keybindings.json` + `tasks.json`。详细可以参考[官方文档](https://code.visualstudio.com/docs/editor/tasks#_binding-keyboard-shortcuts-to-tasks)。

现在看看如何绑定快捷键 `ctrl + h` 和下面这个脚本命令。

```shell
~/src/other/kimserver/run.sh compile all
```

---

## 2. 设置快捷键

1. `F1` 快捷键查找：`short`。
2. 选中 `Preferences: Open Keyboard Shortcuts (JSON)` 选项。
3. 步骤 1 随即会打开快捷键 json 文件：keybindings.json。
4. 添加要绑定的快捷键信息。

![快捷键设置](/images/2020/2020-10-24-17-25-43.png){:data-action="zoom"}

| key     | value                                                                          |
| :------ | :----------------------------------------------------------------------------- |
| key     | 快捷键。注意不要与系统的重复，冲突。                                           |
| command | 运行 task.json 脚本。                                                          |
| args    | 快捷键名称，对应 task.json 里的 'label' 选项。                                 |
| when    | 快捷键生效场景。（例如：焦点在源码编辑窗口上，这个地方可以根据自己需要修改。） |

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

修改 tasks.json 文件，绑定执行命令。

1. `F1` 快捷键查找：`tasks`。
2. 选中 `Tasks: Open User Tasks` 选项。
3. 根据自己脚本的需要选择对应的类型，笔者选择了 `Others`。
4. 步骤 3 后就可以编辑 tasks.json 文件即可。

![编辑 tasks.json](/images/2020/2020-10-24-17-55-14.png){:data-action="zoom"}

![编辑 tasks.json](/images/2020/2020-10-24-17-57-16.png){:data-action="zoom"}

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

## 4. 其它

当运行快捷键后，vscode 底部的 terminal 窗口会弹出，可以修改 keybindings.json 绑定 `esc` 键，快捷隐藏。

``` json
{
    "key": "escape",
    "command": "workbench.action.closePanel",
    "when": "activePanel"
}
```

---

## 5. 小结

通过这种方法，可以将更多脚本命令关联快捷键，例如 `F6`，`F7`，`F10` 这些快捷键可以关联：编译，全编译，运行脚本，真正做到一键执行。

> 在 13 寸本子上撸代码，就那么一点空间，只能使劲折腾。

---

## 6. 参考

* [Integrate with External Tools via Tasks](https://code.visualstudio.com/docs/editor/tasks#_binding-keyboard-shortcuts-to-tasks)
* [vscode 快捷键配置](https://www.cnblogs.com/JohnRain/p/10361940.html)
* [在Visual Studio Code中在编辑器和集成终端之间切换焦点](https://blog.csdn.net/CHCH998/article/details/106451078)
