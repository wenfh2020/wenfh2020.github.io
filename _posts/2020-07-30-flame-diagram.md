---
layout: post
title:  "软件性能检测--火焰图🔥"
categories: tool
tags: flame diagram performance
author: wenfh2020
---

火焰图是 svg 格式的矢量图，基于 `perf` 软件性能分析工具。通过对软件在系统上的工作行为记录进行采样。并将数据进行图形化，从而获得比较直观的可视化数据矢量图。




* content
{:toc}

---

## 1. 概述

基于 Linux 平台的 `perf` 采样脚本（[fg.sh](https://github.com/wenfh2020/shell/blob/master/fg.sh)），对指定进程进行采样，生成火焰图 `perf.svg`。

> 🔥 生成火焰图视频教程 [《生成火焰图（Generate flame diagram）》](https://www.bilibili.com/video/BV1My4y1q7YK/)

---

### 1.1. 安装 perf 和 FlameGraph

```shell
yum install perf
cd /usr/local/src
git clone https://github.com/brendangregg/FlameGraph.git
ln -s /usr/local/src/FlameGraph/flamegraph.pl /usr/local/bin/flamegraph.pl
ln -s /usr/local/src/FlameGraph/stackcollapse-perf.pl /usr/local/bin/stackcollapse-perf.pl
```

---

### 1.2. 脚本

* [fg.sh](https://github.com/wenfh2020/shell/blob/master/fg.sh) 。

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

* 命令。

```shell
./fg.sh <pid>
```

---

## 2. 火焰图

通过上面脚本，对指定进程（`pid`）进行数据采集，即可生成下面的二维火焰图：

* Y 轴是函数块叠加而成，有点像程序调试堆栈；
* X 轴代表程序函数，在单位时间内被采样的密集度。函数块越长，说明采样越多，工作频率越高，耗性能越多。

通过图象，我们对自己写的代码工作效率一目了然，这样可以针对性优化源码性能。

* siege 压测工具。

```shell
# siege 压力测试工具
# $ ./http_pressure.sh

{
        "transactions":                        50000,
        "availability":                       100.00,
        "elapsed_time":                         1.62,
        "data_transferred":                     3.43,
        "response_time":                        0.00,
        "transaction_rate":                 30864.20,
        "throughput":                           2.12,
        "concurrency":                         46.59,
        "successful_transactions":             50000,
        "failed_transactions":                     0,
        "longest_transaction":                  0.01,
        "shortest_transaction":                 0.00
}
```

* 火焰图🔥

![火焰图](/images/2020-07-30-19-33-44.png){:data-action="zoom"}

---

## 3. 定位问题

### 3.1. 问题一

<div align=center><img src="/images/2020-08-07-00-05-48.png" data-action="zoom" width="40%"/></div>

上图可以看到 `vsnprintf` 在优化前使用频率非常高，占 6.7%。在源码中查找 `vsnprintf`，发现日志入口，对日志等级 level 的判断写在 `log_raw` 里面了，导致高等级的日志虽然没有被记录，仍然执行了 `vsnprintf` 操作。后面将判断放在 `vsnprintf` 前，重复进行测试，占 1.54%。 性能提高 5 个百分点——good!

```c++
bool Log::log_data(const char* file_name, int file_line, const char* func_name, int level, const char* fmt, ...) {
    if (level < LL_EMERG || level > LL_DEBUG || level > m_cur_level) {
        return false;
    }
    va_list ap;
    char msg[LOG_MAX_LEN] = {0};
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);
    return log_raw(file_name, file_line, func_name, level, msg);
}
```

---

### 3.2. 问题二

如果不是火焰图，你无法想象 `std::list::size()` 这个接口时间复杂度竟然是 O(N)。

![火焰图问题二](/images/2020-12-11-17-43-59.png){:data-action="zoom"}

---

## 4. 参考

* [Siege HTTP 压力测试](https://wenfh2020.com/2018/05/02/siege-pressure/)
