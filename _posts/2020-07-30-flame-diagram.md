---
layout: post
title:  "检测软件性能--火焰图"
categories: c/c++
tags: flame diagram performance
author: wenfh2020
---

火焰图是 svg 格式的矢量图，基于 `perf` 软件性能分析工具。通过对软件在系统上的工作行为记录进行采样。并将数据进行图形化，从而得出比较直观的可视化数据矢量图。




* content
{:toc}

---

## 1. perf 采样

* 基于 Linux 平台的 `perf` 采样脚本（[fg.sh - github 源码](https://github.com/wenfh2020/shell/blob/master/fg.sh)），对指定进程（pid）进行采样，生成火焰图 `perf.svg`。

```shell
#!/bin/sh

if [ $# -lt 1 ]; then
    echo 'input pid'
    exit 1
fi

rm -f perf.*
perf record -F 99 -p $1 -g -- sleep 60
perf script -i perf.data &> perf.unfold
stackcollapse-perf.pl perf.unfold &> perf.folded
flamegraph.pl perf.folded > perf.svg
```

---

## 2. 火焰图

压力测试自己的源码，通过上面的 fg.sh 脚本，对指定进程（`pid`）进行数据采集，即可生成下面的火焰图。

火焰图是二维图像：Y 轴是函数块叠加而成，有点像程序调试堆栈；X 轴代表函数工作，在单位时间内被采样的密集度，函数块越长说明，采样越多，耗性能越多。

通过图象，我们对自己写的代码工作效率一目了然，这样就可以针对性地优化耗性能部分代码。

![火焰图](/images/2020-07-30-19-33-44.png){:data-action="zoom"}

---

> 🔥文章来源：[wenfh2020.com](https://wenfh2020.com/2020/07/30/flame/diagram/)
