# `tpu_frontend_axil.sv` 小白版逐段细讲

对应源码：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/05_tpu_frontend_axil.sv`

原版讲解：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/06_tpu_frontend_axil.sv_guide_zh.md`

建议先看前一份：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/05A_control_unit.sv_beginner_line_by_line_zh.md`

前一份讲的是：

**一条 32-bit instruction 怎么被 control_unit 拆成 UB / systolic / VPU 的控制信号。**

这一份讲的是：

**这些 instruction 从哪里来、什么时候发给 control_unit、什么时候等系统完成。**

---

## 0. 先给这个文件定位

`control_unit.sv` 是 decoder。

`tpu_frontend_axil.sv` 是控制入口。

你可以先把它理解成 4 个东西叠在一起：

1. AXI-Lite slave 寄存器接口。
2. Host 往 UB 写数据的入口。
3. Host 往 IMEM 装程序的入口。
4. 自动取指、发指令、等待完成的 sequencer。

如果只用一句话概括：

**`tpu_frontend_axil.sv` 把 Host 的寄存器读写，变成 TPU 内部真正执行的一轮程序。**

---

## 1. 这个文件为什么要放在 `control_unit.sv` 后面看

前一份 `control_unit.sv` 里，输入是：

```systemverilog
input logic [31:0] instruction
```

它只管拆这一条 instruction。

但它不回答这些问题：

- instruction 放在哪里？
- instruction 什么时候送进去？
- 是单步执行，还是自动跑完整个程序？
- 执行完一条后，什么时候进入下一条？
- `wait_after` bit23 到底谁在用？

这些问题都在 `tpu_frontend_axil.sv` 里回答。

所以阅读链路是：

```text
encode_instrs.py
  -> imem.hex
  -> tpu_frontend_axil.sv 负责装载和取指
  -> control_unit.sv 负责 decode 当前指令
  -> TPU core 执行
```

---

## 2. 文件开头注释：它不是普通 AXI 壳

对应源码：

```systemverilog
// TinyTPU AXI-Lite Frontend (step mode + IMEM + sequencer)
```

这行注释已经把它的核心功能写出来了。

### 2.1 `AXI-Lite Frontend`

说明 Host 是通过 AXI-Lite 寄存器来控制 TPU。

你可以把 AXI-Lite 理解成：

**CPU/Host 通过固定地址读写一组寄存器。**

例如：

- 写 `0x030` 表示设置 IMEM 地址。
- 写 `0x034` 表示设置 IMEM 数据。
- 写 `0x040` 表示提交这一条 IMEM 指令。
- 写 `0x000 = 0x2` 表示 start。

### 2.2 `step mode`

`step mode` 是单步模式。

它不是从 IMEM 里自动跑完整程序，而是 Host 先把一条 instruction 写到 `INSTR_W0`，再写 `CTRL.step`，让硬件打一条。

小白可以理解成：

**调试时手动打一条指令。**

### 2.3 `IMEM`

IMEM 是 instruction memory。

它保存前面 `encode_instrs.py` 生成的 `imem.hex` 指令。

例如 `imem.txt` 里第一条：

```text
[00] 0001c462  forward_layer1.load_w1_shadow
```

最后会被 Host 写进 `imem[0]`。

### 2.4 `sequencer`

sequencer 是自动执行器。

它会从 `imem[0]` 开始取指，发给 `control_unit`，必要时等待 `vpu_drain`，然后前进到下一条。

所以这个文件不是边角料。

它是：

**Host 世界进入 TPU 训练闭环的控制门口。**

---

## 3. 顶部寄存器地图：先看懂 Host 能写什么

对应源码：

```systemverilog
//   0x00  CTRL       bit0=step
//                   bit1=start
//   0x04  STATUS     bit0=busy
//                   bit1=running
//   0x10  INSTR_W0   32-bit opcode instruction
//   0x20  UB_DATA    bits[15:0] = 16-bit word to write into UB
//   0x24  UB_PUSH    write-1 drives ub_wr_host_valid for one cycle
//   0x30  IMEM_ADDR  instruction slot address
//   0x34  IMEM_W0    32-bit opcode instruction to commit
//   0x40  IMEM_WE    write-1 commits IMEM_W0 into imem[IMEM_ADDR]
//   0x44  IMEM_LEN   number of valid instructions in IMEM
//   0x50  LEAK       leaky-relu factor
//   0x54  INV_BATCH  inverse batch scaling
//   0x58  LR         learning rate
```

这张表非常重要。

它说明 Host 不是直接拉 RTL 信号，而是通过寄存器控制硬件。

### 3.1 `0x00 CTRL`

`CTRL` 是控制寄存器。

源码里后面会看到：

```systemverilog
12'h000: begin
    if (wd_lat[0]) step_pulse  <= 1'b1;
    if (wd_lat[1]) start_pulse <= 1'b1;
end
```

意思是：

- 写 `0x000` 的 bit0 为 1，会产生 `step_pulse`。
- 写 `0x000` 的 bit1 为 1，会产生 `start_pulse`。

测试脚本里跑一轮训练就是：

```python
await axil_write(dut, 0x000, 0x2)
```

`0x2` 的二进制是 `10`，所以 bit1 为 1。

这就是 start。

### 3.2 `0x04 STATUS`

`STATUS` 是状态寄存器。

后面读通道里会看到：

```systemverilog
12'h004: s_axil_rdata <= {30'h0, seq_running, busy_reg};
```

所以：

- bit0 是 `busy_reg`。
- bit1 是 `seq_running`。

测试脚本里轮询：

```python
status = await axil_read(dut, 0x004)
if not (status & 0x1):
    return
