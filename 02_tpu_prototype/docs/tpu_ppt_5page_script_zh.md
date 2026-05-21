# TinyTPU AXI-Lite SoC 面试 PPT 逐页文案（5 页）

## 使用方式

- 每页分成三部分：`页标题`、`页内文字`、`口述稿`。
- `页内文字` 直接放 PPT。
- `口述稿` 控制在 40 到 70 秒，按这个讲基本不会超时。
- 主图统一使用：`docs/tpu_project_architecture_16x9_zh.png`

---

## P1 项目定义

### 页标题

`TinyTPU AXI-Lite SoC：从裸 RTL 到训练闭环原型`

### 页内文字

一句话定位：
- 把原来主要靠 testbench 直驱的 tiny-tpu RTL，补成带 AXI-Lite 前端、IMEM 和 sequencer 的 SoC 原型。

我负责的三件事：
- SoC 前端与控制链路
- 指令化执行与 IMEM 驱动
- cocotb 闭环验证与关键 bug 收敛

当前验证范围：
- `2x2 tiny-tpu`
- `Q8.8 fixed-point`
- `2-layer MLP / XOR`
- `59 条 IMEM 指令`

### 口述稿

“这个项目我做的重点不是单个算子，而是把原来偏裸 RTL、主要靠 testbench 直接驱动的 tiny-tpu，补成一个可控、可验证的 SoC 原型。具体来说，我补了 AXI-Lite 前端、IMEM 和 sequencer，让整个系统可以通过寄存器配置、加载指令、启动执行，再到结果回读。然后我又把当前 2x2、Q8.8、2-layer MLP 的流程做成了 59 条 IMEM 指令，并且用 cocotb 把单次 e2e 和多 epoch 训练闭环都验证起来。所以这个项目我更愿意把它定义成系统集成、控制链路和验证闭环，而不是只做了一个接口壳。”

### 页面建议

- 左侧放标题和一句话定位。
- 右侧放 4 个数字标签：`2x2`、`Q8.8`、`59 条指令`、`41/41 PASS`。

---

## P2 整体架构

### 页标题

`整体架构：软件驱动 -> SoC 控制 -> 计算核心 -> 验证闭环`

### 页内文字

主图：
- `docs/tpu_project_architecture_16x9_zh.png`

你要强调的四层：
- 软件与驱动：模型规格、scheduler、编码器、cocotb、directed bench
- SoC 控制与执行：AXI-Lite 前端、寄存器堆、IMEM、sequencer、tpu_soc
- 计算核心：UB、Systolic Array、VPU、参数更新路径
- 验证与结果：scoreboard、收敛验证、最终结果

### 口述稿

“这页我主要讲整个项目的总链路。最左边是软件和驱动层，包括模型规格、scheduler、指令编码，还有 cocotb 和 directed bench。中间一层是 SoC 控制与执行层，Host 通过 AXI-Lite 写寄存器、写 IMEM，再由 sequencer 把 IMEM 指令逐条打给 `tpu_soc`。再往右是计算核心层，包括 Unified Buffer、2x2 的 systolic array、VPU 算子链，以及参数更新和回写路径。最后一层是验证与结果层，硬件输出会被 cocotb 的 scoreboard 检查，同时再看多 epoch 的收敛趋势和最终 XOR 分类结果。也就是说，这个项目不是只把接口接上，而是软件驱动、控制链路、计算执行和验证闭环都连起来了。”

### 页面建议

- 这一页尽量少字，核心靠你讲图。
- 讲的时候严格按左到右顺序走，不要来回跳。

---

## P3 控制与执行链路

### 页标题

`AXI-Lite + IMEM + Sequencer 如何驱动 TPU`

### 页内文字

关键模块：
- `src_axi/tpu_frontend_axil.sv`
- `src_axi/tpu_soc.sv`
- `src_axi/control_unit.sv`
- `compiler/scheduler.py`
- `compiler/encode_instrs.py`

关键机制：
- AXI-Lite 前端负责寄存器写入、状态读取、IMEM 装载
- `wait_after` 显式控制等待语义
- `seq_instr_pulse` 负责把当前指令打一拍送到控制链路
- `vpu_data_pathway` 需要保持，而不是只在 dispatch 当拍有效

### 口述稿

“这一页我想强调的是，控制链路是怎么把 TPU 从 testbench 直驱变成可编程原型的。Host 侧通过 AXI-Lite 把数据和参数写进去，同时把 scheduler 编码好的 IMEM 指令装进去。前端模块 `tpu_frontend_axil.sv` 一方面做寄存器堆和状态控制，另一方面驱动 sequencer。sequencer 再把每条 IMEM 指令打一拍，也就是 `seq_instr_pulse`，送到控制链路。这里有两个实现细节我会重点讲：第一，等待语义不是隐式推出来的，而是由 IMEM 里的 `wait_after` 位显式控制；第二，`vpu_data_pathway` 不能只在 dispatch 当拍有效，因为 systolic 输出会晚几拍到，所以它必须被寄存起来保持。控制链路打通以后，整个 tiny-tpu 才真正变成一个寄存器可控、指令可控的原型。”

