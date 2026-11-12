# MoonRainflow

[English](README.md) · [公共接口](pkg.generated.mbti)

一段台架载荷记录里，缓慢的大幅波动中可能嵌着几次快速的小幅往复。MoonRainflow 从原始读数中找出这些循环，给出**极差、均值、权重和原始采样下标**，再按极差和均值统计循环谱。核心由 MoonBit 编写，无第三方运行依赖。适用于单通道测量数据的离线复核或连续采集。

## 一分钟复现

在本项目根目录打开终端，使用 MoonBit 工具链（本机验证：`moonc v0.10.19`）运行：

```sh
moon run cmd/demo --target wasm-gc
```

示例把 `[-2, 1, -3, 5, -1, 3, -4, 4, -2]` 分成三块输入。第 4 到第 5 号样本从 −1 到 3，形成极差 4、均值 1 的**整循环**；第 0 到第 1 号样本只贡献半循环。输出共 7 行（1 整、6 半），合计 4 个等效完整循环。二维矩阵以半循环为整数单位，最后几行是：

```text
7 records; 4 equivalent cycles
Matrix in half-cycle units (rows: range; columns: mean):
  [1, 0]
  [1, 5]
Outside grid: 1 half-cycle unit(s)
```

矩阵内的 7 个半循环单位加上超界的 1 个，正好等于 4 个完整循环。该超界记录的极差为 9，而示例分箱只覆盖到 8。

## 用自己的数据

文件为 UTF-8 文本，每行一个十进制数，允许科学计数法、空行和 CRLF。使用 Node.js 22.12 或更高版本（已测 24.19）：

```sh
moon build --target js --release cmd/bridge
node cmd/rainflow.mjs examples/mathworks-nine.txt
node cmd/rainflow.mjs measurements.txt > cycles.csv
```

省略文件名或传 `-` 可从标准输入持续读取。首行为 `start_index,end_index,range,mean,half_units`；下标从 0 开始、忽略空行。极差是峰谷之差的绝对值，振幅为极差的一半；`half_units / 2` 才是循环次数。结果按**可确定的先后顺序**输出，起止下标未必随输出行递增。遇到非法值会在标准错误报告物理行号、退出码非零；已输出的行会保留，自动化任务请检查退出码后再使用整个文件。

## 从 MoonBit 调用

本仓库的 `cmd/demo/moon.pkg` 展示了如何把根包导入为 `@rain`。跨批次要复用同一个计数器；每收到一块就处理当时已经确定的循环。以下代码可放进允许抛出 `@rain.RainError` 的函数中：

```moonbit
let counter = @rain.Counter::new()
let grid = @rain.Spectrum::new([0.0, 4.0, 8.0], [-1.0, 0.0, 1.0])
for block in [[-2.0, 1.0, -3.0], [5.0, -1.0], [3.0, -4.0, 4.0, -2.0]] {
  for c in counter.push_chunk(block) { grid.add(c) }
}
for c in counter.finish() { grid.add(c) }
let matrix = grid.matrix() // 行 = 极差箱；列 = 均值箱
```

只处理短数组可直接用 `@rain.extract(samples)`。每次 `push_chunk` 先校验整块；只要有一个无效值，该块不会被部分消费，可以修正后原位重试。`finish()` 在记录结束时结算残余部分，重复调用返回空数组；此后追加会得到 `ClosedCounter`。不同试验段、不同传感器不能共用同一条未结束的记录，否则段与段之间会被当作一次真实运动。

## 计数口径

- 采用三点雨流法处理非周期记录。滤除单调段中的非转折点；连续相等值归入同一平台，下标取首次达到的位置（包括结尾平台）。空、单点、全常值输入没有循环，两点不同则有一个半循环。
- 新极差大于或等于上一极差时结算；左边界配对算半循环，内部配对算整循环。到达末尾后把剩余相邻点从左到右算作半循环。不自动首尾拼接，不进行滞回滤波或噪声门限处理。
- 接受区间 `[-1e300, 1e300]` 内的有限 Double，为极差、均值的中间计算留出空间。输出 Int64 下标；不推断采样频率和单位。已知采样时间时，可用下标查回原始时间戳。
- 两个分箱轴各需至少两个严格递增的有限边界，极差边界非负。分箱左闭右开，最后一箱包含最右端点。超出任一轴只记一次超界权重。矩阵最多 100 万格，输入边界和输出矩阵都不会与内部可变状态共享。
- 核心计数对 n 个采样点总耗时 O(n)；状态只需当前候选点和未闭合转折点栈。最坏情况下这个栈仍可随输入增长。每条循环分箱为 O(log R + log M)，R、M 分别是两轴的箱数。库只生成载荷谱，不包含材料模型、寿命预测或安全判定。

## 怎样验证

```sh
moon fmt --check
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon build --target js --release cmd/bridge --deny-warn
node --test scripts/cli.test.mjs
```

测试将 [MathWorks 公开算例](https://www.mathworks.com/help/signal/ref/rainflow.html)的 7 条循环逐字段比对，考察该序列全部 256 种切块方法，并穷举长度 0 到 7、取值 −1/0/1 的 3,280 条短序列，检查循环还原的总变差等于输入总变差。CLI 验收覆盖文件、管道、格式诊断以及输入关闭前就能收到已确定的循环。

另附独立对拍脚本：在独立 Python 环境执行 `python -m pip install rainflow==3.2.0`，构建 JS 桥后运行 `python scripts/check_reference.py`。它用固定输入及固定种子产生 100 条记录，将 CLI 返回的 3,540 条循环逐字段与 [Python rainflow](https://github.com/iamlikeme/rainflow) 对照。随机记录无相邻重复值，以避免不同平台下标约定产生假差异；平台段另在 MoonBit 测试覆盖。Python 仅用于这项验收。

实现采用 [Apache-2.0](LICENSE)。公开算法和对拍来源见上文，未复制参考项目源码，不声称取得 ASTM 认证。