```

意思是：

**只要 busy bit 清零，就认为这轮 sequencer 跑完了。**

### 3.3 `0x10 INSTR_W0`

`INSTR_W0` 是 step mode 用的临时 instruction 寄存器。

源码：

```systemverilog
12'h010: instr_w0_reg <= wd_lat;
```

Host 写一条 32-bit 指令到这里，然后写 `CTRL.step`，就能单步发这条指令。

### 3.4 `0x20 / 0x028 / 0x024`：Host 往 UB 写数据

顶部注释只写了 `0x20 UB_DATA` 和 `0x24 UB_PUSH`。

但实际源码里还有：

```systemverilog
12'h020: ub_data0_reg <= wd_lat[15:0];
12'h028: ub_data1_reg <= wd_lat[15:0];
12'h024: begin
    if (wd_lat[0]) ub_push0_pulse <= 1'b1;
    if (wd_lat[1]) ub_push1_pulse <= 1'b1;
end
```

所以真实用法是：

- `0x020` 写 lane0 的 16-bit 数据。
- `0x028` 写 lane1 的 16-bit 数据。
- `0x024` 写 push mask，触发 valid 脉冲。

测试脚本里对应：

```python
await axil_write(dut, 0x020, d0 & 0xFFFF)
await axil_write(dut, 0x028, d1 & 0xFFFF)
await axil_write(dut, 0x024, push_mask)
```

这就是 Host 把初始 `X/Y/W/B` 数据装进 UB 的路径。

### 3.5 `0x30 / 0x34 / 0x40 / 0x44`：Host 往 IMEM 装程序

这四个地址一起用。

源码：

```systemverilog
12'h030: imem_addr_reg <= wd_lat[$clog2(IMEM_DEPTH)-1:0];
12'h034: imem_w0_reg   <= wd_lat;
12'h040: if (wd_lat[0]) imem[imem_addr_reg] <= imem_w0_reg;
12'h044: imem_len_reg  <= wd_lat[5:0];
```

意思是：

1. 写 `0x030`，告诉硬件要写 IMEM 的第几个槽位。
2. 写 `0x034`，告诉硬件这条 32-bit instruction 的值。
3. 写 `0x040 = 1`，真正提交写入 `imem[imem_addr_reg]`。
4. 全部写完后，写 `0x044`，告诉 sequencer 有多少条有效 instruction。

测试脚本里对应：

```python
for i, instr in enumerate(instrs):
    await axil_write(dut, 0x030, i)
    await axil_write(dut, 0x034, instr)
    await axil_write(dut, 0x040, 1)