### 页面建议

- 用整体架构图裁出中间两列：`软件与驱动 + SoC 控制`。
- 右下角小字列 4 个关键词：`AXI-Lite`、`IMEM`、`wait_after`、`seq_instr_pulse`。

---

## P4 实现细节与关键 Bug

### 页标题

`实现细节与 3 个关键问题收敛`

### 页内文字

Bug 1：host write 无效
- 现象：AXI 写了 UB，但 `wr_ptr` 不动
- 根因：frontend 到 UB 的有效信号没有被正确采样
- 修复：桥接 host valid，确保写使能真正进入 UB

Bug 2：`vpu_data_pathway` 不保持
- 现象：dispatch 后几拍 pathway 变 0，VPU 直接 bypass
- 根因：控制只在当前拍有效，没覆盖后续流水线延迟
- 修复：在 sequencer 侧 latch pathway

Bug 3：wait 逻辑卡死
- 现象：sequencer 消耗错了 drain 事件，后续阶段不再推进
- 根因：等待语义靠隐式规则推断，边界不稳
- 修复：改成 IMEM 显式 `wait_after`

### 口述稿

“这一页我只讲三个最能体现工程能力的问题。第一个是 host write 无效，现象是 AXI 明明把数据写进去了，但 UB 这边 `wr_ptr` 不动，最后我定位到 frontend 到 UB 的有效写信号没有被正确采样，修完之后 host load 才真正打通。第二个是 `vpu_data_pathway` 不保持，问题在于 dispatch 当拍控制是对的，但 systolic 的输出要过几拍才到，这时 pathway 已经掉回 0 了，导致本来该经过 bias 和激活的数据被错误 bypass，最后是通过寄存器保持修掉。第三个是 wait 逻辑卡死，早期用隐式规则推等待，结果 drain 事件被前一条指令提前消费掉，后面的阶段永远等不到，我最后把等待语义改成 IMEM 显式 `wait_after`，状态机就稳定了。这三个问题基本覆盖了接口、流水线保持和状态机语义三个层面。”

### 页面建议

- 不要堆太多代码截图。
- 每个 bug 最多三行，靠你口头展开。
- 如果时间紧，这一页就只讲前两个 bug。

---

## P5 验证结果与边界

### 页标题

`验证结果、项目价值与边界`

### 页内文字

结果：
- 单次 e2e：`41 / 41 PASS`
- 多 epoch：`12 epoch, loss 0.2529 -> 0.1777`
- 最终 XOR：`(0, 1, 1, 0)`
- pipeline 变体：`164.10 -> 183.91 MHz`

项目价值：
- 接口补齐
- 控制链路补齐
- 验证闭环补齐
- 关键 bug 能收敛到模块和信号级

边界：
- 当前 tiny-tpu 原型
- 当前网络规模与数据格式下验证扎实
- 不是通用编译器
- 不是完整 DMA/IRQ SoC

### 口述稿

“最后一页我主要给出结果和边界。验证结果上，单次 AXI e2e 已经做到 41/41 PASS，覆盖 H1、dZ2、dZ1 和 UB update；多 epoch 训练在当前 XOR 配置下也能收敛，12 个 epoch 后 loss 从 0.2529 降到 0.1777，最终预测是 `(0,1,1,0)`。如果补充一个实现亮点，pipeline 变体还把 Fmax 从 164.10MHz 提到了 183.91MHz。这个项目对我来说最核心的价值，不是把故事讲得很大，而是把边界讲清楚的前提下，把系统集成、控制链路、验证闭环和关键 bug 收敛都做扎实。边界上我会明确说，这是当前 tiny-tpu 原型，在当前网络规模和 Q8.8 固定点配置下验证得比较完整，但我不会把它讲成通用编译器或者完整 DMA/IRQ SoC。”

### 页面建议

- 这页结束时一定主动补一句“边界我会守住”。
- 面试官一般会在这一页开始追问，正好切到你最熟的 bug 和验证故事。

---

## 30 秒收尾版

如果时间突然被压缩到 30 秒，可以只说：

“我这个项目的核心，是把原来偏裸 RTL 的 tiny-tpu，补成了带 AXI-Lite 前端、IMEM 和 sequencer 的 SoC 原型，并用 cocotb 把单次 e2e 和多 epoch 训练闭环都验证起来。当前结果是 41/41 PASS，12 个 epoch 后 loss 从 0.2529 降到 0.1777，最终 XOR 分类正确。我会把它定义成系统集成、控制链路和验证闭环项目，而不是只做了一个接口壳。”
