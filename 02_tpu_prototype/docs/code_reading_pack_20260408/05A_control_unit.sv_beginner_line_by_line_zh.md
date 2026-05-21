# `control_unit.sv` 小白版逐段细讲

对应源码：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/04_control_unit.sv`

原版讲解：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/05_control_unit.sv_guide_zh.md`

建议先看前一份：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/04A_encode_instrs.py_beginner_line_by_line_zh.md`

因为前一份讲的是：

**软件怎么把 schedule 命令打包成 32-bit 指令。**

这一份讲的是：

**RTL 怎么把 32-bit 指令拆回 UB / systolic / VPU 能用的控制信号。**

---

## 0. 先记住 5 句话

1. `control_unit.sv` 不负责决定执行节奏。
2. `control_unit.sv` 不负责存指令。
3. `control_unit.sv` 不负责等待 `vpu_drain`。
4. 它主要负责把 `instruction[31:0]` 拆成一堆控制字段。
5. 它是软件 32-bit 指令和硬件控制信号之间的“拆包器”。

如果你只记一句话，就记：

**`control_unit.sv` 是 32-bit 指令的组合逻辑 decoder。**

---

## 1. 为什么这一份要接在 `encode_instrs.py` 后面看

前面 `encode_instrs.py` 里有这些编码：

```python
instr |= addr << 3
instr |= row << 9
instr |= col << 13
instr |= transpose << 15
instr |= ptr_sel << 16
instr |= vpu_path << 19
instr |= wait_after << 23
```

这表示软件把字段塞到了固定 bit 位。

现在 `control_unit.sv` 做的事情就是把其中一部分字段拆回来：

```systemverilog
assign f_addr  = instruction[8:3];
assign f_row   = instruction[12:9];
assign f_col   = instruction[14:13];
assign f_trans = instruction[15];
assign f_ptr   = instruction[18:16];
assign f_vpu   = instruction[22:19];
```

所以这两个文件一定要连着看：

- `encode_instrs.py`：软件打包
- `control_unit.sv`：硬件拆包

---

## 2. 第 1 到 2 行：仿真时间和默认线网规则

对应源码：

```systemverilog
1 `timescale 1ns/1ps
2 `default_nettype none
```

### 2.1 `timescale`

```systemverilog
`timescale 1ns/1ps
```

这表示仿真时间单位是 `1ns`，精度是 `1ps`。

对你理解 decode 逻辑影响不大。

### 2.2 `default_nettype none`

