---
layout: post
title:  "自动代码工具 - 分析 mysql 脚本（*.sql）生成 C++ 源码"
categories: c/c++ mysql
tags: mysql script database gencode c++
author: wenfh2020
---

自动代码工具，根据 sql 脚本的语法特征，提取脚本的表名（table name）和其对应的列（column）信息，抽象成类，并生成对应的 C++ 源码文件。



* content
{:toc}

---

## 1. 工具作用

自动代码工具作用，类似 protobuf 通过 *.proto 文件，用工具生成相应的源码文件。

1. 直接减少了团队开发工作量。
2. 有利于团队代码风格统一。
3. 数据操作面向对象，操作人性化。

---

## 2. 使用

源码已上传 [github](https://github.com/wenfh2020/db_gencode)。

* 命令

```shell
./db_gencode <file_name>
```

* 脚本（upload.sql）。

```sql
-- MySQL dump 10.13  Distrib 5.7.22, for Linux (x86_64)
--
-- Host: localhost    Database: upload
-- ------------------------------------------------------
-- Server version   5.7.22

--
-- Table structure for table `tb_file`
--

DROP TABLE IF EXISTS `tb_file`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `tb_file` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `file_name` varchar(255) NOT NULL,
  `file_size` int(11) NOT NULL DEFAULT '0',
  `md5` char(32) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
) ENGINE=MyISAM AUTO_INCREMENT=55688 DEFAULT CHARSET=utf8;
```

* 编译源码使用。

```shell
git clone https://github.com/wenfh2020/db_gencode.git
cd db_gencode
make
./db_gencode upload.sql
```

* c++ 源码文件(\*.h/\*.cpp)。

```c++
// tb_file.h
class tb_file {
public:
    tb_file();
    tb_file(const tb_file& obj);
    ~tb_file() {}

    tb_file& operator = (const tb_file& obj);

    inline const char* table_name() const { return "tb_file"; }
    inline tb_uint32 get_count() const { return 4; }
    string serialize() const;

    inline const char* col_id() const { return "`id`"; }
    inline const char* col_file_name() const { return "`file_name`"; }
    inline const char* col_file_size() const { return "`file_size`"; }
    inline const char* col_md5() const { return "`md5`"; }

    bool set_id(const tb_uint32 value);
    bool set_file_name(const string& value);
    bool set_file_name(const char* value, size_t size);
    bool set_file_name(const char* value);
    bool set_file_size(const tb_int32 value);
    bool set_md5(const string& value);
    bool set_md5(const char* value, size_t size);
    bool set_md5(const char* value);

    inline tb_uint32 id() const { return m_ui_id; }
    inline const string& file_name() const { return m_str_file_name; }
    inline tb_int32 file_size() const { return m_i_file_size; }
    inline const string& md5() const { return m_str_md5; }

    inline bool has_id() { return (m_ui_has_bit & 0x00000001) != 0; }
    inline bool has_file_name() { return (m_ui_has_bit & 0x00000002) != 0; }
    inline bool has_file_size() { return (m_ui_has_bit & 0x00000004) != 0; }
    inline bool has_md5() { return (m_ui_has_bit & 0x00000008) != 0; }

    inline void clear_has_id() { m_ui_has_bit &= ~0x00000001; }
    inline void clear_has_file_name() { m_ui_has_bit &= ~0x00000002; }
    inline void clear_has_file_size() { m_ui_has_bit &= ~0x00000004; }
    inline void clear_has_md5() { m_ui_has_bit &= ~0x00000008; }

    inline bool is_valid() const {return (m_ui_has_bit & 0x0000000f) != 0;}

private:
    tb_uint32 m_ui_has_bit;
    tb_uint32 m_ui_id;
    string m_str_file_name;
    tb_int32 m_i_file_size;
    string m_str_md5;
};
```
