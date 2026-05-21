# `tpu_frontend_axil.sv` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`

这份文档只讲一个文件：`tpu_frontend_axil.sv`。
目标不是把每个 AXI 信号都解释一遍，而是让你真正理解：
**为什么这个文件是整个项目的控制中枢，它到底怎么把 Host 的寄存器写操作，变成 TPU 可以执行的一轮程序。**

---

## 1. 先给这个文件一个定位

很多人第一次看它，会把它误解成“AXI-Lite 外壳”。
这不对。

它至少叠了 4 个角色：

1. AXI-Lite slave 寄存器接口
2. IMEM 装载器
3. Sequencer
4. 指令译码后的控制脉冲分发器

所以这个文件不是边角料，而是：
**Host 世界进入 TPU 系统的控制入口。**

---

## 2. 文件开头已经把系统意图写出来了

最值得先看的不是 always_ff，而是顶部注释：

```systemverilog
// TinyTPU AXI-Lite Frontend (step mode + IMEM + sequencer)
```

这句话已经把三层能力讲清楚了：
- `step mode`：单步调试/打 staging 指令
- `IMEM`：把程序装起来
- `sequencer`：按程序自动推进

如果没有这三层，这个项目就只能停留在 testbench 手工打信号。

---

## 3. 寄存器地图就是控制语义地图

开头的寄存器定义非常关键：

```systemverilog
//   0x00  CTRL       bit0=step
//                   bit1=start
//   0x04  STATUS     bit0=busy
//                   bit1=running
//   0x10  INSTR_W0   32-bit opcode instruction
//   0x20  UB_DATA
//   0x24  UB_PUSH
//   0x30  IMEM_ADDR
//   0x34  IMEM_W0
//   0x40  IMEM_WE
//   0x44  IMEM_LEN
//   0x50  LEAK
//   0x54  INV_BATCH
//   0x58  LR
```

你可以把它直接翻译成人话：

- `CTRL`：开始跑，或者单步打一条
- `STATUS`：现在是不是还在执行
- `INSTR_W0`：step 模式临时放一条指令
- `UB_DATA/UB_PUSH`：Host 往 UB 里塞数据
- `IMEM_*`：Host 往程序存储里塞指令
- `LEAK / INV_BATCH / LR`：训练路径的参数配置

这个寄存器图已经说明，这个前端不是为“纯推理加速器”设计的，而是为当前 tiny-tpu 训练原型设计的。

---

## 4. 输出端口其实就是整个系统的控制面

文件的 output 很值得专门看一次：

```systemverilog
output logic [15:0] ub_wr_host_data_out_0,
output logic        ub_wr_host_valid_out_0,
output logic [15:0] ub_wr_host_data_out_1,
output logic        ub_wr_host_valid_out_1,
output logic        ub_wr_ptr_restore_out,

output logic        sys_switch_out,
output logic        ub_rd_start_out,
output logic        ub_rd_transpose_out,
output logic [1:0]  ub_rd_col_size_out,
output logic [3:0]  ub_rd_row_size_out,
output logic [5:0]  ub_rd_addr_out,
output logic [2:0]  ub_ptr_sel_out,
output logic [3:0]  vpu_data_pathway_out,
```

这批信号其实就是 PPT 里的“控制主链”。
它们大致分成三类：

1. Host 写 UB 的入口
2. UB 读流的控制字段
3. systolic/VPU 的运行语义字段

也就是说，Frontend 做的不是“协议搬运”，而是“控制语义发射”。

---

## 5. `clk_out` / `rst_out` 和 `start -> restore` 这两句值得单独记

先看：

```systemverilog
assign clk_out = s_axil_aclk;
assign rst_out = ~s_axil_aresetn;
assign ub_wr_ptr_restore_out = start_pulse;
```

前两句很好理解：
- TPU core 直接复用 AXI-Lite 时钟
- AXI-Lite 的低有效 reset 翻成 TPU 用的高有效 reset

第三句特别关键：

```systemverilog
assign ub_wr_ptr_restore_out = start_pulse;
```

这表示每次 `CTRL.start` 触发 auto-run 时，前端会同时触发 `wr_ptr_restore`。
也就是说：
- `start` 不只是“开始跑”
- 它还意味着“把运行时写指针恢复到静态参数区边界之后”

所以从系统语义上讲，`start` 其实等于：
**从一个干净边界重新开始一轮程序。**

---

## 6. 文件里真正的灵魂：Sequencer