```systemverilog
`default_nettype none
```

这行很重要。

它的作用是防止你不小心写错信号名时，Verilog 自动帮你创建一个隐式 wire。

小白可以这样理解：

**强制所有信号都必须明确声明，避免拼写错误变成隐藏 bug。**

---

## 3. 第 4 到 21 行：顶部注释就是 RTL 侧的指令格式表

对应源码：

```systemverilog
4  // TinyTPU Control Unit - 32-bit opcode instruction decoder
6  // Instruction format (32-bit):
7  //   opcode=3'b000  NOP      no operation
8  //   opcode=3'b001  SWITCH   sys_switch_in=1
9  //   opcode=3'b010  UB_RD    ub_rd_start_in=1, fields below
10 //     [2:0]   opcode
11 //     [8:3]   ub_rd_addr_in[5:0]
12 //     [12:9]  ub_rd_row_size[3:0]
13 //     [14:13] ub_rd_col_size[1:0]
14 //     [15]    ub_rd_transpose
15 //     [18:16] ub_ptr_sel[2:0]
16 //     [22:19] vpu_data_pathway[3:0]
17 //     [31:23] reserved
18 //   opcode=3'b011  UB_WR_HOST  drive ub_wr_host_valid for one cycle
19 //     [2:0]   opcode
20 //     [18:3]  ub_wr_host_data[15:0]
21 //     [31:19] reserved
```

### 3.1 第 4 行

```systemverilog
// TinyTPU Control Unit - 32-bit opcode instruction decoder
```

这行直接说明这个模块的定位：

**它是 32-bit opcode 指令 decoder。**

也就是说，它不是完整控制器，更像“指令字段翻译器”。

### 3.2 第 7 行：`NOP`

```systemverilog
// opcode=3'b000  NOP      no operation
```

opcode 是 `000` 时，不做任何事。

后面 case 里也会看到：

```systemverilog
3'b000: ; // NOP - all defaults
```

### 3.3 第 8 行：`SWITCH`

```systemverilog
// opcode=3'b001  SWITCH   sys_switch_in=1
```

opcode 是 `001` 时，输出：

```systemverilog
sys_switch_in = 1'b1;
```

这对应 systolic array 的 shadow/active 切换。

### 3.4 第 9 到 17 行：`UB_RD`

`UB_RD` 是最重要的指令类型。

它会把一条指令里的字段拆成：

- `ub_rd_start_in`
- `ub_rd_addr_in`
- `ub_rd_row_size`
- `ub_rd_col_size`
- `ub_rd_transpose`
- `ub_ptr_sel`
- `vpu_data_pathway`

也就是说，一条 `UB_RD` 不只是“读一下 UB”，而是同时携带了数据流语义。

### 3.5 第 18 到 21 行：`UB_WR_HOST`

这是 host 写 UB 相关指令。

当前主线更常见的是 AXI 侧写 UB，但这条 opcode 说明：

**指令格式里也保留了一种通过指令驱动 host 写口的能力。**

### 3.6 这一段你应该记住什么

**顶部注释就是 RTL 侧的 ISA 表，必须和 `encode_instrs.py` 的编码位段保持一致。**

---

## 4. 第 23 到 40 行：模块端口定义

对应源码：

```systemverilog
module control_unit (
    input  logic [31:0] instruction,

    output logic        sys_switch_in,
    output logic        ub_rd_start_in,
    output logic        ub_rd_transpose,
    output logic        ub_wr_host_valid_in_1,
    output logic        ub_wr_host_valid_in_2,
    output logic [1:0]  ub_rd_col_size,
    output logic [3:0]  ub_rd_row_size,
    output logic [5:0]  ub_rd_addr_in,
    output logic [2:0]  ub_ptr_sel,
    output logic [15:0] ub_wr_host_data_in_1,
    output logic [15:0] ub_wr_host_data_in_2,
    output logic [3:0]  vpu_data_pathway,
    input  logic [15:0] inv_batch_size_times_two_in,
    input  logic [15:0] vpu_leak_factor_in
);
```

### 4.1 输入 `instruction`

```systemverilog
input logic [31:0] instruction
```

这是这个模块最重要的输入。

它就是前面 `encode_instrs.py` 生成的 32-bit 指令。

### 4.2 输出 `sys_switch_in`

```systemverilog
output logic sys_switch_in
```

这条输出用于触发系统切换。

在当前项目里，主要对应 systolic array 的权重 shadow/active 切换。

### 4.3 输出 `ub_rd_start_in`

```systemverilog
output logic ub_rd_start_in
```

这条输出表示开始一次 UB 读。

当 opcode 是 `UB_RD` 时，它会被拉高。

### 4.4 输出 `ub_rd_transpose`

```systemverilog
output logic ub_rd_transpose
```

表示这次 UB 读是否按转置方式输出。

例如前面 scheduler 里 `load_w1_shadow` 会有 `transpose=True`。

### 4.5 输出 `ub_wr_host_valid_in_1/2`

```systemverilog
output logic ub_wr_host_valid_in_1
output logic ub_wr_host_valid_in_2
```

这两条是 host 写 UB 的 valid 信号。

当前主线里你先不用把它当成最核心。
重点仍然是 `UB_RD`。

### 4.6 输出 `ub_rd_col_size / ub_rd_row_size / ub_rd_addr_in`

```systemverilog
output logic [1:0] ub_rd_col_size
output logic [3:0] ub_rd_row_size
output logic [5:0] ub_rd_addr_in
```

这三条控制：

- 从 UB 哪个地址开始读
- 读几行
- 读几列

它们直接来自 instruction 的 bit 字段。

### 4.7 输出 `ub_ptr_sel`

```systemverilog
output logic [2:0] ub_ptr_sel
```

这条信号决定当前 UB 读是什么语义。

比如：
- input
- weight
- bias
- Y
- H
- grad_bias
- grad_weight

这正好对应前面 encoder 里的 `ptr_sel`。

### 4.8 输出 `vpu_data_pathway`

```systemverilog
output logic [3:0] vpu_data_pathway
```

这条信号告诉 VPU 当前走哪条数据路径。

比如 schedule 里写 `1100`，encoder 会编码进去，control unit 会拆成 `vpu_data_pathway`。

### 4.9 输入 `inv_batch_size_times_two_in` 和 `vpu_leak_factor_in`

```systemverilog
input logic [15:0] inv_batch_size_times_two_in
input logic [15:0] vpu_leak_factor_in
```

这两个输入在当前这个模块里没有实际使用。

这说明它们可能是历史接口或预留接口。
你现在不要把注意力放在它们上面。

### 4.10 这一段你应该记住什么

**这个模块只有一条核心输入 `instruction`，然后输出一堆后级模块需要的控制字段。**

---

## 5. 第 42 到 43 行：先拆 opcode

对应源码：

```systemverilog
logic [2:0] opcode;
assign opcode = instruction[2:0];
```

### 5.1 `opcode` 是什么

`opcode` 是指令类型。

它决定这条指令应该按哪种方式解释。

当前定义是：

```text
000 -> NOP
001 -> SWITCH
010 -> UB_RD
011 -> UB_WR_HOST
```

### 5.2 为什么取 `instruction[2:0]`

因为指令格式里约定了：

```text
[2:0] opcode
```

也就是最低 3 bit 存 opcode。

### 5.3 这一段你应该记住什么

**硬件 decode 的第一步，就是先看 instruction 的最低 3 位，判断这条指令是什么类型。**

---

## 6. 第 45 到 52 行：把指令里的字段先拆出来

对应源码：

```systemverilog
// Break out fields as intermediate assigns to avoid Icarus always_comb part-select limitation
logic [5:0]  f_addr;    assign f_addr   = instruction[8:3];
logic [3:0]  f_row;     assign f_row    = instruction[12:9];
logic [1:0]  f_col;     assign f_col    = instruction[14:13];
logic        f_trans;   assign f_trans  = instruction[15];
logic [2:0]  f_ptr;     assign f_ptr    = instruction[18:16];
logic [3:0]  f_vpu;     assign f_vpu    = instruction[22:19];
logic [15:0] f_wrdata;  assign f_wrdata = instruction[18:3];
```

### 6.1 为什么先拆到 `f_` 临时信号

注释已经说了：

```systemverilog
avoid Icarus always_comb part-select limitation
```

意思是为了避开 Icarus Verilog 对某些 always_comb 里 part-select 的限制。

小白可以理解为：

**先在外面把字段拆好，后面 always 块里直接用这些中间信号，更稳。**

### 6.2 `f_addr`

```systemverilog
assign f_addr = instruction[8:3];
```

这是 UB 读起始地址。

对应 encoder：

```python
instr |= addr << 3
```

### 6.3 `f_row`

```systemverilog
assign f_row = instruction[12:9];
```

这是 UB 读行数。

对应 encoder：

```python
instr |= row << 9
```

### 6.4 `f_col`

```systemverilog
assign f_col = instruction[14:13];
```

这是 UB 读列数。

对应 encoder：

```python
instr |= col << 13
```

### 6.5 `f_trans`

```systemverilog
assign f_trans = instruction[15];
```

这是转置标记。

对应 encoder：

```python
instr |= transpose << 15
```

### 6.6 `f_ptr`

```systemverilog
assign f_ptr = instruction[18:16];
```

这是 UB 指针/读语义选择。

对应 encoder：

```python
instr |= ptr_sel << 16
```

### 6.7 `f_vpu`

```systemverilog
assign f_vpu = instruction[22:19];
```

这是 VPU pathway。

对应 encoder：

```python
instr |= vpu_path << 19
```

### 6.8 `f_wrdata`

```systemverilog
assign f_wrdata = instruction[18:3];
```

这是 `UB_WR_HOST` 指令会用到的 16-bit 数据字段。

它和 `UB_RD` 的 addr/row/col/ptr 字段重叠。

为什么能重叠？

因为不同 opcode 会用不同解释方式。
同一段 bit 在 `UB_RD` 下是一组字段，在 `UB_WR_HOST` 下可以解释成 data。

### 6.9 这一段你应该记住什么

**第 45 到 52 行就是把一条 32-bit 指令按固定 bit 位先拆成临时字段。**

---

## 7. 第 54 到 67 行：`always @(*)` 里先给所有输出默认值

对应源码：

```systemverilog
always @(*) begin
    // defaults
    sys_switch_in              = 1'b0;
    ub_rd_start_in             = 1'b0;
    ub_rd_transpose            = 1'b0;
    ub_wr_host_valid_in_1      = 1'b0;
    ub_wr_host_valid_in_2      = 1'b0;
    ub_rd_col_size             = 2'b0;
    ub_rd_row_size             = 4'b0;
    ub_rd_addr_in              = 6'b0;
    ub_ptr_sel                 = 3'b0;
    ub_wr_host_data_in_1       = 16'b0;
    ub_wr_host_data_in_2       = 16'b0;
    vpu_data_pathway           = 4'b0;
