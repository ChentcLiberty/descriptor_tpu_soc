# `control_unit.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/control_unit.sv`

这份文档按源码行号解释 `control_unit.sv`。
它的重点不是讨论综合技巧，而是要解释：
**Frontend 发出去的一条 32-bit 指令，在这里是怎么被拆成真正的 UB / systolic / VPU 控制字段的。**

---

## [1-15] 端口定义：它不是“控制器”，更像“字段拆包器”

如果你直接看端口，会发现它没有时钟，也没有状态机，几乎全是组合式输出：

- 输入：`instruction`
- 输出：`sys_switch_in`
- 输出：`ub_rd_start_in`
- 输出：`ub_rd_transpose`
- 输出：`ub_wr_host_valid_in_1/2`
- 输出：`ub_rd_col_size`
- 输出：`ub_rd_row_size`
- 输出：`ub_rd_addr_in`
- 输出：`ub_ptr_sel`
- 输出：`ub_wr_host_data_in_1/2`
- 输出：`vpu_data_pathway`
- 透传：`inv_batch_size_times_two_in`、`vpu_leak_factor_in`

这说明它做的不是复杂时序控制，而是：
**把 32-bit 指令拆成后级模块能理解的字段。**

---

## [18-21] 指令拆字段：一眼看懂 32-bit 指令格式怎么落地

```systemverilog
wire [2:0] opcode  = instruction[2:0];
wire [15:0] imm16  = instruction[18:3];
wire [5:0]  ub_addr = instruction[8:3];
wire [3:0]  ub_row  = instruction[12:9];
wire [1:0]  ub_col  = instruction[14:13];
```

这一段很关键，因为它把前面 Frontend 注释里的“指令格式”真正落到了电路字段上。

你可以直接对应：
- `opcode`
- `addr`
- `row`
- `col`
- `imm16`

所以从编译器视角看，scheduler 生成的 32-bit 控制字，最终就是在这里被拆出来的。

---

## [23-40] always @(*)：整个模块就是纯组合 decode

```systemverilog
always @(*) begin
    ...
    case (opcode)
        3'b000: begin ... end
        3'b001: begin ... end
        3'b010: begin ... end
        3'b011: begin ... end
        default: begin ... end
    endcase
end
```

这说明 `control_unit` 没有内部状态，不记历史，不决定节奏。
它只做一件事：
**当前拍来的这条指令，到底该翻译成什么控制字段。**

所以系统节奏是 Frontend sequencer 决定的；字段语义是这里 decode 的。

---

## [24-35] 默认值：为什么 decode 模块一定要先清零

这一段会先把输出默认清零：

- `sys_switch_in = 0`
- `ub_rd_start_in = 0`
- `ub_rd_transpose = 0`
- `ub_wr_host_valid_in_1/2 = 0`
- `ub_rd_col_size = 0`
- `ub_rd_row_size = 0`
- `ub_rd_addr_in = 0`
- `ub_ptr_sel = 0`
- `ub_wr_host_data_in_1/2 = 0`
- `vpu_data_pathway = 0`

这个模式很重要，因为这说明 decode 的语义是：
- 只有命中的 opcode 字段才会被显式驱动
- 其他控制默认不动作

所以它天然适合被 sequencer 以单拍 pulse 驱动。

---

## [42-44] `NOP`：空操作就是所有字段都保持默认零

```systemverilog
3'b000: begin
    // NOP
end
```

这说明 NOP 的本质不是“做点什么”，而是“什么也不驱动”。

结合 scheduler 里的 `_nop()`，你就会明白：
- compiler 插入 NOP 不是为了表达算法
- 而是为了在系统时序上留空拍，让装载波前、路径切换、下游状态稳定下来

---

## [46-48] `SWITCH`：阵列权重激活边界就在这三行里

```systemverilog
3'b001: begin
    sys_switch_in = 1'b1;
end
```

