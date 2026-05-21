# TinyTPU AXI-Lite SoC PPT 最终短句版（5 页）

适用场景：直接复制到 PPT 页面中。
原则：每页只保留最短、最稳、最容易讲清的文字。

---

## P1 项目定义

### 标题

`TinyTPU AXI-Lite SoC：从裸 RTL 到训练闭环原型`

### 副标题

`系统集成 + 指令化执行 + cocotb 闭环验证`

### 页面文案

- 原始 tiny-tpu 主要靠 testbench 直驱 RTL
- 我把它补成了带 AXI-Lite 前端、IMEM 和 sequencer 的 SoC 原型
- 当前验证范围：`2x2 / Q8.8 / 2-layer MLP / XOR`
- 当前执行规模：`59 条 IMEM 指令`

### 页脚强调

`重点不是单个算子，而是把控制链路和验证闭环补完整。`

---

## P2 整体架构

### 标题

`整体架构：软件驱动 -> SoC 控制 -> 计算核心 -> 验证结果`

### 页面文案

- 软件与驱动：模型规格、scheduler、编码器、cocotb、directed bench
- SoC 控制：AXI-Lite 前端、寄存器堆、IMEM、sequencer、tpu_soc
- 计算核心：UB、Systolic Array、VPU、参数更新路径
- 验证结果：scoreboard、收敛验证、最终 XOR 分类

### 配图

- 插入：`docs/tpu_project_architecture_16x9_zh.png`

### 页脚强调

`这张图讲的是整条闭环，不只是 SoC 连线。`

---

## P3 控制与执行链路

### 标题

`AXI-Lite + IMEM + Sequencer 如何驱动 TPU`

### 页面文案

- AXI-Lite 前端负责寄存器写入、状态读取和 IMEM 装载
- `wait_after` 显式定义等待语义，避免隐式推断不稳定
- `seq_instr_pulse` 把当前指令打一拍送到控制链路
- `vpu_data_pathway` 需要保持，覆盖后续流水线延迟

### 右下角关键词

- `AXI-Lite`
- `IMEM`
- `wait_after`
- `seq_instr_pulse`

### 页脚强调

`控制链路打通之后，TPU 才真正变成寄存器可控、指令可控的原型。`

---

## P4 实现细节与关键 Bug

### 标题

`实现细节与 3 个关键问题收敛`

### 页面文案

- Host write 无效：AXI 写入到了，但 UB 不采样
- `vpu_data_pathway` 不保持：dispatch 后几拍错误 bypass
- wait 逻辑卡死：错误消费 drain 事件，状态机无法推进

### 每个问题统一表达

- 现象
- 根因
- 修复动作
- 如何验证

### 页脚强调

`这页不要铺太开，最多讲 3 个问题。`

---

## P5 验证结果与边界

### 标题

`验证结果、项目价值与边界`

### 页面文案

- 单次 e2e：`41 / 41 PASS`
- 多 epoch：`12 epoch, loss 0.2529 -> 0.1777`
- 最终 XOR：`(0, 1, 1, 0)`
- pipeline 变体：`164.10 -> 183.91 MHz`

### 边界说明

- 当前 tiny-tpu 原型
- 当前网络规模与 Q8.8 配置下验证扎实
- 不是通用编译器
- 不是完整 DMA / IRQ SoC

### 页脚强调

`边界讲清楚，反而更显得项目扎实。`

---

## 开场 20 秒版本

`这个项目我做的重点不是单个算子，而是把原来主要靠 testbench 直驱的 tiny-tpu，补成了带 AXI-Lite 前端、IMEM 和 sequencer 的 SoC 原型，并用 cocotb 把单次 e2e 和多 epoch 训练闭环验证跑通。`

## 收尾 20 秒版本

`所以我会把这个项目定义成系统集成、控制链路和验证闭环项目。当前范围我讲得比较克制，只覆盖 tiny-tpu 原型、当前网络规模和当前验证链路，但这部分我做得比较扎实。`
