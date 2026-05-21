# TPU 项目面试前 10 分钟速记版

这份文档只给你最后上场前看。
目标不是系统学习，而是：
**10 分钟内把主线、关键词、证据和高频追问全部拉回脑子里。**

---

## 1. 开场 20 秒

我这次做的是一个 TinyTPU AXI-Lite SoC 项目。
核心不是单个 PE，而是把编译器、Frontend、UB、PE、VPU、验证真正接成一条训练闭环。
所以它不是单点 demo，而是一个可控、可观测、可验证的系统原型。

---

## 2. 8 页主讲版到底在讲什么

### 第 1 页 封面
只定题。

### 第 2 页 系统总览
一句话：
从 `compiler -> frontend -> UB/PE/VPU -> waveform/convergence` 是一条闭环。

### 第 3 页 RTL 结构
一句话：
`tpu_soc` 把 Host、Frontend、TPU core 焊成系统顶层。

### 第 4 页 编译器与指令组织
一句话：
`scheduler.py` 生成控制序列，`control_unit.sv` 按位拆成硬件字段。

### 第 5 页 Unified Buffer
一句话：
UB 是训练数据流和阶段边界的汇合点，不只是 RAM。

### 第 6 页 PE 与计算阵列
一句话：
PE 做乘加，VPU 做训练路径语义，二者和 UB 组成执行闭环。

### 第 7 页 验证与波形
一句话：
不是只看波形，而是波形 + 回归 + 收敛三层证据。

### 第 8 页 结果与边界
一句话：
已经做成系统闭环，下一步自然是 DMA、IRQ、更大阵列和更完整软件栈。

---

## 3. 必须脱口而出的 8 个关键词

1. `AXI-Lite controllable SoC wrapper`
2. `Frontend sequencer + IMEM`
3. `32-bit instruction -> control fields`
4. `UB pointer select / restore`
5. `shadow -> active switch`
6. `UB -> systolic -> VPU -> UB`
7. `waveform + regression + convergence`
8. `not a single-point demo, but a full closed loop`

---

## 4. 最强的 3 个证据

### 证据 1
Host 能通过 AXI-Lite 装程序、装数据、启动执行。

### 证据 2
波形能看到 Frontend、UB、PE、VPU 按阶段推进。

### 证据 3
训练收敛测试说明它不是只“有波形”，而是真的语义跑通。

---

## 5. 你最该主动强调的 4 个个人贡献

1. 把 tiny-tpu 接成可控 SoC 顶层。
2. 把编译器控制序列和 RTL 字段一一对齐。
3. 修了阶段边界相关 bug，比如 `wait_after`、`pathway hold`、`wr_ptr restore`。
4. 用端到端验证和 train convergence 把系统正确性证明出来。

---

## 6. 高频追问，一句先答什么

### Q1 你到底做成了什么？
我做成的是 SoC 级训练闭环，不是单点计算 demo。

### Q2 为什么不是推理 demo？
因为结果会从 VPU 写回 UB，继续参与 backward 和 update。

### Q3 编译器怎么对上 RTL？
软件生成 32-bit 控制字，RTL 按位 decode 成执行字段。

### Q4 UB 为什么难？
因为它承载了多语义数据区、指针恢复和阶段边界。

### Q5 怎么证明跑对？
波形证明时序，收敛证明语义，二者一起才算系统正确。

### Q6 你最难的工作是什么？
把软件、控制、执行和验证接成闭环，并把阶段边界 bug 修稳。

---

## 7. 最容易被打断的地方

### 风险 1
一开口就钻细节。

修正：
先讲主线，再钻模块。

### 风险 2
把 UB 讲成普通 RAM。

修正：
强调它是训练数据流和阶段边界汇合点。

### 风险 3
只讲波形，不讲收敛。

修正：
一定补一句 train convergence 是系统级语义证据。

### 风险 4
只说自己写了模块，不说系统价值。

修正：
最后一定落回“闭环”和“跨层联调”。

---

## 8. 最后 15 秒收尾模板

这个项目最有价值的地方，不是做了一个小 TPU，
而是把编译器、控制、执行和验证真正接成了一条可证明的训练闭环。
我觉得这里最能体现的是系统工程和跨层联调能力。

---

## 9. 上台前最后看什么

如果只剩 3 分钟：
- 看这份速记版
- 看 `01_main_8p.pptx`

如果只剩 30 秒：
- 背熟开场 20 秒
- 背熟最后 15 秒收尾
- 记住 6 个高频追问的一句答法

一句话：
**主线比细节更重要，闭环比模块名更重要，证据比口头描述更重要。**