### 6.1 状态定义本身就已经说明问题

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
```

这 4 个状态的意义是：

- `IDLE`：等 step/start
- `DISPATCH`：打一拍控制脉冲
- `WAIT`：等系统级完成边界
- `ADVANCE`：PC 前进到下一条

重点是：这里不是简单“取指-执行”，而是显式把系统同步边界单独做成一个状态。

### 6.2 `wait_after` 是怎么来的

```systemverilog
logic seq_needs_wait;
assign seq_needs_wait = seq_instr[23];
```

这说明前端直接把指令 bit23 当成 `wait_after`。
这和 PPT 里讲的“编译器会在 stage 边界插入 wait 语义”完全对应。

所以如果你被问“wait_after 最后落在哪里”，答案就是：
**落在 Frontend sequencer 的 `seq_instr[23]` 上。**

### 6.3 `IDLE` 同时支持 step 和 auto-run

看这段：

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

这里特别值得注意：
- `step` 走的是“打一条 staging 指令”
- `start` 走的是“PC 置零，从 IMEM[0] 开始自动运行”

所以这个前端同时支持：
- 调试模式
- 程序模式

这就是为什么它比普通寄存器接口更像一个小控制器。

### 6.4 `DISPATCH` 只负责打一拍，不负责收尾

```systemverilog
SEQ_DISPATCH: begin
    seq_instr_pulse <= 1'b1;
    if (seq_needs_wait)
        seq_state <= SEQ_WAIT;
    else
        seq_state <= SEQ_ADVANCE;
end
```

这段很重要，因为它强调：
**dispatch 只负责把控制发出去，不负责判断“这一步是否真的完成”。**

真正的完成边界要看后面 `WAIT`。

### 6.5 `WAIT` 不是等 dispatch 结束，而是等 `vpu_drain`

```systemverilog
if (vpu_drain) begin
    if (seq_running)
        seq_state <= SEQ_ADVANCE;
    else begin
        busy_reg  <= 1'b0;
        seq_state <= SEQ_IDLE;
    end
