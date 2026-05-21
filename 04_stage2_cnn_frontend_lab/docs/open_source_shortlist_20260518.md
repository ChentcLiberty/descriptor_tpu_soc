# Open-Source Shortlist

更新时间：2026-05-18

## 目标

为当前 `Panda CPU + shared SRAM + stage2 descriptor + real TPU wrapper` 主线找可复用的开源参考。

## 候选分类

### A. 优先参考控制/搬运骨架

#### `pulp-platform/pulpissimo`

- 价值：
  - 给出了 `uDMA + memory-mapped accelerator` 的 SoC 集成思路。
  - README 明确把 `uDMA`、`HWPE`、memory-mapped accelerator 放在同一套微控制器系统里。
- 适合借鉴：
  - 控制面怎么把 CPU、DMA、accelerator 接到统一内存空间。
  - “CPU 发命令，DMA/accelerator 自主搬运执行”的组织方式。
- 不适合直接导入：
  - 平台本身比当前 Panda SoC 复杂得多。
  - 总线和软件栈不是你当前工程的原生形态。

#### `pulp-platform/hwpe-mac-engine`

- 价值：
  - README 明确说明这是一个 `HWPE` 例子，配 `hwpe-ctrl` 和 `hwpe-stream`。
  - 非常适合拿来学“一个小型 streaming accelerator 应该怎么被 CPU 配置、怎么接数据面”。
- 适合借鉴：
  - 控制寄存器/streaming data plane 的划分。
  - 固定点流式算子最小集成壳。
- 不适合直接导入：
  - 它是 MAC 例子，不是 CNN/front-end 专用核。

#### `pulp-platform/hwpe-tb`

- 价值：
  - 提供了“RISC-V core + dummy memory + accelerator”的近独立验证壳。
- 适合借鉴：
  - 你的 `tb_panda_soc_stage2_cpu_boot_*` 之外，额外做一个更小的 `cnn_frontend` 局部验证平台。
- 不适合直接导入：
  - 还是 PULP 生态，主要用于验证方法参考。

#### `pulp-platform/iDMA`

- 价值：
  - README 把 DMA 清楚拆成 `frontend / midend / backend` 三层。
  - 这和你现在 `descriptor -> fetch -> execute -> writeback` 的 stage2 壳很容易映射。
- 适合借鉴：
  - 若后续想把 `cnn_frontend` 从“本地 SRAM 直连”扩成更通用的数据搬运器，这个分层很值得抄。
- 不适合直接导入：
  - 过于通用，直接接进来比自己在现有 stage2 壳上补一层更重。

### B. 优先参考 AXI / AXIS / 小型 buffer 积木

#### `pulp-platform/axi_stream`

- 价值：
  - 现代 SystemVerilog 写法，模块边界清晰。
  - 自带 `cut`、`downsizer`、`upsizer`、`multicut`、test utilities。
- 适合借鉴：
  - 如果把 `cnn_frontend` 切成 `fetch -> window -> conv -> pool -> writeback` 多级流水，这些 AXIS glue 很顺手。
- 风险：
  - 你当前主工程主要是平铺 `.v` 风格和 shared-SRAM/DMA 语义，不一定要全盘换成 AXIS。

#### `alexforencich/verilog-axis`

- 价值：
  - 组件全，验证基础成熟。
  - `axis_adapter`、`axis_async_fifo`、`axis_arb_mux` 这类模块都能直接当结构参考。
- 适合借鉴：
  - 做寄存器切片、宽度转换、FIFO、mux/demux。
- 风险：
  - 仓库已 deprecated，README 明确建议看 `fpganinja/taxi`。

#### `fpganinja/taxi`

- 价值：
  - `verilog-axis` 的现代延续版本，覆盖 AXI / AXIS / UART / I2C 等数据搬运积木。
  - 对后续若想把 raw signal 接成流式外设很有帮助。
- 风险：
  - 许可证是 `CERN-OHL-S` 或商业许可证，若你之后有更严格的复用边界，要先想清楚。

#### `ultraembedded/core_audio`

- 价值：
  - 不是 CNN 核，但若以后要把真实音频/时序信号采集接到 SoC，`AXI4-L + buffer + interrupt` 这种小外设壳非常贴近“前端输入”。
- 适合借鉴：
  - 输入 ring buffer、阈值中断、简单寄存器控制。