await axil_write(dut, 0x044, len(instrs))
```

这就是 `imem.hex` 进入 RTL 的路径。

### 3.6 `0x50 / 0x54 / 0x58`：训练参数

源码：

```systemverilog
12'h050: leak_factor_reg    <= wd_lat[15:0];
12'h054: inv_batch_n2_reg   <= wd_lat[15:0];
12'h058: learning_rate_reg  <= wd_lat[15:0];
```

它们分别是：

- `LEAK`：Leaky ReLU 的系数。
- `INV_BATCH`：loss/梯度路径里的 batch 缩放。
- `LR`：learning rate。

这些都是 Q8.8 定点参数。

小白可以先记成：

**Host 不只装数据和程序，也装训练需要的超参数。**

---

## 4. module 参数和端口：先看它连接哪两边

对应源码：

```systemverilog
module tpu_frontend_axil #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2,
    parameter int IMEM_DEPTH           = 64
)(
```

### 4.1 `SYSTOLIC_ARRAY_WIDTH`

这个参数表示 systolic array 宽度。

当前项目主要是 2x2，所以默认是 `2`。

### 4.2 `IMEM_DEPTH`

这个参数表示 IMEM 最多能放多少条 instruction。

默认是 `64`。

当前 `imem.txt` 里写的是：

```text
59 instructions
```

所以 64 深度足够放当前 MLP 训练程序。

---

## 5. AXI-Lite slave 端口：Host 从这里进来

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
...
```

这些是 AXI-Lite 的标准读写握手信号。

你作为面试讲项目时，不需要把每根 AXI 信号背成协议课。

你要抓住：

- `AW` 是写地址。
- `W` 是写数据。
- `B` 是写响应。
- `AR` 是读地址。
- `R` 是读数据。

这个文件用这些信号把 Host 的寄存器访问接进来。

### 5.1 `s_axil_wstrb` 当前没有被重点使用

源码里有 `s_axil_wstrb` 输入，但寄存器写 decode 主要看 `wd_lat`。

也就是说当前实现基本假设 Host 做完整 32-bit 写。

面试中如果被问，可以说：

**当前原型侧重系统闭环，AXI-Lite 的 byte strobe 精细写掩码没有作为核心功能展开。**

---

## 6. `tpu_vpu_valid_in`：Frontend 怎么知道系统尾拍结束

对应源码：

```systemverilog
input logic tpu_vpu_valid_in,  // OR of all vpu_valid_out
```

这根信号非常重要。

它不是 Host 侧信号，而是 TPU core 回给 Frontend 的完成线索。

注释写得很清楚：

```text
OR of all vpu_valid_out
```

意思是：

**只要任意 VPU 输出还 valid，`tpu_vpu_valid_in` 就还是 1。**

后面 Frontend 会用它做 `vpu_drain`。

---

## 7. 输出到 TPU core 的控制信号

对应源码：

```systemverilog
output logic        sys_switch_out,
output logic        ub_rd_start_out,
output logic        ub_rd_transpose_out,
output logic [1:0]  ub_rd_col_size_out,
output logic [3:0]  ub_rd_row_size_out,
output logic [5:0]  ub_rd_addr_out,
output logic [2:0]  ub_ptr_sel_out,
output logic [3:0]  vpu_data_pathway_out,
output logic [15:0] inv_batch_size_times_two_out,
output logic [15:0] vpu_leak_factor_out,
output logic [15:0] learning_rate_out
```

这批输出就是 Frontend 对 TPU core 发出的控制面。

你可以分成三组看。

### 7.1 UB 读相关

```systemverilog
ub_rd_start_out
ub_rd_transpose_out
ub_rd_col_size_out
ub_rd_row_size_out
ub_rd_addr_out
ub_ptr_sel_out
```

这几根来自 `control_unit` 解码。

它们决定：

- 从 UB 哪个地址读。
- 读多大块。
- 是否转置。
- 这次读是 input/weight/bias/gradient 哪种语义。

### 7.2 systolic / VPU 语义相关

```systemverilog
sys_switch_out
vpu_data_pathway_out
```

`sys_switch_out` 用于切换 systolic array 的 shadow/active 权重。

`vpu_data_pathway_out` 用于告诉 VPU 当前走 forward、loss、backward、update 里的哪条路径。

### 7.3 训练参数相关

```systemverilog
inv_batch_size_times_two_out
vpu_leak_factor_out
learning_rate_out
```

这些来自 Host 写的参数寄存器。

它们不是每条 instruction 里都带，而是配置寄存器持续输出给后级。

---

## 8. 时钟、复位、start 时恢复写指针

对应源码：

```systemverilog
assign clk_out = s_axil_aclk;
assign rst_out = ~s_axil_aresetn;
assign ub_wr_ptr_restore_out = start_pulse;
```

### 8.1 `clk_out`

```systemverilog
assign clk_out = s_axil_aclk;
```

TPU core 使用 AXI-Lite 的时钟。

这说明当前原型没有做复杂跨时钟域。

### 8.2 `rst_out`

```systemverilog
assign rst_out = ~s_axil_aresetn;
```

AXI-Lite reset 是低有效：`aresetn=0` 表示复位。

TPU core 需要高有效 reset。

所以这里取反。

### 8.3 `ub_wr_ptr_restore_out`

```systemverilog
assign ub_wr_ptr_restore_out = start_pulse;
```

这句要重点记。

它表示：

**每次 Host 写 start，Frontend 不只是启动 sequencer，还会让 UB 写指针恢复到运行前的边界。**

为什么要这样？

因为训练程序会把中间结果、梯度、更新结果写回 UB。

如果下一轮训练开始时写指针还停在上一轮尾部，就可能把 UB 布局写乱。

所以 start 的真实语义是：

```text
开始一轮自动程序
+ 恢复 UB runtime 写指针
```

这也是 PPT 里“顶层集成过程”应该讲清楚的点。

---

## 9. 内部寄存器和 pulse：先理解“寄存器保存值，pulse 表示事件”

对应源码：

```systemverilog
logic [31:0] instr_w0_reg;
logic [15:0] ub_data0_reg;
logic [15:0] ub_data1_reg;
logic        step_pulse;
logic        start_pulse;
logic        ub_push0_pulse;
logic        ub_push1_pulse;
logic        busy_reg;
logic [15:0] leak_factor_reg;
logic [15:0] inv_batch_n2_reg;
logic [15:0] learning_rate_reg;
logic [3:0]  vpu_pathway_reg;
```

### 9.1 带 `_reg` 的信号

一般表示寄存器保存的值。

例如：

- `instr_w0_reg` 保存 step mode 的 instruction。
- `ub_data0_reg` 保存 lane0 待写入 UB 的数据。
- `ub_data1_reg` 保存 lane1 待写入 UB 的数据。
- `leak_factor_reg` 保存 Leaky ReLU 参数。
- `learning_rate_reg` 保存学习率。

### 9.2 带 `_pulse` 的信号

一般表示只持续一个时钟周期的事件。

例如：

- `step_pulse` 表示 Host 刚刚写了 step。
- `start_pulse` 表示 Host 刚刚写了 start。
- `ub_push0_pulse` 表示 lane0 这拍要写 UB。
- `ub_push1_pulse` 表示 lane1 这拍要写 UB。

后面寄存器写 decode 里每拍都会先清零这些 pulse：

```systemverilog
step_pulse     <= 1'b0;
start_pulse    <= 1'b0;
ub_push0_pulse <= 1'b0;
ub_push1_pulse <= 1'b0;
```

所以它们不是长期保持的配置，而是一拍事件。

---

## 10. IMEM 定义：程序存在这里

对应源码：

```systemverilog
logic [31:0] imem [0:IMEM_DEPTH-1];
logic [$clog2(IMEM_DEPTH)-1:0] imem_addr_reg;
logic [31:0] imem_w0_reg;
logic [5:0]  imem_len_reg;
```

### 10.1 `imem`

```systemverilog
logic [31:0] imem [0:IMEM_DEPTH-1];
```

这是一个 32-bit 宽、深度为 `IMEM_DEPTH` 的指令数组。

当前默认深度是 64。

### 10.2 `imem_addr_reg`

保存 Host 要写的 IMEM 槽位。

测试脚本里每条指令都会先写地址：

```python
await axil_write(dut, 0x030, i)
```

### 10.3 `imem_w0_reg`

保存 Host 要写的 32-bit instruction。

测试脚本里：

```python
await axil_write(dut, 0x034, instr)
```

### 10.4 `imem_len_reg`

保存有效 instruction 条数。

sequencer 后面用它判断什么时候跑完。

当前 `imem.txt` 里是：

```text
59 instructions
```

所以 Host 最后会写：

```python
await axil_write(dut, 0x044, len(instrs))
```

---

## 11. Sequencer 状态机：这个文件的核心

对应源码：

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
```

这个状态机是整份文件最重要的部分。

### 11.1 `SEQ_IDLE`

空闲状态。

等待 Host 写 step 或 start。

### 11.2 `SEQ_DISPATCH`

发射状态。

它会让 `seq_instr_pulse` 拉高一拍，把当前 instruction 送给 `control_unit`。

### 11.3 `SEQ_WAIT`

等待状态。

它不是随便等几拍。

它等的是：

```systemverilog
vpu_drain
```

也就是 VPU valid 从 1 掉到 0 的收尾边界。

### 11.4 `SEQ_ADVANCE`

前进状态。

如果还有下一条 instruction，就 `pc + 1`。

如果没有了，就清 `running/busy`，回到 `IDLE`。

---

## 12. PC、当前 instruction、vpu_drain、wait_after

对应源码：

```systemverilog
logic [$clog2(IMEM_DEPTH)-1:0] pc;
logic        seq_running;
logic        seq_instr_pulse;
logic [31:0] seq_instr;
logic        vpu_valid_prev;
logic        vpu_drain;

logic seq_needs_wait;
assign seq_needs_wait = seq_instr[23];
```

### 12.1 `pc`

`pc` 是 program counter。

它表示当前正在执行 IMEM 的第几条。

### 12.2 `seq_running`

表示 sequencer 正在自动运行。

注意：

step mode 不一定等于 `seq_running=1`。

`seq_running` 更偏向 IMEM auto-run。

### 12.3 `seq_instr_pulse`

表示当前这拍要把 `seq_instr` 发给 `control_unit`。

后面有一句：

```systemverilog
assign instr_to_cu = seq_instr_pulse ? seq_instr : '0;
```

所以如果 `seq_instr_pulse` 不为 1，control_unit 看到的是 0，也就是 NOP。

### 12.4 `seq_instr`

保存当前要执行的 32-bit instruction。

auto-run 时它来自：

```systemverilog
seq_instr <= imem[0];
seq_instr <= imem[pc + 1];
```

step mode 时它来自：

```systemverilog
seq_instr <= instr_w0_reg;
```

### 12.5 `vpu_valid_prev` 和 `vpu_drain`

源码：

```systemverilog
vpu_valid_prev <= tpu_vpu_valid_in;
vpu_drain      <= vpu_valid_prev && !tpu_vpu_valid_in;
```

这是一种边沿检测。

意思是：

- 上一拍 VPU 还有 valid。
- 当前拍 VPU 没有 valid。
- 所以 VPU 输出流已经 drain 掉。

换句话说：

**`vpu_drain` 表示一个阶段的尾拍已经排空。**

### 12.6 `seq_needs_wait`

源码：

```systemverilog
assign seq_needs_wait = seq_instr[23];
```

这就是前面你问过的 `wait_after`。

它不在 `control_unit.sv` 里处理。

它在 Frontend sequencer 里处理。

也就是说：

```text
encode_instrs.py 设置 bit23
Frontend 读取 seq_instr[23]
如果 bit23=1，dispatch 后进入 SEQ_WAIT
SEQ_WAIT 等 vpu_drain
```

这就是 `wait_after` 的硬件落点。

---

## 13. Sequencer reset：复位时清到安全状态

对应源码：

```systemverilog
if (!s_axil_aresetn) begin
    seq_state       <= SEQ_IDLE;
    pc              <= '0;
    seq_running     <= 1'b0;
    seq_instr_pulse <= 1'b0;
    seq_instr       <= '0;
    vpu_valid_prev  <= 1'b0;
    vpu_drain       <= 1'b0;
    busy_reg        <= 1'b0;
end
```

这段很好理解。

复位时：

- 状态机回到 `SEQ_IDLE`。
- PC 清零。
- 不再 running。
- 不发 instruction pulse。
- 当前 instruction 清零。
- busy 清零。

小白可以记成：

**复位后前端不执行任何程序，也不向 TPU 发控制脉冲。**

---

## 14. Sequencer 每拍先做的事

对应源码：

```systemverilog
vpu_valid_prev <= tpu_vpu_valid_in;
vpu_drain      <= vpu_valid_prev && !tpu_vpu_valid_in;
seq_instr_pulse <= 1'b0;
```

### 14.1 更新 VPU valid 历史

```systemverilog
vpu_valid_prev <= tpu_vpu_valid_in;
```

保存这一拍的 VPU valid，供下一拍判断下降沿。

### 14.2 计算 drain

```systemverilog
vpu_drain <= vpu_valid_prev && !tpu_vpu_valid_in;
```

如果上一拍 valid=1，当前拍 valid=0，就是 drain。

### 14.3 默认不发指令

```systemverilog
seq_instr_pulse <= 1'b0;
```

这行很关键。

它表示：

**除非状态机明确进入 dispatch，否则默认每拍都不发新指令。**

这样 control_unit 平时看到 NOP，不会一直重复驱动同一条指令。

---

## 15. `vpu_pathway_reg` 为什么要 latch

对应源码：

```systemverilog
if (seq_instr_pulse && seq_instr[2:0] == 3'b010)
    vpu_pathway_reg <= seq_instr[22:19];
```

这里判断的是：

- 当前有 instruction pulse。
- 当前 instruction 的 opcode 是 `3'b010`，也就是 `UB_RD`。

如果满足，就把 `seq_instr[22:19]` 保存到 `vpu_pathway_reg`。

为什么要保存？

因为 VPU pathway 不是只打一拍就没用。

例如一条 `UB_RD` 启动后，后面数据流还会持续一段时间。

VPU 在这一段期间都需要知道自己走哪条路径。

所以后面输出不是直接用 control_unit 的一拍输出，而是：

```systemverilog
assign vpu_data_pathway_out = vpu_pathway_reg;
```

这表示 pathway 会持续保持到下一次 UB_RD 更新它。

面试里可以这样说：

**`ub_rd_start` 是脉冲，但 `vpu_data_pathway` 是阶段语义，需要 latch 保持。**

---

## 16. `SEQ_IDLE`：等 step 或 start

对应源码：

```systemverilog
SEQ_IDLE: begin
    seq_running <= 1'b0;
    if (step_pulse) begin
        seq_instr       <= instr_w0_reg;
        seq_instr_pulse <= 1'b1;
        busy_reg        <= 1'b1;
        seq_state       <= SEQ_WAIT;
    end else if (start_pulse) begin
        pc          <= '0;
        seq_instr   <= imem[0];
        seq_running <= 1'b1;
        busy_reg    <= 1'b1;
        seq_state   <= SEQ_DISPATCH;
    end
end
```

这一段把两种执行方式区分开了。

### 16.1 step mode

```systemverilog
if (step_pulse) begin
    seq_instr       <= instr_w0_reg;
    seq_instr_pulse <= 1'b1;
    busy_reg        <= 1'b1;
    seq_state       <= SEQ_WAIT;
end
```

Host 先写 `0x010`，把一条 instruction 放进 `instr_w0_reg`。

然后 Host 写 `0x000` 的 bit0。

Frontend 就会：

- 把 `instr_w0_reg` 放到 `seq_instr`。
- 产生一拍 `seq_instr_pulse`。
- busy 拉高。
- 进入 `SEQ_WAIT`。

小白理解：

**step 是打一条临时指令。**

### 16.2 auto-run mode

```systemverilog
else if (start_pulse) begin
    pc          <= '0;
    seq_instr   <= imem[0];
    seq_running <= 1'b1;
    busy_reg    <= 1'b1;
    seq_state   <= SEQ_DISPATCH;
end
```

Host 写 `0x000 = 0x2` 后，Frontend 会：

- PC 清零。
- 取 `imem[0]`。
- `seq_running` 拉高。
- `busy_reg` 拉高。
- 进入 `SEQ_DISPATCH`。

这就是正式跑一轮训练程序的入口。

测试脚本里的：

```python
await axil_write(dut, 0x000, 0x2)
```

就会走到这个分支。

---

## 17. `SEQ_DISPATCH`：只负责打一拍指令

对应源码：

```systemverilog
SEQ_DISPATCH: begin
    seq_instr_pulse <= 1'b1;
    if (seq_needs_wait)
        seq_state <= SEQ_WAIT;
    else
        seq_state <= SEQ_ADVANCE;
end
```

这段非常关键。

### 17.1 `seq_instr_pulse <= 1'b1`

表示这拍把当前 `seq_instr` 发给 `control_unit`。

后面 `instr_to_cu` 会变成当前 instruction。

### 17.2 如果需要 wait

```systemverilog
if (seq_needs_wait)
    seq_state <= SEQ_WAIT;
```

`seq_needs_wait` 来自 `seq_instr[23]`。

如果 bit23 为 1，就说明这条 instruction 后面要等系统 drain。

### 17.3 如果不需要 wait

```systemverilog
else
    seq_state <= SEQ_ADVANCE;
```

如果 bit23 为 0，就不等 VPU drain，直接准备前进到下一条。

### 17.4 这对性能有什么意义

不是每条 instruction 后面都等。

例如加载权重后可能插入 NOP，某些连续流可以继续推进。

只在 stage 边界等 `vpu_drain`，这样比每条都强行等待更少浪费。

但当前编译器还不是最优 cycle-accurate，只是规则式地在关键边界插入 `wait_after`。

这就是后续优化方向：

**根据硬件 latency/资源冲突模型自动计算最小安全等待。**

---

## 18. `SEQ_WAIT`：等的不是 dispatch，而是 vpu_drain

对应源码：

```systemverilog
SEQ_WAIT: begin
    if (vpu_drain) begin
        if (seq_running)
            seq_state <= SEQ_ADVANCE;
        else begin
            busy_reg  <= 1'b0;
            seq_state <= SEQ_IDLE;
        end
    end
end
```

这一段是你面试很可能被问到的点。

### 18.1 为什么不是 dispatch 完就算完成

`dispatch` 只是控制脉冲发出去了。

但是 TPU core 里还有：

- UB 读流。
- systolic array pipeline。
- VPU pipeline。
- VPU writeback。

所以发出指令的一拍，不等于结果已经写回。

真正安全的阶段边界是：

**VPU 输出流已经从 valid 变成 not valid。**

这就是 `vpu_drain`。

### 18.2 `seq_running=1` 的情况

如果是在 auto-run 模式：

```systemverilog
if (seq_running)
    seq_state <= SEQ_ADVANCE;
```

等到 drain 后，继续前进到下一条 instruction。

### 18.3 `seq_running=0` 的情况

如果是 step mode：

```systemverilog
else begin
    busy_reg  <= 1'b0;
    seq_state <= SEQ_IDLE;
end
```

等到 drain 后，busy 清零，回到 IDLE。

### 18.4 `vpu_drain` 会不会影响性能

会。

等待一定会让 sequencer 停住。

但它是为了正确性。

如果不等 drain，下一阶段可能在上一阶段尾拍还没写回时提前启动，造成：

- UB 读写重叠。
- VPU pathway 被提前切走。
- 后一阶段读到旧数据或半更新数据。

更好的办法不是删掉 `vpu_drain`，而是让编译器更聪明：

- 精确知道每条路径的 latency。
- 精确知道哪些资源会冲突。
- 自动把等待缩到最少。
- 尽量重排 load/compute，让等待被有用工作覆盖。

所以你可以回答：

**`vpu_drain` 是当前系统的安全完成边界；它可能牺牲性能，但能保证阶段正确。后续优化方向是做 cycle-accurate 调度，而不是直接取消 drain。**

---

## 19. `SEQ_ADVANCE`：PC 前进或程序结束

对应源码：

```systemverilog
SEQ_ADVANCE: begin
    if (pc + 1 < {{($clog2(IMEM_DEPTH)-6){1'b0}}, imem_len_reg}) begin
        pc        <= pc + 1;
        seq_instr <= imem[pc + 1];
        seq_state <= SEQ_DISPATCH;
    end else begin
        seq_running <= 1'b0;
        busy_reg    <= 1'b0;
        seq_state   <= SEQ_IDLE;
    end
end
```

### 19.1 如果还有下一条

```systemverilog
pc        <= pc + 1;
seq_instr <= imem[pc + 1];
seq_state <= SEQ_DISPATCH;
```

PC 加 1，取下一条 instruction，然后回到 dispatch。

### 19.2 如果已经到末尾

```systemverilog
seq_running <= 1'b0;
busy_reg    <= 1'b0;
seq_state   <= SEQ_IDLE;
```

表示程序跑完。

Host 轮询 `STATUS.busy` 时会看到 bit0 清零。

### 19.3 `imem_len_reg` 的作用

sequencer 不会盲目跑满 64 条。

它只跑 `imem_len_reg` 指定的有效条数。

当前测试中 `imem_len_reg` 来自：

```python
await axil_write(dut, 0x044, len(instrs))
```

---

## 20. AXI-Lite 写通道：先把地址和数据凑齐

对应源码：

```systemverilog
typedef enum logic [1:0] {
    W_IDLE      = 2'b00,
    W_WAIT_W    = 2'b01,
    W_WAIT_AW   = 2'b10,
    W_RESP      = 2'b11
} w_state_t;
```

这部分是标准 AXI-Lite 写握手。

你先不用死背每个状态。

抓住一句话：

**它负责把写地址 AW 和写数据 W 收齐，然后产生一拍 `wr_fire`。**

### 20.1 `W_IDLE`

空闲。

如果地址和数据同一拍都到了，就直接保存并 `wr_fire=1`。

如果只来了地址，就等数据。

如果只来了数据，就等地址。

### 20.2 `W_WAIT_W`

已经有地址，还在等写数据。

### 20.3 `W_WAIT_AW`

已经有写数据，还在等地址。

### 20.4 `W_RESP`

写操作已经被接受，返回 AXI-Lite 写响应。

源码：

```systemverilog
s_axil_bvalid <= 1'b1;
s_axil_bresp  <= 2'b00;
```

`2'b00` 表示 OKAY。

---

## 21. `aw_lat`、`wd_lat`、`wr_fire`

对应源码：

```systemverilog
logic [11:0] aw_lat;
logic [31:0] wd_lat;
logic        wr_fire;
```

### 21.1 `aw_lat`

保存写地址。

比如 Host 写 `0x030`，这里会保存 `12'h030`。

### 21.2 `wd_lat`

保存写数据。

比如 Host 写一条 instruction，`wd_lat` 就是这条 32-bit instruction。

### 21.3 `wr_fire`

表示一次完整写事务成立。

后面的寄存器写 decode 只在：

```systemverilog
if (wr_fire) begin
```

里面真正更新寄存器。

所以 `wr_fire` 是 AXI 写通道和寄存器文件之间的桥。

---

## 22. Register write decode：Host 写寄存器后真正发生什么

对应源码：

```systemverilog
always_ff @(posedge s_axil_aclk or negedge s_axil_aresetn) begin
    if (!s_axil_aresetn) begin
        ...
    end else begin
        step_pulse     <= 1'b0;
        start_pulse    <= 1'b0;
        ub_push0_pulse <= 1'b0;
        ub_push1_pulse <= 1'b0;
        if (wr_fire) begin
            case (aw_lat)
                ...
            endcase
        end
    end
end
```

### 22.1 先清 pulse

```systemverilog
step_pulse     <= 1'b0;
start_pulse    <= 1'b0;
ub_push0_pulse <= 1'b0;
ub_push1_pulse <= 1'b0;
```

这说明这些 pulse 默认只打一拍。

只有 Host 写到对应地址时，它们才在当前时钟周期拉高。

### 22.2 `0x000`：CTRL

```systemverilog
12'h000: begin
    if (wd_lat[0]) step_pulse  <= 1'b1;
    if (wd_lat[1]) start_pulse <= 1'b1;
end
```

写 `0x000 = 1`：step。

写 `0x000 = 2`：start。

当前训练测试用的是 start。

### 22.3 `0x010`：INSTR_W0

```systemverilog
12'h010: instr_w0_reg <= wd_lat;
```

保存 step mode 的临时 instruction。

### 22.4 `0x020`：lane0 UB data

```systemverilog
12'h020: ub_data0_reg <= wd_lat[15:0];
```

保存 lane0 要写入 UB 的 16-bit 数据。

### 22.5 `0x028`：lane1 UB data

```systemverilog
12'h028: ub_data1_reg <= wd_lat[15:0];
```

保存 lane1 要写入 UB 的 16-bit 数据。

这点要注意：

**顶部注释没有单独列出 `0x028`，但源码和测试都在用它。**

### 22.6 `0x024`：UB_PUSH

```systemverilog
12'h024: begin
    if (wd_lat[0]) ub_push0_pulse <= 1'b1;
    if (wd_lat[1]) ub_push1_pulse <= 1'b1;
end
```

这不是写数据本身。

它是告诉硬件：

- bit0 为 1：把 lane0 数据 push 进 UB。
- bit1 为 1：把 lane1 数据 push 进 UB。

所以正确顺序是：

```text
先写 0x020 / 0x028 放数据
再写 0x024 触发 valid
```

### 22.7 `0x030 / 0x034 / 0x040 / 0x044`：IMEM 装载

```systemverilog
12'h030: imem_addr_reg <= wd_lat[$clog2(IMEM_DEPTH)-1:0];
12'h034: imem_w0_reg   <= wd_lat;
12'h040: if (wd_lat[0]) imem[imem_addr_reg] <= imem_w0_reg;
12'h044: imem_len_reg  <= wd_lat[5:0];
```

这四个寄存器是装程序的核心。

顺序必须理解清楚：

```text
0x030 设置写哪个 IMEM 槽位
0x034 设置这条 instruction 的内容
0x040 写 1，把 instruction 提交进 imem[地址]
0x044 设置有效程序长度
```

### 22.8 `0x050 / 0x054 / 0x058`：训练参数

```systemverilog
12'h050: leak_factor_reg    <= wd_lat[15:0];
12'h054: inv_batch_n2_reg   <= wd_lat[15:0];
12'h058: learning_rate_reg  <= wd_lat[15:0];
```

这三项会持续输出到 TPU core。

后面有：

```systemverilog
assign inv_batch_size_times_two_out = inv_batch_n2_reg;
assign vpu_leak_factor_out          = leak_factor_reg;
assign learning_rate_out            = learning_rate_reg;
```

---

## 23. AXI-Lite 读通道：Host 怎么看状态

对应源码：

```systemverilog
always_ff @(posedge s_axil_aclk or negedge s_axil_aresetn) begin
    if (!s_axil_aresetn) begin
        ...
    end else begin
        s_axil_arready <= 1'b0;
        if (s_axil_arvalid && !s_axil_rvalid) begin
            s_axil_arready <= 1'b1;
            s_axil_rvalid  <= 1'b1;
            s_axil_rresp   <= 2'b00;
            case (s_axil_araddr)
                ...
            endcase
        end else if (s_axil_rvalid && s_axil_rready) begin
            s_axil_rvalid <= 1'b0;
        end
    end
end
```

读通道的核心是：

**Host 给读地址，Frontend 返回对应寄存器值。**

### 23.1 最重要的是 `0x004 STATUS`

源码：

```systemverilog
12'h004: s_axil_rdata <= {30'h0, seq_running, busy_reg};
```

所以读 `0x004` 返回：

```text
bit0 = busy_reg
bit1 = seq_running
```

测试脚本用 bit0 判断是否跑完：

```python
status = await axil_read(dut, 0x004)
if not (status & 0x1):
    return
```

### 23.2 为什么这是完整系统闭环

Host 不是写 start 后盲等固定 cycle。

Host 是：

```text
写 CTRL.start
反复读 STATUS.busy
busy 清零后认为一轮结束
```

这比固定延时更像真实 SoC 控制。

---

## 24. `instr_to_cu`：只有 pulse 那一拍才给 control_unit 真指令

对应源码：

```systemverilog
logic [31:0] instr_to_cu;
assign instr_to_cu = seq_instr_pulse ? seq_instr : '0;
```

这句非常重要。

如果 `seq_instr_pulse=1`：

```text
instr_to_cu = seq_instr
```

如果 `seq_instr_pulse=0`：

```text
instr_to_cu = 0
```

而 `0` 对应 opcode `000`，也就是 NOP。

所以 control_unit 不是一直看到同一条 instruction。

它只在 dispatch 那一拍看到真指令。

这样可以避免：

- `ub_rd_start` 连续多拍误触发。
- `sys_switch` 连续多拍误触发。
- 同一条 instruction 被重复执行。

---

## 25. 实例化 `control_unit`：Frontend 不自己拆字段

对应源码：

```systemverilog
control_unit cu_inst (
    .instruction           (instr_to_cu),
    .sys_switch_in         (sys_switch_out),
    .ub_rd_start_in        (ub_rd_start_out),
    .ub_rd_transpose       (ub_rd_transpose_out),
    .ub_rd_col_size        (ub_rd_col_size_out),
    .ub_rd_row_size        (ub_rd_row_size_out),
    .ub_rd_addr_in         (ub_rd_addr_out),
    .ub_ptr_sel            (ub_ptr_sel_out),
    .vpu_data_pathway      (cu_vpu_data_pathway),
    ...
);
```

这说明 Frontend 和 control_unit 的分工是：

- Frontend 决定什么时候发 instruction。
- control_unit 决定 instruction 每个 bit 字段怎么拆。
- Frontend 把拆出来的信号接到 TPU core。

你可以用一句话讲：

**Frontend 管时序，control_unit 管译码。**

---

## 26. 为什么 `cu_vpu_data_pathway` 没有直接输出

源码里有：

```systemverilog
logic [3:0] cu_vpu_data_pathway;  // unused directly; pathway persists via vpu_pathway_reg
```

control_unit 的 pathway 输出接到了 `cu_vpu_data_pathway`。

但最终输出给 TPU core 的是：

```systemverilog
assign vpu_data_pathway_out = vpu_pathway_reg;
```

原因前面已经讲过：

**control_unit 的输出只在 instruction pulse 那一拍有效，但 VPU pathway 要在阶段期间持续有效。**

所以这里用 `vpu_pathway_reg` 保存它。

---

## 27. UB host write mux：一个写口，两种来源

对应源码：

```systemverilog
assign ub_wr_host_valid_out_0 = ub_push0_pulse ? 1'b1         : cu_ub_valid_0;
assign ub_wr_host_valid_out_1 = ub_push1_pulse ? 1'b1         : cu_ub_valid_1;
assign ub_wr_host_data_out_0  = ub_push0_pulse ? ub_data0_reg : cu_ub_data_0;
assign ub_wr_host_data_out_1  = ub_push1_pulse ? ub_data1_reg : cu_ub_data_1;
```

这段是在做仲裁。

UB 的 host write 口可能来自两种来源：

1. Host 通过 AXI `UB_PUSH` 直接写 UB。
2. control_unit 通过 `UB_WR_HOST` instruction 写 UB。

如果当前 Host 正在 push，那么 Host 优先。

所以：

```text
ub_push0_pulse=1 -> 用 ub_data0_reg
否则 -> 用 cu_ub_data_0
```

这就是 mux。

面试可以这样说：

**Frontend 统一仲裁 Host 直接写 UB 和指令侧 UB_WR_HOST，两条路径最终共用 UB host write 口。**

---

## 28. 把 Host 装数据、装程序、启动训练串起来

现在把这个文件和测试脚本连起来看。

### 28.1 第一步：Host 装初始数据到 UB

测试里：

```python
await axil_write(dut, 0x020, d0 & 0xFFFF)
await axil_write(dut, 0x028, d1 & 0xFFFF)
await axil_write(dut, 0x024, push_mask)
```

Frontend 里：

```systemverilog
12'h020: ub_data0_reg <= wd_lat[15:0];
12'h028: ub_data1_reg <= wd_lat[15:0];
12'h024: begin
    if (wd_lat[0]) ub_push0_pulse <= 1'b1;
    if (wd_lat[1]) ub_push1_pulse <= 1'b1;
end
```

最终通过 mux 输出到 UB host write 口。

### 28.2 第二步：Host 装 IMEM 程序

测试里：

```python
await axil_write(dut, 0x030, i)
await axil_write(dut, 0x034, instr)
await axil_write(dut, 0x040, 1)
await axil_write(dut, 0x044, len(instrs))
```

Frontend 里：

```systemverilog
imem[imem_addr_reg] <= imem_w0_reg;
imem_len_reg <= wd_lat[5:0];
```

这一步把 `imem.hex` 放进硬件 IMEM。

### 28.3 第三步：Host 写 start

测试里：

```python
await axil_write(dut, 0x000, 0x2)
```

Frontend 里：

```systemverilog
if (wd_lat[1]) start_pulse <= 1'b1;
```

然后 sequencer 进入 auto-run：

```systemverilog
pc          <= '0;
seq_instr   <= imem[0];
seq_running <= 1'b1;
busy_reg    <= 1'b1;
seq_state   <= SEQ_DISPATCH;
```

### 28.4 第四步：Frontend 逐条发 IMEM 指令

每条指令会经历：

```text
SEQ_DISPATCH
  -> 可能 SEQ_WAIT
  -> SEQ_ADVANCE
  -> 下一条 SEQ_DISPATCH
```

如果 instruction bit23 为 1，就等 `vpu_drain`。

如果 bit23 为 0，就直接 advance。

### 28.5 第五步：Host 轮询 STATUS

测试里：

```python
status = await axil_read(dut, 0x004)
if not (status & 0x1):
    return
```

Frontend 里：

```systemverilog
12'h004: s_axil_rdata <= {30'h0, seq_running, busy_reg};
```

所以 Host 通过 busy bit 判断一轮训练程序是否结束。

---

## 29. 和 `imem.txt` 对一条真实指令

`imem.txt` 里第一条：

```text
[00] 0001c462  forward_layer1.load_w1_shadow
```

Host 装 IMEM 时会把 `0001c462` 写进 `imem[0]`。

Host 写 start 后，Frontend 做：

```systemverilog
pc        <= '0;
seq_instr <= imem[0];
```

下一步进入 `SEQ_DISPATCH`：

```systemverilog
seq_instr_pulse <= 1'b1;
```

于是：

```systemverilog
instr_to_cu = seq_instr
```

control_unit 解码后会输出：

- `ub_rd_start_out`
- `ub_rd_addr_out`
- `ub_rd_row_size_out`
- `ub_rd_col_size_out`
- `ub_rd_transpose_out`
- `ub_ptr_sel_out`

这就是一条软件 schedule 指令进入 RTL 执行链路的过程。

---

## 30. 小白最容易混的 8 个点

### 30.1 Frontend 不是 control_unit

Frontend 管寄存器、IMEM、sequencer、时序。

control_unit 管 instruction bit 字段 decode。

### 30.2 `start` 不是普通 enable

`start_pulse` 会启动 sequencer，还会触发：

```systemverilog
ub_wr_ptr_restore_out = start_pulse;
```

也就是恢复 UB runtime 写指针。

### 30.3 `step` 和 `start` 不一样

`step` 是打一条 `instr_w0_reg`。

`start` 是从 `imem[0]` 开始跑完整程序。

### 30.4 `wait_after` 不在 control_unit 里

`wait_after` 是：

```systemverilog
seq_needs_wait = seq_instr[23]
```

它由 Frontend sequencer 使用。

### 30.5 `DISPATCH` 不等于完成

`DISPATCH` 只表示指令发出。

完成要看 `vpu_drain`。

### 30.6 `vpu_drain` 是安全边界

它表示 VPU valid 从 1 掉到 0。

这说明上一段输出流已经排空。

### 30.7 `vpu_data_pathway_out` 是寄存器保持的

它不是直接用 control_unit 的一拍输出。

它来自：

```systemverilog
vpu_pathway_reg
```

### 30.8 Host 写 UB 有 lane0/lane1 两路

真实源码里：

- `0x020` 是 lane0 data。
- `0x028` 是 lane1 data。
- `0x024` 是 push mask。

---

## 31. 面试时可以这样讲这个文件

如果面试官问：

**你这个 SoC 顶层怎么从软件控制 TPU？**

你可以答：

```text
我用了一个 AXI-Lite frontend 作为 Host 和 TPU core 的控制入口。
Host 先通过 AXI 寄存器把初始数据 push 到 UB，再把编译器生成的 imem.hex 按地址写入 IMEM，并设置 IMEM_LEN。
之后 Host 写 CTRL.start，frontend 会恢复 UB runtime 写指针，从 imem[0] 开始启动 sequencer。
sequencer 每次 dispatch 一条 32-bit instruction 给 control_unit，control_unit 译码出 UB 读、systolic switch 和 VPU pathway 等控制信号。
如果 instruction bit23 置位，sequencer 会进入 WAIT，等 VPU valid 下降沿形成的 vpu_drain，再前进到下一条。
程序跑完后 frontend 清 busy，Host 通过 STATUS.busy 轮询知道一轮训练结束。
```

这段话基本覆盖了：

- Host 接口。
- 数据装载。
- IMEM 装载。
- start 语义。
- sequencer。
- control_unit。
- wait_after。
- vpu_drain。
- STATUS 轮询。

---

## 32. 最后一页总结

如果你只记 10 句话：

1. `tpu_frontend_axil.sv` 是 Host 进入 TPU 的控制入口。
2. 它不是单纯 AXI 壳，而是 AXI-Lite 寄存器 + IMEM + sequencer + control_unit glue。
3. Host 用 `0x020/0x028/0x024` 把数据 push 到 UB。
4. Host 用 `0x030/0x034/0x040/0x044` 把 `imem.hex` 装进 IMEM。
5. Host 写 `0x000 = 0x2` 产生 `start_pulse`。
6. `start_pulse` 同时触发 auto-run 和 UB 写指针恢复。
7. sequencer 从 `imem[0]` 开始 dispatch instruction。
8. `seq_instr[23]` 就是 `wait_after` 的 RTL 落点。
9. `SEQ_WAIT` 等的是 `vpu_drain`，不是固定 cycle。
10. 程序结束后 `busy_reg` 清零，Host 通过 `STATUS.busy` 知道一轮完成。

最终一句话：

**`tpu_frontend_axil.sv` 的价值，是把软件侧的寄存器写操作组织成硬件侧可执行、可等待、可轮询的一整轮 TPU 程序。**

---

## 33. 你看完这份后，下一步看什么

下一步建议看：

```text
/home/jjt/tpu-soc/docs/code_reading_pack_20260408/07_tpu_soc.sv_guide_zh.md
```

也就是 `tpu_soc.sv`。

原因是：

**你现在知道 Frontend 怎么发控制；下一步要看 SoC 顶层怎么把 Frontend、TPU core、VPU valid 回传这些线接在一起。**

如果你继续，我下一份就做：

**`07_tpu_soc.sv` 的同风格小白逐段细讲版。**
