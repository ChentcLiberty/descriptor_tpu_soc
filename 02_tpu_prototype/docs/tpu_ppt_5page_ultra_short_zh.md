# TinyTPU AXI-Lite SoC PPT 超短版（5 页）

适用场景：PPT 页面字数要极少，只保留标题和 3 到 4 条短句。

---

## P1 项目定义

标题：
`TinyTPU AXI-Lite SoC 原型`

副标题：
`从裸 RTL 到训练闭环`

页面短句：
- 补齐 AXI-Lite 前端
- 补齐 IMEM + sequencer
- 跑通训练闭环验证
- 当前范围：`2x2 / Q8.8 / XOR`

---

## P2 整体架构

标题：
`整体架构`

页面短句：
- 软件驱动层
- SoC 控制层
- 计算核心层
- 验证结果层

配图：
- `docs/tpu_project_architecture_16x9_zh.png`

---

## P3 控制与执行

标题：
`控制链路`

页面短句：
- AXI-Lite 写寄存器 / IMEM
- Sequencer 分发指令
- `wait_after` 控制等待
- `seq_instr_pulse` 驱动执行

---

## P4 实现细节

标题：
`关键问题收敛`

页面短句：
- host write 无效
- pathway 不保持
- wait 逻辑卡死
- 都已定位并修复

---

## P5 结果与边界

标题：
`结果与边界`

页面短句：
- `41/41 PASS`
- `12 epoch: 0.2529 -> 0.1777`
- `XOR = (0,1,1,0)`
- 当前 tiny-tpu 原型，不夸大边界

---

## 最稳的开场句

`我这个项目的核心，是把原来偏裸 RTL 的 tiny-tpu，补成了带 AXI-Lite 前端、IMEM 和 sequencer 的 SoC 原型，并把训练闭环验证跑通。`

## 最稳的收尾句

`所以我会把它定义成系统集成、控制链路和验证闭环项目，而不是只做了一个接口壳。`
