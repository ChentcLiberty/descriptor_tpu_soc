# `tpu_soc.sv` 小白版逐段细讲

对应源码：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/06_tpu_soc.sv`

原版讲解：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/07_tpu_soc.sv_guide_zh.md`

建议先看前一份：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/06A_tpu_frontend_axil.sv_beginner_line_by_line_zh.md`

前一份讲的是：

**Frontend 怎么通过 AXI-Lite、IMEM、sequencer 发出 TPU 控制信号。**

这一份讲的是：

**SoC 顶层怎么把 Frontend 和真正的 TPU core 接成一个完整系统。**

---

## 0. 先给这个文件定位

`tpu_soc.sv` 不是算法文件。

它不做矩阵乘法。

它不做激活函数。

它不做梯度下降。

它主要做一件事：

**把 Host 可控的 Frontend 和真正执行计算的 `tpu.sv` core 接起来。**

你可以先把它理解成一张硬件连线图。

它解决的问题是：

```text
Host / AXI-Lite
  -> tpu_frontend_axil.sv
  -> tpu.sv
  -> VPU/Systolic 输出
  -> 再反馈给 Frontend 判断完成
```

所以如果只记一句话：

**`tpu_soc.sv` 是整个项目从“TPU 裸核”变成“Host 可控 SoC 原型”的顶层包装层。**

---

## 1. 为什么这一份要接在 `tpu_frontend_axil.sv` 后面看

前一份 `tpu_frontend_axil.sv` 已经讲了：

- Host 写 `0x020/0x028/0x024`，Frontend 生成 UB host write。
- Host 写 `0x030/0x034/0x040/0x044`，Frontend 装 IMEM。
- Host 写 `0x000 = 0x2`，Frontend 产生 `start_pulse`。
- Sequencer 发 `ub_rd_start / sys_switch / vpu_data_pathway`。
- Frontend 通过 `tpu_vpu_valid_in` 形成 `vpu_drain`。

但前一份还没回答一个问题：

**Frontend 这些输出到底接到哪里？**

`tpu_soc.sv` 就回答这个问题。

它把 Frontend 输出接到 `tpu.sv` 的输入。

并且把 `tpu.sv` 的 `vpu_valid_out_1/2` OR 回 Frontend。

这就是系统闭环。

---

## 2. 第 1 到 2 行：基础编译规则

对应源码：

```systemverilog
`timescale 1ns/1ps
`default_nettype none
```

### 2.1 `timescale`

表示仿真时间单位是 `1ns`，精度是 `1ps`。

### 2.2 `default_nettype none`

表示禁止 Verilog 自动创建隐式 wire。

小白理解：

**写错信号名时，不允许工具悄悄帮你生成一个新线网。**

这能减少拼写错误带来的隐藏 bug。

---

## 3. 第 4 到 11 行：文件头注释里有一个历史残留

对应源码：

```systemverilog
// TinyTPU SoC Top
// Wraps tpu_frontend_axil + tpu into a single AXI-Lite controlled accelerator.
//
// CPU controls TPU via AXI-Lite:
//   - Load data into UB via UB_DATA / UB_PUSH registers
//   - Stage an 88-bit instruction via INSTR_W0/W1/W2
//   - Dispatch it with CTRL.step=1
//   - Wait enough cycles, then dispatch next instruction
```

### 3.1 前两句是当前仍然正确的

```systemverilog
// TinyTPU SoC Top
// Wraps tpu_frontend_axil + tpu into a single AXI-Lite controlled accelerator.
```

这两句说明：

**这个文件把 `tpu_frontend_axil` 和 `tpu` 包成一个 AXI-Lite 可控加速器。**

这是 `tpu_soc.sv` 的核心定位。

### 3.2 后面几句有历史残留

注释里写了：

```systemverilog
//   - Stage an 88-bit instruction via INSTR_W0/W1/W2
//   - Dispatch it with CTRL.step=1
//   - Wait enough cycles, then dispatch next instruction
```

这更像早期 step-mode 的旧设计描述。

但当前你正在看的实现已经是：

- 32-bit opcode instruction。
- IMEM 装载。
- `CTRL.start` 自动从 `imem[0]` 开始跑。
- `wait_after` bit23 + `SEQ_WAIT` + `vpu_drain`。

所以看这个文件时要以实际代码为准。

可以在面试里说：

**文件头注释里还留着旧版 88-bit step-mode 描述，但当前主线已经演进成 32-bit IMEM/sequencer 自动运行路径。**

这不是坏事，反而说明你真的看过源码，不是背 PPT。

---

## 4. 第 13 到 15 行：module 名和参数

对应源码：

```systemverilog
module tpu_soc #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2
)(
```

### 4.1 `tpu_soc`

这是 SoC 顶层模块名。

测试脚本和 testbench 最终会实例化这个顶层，或者实例化包装它的 testbench top。

### 4.2 `SYSTOLIC_ARRAY_WIDTH = 2`

当前项目是 2x2 systolic array。

所以默认宽度是 `2`。

这也解释了为什么后面很多信号有 lane0/lane1 或 out_1/out_2 两路。

---

## 5. 第 16 到 39 行：AXI-Lite slave 接口

对应源码：

```systemverilog
input  logic        s_axil_aclk,
input  logic        s_axil_aresetn,

input  logic [11:0] s_axil_awaddr,
input  logic        s_axil_awvalid,
output logic        s_axil_awready,

input  logic [31:0] s_axil_wdata,
input  logic [3:0]  s_axil_wstrb,
input  logic        s_axil_wvalid,
output logic        s_axil_wready,

output logic [1:0]  s_axil_bresp,
output logic        s_axil_bvalid,
input  logic        s_axil_bready,

input  logic [11:0] s_axil_araddr,
input  logic        s_axil_arvalid,
output logic        s_axil_arready,

output logic [31:0] s_axil_rdata,
output logic [1:0]  s_axil_rresp,
output logic        s_axil_rvalid,
input  logic        s_axil_rready,
```

这段定义了 SoC 对 Host 暴露的控制接口。

### 5.1 小白怎么理解 AXI-Lite

AXI-Lite 可以先理解成：

**Host 通过固定地址读写寄存器。**

例如测试脚本里：

```python
await axil_write(dut, 0x000, 0x2)
status = await axil_read(dut, 0x004)
```

这些最终就是走这里的 AXI-Lite 信号。

### 5.2 为什么 AXI-Lite 在 `tpu_soc.sv` 顶层暴露

因为 `tpu_soc.sv` 是外部系统看到的加速器顶层。

Host 不应该直接看到内部的 `ub_rd_start`、`sys_switch`、`vpu_data_pathway`。

Host 只需要看到一套标准寄存器接口。

Frontend 再把寄存器写操作翻译成内部控制信号。

### 5.3 这一段你应该记住什么

**`tpu_soc.sv` 的外部控制边界就是 AXI-Lite。**

这就是它成为 SoC 原型的关键。

---

## 6. 第 41 到 52 行：对外可观测输出

对应源码：

```systemverilog
output logic [15:0] vpu_data_out_1,
output logic [15:0] vpu_data_out_2,
output logic        vpu_valid_out_1,
output logic        vpu_valid_out_2,

output logic [15:0] sys_data_out_21,
output logic [15:0] sys_data_out_22,
output logic        sys_valid_out_21,
output logic        sys_valid_out_22
```

这些是从 TPU core 暴露到 SoC 顶层的观测信号。

### 6.1 VPU 输出

```systemverilog
vpu_data_out_1
vpu_data_out_2
vpu_valid_out_1
vpu_valid_out_2
```

这两路是 VPU 输出数据和 valid。

它们很重要，因为：

- 测试可以观察 VPU 输出结果。
- Frontend 也会用 valid 来判断 `vpu_drain`。

### 6.2 systolic 输出

```systemverilog
sys_data_out_21
sys_data_out_22
sys_valid_out_21
sys_valid_out_22
```

这些是 systolic array 的输出。

它们便于验证矩阵乘加的中间结果。

### 6.3 为什么要暴露这些信号

因为项目验证需要可观测性。

如果顶层完全封死，你很难在 testbench 或波形里判断：

- systolic 是否出数。
- VPU 是否出数。
- valid 是否正常。
- drain 边界是否成立。

所以这几个输出让系统不是黑盒。

一句话：

**`tpu_soc.sv` 不只让系统可控，也让系统可观测。**

---

## 7. 第 55 到 57 行：Frontend 和 TPU core 之间的时钟复位线

对应源码：

```systemverilog
// Internal wires between frontend and TPU core
logic clk, rst;
```

`clk` 和 `rst` 是内部连线。

它们由 Frontend 输出：

```systemverilog
.clk_out (clk)
.rst_out (rst)
```

然后送给 TPU core：

```systemverilog
.clk (clk)
.rst (rst)
```

这表示当前原型里：

**Frontend 负责把 AXI-Lite 时钟/复位整理后传给 TPU core。**

前一份已经讲过，Frontend 里是：

```systemverilog
assign clk_out = s_axil_aclk;
assign rst_out = ~s_axil_aresetn;
```

所以这里本质是把 AXI-Lite 的低有效 reset 转成 TPU core 的高有效 reset 后继续传下去。

---

## 8. 第 59 到 62 行：Host 写 UB 的内部桥接信号

对应源码：

```systemverilog
logic [15:0] ub_wr_host_data_0, ub_wr_host_data_1;
logic        ub_wr_host_valid_0, ub_wr_host_valid_1;
logic        ub_wr_ptr_restore;
```

这组信号来自 Frontend，送往 TPU core 的 UB。

### 8.1 `ub_wr_host_data_0/1`

Host 要写进 UB 的两路 16-bit 数据。

对应前一份里的：

```text
0x020 -> lane0 data
0x028 -> lane1 data
```

### 8.2 `ub_wr_host_valid_0/1`

Host 写 UB 的 valid 脉冲。

对应前一份里的：

```text
0x024 -> UB_PUSH mask
```

### 8.3 `ub_wr_ptr_restore`

这个信号来自：

```systemverilog
ub_wr_ptr_restore_out = start_pulse;
```

也就是说 Host 写 start 时，Frontend 会让 UB 写指针恢复到运行边界。

这对多轮训练很重要。

否则上一轮训练写回的位置可能影响下一轮。

---

## 9. 第 63 到 69 行：为什么要把标量桥接成数组

对应源码：

```systemverilog
// Bridge scalars to unpacked arrays for tpu.sv ports
logic [15:0] ub_wr_host_data [0:SYSTOLIC_ARRAY_WIDTH-1];
logic        ub_wr_host_valid [0:SYSTOLIC_ARRAY_WIDTH-1];
assign ub_wr_host_data[0]  = ub_wr_host_data_0;
assign ub_wr_host_data[1]  = ub_wr_host_data_1;
assign ub_wr_host_valid[0] = ub_wr_host_valid_0;
assign ub_wr_host_valid[1] = ub_wr_host_valid_1;
```

这一段不是算法逻辑，是接口适配。

### 9.1 Frontend 侧是什么形式

Frontend 输出的是分开的标量端口：

```text
ub_wr_host_data_out_0
ub_wr_host_data_out_1
ub_wr_host_valid_out_0
ub_wr_host_valid_out_1
```

### 9.2 TPU core 侧是什么形式

`tpu.sv` 输入是 unpacked array：

```systemverilog
input logic [15:0] ub_wr_host_data_in [0:SYSTOLIC_ARRAY_WIDTH-1]
input logic        ub_wr_host_valid_in [0:SYSTOLIC_ARRAY_WIDTH-1]
```

所以 `tpu_soc.sv` 必须在中间做桥接。

### 9.3 小白该怎么理解

这就像把两个单独的口：

```text
data_0, data_1
```

整理成一个数组：

```text
data[0], data[1]
```

这样才能接到 `tpu.sv`。

一句话：

**`tpu_soc.sv` 还负责做端口形状适配，不只是简单直连。**

---

## 10. 第 71 到 82 行：Frontend 输出的控制语义信号

对应源码：

```systemverilog
logic        sys_switch;
logic        ub_rd_start;
logic        ub_rd_transpose;
logic [1:0]  ub_rd_col_size;
logic [3:0]  ub_rd_row_size;
logic [5:0]  ub_rd_addr;
logic [2:0]  ub_ptr_sel;
logic [3:0]  vpu_data_pathway;
logic [15:0] inv_batch_size_times_two;
logic [15:0] vpu_leak_factor;
logic [15:0] learning_rate;
```

这组信号就是前一份 Frontend 讲的控制输出。

### 10.1 `sys_switch`

控制 systolic array 权重从 shadow 切到 active。

对应 `SWITCH` 指令。

### 10.2 `ub_rd_start`

启动一次 UB 读。

对应 `UB_RD` 指令。

### 10.3 `ub_rd_transpose`

告诉 UB 本次读是否转置。

例如加载权重到 systolic 顶部时可能要转置。

### 10.4 `ub_rd_col_size / ub_rd_row_size / ub_rd_addr`

告诉 UB：

- 从哪里读。
- 读多少行。
- 读多少列。

### 10.5 `ub_ptr_sel`

告诉 UB 当前读的语义是什么。

比如 input、weight、bias、Y、H、grad_bias、grad_weight。

### 10.6 `vpu_data_pathway`

告诉 VPU 当前走哪条路径。

比如 forward、loss、backward derivative、gradient descent 等。

### 10.7 `inv_batch_size_times_two / vpu_leak_factor / learning_rate`

这些是训练参数。

来自 Host 写的配置寄存器。

它们会送到 TPU core，再送给 VPU/UB 内部需要的模块。

### 10.8 这一段你应该记住什么

**这些信号就是 Frontend 到 TPU core 的“控制语义总线”。**

---

## 11. 第 84 到 91 行：UB read 输出暂存在顶层内部

对应源码：

```systemverilog
// UB read outputs (not exposed at SoC top in this version)
logic [15:0] ub_rd_input_data_out_0, ub_rd_input_data_out_1;
logic        ub_rd_input_valid_out_0, ub_rd_input_valid_out_1;
logic [15:0] ub_rd_weight_data_out_0, ub_rd_weight_data_out_1;
logic        ub_rd_weight_valid_out_0, ub_rd_weight_valid_out_1;
```

这组信号是 `tpu.sv` 暴露出来的 UB 读流。

但当前 SoC 顶层没有把它们作为 output 暴露到模块外。

所以注释写：

```text
not exposed at SoC top in this version
```

### 11.1 为什么保留这些内部线

因为 `tpu_inst` 的端口需要连接。

如果 `tpu.sv` 有这些输出端口，顶层实例化时就要接线。

哪怕当前不对外暴露，也需要内部 wire 接住。

### 11.2 这说明什么

说明当前 SoC 顶层只对外暴露了部分观测信号：

- VPU 输出。
- systolic 输出。

UB 读流暂时只在顶层内部连线，不作为外部 output。

这是一个工程取舍。

---

## 12. 第 96 到 98 行：实例化 Frontend

对应源码：

```systemverilog
tpu_frontend_axil #(
    .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
) frontend (
```

这里创建了一个 Frontend 实例，名字叫 `frontend`。

### 12.1 参数传递

```systemverilog
.SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
```

意思是：

顶层 `tpu_soc` 的 array width 参数传给 Frontend。

这样两边都知道当前是几 lane/几列系统。

### 12.2 为什么 Frontend 在 SoC 顶层实例化

因为 Frontend 是 Host 控制入口。

SoC 顶层必须把 AXI-Lite 接进 Frontend。

然后再把 Frontend 的输出接到 TPU core。

这正是 `tpu_soc.sv` 的主要职责。

---

## 13. 第 99 到 116 行：AXI-Lite 端口原样接给 Frontend

对应源码：

```systemverilog
.s_axil_aclk    (s_axil_aclk),
.s_axil_aresetn (s_axil_aresetn),

.s_axil_awaddr  (s_axil_awaddr),
.s_axil_awvalid (s_axil_awvalid),
.s_axil_awready (s_axil_awready),

.s_axil_wdata   (s_axil_wdata),
.s_axil_wstrb   (s_axil_wstrb),
.s_axil_wvalid  (s_axil_wvalid),
.s_axil_wready  (s_axil_wready),
...
```

这段几乎都是同名连接。

意思是：

**SoC 顶层收到的 AXI-Lite 信号，直接交给 Frontend 处理。**

`tpu_soc.sv` 自己不解码 AXI 地址。

AXI 地址 decode 在 `tpu_frontend_axil.sv` 里。

小白可以这样理解：

```text
外部 Host -> tpu_soc 端口 -> frontend 端口 -> frontend 内部寄存器 decode
```

---

## 14. 第 117 行：最关键的反馈闭环 `tpu_vpu_valid_in`

对应源码：

```systemverilog
.tpu_vpu_valid_in (vpu_valid_out_1 | vpu_valid_out_2),
```

这行非常重要。

它把 TPU core 的两路 VPU valid 做 OR，然后送回 Frontend。

### 14.1 为什么要 OR 两路 valid

当前系统宽度是 2，所以 VPU 有两路输出 valid：

```text
vpu_valid_out_1
vpu_valid_out_2
```

只要任意一路还在输出，就说明 VPU 还没完全 drain。

所以要用：

```systemverilog
vpu_valid_out_1 | vpu_valid_out_2
```

表示整体 VPU 仍有有效输出。

### 14.2 Frontend 拿它做什么

前一份里讲过，Frontend 内部有：

```systemverilog
vpu_valid_prev <= tpu_vpu_valid_in;
vpu_drain      <= vpu_valid_prev && !tpu_vpu_valid_in;
```

所以这条线是 `vpu_drain` 的输入来源。

### 14.3 为什么说这是闭环

因为链路是：

```text
Frontend 发 instruction
  -> TPU core 执行
  -> VPU 输出 valid
  -> tpu_soc OR valid
  -> 回送 Frontend
  -> Frontend 判断 drain 后 advance
```

这就是控制闭环。

如果没有这条线，Frontend 只能猜测什么时候完成。

有了这条线，Frontend 才能用真实执行结果判断阶段边界。

面试可以直接说：

**`tpu_soc.sv` 最关键的一条反馈线，是把 `vpu_valid_out_1 | vpu_valid_out_2` 回送给 Frontend，作为 `vpu_drain` 的来源。**

---

## 15. 第 119 到 122 行：Frontend 输出时钟、复位、Host 写 UB

对应源码：

```systemverilog
.clk_out                    (clk),
.rst_out                    (rst),

.ub_wr_host_data_out_0       (ub_wr_host_data_0),
.ub_wr_host_valid_out_0      (ub_wr_host_valid_0),
.ub_wr_host_data_out_1       (ub_wr_host_data_1),
.ub_wr_host_valid_out_1      (ub_wr_host_valid_1),
.ub_wr_ptr_restore_out       (ub_wr_ptr_restore),
```

### 15.1 `clk/rst`

Frontend 输出整理后的 `clk/rst`，后面送给 `tpu_inst`。

### 15.2 Host 写 UB 数据

Frontend 的：

```text
ub_wr_host_data_out_0/1
ub_wr_host_valid_out_0/1
```

接到顶层内部信号：

```text
ub_wr_host_data_0/1
ub_wr_host_valid_0/1
```

然后再通过数组桥接送进 `tpu.sv`。

### 15.3 `ub_wr_ptr_restore`

Frontend 的 restore 输出也接出来。

后面送进 TPU core 的 UB。

这就把 `start_pulse -> restore` 这条语义真正落到了执行核心里。

---

## 16. 第 124 到 138 行：Frontend 输出控制信号

对应源码：

```systemverilog
.sys_switch_out              (sys_switch),
.ub_rd_start_out             (ub_rd_start),
.ub_rd_transpose_out         (ub_rd_transpose),
.ub_rd_col_size_out          (ub_rd_col_size),
.ub_rd_row_size_out          (ub_rd_row_size),
.ub_rd_addr_out              (ub_rd_addr),
.ub_ptr_sel_out              (ub_ptr_sel),
.vpu_data_pathway_out        (vpu_data_pathway),
.inv_batch_size_times_two_out(inv_batch_size_times_two),
.vpu_leak_factor_out         (vpu_leak_factor),
.learning_rate_out           (learning_rate)
```

这些都是 Frontend 生成的运行控制语义。

小白可以把这一段读成：

```text
Frontend 解析 Host/IMEM/指令后，输出：
- 是否 switch 权重
- 是否启动 UB read
- UB read 地址和形状
- UB read 语义 ptr_sel
- VPU pathway
- 训练参数
```

这些信号后面全部会接到 `tpu_inst`。

所以这段是：

**控制面从 Frontend 出来的出口。**

---

## 17. 第 145 到 147 行：实例化 TPU core

对应源码：

```systemverilog
tpu #(
    .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
) tpu_inst (
```

这里创建了真正执行计算的 TPU core，实例名叫 `tpu_inst`。

`tpu.sv` 内部会继续实例化：

- `unified_buffer`
- `systolic`
- `vpu`

所以从层级上看：

```text
tpu_soc.sv
  -> tpu_frontend_axil.sv
  -> tpu.sv
       -> unified_buffer
       -> systolic
       -> vpu
```

`tpu_soc.sv` 自己不做计算。

它把控制和数据入口接到 `tpu.sv`。

---

## 18. 第 148 到 150 行：把 Frontend 的时钟复位送进 TPU core

对应源码：

```systemverilog
.clk (clk),
.rst (rst),
```

这两根线来自 Frontend。

当前项目里，Frontend 其实只是把 AXI 时钟/复位整理后输出。

所以链路是：

```text
s_axil_aclk / s_axil_aresetn
  -> frontend
  -> clk / rst
  -> tpu_inst
```

这说明当前系统是单时钟域原型。

如果以后做更真实 SoC，可能会引入 CDC，但当前主线没有复杂跨时钟域。

---

## 19. 第 152 到 154 行：Host 写 UB 和 restore 进入 TPU core

对应源码：

```systemverilog
.ub_wr_host_data_in         (ub_wr_host_data),
.ub_wr_host_valid_in        (ub_wr_host_valid),
.ub_wr_ptr_restore_in       (ub_wr_ptr_restore),
```

这三项会进入 `tpu.sv`。

在 `tpu.sv` 里，它们会继续接到 `unified_buffer`。

### 19.1 `ub_wr_host_data_in`

Host 初始装载的数据。

比如 X、Y、W、B。

### 19.2 `ub_wr_host_valid_in`

告诉 UB 当前哪一路 Host 数据有效。

### 19.3 `ub_wr_ptr_restore_in`

告诉 UB 恢复 runtime 写指针。

这条通常在每次 start 时触发。

一句话：

**Host 装载路径最终落点是 TPU core 里的 UB。**

---

## 20. 第 156 到 161 行：UB 读控制信号进入 TPU core，并做宽度适配

对应源码：

```systemverilog
.ub_rd_start_in             (ub_rd_start),
.ub_rd_transpose            (ub_rd_transpose),
.ub_ptr_select              ({6'h0, ub_ptr_sel}),       // 9-bit, extend from 3-bit
.ub_rd_addr_in              ({10'h0, ub_rd_addr}),      // 16-bit, extend from 6-bit
.ub_rd_row_size             ({12'h0, ub_rd_row_size}),  // 16-bit, extend from 4-bit
.ub_rd_col_size             ({14'h0, ub_rd_col_size}),  // 16-bit, extend from 2-bit
```

这段很重要，因为它说明 Frontend 和 TPU core 的端口宽度不完全一样。

### 20.1 前端输出比较窄

Frontend 输出：

```text
ub_ptr_sel       3 bit
ub_rd_addr       6 bit
ub_rd_row_size   4 bit
ub_rd_col_size   2 bit
```

这些宽度对当前小模型足够。

### 20.2 TPU core 接口比较宽

`tpu.sv` 输入：

```systemverilog
input logic [8:0]  ub_ptr_select
input logic [15:0] ub_rd_addr_in
input logic [15:0] ub_rd_row_size
input logic [15:0] ub_rd_col_size
```

所以顶层要补零扩展。

### 20.3 `{6'h0, ub_ptr_sel}` 是什么意思

```systemverilog
{6'h0, ub_ptr_sel}
```

这是拼接。

前面补 6 个 0，后面接 3-bit `ub_ptr_sel`。

最终变成 9-bit。

### 20.4 `{10'h0, ub_rd_addr}` 是什么意思

前面补 10 个 0，后面接 6-bit 地址。

最终变成 16-bit 地址。

### 20.5 为什么要这样做

因为当前 Frontend 指令格式比较紧凑，只需要较小字段。

但 TPU core/UB 接口保留了更宽的扩展空间。

`tpu_soc.sv` 在中间做宽度兼容。

面试可以这样讲：

**当前 32-bit 指令只编码了小模型所需的窄字段，SoC 顶层通过零扩展接入 TPU core 的宽接口，保证接口兼容和后续扩展空间。**

---

## 21. 第 163 到 169 行：训练参数、VPU pathway、switch 进入 TPU core

对应源码：

```systemverilog
.learning_rate_in           (learning_rate),

.vpu_data_pathway           (vpu_data_pathway),
.sys_switch_in              (sys_switch),
.vpu_leak_factor_in         (vpu_leak_factor),
.inv_batch_size_times_two_in(inv_batch_size_times_two),
```

这段把训练语义送进 TPU core。

### 21.1 `learning_rate`

送给 UB/梯度下降相关路径。

### 21.2 `vpu_data_pathway`

送给 VPU，告诉它当前走哪条路径。

比如：

- forward + bias + activation
- loss / derivative
- backward derivative
- gradient descent/update

### 21.3 `sys_switch`

送给 systolic array。

用于权重 shadow/active 切换。

### 21.4 `vpu_leak_factor`

送给 VPU 的 Leaky ReLU 路径。

### 21.5 `inv_batch_size_times_two`

送给 VPU loss/梯度缩放路径。

### 21.6 这一段说明什么

说明 SoC 顶层送进 TPU core 的不只是地址和 start。

它还送入了训练需要的运行参数和路径语义。

所以这个项目不是“只把一个矩阵乘法核包成 AXI 外设”，而是在接一套训练执行链。

---

## 22. 第 171 到 178 行：TPU core 的 VPU 和 systolic 输出接到 SoC 顶层

对应源码：

```systemverilog
.vpu_data_out_1             (vpu_data_out_1),
.vpu_data_out_2             (vpu_data_out_2),
.vpu_valid_out_1            (vpu_valid_out_1),
.vpu_valid_out_2            (vpu_valid_out_2),

.sys_data_out_21            (sys_data_out_21),
.sys_data_out_22            (sys_data_out_22),
.sys_valid_out_21           (sys_valid_out_21),
.sys_valid_out_22           (sys_valid_out_22),
```

这些信号从 `tpu_inst` 输出，然后直接成为 `tpu_soc` 的 output。

### 22.1 为什么 VPU 输出重要

VPU 输出既是训练路径结果，也是写回 UB 的数据来源。

在 `tpu.sv` 内部还会有：

```systemverilog
assign ub_wr_data_in[0] = vpu_data_out_1;
assign ub_wr_data_in[1] = vpu_data_out_2;
assign ub_wr_valid_in[0] = vpu_valid_out_1;
assign ub_wr_valid_in[1] = vpu_valid_out_2;
```

所以 VPU 输出不只是给外面看的。

它还是 `UB -> systolic -> VPU -> UB` 闭环的一部分。

### 22.2 为什么 systolic 输出重要

systolic 输出是 PE 阵列乘加结果。

它会进入 VPU，也被顶层暴露出来便于观察。

### 22.3 和第 117 行的关系

这里输出的：

```text
vpu_valid_out_1
vpu_valid_out_2
```

同时又在第 117 行 OR 回 Frontend：

```systemverilog
.tpu_vpu_valid_in (vpu_valid_out_1 | vpu_valid_out_2)
```

所以同一组 valid 信号有两种作用：

- 对外可观测。
- 对内反馈给 Frontend 做 drain 判断。

---

## 23. 第 180 到 187 行：UB 读流输出接住但不对外暴露

对应源码：

```systemverilog
.ub_rd_input_data_out_0     (ub_rd_input_data_out_0),
.ub_rd_input_data_out_1     (ub_rd_input_data_out_1),
.ub_rd_input_valid_out_0    (ub_rd_input_valid_out_0),
.ub_rd_input_valid_out_1    (ub_rd_input_valid_out_1),
.ub_rd_weight_data_out_0    (ub_rd_weight_data_out_0),
.ub_rd_weight_data_out_1    (ub_rd_weight_data_out_1),
.ub_rd_weight_valid_out_0   (ub_rd_weight_valid_out_0),
.ub_rd_weight_valid_out_1   (ub_rd_weight_valid_out_1)
```

这组输出是 `tpu.sv` 的 UB 读流观测端口。

当前 `tpu_soc.sv` 里只是用内部 wire 接住，没有继续暴露到 SoC 外部端口。

### 23.1 为什么不暴露也要接

因为实例化模块时，端口需要连接。

如果不连接，工具可能允许空接，但显式接住更清楚。

### 23.2 这对你读代码有什么帮助

你看到这些信号时不要误会：

它们不是从 SoC 顶层给外部 Host 的正式 output。

它们只是当前版本内部保留的 UB 读流观察线。

---

## 24. 第 190 行：模块结束

对应源码：

```systemverilog
endmodule
```

`tpu_soc.sv` 到这里结束。

你会发现它没有复杂 always 块。

这很正常。

因为它不是状态机。

真正的状态机在：

```text
tpu_frontend_axil.sv
```

真正的数据通路组合在：

```text
tpu.sv
```

`tpu_soc.sv` 主要负责：

```text
实例化 + 接线 + 接口适配 + 反馈闭环
```

---

## 25. 把整个 SoC 顶层链路串起来

你可以把 `tpu_soc.sv` 理解成下面这条链：

```text
外部 Host
  -> AXI-Lite signals
  -> tpu_soc.sv 顶层端口
  -> tpu_frontend_axil.sv
  -> ub_wr_host_* / ub_rd_* / sys_switch / vpu_pathway / training params
  -> tpu.sv
  -> unified_buffer + systolic + vpu
  -> vpu_valid_out_1/2
  -> OR 回 tpu_frontend_axil.sv
  -> 形成 vpu_drain
  -> sequencer advance
```

这就是为什么 `tpu_soc.sv` 很关键。

它把前面几份文档讲的东西真正接在一起。

---

## 26. 和 PPT 架构图怎么对应

如果你在 PPT 上讲项目顶层架构，可以这样对应：

```text
tpu_soc.sv
  外层框：AXI-Lite controlled accelerator

frontend
  控制域：AXI-Lite register file + IMEM + sequencer + control_unit

tpu_inst
  执行域：UB + systolic + VPU

vpu_valid_out_1 | vpu_valid_out_2
  反馈边：执行域回到控制域，用于 vpu_drain
```

你可以把 `tpu_soc.sv` 讲成三层：

1. 外部边界：AXI-Lite + observable outputs。
2. 控制域：`tpu_frontend_axil.sv`。
3. 执行域：`tpu.sv`。

中间最关键的箭头是：

```text
Frontend -> TPU core：控制和参数
TPU core -> Frontend：vpu_valid drain 证据
```

---

## 27. 面试时可以这样讲 `tpu_soc.sv`

如果面试官问：

**你这个顶层 SoC 是怎么接的？**

你可以答：

```text
`tpu_soc.sv` 是我的 AXI-Lite controlled accelerator 顶层。它外侧暴露 AXI-Lite slave 接口给 Host，内部实例化 `tpu_frontend_axil` 和 `tpu` 两块。

Frontend 负责 AXI 寄存器、IMEM 装载、sequencer 和 32-bit 指令发射，输出 UB 读控制、host 写 UB、systolic switch、VPU pathway 和训练参数。

`tpu.sv` 是执行核心，内部再连接 UB、systolic array 和 VPU。SoC 顶层把 Frontend 输出的窄控制字段做零扩展后接进 TPU core，同时把 VPU 的 `vpu_valid_out_1 | vpu_valid_out_2` 回送给 Frontend，作为 `vpu_drain` 的来源。

所以这个顶层不实现算法，但它完成了 Host 控制、执行核心、可观测输出和完成反馈之间的系统级闭环。
```

这段话基本覆盖了：

- AXI-Lite 外部控制。
- Frontend。
- TPU core。
- 宽度适配。
- VPU valid 回传。
- 可控、可观测、可等待的系统闭环。

---

## 28. 小白最容易混的 7 个点

### 28.1 `tpu_soc.sv` 不是 `tpu.sv`

`tpu_soc.sv` 是 SoC 包装顶层。

`tpu.sv` 是执行核心组合层。

### 28.2 `tpu_soc.sv` 不解码 AXI 寄存器

AXI-Lite 地址 decode 在 `tpu_frontend_axil.sv` 里。

`tpu_soc.sv` 只是把 AXI-Lite 端口接给 Frontend。

### 28.3 `tpu_soc.sv` 不做 instruction decode

instruction decode 在 `control_unit.sv` 里。

Frontend 实例化了 control_unit。

`tpu_soc.sv` 不直接拆 instruction bit。

### 28.4 `vpu_valid_out` 不是普通输出

它既是对外可观测输出，也是回送 Frontend 的完成证据。

这是理解 `wait_after/vpu_drain` 的关键。

### 28.5 宽度适配不是随便写的

例如：

```systemverilog
{10'h0, ub_rd_addr}
```

表示把 6-bit 前端地址扩展成 16-bit core 地址。

这是为了兼容当前紧凑指令格式和更宽的 core 接口。

### 28.6 Host 写 UB 先变成标量，再变成数组

Frontend 输出 lane0/lane1 标量。

`tpu.sv` 接受 unpacked array。

`tpu_soc.sv` 在中间做桥接。

### 28.7 文件头注释里有旧设计痕迹

注释里的 88-bit instruction 不是当前主线。

当前主线是 32-bit IMEM/sequencer。

面试时如果被问到，要按实际代码讲。

---

## 29. 最后一页总结

如果你只记 8 句话：

1. `tpu_soc.sv` 是 AXI-Lite controlled accelerator 的 SoC 顶层。
2. 它外部暴露 AXI-Lite，让 Host 能通过寄存器控制 TPU。
3. 它内部实例化 `tpu_frontend_axil` 和 `tpu`。
4. Frontend 负责寄存器、IMEM、sequencer 和控制信号输出。
5. TPU core 负责 UB、systolic、VPU 的执行数据通路。
6. `tpu_soc.sv` 负责把 Frontend 的控制信号接到 TPU core，并做标量到数组、窄字段到宽字段的接口适配。
7. `vpu_valid_out_1 | vpu_valid_out_2` 回送 Frontend，是 `vpu_drain` 的来源。
8. 所以 `tpu_soc.sv` 的价值是把 Host 控制、执行核心、可观测输出和完成反馈接成系统闭环。

最终一句话：

**`tpu_soc.sv` 不负责算，但它负责把这个 TPU 项目真正接成一个 Host 可控、结果可观测、阶段可等待的 SoC 原型。**

---

## 30. 你看完这份后，下一步看什么

下一步建议看：

```text
/home/jjt/tpu-soc/docs/code_reading_pack_20260408/08_tpu.sv_guide_zh.md
```

也就是 `tpu.sv`。

原因是：

**你现在知道 SoC 顶层怎么把 Frontend 接到 TPU core；下一步就该看 TPU core 内部怎么把 UB、systolic、VPU 接成真正的训练数据通路闭环。**

如果你继续，我下一份就做：

**`08_tpu.sv` 的同风格小白逐段细讲版。**
