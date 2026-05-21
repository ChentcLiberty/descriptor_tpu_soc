# TinyTPU AXI-Lite SoC 面试 PPT 提纲（5 页）

## P1 项目定义

标题建议：`TinyTPU AXI-Lite SoC：从裸 RTL 到训练闭环原型`

讲述目标：
- 原始 tiny-tpu 主要靠 testbench 直驱 RTL。
- 我的工作不是单个算子，而是把它补成可控、可验证的 SoC 原型。
- 当前范围聚焦 `2x2 / Q8.8 / XOR / 2-layer MLP`。

建议保留数据：
- `59` 条 IMEM 指令
- `41/41 PASS`
- `12 epoch: 0.2529 -> 0.1777`
- `XOR = (0,1,1,0)`

## P2 整体架构

主图：`docs/tpu_project_architecture_16x9_zh.png`

讲述顺序：
1. 软件与驱动层：模型规格、scheduler、encode、cocotb、directed bench
2. SoC 控制层：AXI-Lite 前端、寄存器、IMEM、sequencer、tpu_soc
3. 计算核心层：UB、systolic、VPU、gradient_descent/update
4. 验证与结果层：scoreboard、收敛验证、最终结果

这一页只讲架构关系，不讲细枝末节。

## P3 控制与执行链路

标题建议：`AXI-Lite + IMEM + Sequencer 如何驱动 TPU`

重点：
- AXI-Lite 前端负责寄存器写入、IMEM 装载、start/status。
- `wait_after` 显式控制 sequencer 的等待语义。
- `seq_instr_pulse` 把 IMEM 指令打到控制链路。
- 当前实现让原本 testbench 直驱的 TPU 变成“寄存器可控、指令可控”的原型。

建议配图：
- 用当前总图裁出 `软件与驱动 + SoC 控制` 两列。

## P4 实现细节与关键 Bug

标题建议：`实现细节与 3 个关键问题收敛`

建议只讲 3 个：
- host write 无效：AXI 写入到了，但 UB 不采样。
- `vpu_data_pathway` 不保持：dispatch 后几拍数据被错误 bypass。
- wait 逻辑卡死：错误消费 drain 事件，sequencer 无法推进。

每个 bug 只讲四句话：
- 现象
- 根因
- 修复动作
- 如何验证

## P5 验证结果与边界

标题建议：`验证结果、可对外表述边界、项目价值`

重点：
- 单次 e2e：`41/41 PASS`
- 多 epoch：`12 epoch loss 0.2529 -> 0.1777`
- 最终 XOR：`(0,1,1,0)`
- pipeline 变体：`164.10 -> 183.91 MHz`

边界一定说明：
- 当前 tiny-tpu 原型
- 不是通用编译器
- 不是完整 DMA/IRQ SoC
- 但在当前规模下，系统集成、控制链路、验证闭环是扎实的

## 结论

5 页是够的，不需要再扩页。
真正容易超时的不是页数，而是 P4 讲 bug 时铺得太开。建议把 P4 严格限制在 3 个问题以内。
