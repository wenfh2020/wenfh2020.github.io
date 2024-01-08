---
layout: post
title:  "[数据库] sqlite3 模糊查找效率"
categories: database
tags: mysql config command
author: wenfh2020
---

sqlite 是轻量级数据库，适用于小型的数据存储应用场景。

在 Linux 系统测试了一下 sqlite 的模糊查询功能：从 100w 条数据里（文件夹/文件名称），模糊查询字符串。

* 极端情况，搜索一个字符或一个汉字，从请求到返回结果耗时约 400 毫秒。
* 正常情况，搜索词组，耗时 200 毫秒左右，感觉效率还不错。

---


* content
{:toc}



---

## 1. 需求

数据库保存系统的文件夹/文件名，根据字符串进行模糊搜索。

---

## 2. 建库

```shell
# 系统
cat /proc/version
Linux version 3.10.0-1127.19.1.el7.x86_64

# 安装高版本 sqlite
wget https://www.sqlite.org/2023/sqlite-autoconf-3440200.tar.gz
tar zxf sqlite-autoconf-3440200.tar.gz
cd sqlite-autoconf-3440200
./configure --prefix=/usr/local --enable-fts5
make -j4
make install
ln -s /usr/local/bin/sqlite3 /usr/bin/sqlite3

# 版本
sqlite3 --version
3.44.2 2023-11-24 ... (64-bit)

# 建库
sqlite3 db_file_objs.db
```

---

## 3. 实现

### 3.1. 脚本

```python
#!/usr/bin/env python3
# -*- coding: UTF-8 -*-

import os, sys
import sqlite3
from datetime import datetime
import time

# 建表
def create_table(c):
    c.execute("create table if not exists file_object ( \
                    id INTEGER PRIMARY KEY AUTOINCREMENT, \
                    name TEXT NOT NULL, \
                    path TEXT NOT NULL, \
                    type UNSIGNED SHORT NOT NULL, \
                    date TEXT NOT NULL);"
    )

# 遍历文件夹/文件，插入数据
def recursive_file_search(conn, dir_path):
    obj_cnt = 0
    cur = conn.cursor()
    for root, dirs, files in os.walk(dir_path):
        for dir in dirs:
            obj_cnt += 1
            path = os.path.join(root, dir)
            cur.execute("insert into file_object (name, path, type, date) \
                values (?, ?, ?, ?)", \
                (dir, path, 1, datetime.now().strftime('%Y-%m-%d')))
        for file in files:
            obj_cnt += 1
            path = os.path.join(root, file)
            cur.execute("insert into file_object (name, path, type, date) \
                values (?, ?, ?, ?)", \
                (file, path, 2, datetime.now().strftime('%Y-%m-%d')))
    # 提交事务
    conn.commit()
    return obj_cnt

# 模糊查找数据
def search(conn, text):
    cur = conn.cursor()
    cur.execute("select * from file_object where name like '%{}%'".format(text))
    return cur.fetchall()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("pls input args: [cmd][arg]")
        exit(1)

    cmd = sys.argv[1]
    data = sys.argv[2]
    print("cmd: {}, data: {}".format(cmd, data))

    c = sqlite3.connect('db_file_objs.db')
    c.text_factory = str

    if cmd == 'create':
        create_table(c)
        start_time = time.time()
        cnt = recursive_file_search(c, data)
        time_elapsed = (time.time() - start_time) * 1000
        print("cnt: {}, time val: {} ms".format(cnt, time_elapsed))
    elif cmd == 'search':
        start_time = time.time()
        results = search(c, data)
        time_elapsed = (time.time() - start_time) * 1000
        print("cnt: {}, time val: {} ms".format(len(results), time_elapsed))
    else:
        print("invalid cmd: {}".format(cmd))

    # 关闭数据库连接
    c.close()
```

---

### 3.2. 测试结果

从 1,043,249 条数据里，模糊搜索关键字，详细数据：

* 极端情况，搜索一个字符或一个汉字，从请求到返回结果耗时约 400 毫秒。
* 正常情况，搜索词组，耗时 200 毫秒左右。

```shell
# 遍历根目录，将文件/文件夹名称插入数据库。
➜ python folder.py create /   
cmd: create, data: /
cnt: 481533, time val: 11612.842083 ms

# 查询数据量
➜ sqlite3 ./db_file_objs.db
SQLite version 3.44.2 2023-11-24 11:41:44
sqlite> select count(*) from file_object;
1043249

# 搜索带有 '请' 关键字的名称。
➜ python folder.py search '请'
cmd: search, data: 请
cnt: 2, time val: 403.656959534 ms

# 搜索带有 'mp4' 关键字的名称。 
➜ python folder.py search 'mp4'
cmd: search, data: mp4
cnt: 34, time val: 386.833906174 ms

# 搜索带有 'Makefile' 关键字的名称。 
➜ python folder.py search 'Makefile'
cmd: search, data: Makefile
cnt: 6469, time val: 237.241029739 ms
```

---

## 4. 小结

* sqlite 使用了 like 模糊搜索。
* 因为被搜索内容是文件夹/文件名称，可能搜索的内容长度不会太大，所以效率比较高。
* 如果设置更多的 where sql 条件，搜索的速度应该还能加快。
* 如果数据量很大，被搜索内容很多，可以尝试使用全文搜索（FTS）。