end
```

这段就是整套系统最关键的控制语义之一。

它说明：
- 一个 stage 完成，不是“脉冲发出去了”
- 也不是“UB 开始读了”
- 而是“VPU 最后的 valid 已经 drain 掉了”

所以 `wait_after` 在这套系统里是**系统级同步点**，不是装饰字段。

### 6.6 `ADVANCE` 才是程序边界管理

```systemverilog
if (pc + 1 < {{($clog2(IMEM_DEPTH)-6){1'b0}}, imem_len_reg}) begin
    pc        <= pc + 1;
    seq_instr <= imem[pc + 1];
    seq_state <= SEQ_DISPATCH;
end else begin
    seq_running <= 1'b0;
    busy_reg    <= 1'b0;
    seq_state   <= SEQ_IDLE;
end
```

这段说明 sequencer 并不是无限流，而是明确受 `IMEM_LEN` 约束。
程序跑到最后，会：
- 清 `running`
- 清 `busy`
- 回到 `IDLE`

所以 Host 侧轮询 `STATUS.busy` 就能知道一轮程序什么时候跑完。

---

## 7. `vpu_drain` 是怎么构出来的

代码里用了一个很典型的 edge-detect：

```systemverilog
vpu_valid_prev <= tpu_vpu_valid_in;
vpu_drain      <= vpu_valid_prev && !tpu_vpu_valid_in;
```

意思很直接：
- 这拍之前还有 VPU valid
- 这拍已经没有了
- 那就说明上一段尾拍排空了

所以 `vpu_drain` 的本质是：
**VPU 有效流从 1 掉到 0 的收尾沿。**

这就是 sequencer 用来判断“当前 stage 真正完成”的系统证据。

---

## 8. AXI-Lite 写通道：别钻握手细节，要抓“写了以后系统发生了什么”

### 8.1 写状态机只是标准壳

写通道状态机：

```systemverilog
typedef enum logic [1:0] {
    W_IDLE      = 2'b00,
    W_WAIT_W    = 2'b01,
    W_WAIT_AW   = 2'b10,
    W_RESP      = 2'b11
} w_state_t;
```

这个状态机本身没什么特别的，它主要负责把 AW/W 两拍拼起来，最后产生 `wr_fire`。

### 8.2 真正重要的是寄存器写 decode

```systemverilog
if (wr_fire) begin
    case (aw_lat)
        12'h000: begin
            if (wd_lat[0]) step_pulse  <= 1'b1;
            if (wd_lat[1]) start_pulse <= 1'b1;
        end
        12'h010: instr_w0_reg    <= wd_lat;
        12'h020: ub_data0_reg    <= wd_lat[15:0];
        12'h024: begin
            if (wd_lat[0]) ub_push0_pulse <= 1'b1;
            if (wd_lat[1]) ub_push1_pulse <= 1'b1;
        end
        12'h028: ub_data1_reg    <= wd_lat[15:0];
        12'h030: imem_addr_reg   <= wd_lat[$clog2(IMEM_DEPTH)-1:0];
        12'h034: imem_w0_reg     <= wd_lat;
        12'h040: if (wd_lat[0]) imem[imem_addr_reg] <= imem_w0_reg;
        12'h044: imem_len_reg    <= wd_lat[5:0];
        12'h050: leak_factor_reg   <= wd_lat[15:0];
        12'h054: inv_batch_n2_reg  <= wd_lat[15:0];
        12'h058: learning_rate_reg <= wd_lat[15:0];
    endcase
end
```

这段就是整个 Host 控制面的落点。

你可以按用途理解：
- `0x000`：发 step/start 脉冲
- `0x020/0x024/0x028`：往 UB lane0/lane1 装数据
- `0x030/0x034/0x040/0x044`：装 IMEM 程序
- `0x050/0x054/0x058`：装训练参数

所以你如果想回答“Host 到底怎么控制系统”，答案基本就在这段里。

---

## 9. AXI-Lite 读通道：为什么 `STATUS` 值得记

读通道本身也不难，但 `STATUS` 返回值很关键：

```systemverilog
12'h004: s_axil_rdata <= {30'h0, seq_running, busy_reg};
```

也就是说：
- bit0 = `busy`
- bit1 = `running`

这解释了测试里为什么可以用轮询 `0x004` 的方式等待一轮训练完成。

如果你需要一句非常实战的话术：
**软件侧不是盲等固定周期，而是通过 `STATUS` 观察 sequencer 是否真正结束。**

---

## 10. `control_unit` 在这里扮演什么角色

这一段容易被忽略：

```systemverilog
logic [31:0] instr_to_cu;
assign instr_to_cu = seq_instr_pulse ? seq_instr : '0;

control_unit cu_inst (
    .instruction                 (instr_to_cu),
    .sys_switch_in               (sys_switch_out),
    .ub_rd_start_in              (ub_rd_start_out),
    ...
    .ub_ptr_sel                  (ub_ptr_sel_out),
    .vpu_data_pathway            (cu_vpu_data_pathway),
```

它说明 Frontend 自己并不手写所有字段 decode，而是：
- sequencer 决定“什么时候把一条指令发给 control_unit”
- control_unit 决定“这条指令拆成哪些硬件字段”
- Frontend 再把这些字段组织成系统输出口

所以 Frontend 其实是“sequencer + register file + AXI + mux + decode glue”的组合。

---

## 11. `vpu_pathway_reg` 为什么要 latch

代码里有一句：

```systemverilog
if (seq_instr_pulse && seq_instr[2:0] == 3'b010)
    vpu_pathway_reg <= seq_instr[22:19];
```

后面输出又是：

```systemverilog
assign vpu_data_pathway_out = vpu_pathway_reg;
```

这说明 VPU pathway 不是“打一拍就没了”，而是要在一个阶段里持续保持。

这很合理，因为 VPU 路径决定的是：
- forward
- transition/loss
- backward derivative

这些都不是单拍动作，而是一段流的语义。

所以这句 latch 是为了让 `1100 / 1111 / 0001` 这些路径码在阶段期间稳定生效。

---

## 12. Host UB_PUSH 和 control_unit 的 UB_WR_HOST 为什么要做 mux

这一段很容易考：

```systemverilog
assign ub_wr_host_valid_out_0 = ub_push0_pulse ? 1'b1        : cu_ub_valid_0;
assign ub_wr_host_valid_out_1 = ub_push1_pulse ? 1'b1        : cu_ub_valid_1;
assign ub_wr_host_data_out_0  = ub_push0_pulse ? ub_data0_reg : cu_ub_data_0;
assign ub_wr_host_data_out_1  = ub_push1_pulse ? ub_data1_reg : cu_ub_data_1;
```

这里体现的是：
- Host 可以通过寄存器直接往 UB 推数据
- control_unit 也可能通过指令语义发起 UB_WR_HOST
- 两条路径最终共用同一个 UB host write 口
- 但如果当前有 AXI `UB_PUSH`，它优先

这段 mux 非常工程化，它解决的是“一个写口，两种来源”的问题。

如果你被问“为什么要这样设计”，可以直接答：
**因为系统既要支持 Host 直接装数据，也要支持指令驱动的 host-write 语义，所以最终在前端统一仲裁。**

---

## 13. 把整个文件压成一句流程图

你可以把 `tpu_frontend_axil.sv` 理解成下面这条链：

1. AXI-Lite 写寄存器
2. 寄存器更新 `CTRL / UB / IMEM / training params`
3. `step` 或 `start` 产生脉冲
4. Sequencer 取指并决定 `dispatch / wait / advance`
5. `control_unit` 拆字段
6. Frontend 输出 `ub_rd_start / ptr_sel / pathway / switch / ub_wr_host_*`
7. TPU core 执行
8. Frontend 用 `vpu_drain` 收 stage 边界

这就是整个文件的骨架。

---

## 14. 你最该记住的 8 个点

1. 它不是 AXI 壳，而是控制中枢。
2. `start_pulse` 同时触发一轮正式运行和 `wr_ptr_restore`。
3. `step` 是临时单步，`start` 是程序模式。
4. `wait_after` 直接落在 `seq_instr[23]`。
5. `DISPATCH` 只打一拍，不代表阶段完成。
6. 真正的阶段完成边界是 `vpu_drain`。
7. `vpu_pathway` 会被 latch，在阶段期间持续有效。
8. Host 的 `UB_PUSH` 和 control_unit 的 `UB_WR_HOST` 在这里做统一仲裁。

---

## 15. 最后一句话

如果只让我用一句话概括这个文件，那就是：

**`tpu_frontend_axil.sv` 把 Host 的寄存器写操作，翻译成了 tiny-tpu 整个系统可以按阶段稳定执行的控制节奏。**