```

### 7.1 `always @(*)` 是什么

`always @(*)` 表示组合逻辑。

也就是说：

**输出只由当前输入决定，不靠时钟，不记历史。**

### 7.2 为什么一上来全清零

这是一种很常见、也很重要的写法。

先给默认值可以避免：

- 某些分支忘记赋值
- 组合逻辑推 latch
- 未命中 opcode 时输出乱跳

小白可以这样理解：

**默认什么都不做，只有命中特定 opcode 时才打开对应控制信号。**

### 7.3 这一段你应该记住什么

**decode 模块先清零所有输出，再按 opcode 局部打开需要的信号。**

---

## 8. 第 68 到 93 行：按 opcode 分情况 decode

对应源码：

```systemverilog
case (opcode)
    3'b000: ; // NOP - all defaults

    3'b001: begin // SWITCH
        sys_switch_in = 1'b1;
    end

    3'b010: begin // UB_RD
        ub_rd_start_in   = 1'b1;
        ub_rd_addr_in    = f_addr;
        ub_rd_row_size   = f_row;
        ub_rd_col_size   = f_col;
        ub_rd_transpose  = f_trans;
        ub_ptr_sel       = f_ptr;
        vpu_data_pathway = f_vpu;
    end

    3'b011: begin // UB_WR_HOST
        ub_wr_host_valid_in_1 = 1'b1;
        ub_wr_host_valid_in_2 = 1'b1;
        ub_wr_host_data_in_1  = f_wrdata;
        ub_wr_host_data_in_2  = f_wrdata;
    end

    default: ; // reserved - all defaults
