# `tpu_frontend_axil.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`

这份文档的目标不是再讲概念，而是直接对着源码行号读。
你可以打开源文件，然后按下面的行段往下看。

---

## [4-27] 文件头注释：这个模块到底想做什么

这一段最值钱的不是语法，而是它把模块定位一次讲清楚了：

- `step mode + IMEM + sequencer`
- AXI-Lite 寄存器图
- 32-bit 指令格式

这说明这个模块从设计之初就不是“纯寄存器壳”，而是：
1. 支持单步调试
2. 支持程序化自动运行
3. 支持把控制字拆成 UB / systolic / VPU 能理解的字段

如果你只记一句话：
**这 20 多行注释已经定义了整个前端的系统职责。**

---

## [29-85] 模块端口：整个系统的控制面都从这里出去

这一段最该看的是 output：

- `ub_wr_host_data_out_*`
- `ub_wr_host_valid_out_*`
- `ub_wr_ptr_restore_out`
- `sys_switch_out`
- `ub_rd_start_out`
- `ub_rd_transpose_out`
- `ub_rd_col_size_out`
- `ub_rd_row_size_out`
- `ub_rd_addr_out`
- `ub_ptr_sel_out`
- `vpu_data_pathway_out`
- `inv_batch_size_times_two_out`
- `vpu_leak_factor_out`
- `learning_rate_out`

这批信号几乎就是 PPT 里“控制主链”的原始来源。

理解方法：
- Host 世界通过 AXI-Lite 写寄存器
- 这个模块把寄存器语义变成系统控制口
- 下游 `tpu_soc -> tpu -> UB / systolic / VPU` 再消费这些控制口

所以这段端口定义不是形式化声明，而是整套 SoC 控制面的边界定义。

---

## [87-89] 三条 assign：最短但最关键的语义桥接

```systemverilog
assign clk_out = s_axil_aclk;
assign rst_out = ~s_axil_aresetn;
assign ub_wr_ptr_restore_out = start_pulse;
```

前两句是时钟/复位桥接。
第三句最重要：

- 每次 `CTRL.start=1`
- 前端除了启动 sequencer
- 还会同步触发 `wr_ptr_restore`

这就是为什么 `start` 在系统语义上不只是“开始跑”，而是“从静态参数区边界后重新开始一轮”。

这三句很短，但直接把 Host 控制语义和 UB 内部运行边界接起来了。

---

## [94-113] 前端内部寄存器：分成 4 组看

这段定义不要散看，最好分组理解：

1. staged instruction
- `instr_w0_reg`

2. host 写 UB staging
- `ub_data0_reg`
- `ub_data1_reg`
- `ub_push0_pulse`
- `ub_push1_pulse`

3. sequencer / status
- `step_pulse`
- `start_pulse`
- `busy_reg`

4. training params / IMEM
- `leak_factor_reg`
- `inv_batch_n2_reg`
- `learning_rate_reg`
- `imem_addr_reg`
- `imem_w0_reg`
- `imem_len_reg`

也就是说，这一段内部状态正好覆盖了：
- 指令 staging
- 数据 staging
- 程序执行状态
- 训练参数配置

这也是为什么我一直说，这个前端不是寄存器壳，而是一个小控制器。

---

## [122-139] Sequencer 状态和 `wait_after`

这几行是前端灵魂：

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
...
assign seq_needs_wait = seq_instr[23];
```

关键点有两个：

1. sequencer 把“系统同步边界”单独抽成 `WAIT` 状态。
2. 编译器的 `wait_after` 最终直接落成 `seq_instr[23]`。

所以这里是 software schedule 和 hardware sequencer 真正对接的地方。

---

## [141-180] sequencer 前半段：`IDLE` 和 `DISPATCH`

这一段决定了 step 和 auto-run 的分岔。

### [160-173] `SEQ_IDLE`

```systemverilog
if (step_pulse) begin
    ...
end else if (start_pulse) begin
    pc          <= '0;
    seq_instr   <= imem[0];
    seq_running <= 1'b1;
    ...
end
```

这说明：
- `step` 只打一条 staging 指令
- `start` 才进入程序模式，从 `imem[0]` 开始

### [176-180] `SEQ_DISPATCH`

```systemverilog
seq_instr_pulse <= 1'b1;
if (seq_needs_wait)
    seq_state <= SEQ_WAIT;
else
    seq_state <= SEQ_ADVANCE;