这三行非常短，但意义很大。

它说明：
- 一条 `SWITCH` 指令
- 最终只会拉起 `sys_switch_in`
- 后续由 `systolic` 内部完成 shadow -> active 权重切换

所以 scheduler 里那种：
- load weight shadow
- nop
- switch
- stream input

在 RTL 上真正落地，就是先发若干 UB_RD 和 NOP，再在这里打一拍 `sys_switch_in`。

---

## [49-57] `UB_RD`：整个项目最重要的指令类型

```systemverilog
3'b010: begin
    ub_rd_start_in   = 1'b1;
    ub_rd_addr_in    = ub_addr;
    ub_rd_row_size   = ub_row;
    ub_rd_col_size   = ub_col;
    ub_rd_transpose  = instruction[15];
    ub_ptr_sel       = instruction[18:16];
    vpu_data_pathway = instruction[22:19];
end
```

这 7 行几乎就是整个系统的核心 decode。

它说明一条 `UB_RD` 指令会同时决定：
1. 启动一次 UB 读流
2. 从哪里读
3. 读多大块
4. 是否转置
5. 这次读是什么语义（input/weight/bias/Y/H/old params）
6. 这次执行对应哪条 VPU 路径

换句话说：
**一条 `UB_RD` 不只是“读 memory”，而是一次完整的阶段级执行配置。**

这也是为什么 `_ub_read()` 是 scheduler 的核心 helper。

---

## [58-63] `UB_WR_HOST`：为什么指令也能触发 Host 写口

```systemverilog
3'b011: begin
    ub_wr_host_valid_in_1 = 1'b1;
    ub_wr_host_valid_in_2 = 1'b1;
    ub_wr_host_data_in_1  = imm16;
    ub_wr_host_data_in_2  = imm16;
end
```

这一段说明指令集里还保留了 `UB_WR_HOST` 语义。

虽然当前主线更常用的是 AXI 侧 `UB_PUSH`，但这段 RTL 说明：
- 指令自身也可以编码一个 host-write 类动作
- 最终会走到 Frontend 里的 host write mux

所以你看 Frontend 那段 mux 就能明白：
为什么它要仲裁 AXI `UB_PUSH` 和 CU `UB_WR_HOST` 两条来源。

---

## [49-57] 和 scheduler 的一一对应关系

如果你把这一段和 `scheduler.py` 对起来看，会发现一一映射：

scheduler 输出：
```python
"signals": {
    "ub_rd_start_in": 1,
    "ub_ptr_select": ptr_sel,
    "ub_rd_addr_in": addr,
    "ub_rd_row_size": row,
    "ub_rd_col_size": col,
    "ub_rd_transpose": int(transpose),
}
```

`control_unit` decode：
```systemverilog
ub_rd_start_in   = 1'b1;
ub_rd_addr_in    = ub_addr;
ub_rd_row_size   = ub_row;
ub_rd_col_size   = ub_col;
ub_rd_transpose  = instruction[15];
ub_ptr_sel       = instruction[18:16];
vpu_data_pathway = instruction[22:19];
```

这就是软件和硬件字段真正严丝合缝对上的地方。

---

## 这个文件最该记住的 6 个点

1. 它是纯组合 decode，不决定系统节奏。
2. Frontend sequencer 决定什么时候发指令，它决定这条指令拆成什么字段。
3. `NOP` 的本质是所有输出保持默认零。
4. `SWITCH` 最终只拉起 `sys_switch_in`，为阵列权重激活服务。
5. `UB_RD` 是最重要的 opcode，因为它同时编码 UB 读流和 VPU 路径语义。
6. `UB_WR_HOST` 的存在解释了 Frontend 为什么要仲裁两类 host write 来源。

最后一句话：
**`control_unit.sv` 的价值，不在于复杂，而在于它是软件 32-bit 控制字和硬件执行字段之间那一层最直接、最关键的映射。**