endcase
```

这一段就是整个模块的核心。

---

## 9. 第 69 行：`NOP`

对应源码：

```systemverilog
3'b000: ; // NOP - all defaults
```

`NOP` 什么都不做。

因为前面已经把所有输出都清零了，所以这里直接空着。

对应 `imem.hex` 里的：

```text
00000000
```

### 9.1 小白该记住什么

**NOP 的效果就是保持所有控制输出为默认零。**

---

## 10. 第 71 到 73 行：`SWITCH`

对应源码：

```systemverilog
3'b001: begin // SWITCH
    sys_switch_in = 1'b1;
end
```

这条指令只做一件事：

**把 `sys_switch_in` 拉高。**

这对应 `scheduler.py` 里的：

```python
_switch("forward_layer1", "activate_w1")
```

也对应 `imem.txt` 里的：

```text
[05] 00000001  forward_layer1.activate_w1  (control)
```

### 10.1 为什么这很重要

因为权重通常是先装到 shadow 路径，再通过 switch 变成 active。

所以 `SWITCH` 是：

**“预装载完了，现在正式启用。”**

---

## 11. 第 75 到 83 行：`UB_RD`

对应源码：

```systemverilog
3'b010: begin // UB_RD
    ub_rd_start_in   = 1'b1;
    ub_rd_addr_in    = f_addr;
    ub_rd_row_size   = f_row;
    ub_rd_col_size   = f_col;
    ub_rd_transpose  = f_trans;
    ub_ptr_sel       = f_ptr;
    vpu_data_pathway = f_vpu;