```

这里最重要的认知是：
**dispatch 只负责把控制打一拍送给 `control_unit`，不代表这一阶段真的执行完。**

---

## [181-204] sequencer 后半段：`WAIT` 和 `ADVANCE`

这段一定要和上一段一起看。

### [184-191] `SEQ_WAIT`

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

这一段说明阶段完成边界不是 dispatch，不是 UB 发数开始，也不是 systolic 有输出，而是：
**VPU 的最后一个有效输出已经 drain 掉。**

### [195-204] `SEQ_ADVANCE`

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

这说明前端的程序边界不是硬编码条数，而是看 `IMEM_LEN`。

软件侧为什么能轮询 `STATUS.busy` 判定完成，就是因为这里会在结束时清 `busy_reg`。

---

## [152-157] `vpu_drain` 边沿检测：系统级 wait 的证据源

虽然位置在 sequencer always_ff 内部，但这几行值得单独讲：

```systemverilog
vpu_valid_prev <= tpu_vpu_valid_in;
vpu_drain      <= vpu_valid_prev && !tpu_vpu_valid_in;
...
if (seq_instr_pulse && seq_instr[2:0] == 3'b010)
    vpu_pathway_reg <= seq_instr[22:19];
```

前两句构造 `vpu_drain`，后两句 latch `vpu_pathway`。

它们分别代表：
- “这一阶段什么时候真正结束”
- “这一阶段 VPU 应该按什么训练路径工作”

所以这 6 行虽然小，但直接决定系统节奏和训练语义。

---

## [215-249] 寄存器写 decode：Host 到系统语义的第一跳

这段是软件控制面的核心落点。

### [230-233] `CTRL`

```systemverilog
12'h000: begin
    if (wd_lat[0]) step_pulse  <= 1'b1;
    if (wd_lat[1]) start_pulse <= 1'b1;
end
```

软件写 `0x000`：
- bit0 触发单步
- bit1 触发自动运行

### [234-240] `INSTR_W0 / UB_DATA / UB_PUSH / lane1 data`

这几项对应：
- step 模式暂存指令
- lane0/lane1 的 host 数据 staging
- 再用 `UB_PUSH` 脉冲把它们真正送出去

### [241-244] `IMEM_ADDR / IMEM_W0 / IMEM_WE / IMEM_LEN`

这一组负责把程序写进 IMEM。
其中：
- `0x030` 设地址
- `0x034` 写 staging instruction
- `0x040` commit 进 `imem[imem_addr_reg]`
- `0x044` 设置程序长度

### [145-147] 训练参数

- `0x050` -> `leak_factor_reg`
- `0x054` -> `inv_batch_n2_reg`
- `0x058` -> `learning_rate_reg`

这说明前端不只是调度器，还负责把训练路径参数送进系统。

---

## [157-186] AXI-Lite 读通道：软件侧可观测性从哪里来

这段最重要的不是读协议本身，而是：

```systemverilog
12'h004: s_axil_rdata <= {30'h0, seq_running, busy_reg};
```

这表示：
- bit0 = `busy`
- bit1 = `running`

测试里轮询 `STATUS`，本质上就是在读这里。

所以如果你要回答“软件怎么知道一轮跑完了”，答案不是“估时钟周期”，而是“直接轮询前端导出的 `STATUS`”。

---

## [191-215] `control_unit` 接入：sequencer 和字段 decode 的接缝

```systemverilog
logic [31:0] instr_to_cu;
assign instr_to_cu = seq_instr_pulse ? seq_instr : '0;

control_unit cu_inst (
    .instruction                 (instr_to_cu),
    .sys_switch_in               (sys_switch_out),
    .ub_rd_start_in              (ub_rd_start_out),
    ...
);
```

这里说明前端内部又分两层：

1. sequencer 决定什么时候发一条指令
2. `control_unit` 决定这条指令拆成哪些硬件字段

所以 Frontend 不是手写 decode 的一团逻辑，而是：
- sequencing
- register file
- AXI-Lite
- decode glue
的组合。

---

## [218-228] UB host write mux：为什么要统一仲裁两条写路径

这一段非常工程化：

```systemverilog
assign ub_wr_host_valid_out_0 = ub_push0_pulse ? 1'b1        : cu_ub_valid_0;
assign ub_wr_host_valid_out_1 = ub_push1_pulse ? 1'b1        : cu_ub_valid_1;
assign ub_wr_host_data_out_0  = ub_push0_pulse ? ub_data0_reg : cu_ub_data_0;
assign ub_wr_host_data_out_1  = ub_push1_pulse ? ub_data1_reg : cu_ub_data_1;
```

它解决的问题是：
- Host 可以通过寄存器直接装 UB
- 指令本身也可能有 `UB_WR_HOST` 语义
- 但最终对 UB 来说就只有一条 host-write 入口

所以这里必须做 mux / arbitration。
而且 AXI `UB_PUSH` 优先，说明系统优先相信 Host 的显式装载动作。

---

## 一页总结

如果你只想记这份文件的核心线索，就记这 6 句：

1. 行 `4-27` 定义了它是 `step + IMEM + sequencer` 前端。
2. 行 `66-84` 定义了整个系统的主要控制输出口。
3. 行 `87-89` 说明 `start` 会同步触发 `wr_ptr_restore`。
4. 行 `122-204` 定义了 `wait_after -> vpu_drain` 的系统级执行边界。
5. 行 `128-147` 定义了 Host 如何写 `CTRL / UB / IMEM / training params`。
6. 行 `225-228` 定义了 Host `UB_PUSH` 和指令 `UB_WR_HOST` 的统一仲裁。

最后一句话：
**这个文件最重要的价值，不是“支持 AXI-Lite”，而是把软件的寄存器写操作变成了一条按阶段稳定推进的系统执行节奏。**