- 不适合直接导入：
  - 它解决的是采样输入，不是 CNN/FiLM 计算本身。

### C. 适合参考卷积/池化数据通路，但不适合直接做主线底座

#### `thedatabusdotio/fpga-ml-accelerator`

- 价值：
  - 结构很直白，`convolver / pooler / relu / control_logic` 这些块拆得清楚。
  - 对你要先做 `conv + pool + relu` 最小子集很有参考价值。
- 适合借鉴：
  - window/iterator 组织方式。
  - 小规模卷积核的数据路径。
- 不适合直接导入：
  - 更像教学型/博客型 CNN accelerator，不是现成 SoC IP。

#### `lulinchen/cnn_open`

- 价值：
  - README 很坦诚：只有 `conv / max_pool / relu / iterator` 四个基本模块。
  - 这个拆法和你当前问题很贴近，因为你其实不需要大而全 CNN，只要把最慢的 CPU CNN 环节硬件化。
- 适合借鉴：
  - `iterator + conv + pool` 这种最小 1D/2D 卷积壳。
- 风险：
  - 只有 1 个 commit，README 也明确说“experimental / not full optimized”。

#### `bsc-loca/sauria`

- 价值：
  - 纯 SystemVerilog，支持 on-chip `im2col` lowering。
  - 如果以后要把 front-end 做成更像通用 conv/GEMM 核，它的架构值得深读。
- 不适合直接导入：
  - 更像完整 CNN/GEMM accelerator，不是你当前这条 `1D conv + FiLM + pool + shared SRAM` 主线的最短路径。

### D. 过重或接口生态偏离，不建议直接接入当前工程

#### `nvdla/hw`

- 问题：
  - `nvdlav1` 分支是固定规模 full-precision NVDLA。
  - 自带 `cmod / verif / spec / tools`，整体明显大于你当前需要。
- 结论：
  - 适合作为“成熟 NPU 是怎么组织的”参考，不适合塞进现在的 stage2。

#### `ucb-bar/gemmini`

- 问题：
  - 是 Chisel 生成器，不是小块 RTL IP。
  - 带 scratchpad/accumulator/DMA/dataflow/runtime 假设，接入成本高。
- 结论：
  - 适合学 scratchpad、accumulator、bias load、dataflow；不适合当前直接落地。

#### `google-coral/coralnpu`

- 问题：
  - 是完整 edge NPU core，包含 `matrix / vector / scalar` 三类处理器组件。
- 结论：
  - 和当前“补一个呼吸 front-end CNN”不是同一级别的问题。

#### `BoooC/CNN-Accelerator-Based-on-Eyeriss-v2`

- 问题：
  - README 明确说当前 FPGA 版 `top control` 是按 `LeNet-5` 定制。
  - FPGA 版还不支持 ASIC 版的 NoC systolic array，也不带 pipelining。
- 结论：
  - 能学 cluster/router/dataflow 思路，但不适合作为当前主线基底。

#### `8krisv/CNN-ACCELERATOR`

- 问题：
  - 系统壳是 `NIOS II + On-Chip RAM + Avalon`。
  - 接口生态和你的 Panda/AXI/shared-SRAM 路线不一致。
- 结论：
  - 只适合看“处理器 + CNN accelerator + RAM”的系统拼法，不适合直接移植。

## 评估维度

- 是否是 RTL 为主，而不是 HLS 产物
- 是否自带 AXI / SRAM / DMA 接口
- 是否容易缩成当前呼吸前端需要的最小算子子集
- 是否会破坏现有 `launch/done/status/error` 语义
- 是否能复用现有 shared SRAM 和 descriptor ABI

## 当前推荐

不是“挑一个大项目整仓接入”，而是：

1. 保留你现在的 `descriptor + shared SRAM + stage2 wrapper` 主壳。
2. 新增一个很小的 `cnn_frontend` 或 `conv_film_frontend` 执行块。
3. 只从开源项目借：
   - `PULP` 系列的控制/streaming accelerator 组织方式
   - `axi_stream` / `verilog-axis` / `taxi` 的 glue 模块
   - `cnn_open` / `fpga-ml-accelerator` 的最小卷积/池化/iterator 思路
4. 不导入 `NVDLA / Gemmini / Coral / Eyeriss-v2 FPGA top` 这种整套架构。