end
```

这是最重要的分支。

### 11.1 `ub_rd_start_in = 1'b1`

表示启动一次 UB 读。

### 11.2 `ub_rd_addr_in = f_addr`

把指令里的地址字段送给 UB。

例如 `W1` 的地址是 `12`，那 encoder 会把它塞进 instruction，control unit 再拆出来。

### 11.3 `ub_rd_row_size = f_row`

告诉 UB 读多少行。

### 11.4 `ub_rd_col_size = f_col`

告诉 UB 读多少列。

### 11.5 `ub_rd_transpose = f_trans`

告诉 UB 这次读流要不要转置。

### 11.6 `ub_ptr_sel = f_ptr`

告诉 UB 这次读是什么语义。

比如：
- input
- weight
- bias
- Y
- H
- grad_bias
- grad_weight

### 11.7 `vpu_data_pathway = f_vpu`

告诉 VPU 这次走哪条 pathway。

例如前面 `stream_b1` 的 `1100`，到这里就会变成 4-bit pathway 输出。

### 11.8 这一段你应该记住什么

**一条 `UB_RD` 指令会同时启动 UB 读、指定读地址/大小/转置、选择 UB 语义，并配置 VPU pathway。**

这就是为什么它是整个训练执行流里最核心的指令。

---

## 12. 第 85 到 90 行：`UB_WR_HOST`

对应源码：

```systemverilog
3'b011: begin // UB_WR_HOST
    ub_wr_host_valid_in_1 = 1'b1;
    ub_wr_host_valid_in_2 = 1'b1;
    ub_wr_host_data_in_1  = f_wrdata;
    ub_wr_host_data_in_2  = f_wrdata;
end
```

这条指令会把 `f_wrdata` 同时送到两个 host write data 输出上，并拉高两个 valid。

当前主线里你先不用把它作为重点。
但它说明这个 ISA 里保留了从指令侧发起 host 写 UB 的能力。

### 12.1 为什么是两个 data 输出

当前接口有两路 host 写相关输出：

- `ub_wr_host_data_in_1`
- `ub_wr_host_data_in_2`

所以这里同一份 `f_wrdata` 同时给两路。

### 12.2 这一段你应该记住什么

**`UB_WR_HOST` 是 host 写相关 opcode，但当前项目主线最核心还是 `UB_RD`。**

---

## 13. 第 92 行：default 分支

对应源码：

```systemverilog
default: ; // reserved - all defaults
```

如果 opcode 不属于已知几类，就什么都不做。

因为前面默认值已经全清零，所以 default 等于安全空操作。

这和 `encode_instrs.py` 里未知命令默认编码成 NOP 的思想是一致的：

**不认识的东西，不要乱驱动硬件。**

---

## 14. 第 96 行：模块结束

```systemverilog
endmodule
```

整个 `control_unit.sv` 到这里结束。

你会发现它很短。

短不是因为它不重要。
而是因为它的职责非常聚焦：

**只负责 decode，不负责时序控制。**

---

## 15. 重要补充：`wait_after` 为什么不在这里处理

前一份 `encode_instrs.py` 里说：

```python
instr |= wait_after << 23
```

你可能会问：

“那为什么 `control_unit.sv` 没有拆 `instruction[23]`？”

答案是：

**因为 `wait_after` 是 Frontend sequencer 用的，不是 control_unit 的输出字段。**

你可以看 `tpu_frontend_axil.sv`：

```systemverilog
assign seq_needs_wait = seq_instr[23];
```

然后在 `SEQ_DISPATCH` 里：

```systemverilog
if (seq_needs_wait)
    seq_state <= SEQ_WAIT;
else
    seq_state <= SEQ_ADVANCE;
```

所以分工是：

- `control_unit.sv`
  - 拆 UB / switch / VPU pathway 字段

- `tpu_frontend_axil.sv`
  - 看 bit23 决定是否等待 `vpu_drain`

### 15.1 这一点为什么重要

因为不是所有 instruction bit 都必须在 control unit 里解码。

有些 bit 是给 Frontend sequencer 用的。

`wait_after` 就是这种字段。

---

## 16. 把这个文件和前后链路接起来

现在你已经看了三段软件链：

1. `ub_allocator.py`
   - 定地址

2. `scheduler.py`
   - 生成阶段命令

3. `encode_instrs.py`
   - 把阶段命令编码成 32-bit 指令

现在 `control_unit.sv` 做的是第 4 步：

4. `control_unit.sv`
   - 把 32-bit 指令拆成 RTL 控制信号

链路可以写成：

```text
ub_map.json
  -> schedule.json
  -> imem.hex
  -> instruction[31:0]
  -> control_unit.sv decode
  -> UB / systolic / VPU 控制信号
```

---

## 17. 用 `stream_b1` 再对一次

前一份里说 `stream_b1` 最后编码成：

```text
00e24882
```

这条指令被送到 `control_unit.sv` 后，会先看：

```systemverilog
opcode = instruction[2:0]
```

因为它是 `UB_RD`，所以 opcode 是：

```text
010
```

然后进入：

```systemverilog
3'b010: begin // UB_RD
```

再把字段拆出来：

- `f_addr` -> `ub_rd_addr_in`
- `f_row` -> `ub_rd_row_size`
- `f_col` -> `ub_rd_col_size`
- `f_trans` -> `ub_rd_transpose`
- `f_ptr` -> `ub_ptr_sel`
- `f_vpu` -> `vpu_data_pathway`

所以软件里的一条：

```text
forward_layer1.stream_b1
```

到这里就变成了硬件侧的一组信号。

---

## 18. 小白最容易搞混的 5 个点

### 18.1 它不是状态机

`control_unit.sv` 里没有 `always_ff`，没有 `clk`，没有 `reset`。

所以它不是负责“下一拍去哪”的模块。

### 18.2 它不存 IMEM

IMEM 在 Frontend 那边。

control unit 只是拿到当前 `instruction` 后做组合 decode。

### 18.3 `wait_after` 不在这里处理

bit23 由 Frontend sequencer 直接看。

不要误以为 control unit 会拆所有 bit。

### 18.4 `NOP` 不是什么神秘动作

NOP 就是所有输出保持默认零。

### 18.5 `UB_RD` 不是普通 memory read

它还带着转置、指针语义和 VPU pathway。

所以它更像一次阶段级执行配置。

---

## 19. 最后一页总结

如果你只记 6 件事：

1. `control_unit.sv` 是组合 decode 模块。
2. 它输入一条 `instruction[31:0]`。
3. 它先拆 `opcode = instruction[2:0]`。
4. `SWITCH` 拉高 `sys_switch_in`。
5. `UB_RD` 拆出 UB 地址、行列、转置、ptr_sel、VPU pathway。
6. `wait_after` bit23 不在这里处理，而是在 Frontend sequencer 里处理。

最终一句话：

**`control_unit.sv` 的价值，是把软件打包好的 32-bit 指令，翻译成 UB、systolic、VPU 真正能用的一组硬件控制信号。**

---

## 20. 你看完这份后，下一步看什么

下一步建议看：

```text
/home/jjt/tpu-soc/docs/code_reading_pack_20260408/06_tpu_frontend_axil.sv_guide_zh.md
```

也就是 `tpu_frontend_axil.sv`。

原因是：

**Frontend 才是取 IMEM、发 instruction pulse、看 wait_after、等待 vpu_drain 的地方。**

你可以把阅读顺序记成：

```text
encoder 负责把命令变成 instruction
control_unit 负责把 instruction 拆成控制信号
frontend 负责决定 instruction 什么时候发、什么时候等
```

所以 `control_unit.sv` 看完之后，再看 Frontend，整个“指令从内存到硬件执行”的路径才会接上。

如果你继续，我下一份就做：

**`06_tpu_frontend_axil.sv` 的同风格小白逐段细讲版。**
