# TinyTPU AXI-Lite SoC 源码精讲版

这份文档是“逐文件源码精讲版”。
如果前面三份文档分别是：
- `05_project_explainer_zh.md`：全景说明文
- `06_interview_walkthrough_zh.md`：按 8 页主讲版逐页讲
- `07_study_guide_zh.md`：复习提纲

那么这份文档的定位就是：
**带着你按文件把项目重新走一遍，知道每个关键文件到底在解决什么问题，关键代码为什么要那样写。**

建议配合这几份材料一起看：
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/01_main_8p.pptx`
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/02_appendix_35p.pptx`
- `/home/jjt/tpu-soc/docs/tpu_project_full_explainer_zh.md`
- `/home/jjt/tpu-soc/docs/tpu_project_interview_walkthrough_zh.md`
- `/home/jjt/tpu-soc/docs/tpu_project_study_guide_zh.md`

---

## 1. 先把“源码地图”建立起来

这个项目最关键的源码，其实就 6 个入口：

1. `src_axi/tpu_soc.sv`
2. `src_axi/tpu_frontend_axil.sv`
3. `compiler/scheduler.py`
4. `src_axi/tpu.sv`
5. `src_axi/unified_buffer_v3.sv`
6. `test/test_tpu_soc_axil_train_convergence.py`

它们分别回答的问题是：

1. 顶层到底怎么把 Host、Frontend、TPU core 接起来？
2. AXI-Lite 怎么变成寄存器、IMEM、sequencer 和控制脉冲？
3. 软件侧怎么把模型意图降成当前 RTL 能执行的阶段级命令？
4. TPU core 内部到底由哪三块组成？
5. 为什么 UB 是整个系统的数据中枢，训练更新又是怎么在里面做的？
6. 怎么证明这套系统不只是“看起来会动”，而是真的能跑训练闭环？

这 6 个文件不是平行关系，而是一条链：

`Host / cocotb -> AXI-Lite frontend -> tpu_soc -> tpu -> UB / systolic / VPU -> wave / loss / convergence`

所以阅读方式不要按“哪个文件最长先看哪个”，而要按“控制怎么进去，数据怎么流，结果怎么出来”来读。

---

## 2. `tpu_soc.sv`：顶层桥接层

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_soc.sv`

### 2.1 这个文件的角色

`tpu_soc.sv` 本身不做复杂计算，它做的是桥接。
它把：
- 上面的 AXI-Lite Host
- 中间的 Frontend
- 下面的 TPU core
接成一层真正可控的顶层。

源码开头的注释已经把它的定位写得很直接：

```systemverilog
// TinyTPU SoC Top
// Wraps tpu_frontend_axil + tpu into a single AXI-Lite controlled accelerator.
```

所以理解这个文件的第一原则是：
**它是系统整合层，不是算法层。**

### 2.2 最核心的两实例

真正决定结构的，其实就是这两块：

```systemverilog
tpu_frontend_axil #(
    .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
) frontend (...);

 tpu #(
    .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
) tpu_inst (...);
```

你可以把它理解成：
- `frontend` 负责“把主机命令翻译成 TPU 控制语义”
- `tpu_inst` 负责“真正执行 UB + systolic + VPU 的运算链”

### 2.3 为什么中间有一堆桥接信号

看这组信号就很清楚：

```systemverilog
logic [15:0] ub_wr_host_data_0, ub_wr_host_data_1;
logic        ub_wr_host_valid_0, ub_wr_host_valid_1;
logic        ub_wr_ptr_restore;
logic        sys_switch;
logic        ub_rd_start;
logic [2:0]  ub_ptr_sel;
logic [3:0]  vpu_data_pathway;
```

这些信号不是随便拉的，它们正好对应这套系统的关键控制面：
- host 写 UB
- write pointer restore
- systolic shadow/active 权重切换
- UB 读流启动
- 当前读流语义选择
- VPU 路径选择

所以 `tpu_soc` 干的事情，本质上是把“主机的寄存器世界”变成“核内部能理解的控制世界”。

### 2.4 为什么有零扩展

这里有一段很容易在阅读时忽略，但很重要：

```systemverilog
.ub_ptr_select              ({6'h0, ub_ptr_sel}),
.ub_rd_addr_in              ({10'h0, ub_rd_addr}),
.ub_rd_row_size             ({12'h0, ub_rd_row_size}),
.ub_rd_col_size             ({14'h0, ub_rd_col_size}),
```

这段说明两件事：

1. Frontend 输出的是当前项目足够用的窄控制信号。
2. TPU core/UB 接口保留了更宽的表达能力。

也就是说，当前 SoC 顶层不是在追求“最完美的接口设计”，而是在做一个**够用且稳定的桥接适配层**。

### 2.5 读这个文件时你应该抓什么

你不需要在 `tpu_soc.sv` 里研究算法。
你只需要抓三件事：

1. `frontend` 和 `tpu_inst` 是怎么接起来的。
2. 哪些信号是真正跨模块传递系统语义的。
3. 这个顶层为什么说明项目已经从“裸核原型”变成“主机可控 SoC”。

### 2.6 一句话总结

`tpu_soc.sv` 的价值不是“做了很多逻辑”，而是它让整套系统第一次有了真正的顶层闭环入口。

---

## 3. `tpu_frontend_axil.sv`：控制中枢

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`

### 3.1 这个文件到底是什么

很多人第一次看它，会把它当成“一个 AXI-Lite 寄存器模块”。
这不够准确。

它实际上叠了 4 个角色：

1. AXI-Lite 寄存器块
2. IMEM 装载入口
3. Sequencer
4. 指令译码后的控制脉冲发生器

所以它不是边角料，而是**整个系统的控制中枢**。

### 3.2 先看寄存器地图

文件开头直接给了寄存器定义：

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

这张表已经把项目的控制思路暴露得很清楚：
- `CTRL/STATUS` 控制运行状态
- `INSTR_W0` 支持 step 模式临时打一条指令
- `IMEM_*` 支持 auto-run 模式按程序执行
- `UB_*` 支持 host 直接装载数据
- `LEAK / INV_BATCH / LR` 支持训练参数配置

所以你从这张寄存器图就能看出来：
**这个前端不是只为推理设计的，而是为训练路径设计的。**

### 3.3 step 和 start 两种模式

看这句：

```systemverilog
assign ub_wr_ptr_restore_out = start_pulse;
```

这句很关键。
说明每次 `start` 自动运行一轮时，前端会同时触发 `wr_ptr_restore`。
这意味着：
- `step` 更像单步 debug / staging
- `start` 才是“从 host 装载区边界开始，执行完整一轮程序”的正式运行入口

所以 `start` 不是只拉高 busy，而是在系统语义上代表：
**从一个干净的运行边界重新开始。**

### 3.4 Sequencer 是这文件的核心

最值得看的代码是状态机：

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
```

配合这段：

```systemverilog
case (seq_state)
    SEQ_IDLE: begin
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

    SEQ_DISPATCH: begin
        seq_instr_pulse <= 1'b1;
        if (seq_needs_wait)
            seq_state <= SEQ_WAIT;
        else
            seq_state <= SEQ_ADVANCE;
    end
```

这一段说明：
- `IDLE` 决定是走 step 还是 auto-run
- `DISPATCH` 只打一拍控制脉冲
- `WAIT` 决定系统同步边界
- `ADVANCE` 才推进 PC

所以它不是普通 PC+IMEM，而是带系统同步语义的 sequencer。

### 3.5 `wait_after` 真正靠什么收边界

看这里：

```systemverilog
logic seq_needs_wait;
assign seq_needs_wait = seq_instr[23];
```

再看：

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

这两段拼起来，你就会明白：

- `wait_after` 不是装饰位
- `dispatch` 也不是完成边界
- 真正的系统完成边界是 `vpu_drain`

这就是为什么这项目一直强调“系统级 wait 语义”。
它不是为了写好看，而是为了防止阶段之间尾拍互相踩踏。

### 3.6 一个很容易忽略的细节：VPU pathway latch

这里还有一段值得注意：

```systemverilog
if (seq_instr_pulse && seq_instr[2:0] == 3'b010)
    vpu_pathway_reg <= seq_instr[22:19];
```

这表示：
- VPU pathway 在 UB_RD dispatch 时被 latch 住
- 后续会持续保持，而不是每拍都重新给

这跟 PPT 里讲的 `1100 / 1111 / 0001` 三条路径正好对应。
说明 Frontend 不只是发“读 UB”命令，还负责把 VPU 路径语义稳定地带过去。

### 3.7 一句话总结

`tpu_frontend_axil.sv` 的本质，不是 AXI 壳，而是把“主机寄存器世界”翻译成“系统执行节奏”的控制中枢。

---

## 4. `scheduler.py`：把软件意图降成硬件阶段命令

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/scheduler.py`

### 4.1 不要误解它的定位

这不是一个通用编译器，也不是 cycle-accurate program compiler。
它更像一个：
**当前 tiny-tpu 原型的阶段级调度器。**

文件里 `_validate_current_target()` 已经明确写死了当前边界：

```python
if len(layers) != 2:
    raise ValueError("scheduler currently supports exactly two linear layers")
if hw.get("array_width") != 2 or hw.get("lanes") != 2:
    raise ValueError("scheduler currently targets the 2x2 / 2-lane tiny-tpu prototype")
```

这说明它不是想装成通用框架，而是很诚实地服务当前项目目标。

### 4.2 `_ub_read()` 是理解它的钥匙

最关键的 helper 是：

```python
def _ub_read(
    stage: str,
    name: str,
    tensor: str,
    ptr_sel: int,
    addr: int,
    row: int,
    col: int,
    transpose: bool,
    *,
    vpu_path: str | None = None,
    note: str = "",
    wait_after: bool = False,
) -> dict[str, Any]:
```

生成的命令结构是：

```python
command = {
    "stage": stage,
    "name": name,
    "kind": "ub_read",
    "tensor": tensor,
    "signals": {
        "ub_rd_start_in": 1,
        "ub_ptr_select": ptr_sel,
        "ub_rd_addr_in": addr,
        "ub_rd_row_size": row,
        "ub_rd_col_size": col,
        "ub_rd_transpose": int(transpose),
    },
    "wait_after": int(wait_after),
}
```

这段非常重要，因为它说明编译器输出的核心，不是高层 tensor graph，而是：
- 从 UB 哪读
- 读什么语义
- 读多大块
- 要不要转置
- 读完要不要等系统收边界

也就是说，schedule 已经非常贴近硬件控制接口了。

### 4.3 三类辅助命令

文件里除了 `_ub_read()`，还有：

```python
def _switch(...):
def _wait(...):
def _nop(...):
```

这意味着 scheduler 输出的不是单一“读命令流”，而是一套阶段级动作脚本：
- load weight tile
- nop 让装载波前走完
- switch shadow -> active
- stream input / bias / Y / H
- wait `vpu_drain`

这正是 PPT 里“编译器与指令组织”那页在讲的内容。

### 4.4 `forward_layer1` 怎么体现项目主线

看这一段：

```python
commands.append(
    _ub_read(
        "forward_layer1",
        "load_w1_shadow",
        "W1",
        1,
        tensors["W1"]["addr"],
        hidden_dim,
        input_dim,
        True,
        note="Load W1^T through the top boundary into the PE shadow weight path.",
    )
)
...
commands.append(_switch("forward_layer1", "activate_w1"))
...
commands.append(
    _ub_read(
        "forward_layer1",
        "stream_x",
        "X",
        0,
        tensors["X"]["addr"],
        batch_size,
        input_dim,
        False,
        vpu_path="1100",
    )
)
```

这里几乎把系统思想全说透了：
- 权重先装 shadow
- 再 `switch` 成 active
- 然后输入从左边流进 systolic
- 同时 VPU pathway 设成 `1100`

这已经不是“某个算子怎么实现”的问题，而是**系统如何把一层前向执行成一串可控步骤**。

### 4.5 `transition_layer2` 为什么特别能说明训练语义

看这里：

```python
"stream_h1" ... vpu_path="1111"
"stream_b2" ... vpu_path="1111"
"stream_y"  ... vpu_path="1111"
"load_old_b2" ... ptr_sel=5 ... wait_after=True
```

这表示这一步不是单纯 forward，而是：
- 第二层 forward
- loss gradient
- bias update
三件事绑在同一阶段里。

所以 `1111` 这条路径的意义，不是一个随便的 bit pattern，而是整个训练过渡阶段的语义编码。

### 4.6 backward 和 update 为什么有说服力

后面这几段尤其能体现“这是训练，不是推理”：

```python
"stream_dz2" ... vpu_path="0001"
"stream_h1_for_derivative" ... ptr_sel=4 ... wait_after=True
```

和：

```python
stage = f"update_w1_tile_{tile_index}"
...
"load_old_w1" ... ptr_sel=6 ... wait_after=True
```

这说明：
- backward 需要 `dZ2`、`H1`、旧 bias
- weight update 需要 outer product tile 和旧权重
- 更新并不是在外部软件算好再写回，而是通过 UB 内 gradient descent 在系统内部完成

### 4.7 `host_load_plan` 为什么关键

最终 `build_schedule()` 还返回：

```python
"host_load_plan": host_load_plan,
"ub_allocation": allocation,
"commands": commands,
```

这说明 scheduler 不只是给 RTL 看，它同时也在告诉 Host：
- 先把哪些 tensor 装到 UB 哪些地址
- 然后再按什么阶段序列执行

这一步正是软件和硬件握手的结合点。

### 4.8 一句话总结

`scheduler.py` 的真正价值，是把“模型训练意图”变成“当前 tiny-tpu 原型可以稳定执行的阶段级硬件动作脚本”。

---

## 5. `tpu.sv`：执行核心组合点

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu.sv`

### 5.1 这个文件没有你想象得复杂

第一次看 `tpu.sv`，很容易期待里面有大量复杂控制。
其实没有。
它做的事情非常明确：

```systemverilog
unified_buffer ub_inst(...);
systolic systolic_inst(...);
vpu vpu_inst(...);
```

这说明 `tpu.sv` 是一个**执行核心组合点**。
它不是编译器，不是前端，不是 sequencer，而是把三块执行资源接成一条数据链。

### 5.2 数据怎么从 UB 走进阵列和 VPU

你看接口就会发现它其实把路径切得很清楚：

- UB -> systolic 左边：`ub_rd_input_*`
- UB -> systolic 上边：`ub_rd_weight_*`
- UB -> VPU：`ub_rd_bias_*`, `ub_rd_Y_*`, `ub_rd_H_*`
- systolic -> VPU：`sys_data_out_*`, `sys_valid_out_*`
- VPU -> UB：`vpu_data_out_*`, `vpu_valid_out_*`

所以 `tpu.sv` 是整个项目里“数据流最直观”的文件。

### 5.3 Host 写进来的数据怎么落到 UB

这段也很重要：

```systemverilog
input logic [15:0] ub_wr_host_data_in [0:SYSTOLIC_ARRAY_WIDTH-1],
input logic ub_wr_host_valid_in [0:SYSTOLIC_ARRAY_WIDTH-1],
input logic ub_wr_ptr_restore_in,
```

这说明 Host 不需要直接懂 UB 内部结构，它只要：
- 把数据写进 frontend 暴露的寄存器
- frontend 再把 host write path 接到 UB

所以 `tpu.sv` 是“执行核心组合点”，但同时也是“host data injection 的落点”。

### 5.4 VPU 写回为什么又回到 UB

这里：

```systemverilog
assign ub_wr_data_in[0] = vpu_data_out_1;
assign ub_wr_data_in[1] = vpu_data_out_2;
assign ub_wr_valid_in[0] = vpu_valid_out_1;
assign ub_wr_valid_in[1] = vpu_valid_out_2;
```

这段就是训练闭环的核心证据之一。
因为它说明：
- systolic/VPU 处理出来的中间结果和梯度
- 不会飘在模块外面
- 而是重新写回 UB，供后续阶段再读

这就是为什么我一直说，这不是推理 demo，而是训练闭环。

### 5.5 `sys_switch_in` 为什么从顶层一路传到 systolic

看这句：

```systemverilog
.sys_switch_in(sys_switch_in)
```

说明前端发出的 `SWITCH` 指令，最终是为了控制阵列里的 shadow/active weight 切换。
这也解释了 scheduler 里为什么经常出现：
- load shadow
- nop
- switch
- stream input

因为阵列权重装载不是瞬时完成的，系统必须明确地区分：
- 先准备
- 再生效

### 5.6 一句话总结

`tpu.sv` 不是“最聪明”的模块，但它是最能把系统数据流看清楚的模块：所有训练数据最终都要经过它这里完成闭环。

---

## 6. `unified_buffer_v3.sv`：真正的数据中枢

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`

### 6.1 为什么说 UB 是整个项目最关键的文件之一

如果只看模块名，很多人会把它想成“普通 buffer”。
这会严重低估它。

这个 UB 同时承担：
- host 参数/数据装载
- systolic input 流
- systolic weight 流
- VPU bias/Y/H 读流
- 中间结果写回
- gradient descent in-place update

所以这不是一个普通 RAM wrapper，而是一个：
**以同一块存储承载多语义训练数据流的中枢。**

### 6.2 内部状态为什么这么多

开头这几组寄存器很能说明问题：

```systemverilog
logic [15:0] wr_ptr;
logic [15:0] wr_ptr_base;
...
logic [15:0] rd_input_ptr;
logic signed [15:0] rd_weight_ptr;
logic [15:0] rd_bias_ptr;
logic [15:0] rd_Y_ptr;
logic [15:0] rd_H_ptr;
logic [15:0] rd_grad_bias_ptr;
logic [15:0] rd_grad_weight_ptr;
logic [15:0] grad_descent_ptr;
```

它们不是冗余，而是因为 UB 真正承载了多类独立语义的读写机：
- input 读机
- weight 读机
- bias/Y/H 读机
- old bias / old weight 更新读机
- writeback 和 update 写机

也就是说，UB 已经不是被动存储，而是半个数据调度器。

### 6.3 `ub_ptr_select` 是理解 UB 的第一钥匙

看初始化分派：

```systemverilog
case (ub_ptr_select)
    0: begin ... end
    1: begin ... end
    2: begin ... end
    3: begin ... end
    4: begin ... end
    5: begin ... end
    6: begin ... end
endcase
```

它们实际对应：
- `0` input
- `1` weight
- `2` bias
- `3` Y
- `4` H
- `5` old bias for update
- `6` old weight for update

这说明同一块 UB 被复用成多种“逻辑视图”。
所以 scheduler 里的 `ptr_sel` 不是普通 selector，而是**数据语义选择器**。

### 6.4 `wr_ptr_base / restore` 是第二把钥匙

这段必须看懂：

```systemverilog
if (ub_wr_host_valid_in[0] || ub_wr_host_valid_in[1]) begin
    wr_ptr_base <= wr_ptr_next;
end
if (ub_wr_ptr_restore_in) begin
    wr_ptr <= wr_ptr_base;
end else begin
    wr_ptr <= wr_ptr_next;
end
```

这段逻辑的价值在于：

- Host 初始装载会不断推进 `wr_ptr`
- 同时把“静态区尾部”记在 `wr_ptr_base`
- 每次新一轮 `start` 时，Frontend 把 `ub_wr_ptr_restore_out` 拉起来
- UB 再把 `wr_ptr` 拉回静态区后面

于是运行时写回区永远从一个干净边界开始，避免踩掉初始参数和输入区。

这就是 PPT 那页 `wr_ptr / base / restore` 的核心。
如果你只能记住 UB 一个机制，就记这个。

### 6.5 weight 和 input 为什么读法不一样

看这两段指针逻辑：

```systemverilog
rd_input_ptr_next = rd_input_ptr;
...
rd_input_ptr_next = rd_input_ptr_next + 1;
```

和：

```systemverilog
if(rd_weight_transpose) begin
    ...
    rd_weight_ptr_next = rd_weight_ptr_next + rd_weight_skip_size;
end else begin
    ...
    rd_weight_ptr_next = rd_weight_ptr_next - rd_weight_skip_size;
end
```

这说明：
- input 更像左边界顺序流
- weight 更像顶部装载，需要考虑 transpose 和 column/row 映射

也就是说，UB 对 input 和 weight 的读，不只是地址不同，而是**传播方向和阵列接口语义都不同**。

### 6.6 为什么要单独处理 hold cycle

例如 input 读逻辑：

```systemverilog
else if (rd_input_time_counter + 1 == rd_input_row_size + rd_input_col_size) begin
    // Hold cycle: preserve outputs from last active cycle
```

而 weight 读逻辑又不同：

```systemverilog
// Do not hold weight valids high for an extra cycle.
// The systolic loader samples on every asserted valid...
```

这恰好说明了系统时序对齐的难点：
- input 流最后一拍可能需要 hold
- weight 流最后一拍如果多 hold，反而会误装最后一个权重

所以项目里“UB 发数和 PE 时序对齐”并不是抽象问题，而是在这些 always_ff 里非常具体地体现出来。

### 6.7 gradient descent 为什么在 UB 内完成

看这里：

```systemverilog
gradient_descent gradient_descent_inst (
    .lr_in(learning_rate_in),
    .grad_in(ub_wr_data_in[i]),
    .value_old_in(value_old_in[i]),
    .grad_descent_valid_in(grad_descent_valid_in[i]),
    .grad_bias_or_weight(grad_bias_or_weight),
    .value_updated_out(value_updated_out[i]),
    .grad_descent_done_out(grad_descent_done_out[i])
);
```

这说明更新路径是：
- VPU/阵列产生梯度流
- UB 同时从 memory 里取旧参数 `value_old_in`
- gradient_descent 模块在 UB 内部算更新值
- 再写回 `ub_memory`

所以参数更新不需要跑回软件侧，也不需要独立 DMA/ALU 再兜一圈。
这正是当前 tiny-tpu 原型设计里非常聪明的一点：
**把更新尽量留在数据中枢里完成。**

### 6.8 代码里的 bug 修复痕迹也很有价值

比如这段注释：

```systemverilog
// Weight updates need the final systolic beat as well.
// The current counter is already one cycle ahead ...
// so "+1 <" drops the last lane1 update for W2 and W1 column 2.
```

这说明项目不是只把 happy path 跑通，而是真正遇到过训练路径上的边界问题，然后在 UB 更新时序里修掉了。

还有这段：

```systemverilog
// Bias update old values are consumed by gradient_descent one cycle later, so preload
// the next bias wavefront once the derivative stream has started.
```

说明 bias update 也不是简单直连，而是有时序预取对齐问题。

这些注释本身就是很好的“工程细节证据”。

### 6.9 一句话总结

`unified_buffer_v3.sv` 不是存储模块，而是这套训练闭环里最像“数据控制中枢”的地方。

---

## 7. `test_tpu_soc_axil_train_convergence.py`：最终证据链

文件：
- `/home/jjt/tpu-soc/test/test_tpu_soc_axil_train_convergence.py`

### 7.1 这个测试为什么重要

如果没有这个测试，前面所有模块都可能只是“能响应控制”。
有了这个测试，才能证明：
- Host 真能通过 AXI-Lite 控制系统
- 系统真能连续执行完整训练阶段
- loss 真会下降
- XOR 真能收敛

所以它不是普通单元测试，而是整个项目的**系统级证据页落地文件**。

### 7.2 它先定义了数值语义

开头先定义：

```python
FRAC_BITS = 8
TRAIN_EPOCHS = 12
LOSS_TARGET = 0.21
```

再定义：
- `to_fxp / from_fxp / fxp`
- XOR 数据集 `X / Y`
- 初始化参数 `INIT_W1 / INIT_B1 / INIT_W2 / INIT_B2`
- `LEAK / INV_N2 / LR`

这说明测试不是只看信号 toggling，而是对照固定 Q8.8 数值语义在跑。

### 7.3 Host 侧控制入口很清楚

这几个 helper 很关键：

```python
async def axil_write(dut, addr, data):
async def axil_read(dut, addr):
async def ub_write_cycle(dut, d0, d1, push_mask):
```

它们把 Host 世界的动作写得很明白：
- 写寄存器
- 读状态
- 分 lane 往 UB 推数据

所以当你讲“AXI-Lite 真能控制系统”时，不要空说，直接说这几个 helper 就够了。

### 7.4 UB 装载是怎么做的

这段特别能体现 Host 和 UB 的对应关系：

```python
async def load_all_data_axil(dut, x, y, w1, b1, w2, b2):
    seq = [
        (to_fxp(x[0][0]), 0, 1),
        (to_fxp(x[1][0]), to_fxp(x[0][1]), 3),
        ...
        (to_fxp(b2[0]), to_fxp(w2[1]), 3),
    ]
```

这里你能直接看到：
- host 不是随便写 UB
- 它是按照当前 compiler/UB 约定的布局，把 X/Y/W1/B1/W2/B2 组织成具体 lane push 序列

这就是 `host_load_plan` 在测试侧的具体落实。

### 7.5 IMEM 装载怎么发生

```python
async def imem_load(dut, hex_path):
    lines = Path(hex_path).read_text().strip().splitlines()
    instrs = [int(line.strip(), 16) for line in lines if line.strip()]
    for i, instr in enumerate(instrs):
        await axil_write(dut, 0x030, i)
        await axil_write(dut, 0x034, instr)
        await axil_write(dut, 0x040, 1)
```

这段跟 frontend 寄存器图完全对上：
- `0x30` 设地址
- `0x34` 写指令字
- `0x40` commit
- `0x44` 写 `IMEM_LEN`

所以“编译器 -> IMEM -> Frontend”的链路在这里真正闭合了。

### 7.6 一轮训练怎么启动

```python
async def run_one_epoch(dut, epoch_idx):
    await axil_write(dut, 0x000, 0x2)
    for attempt in range(200):
        await ClockCycles(dut.s_axil_aclk, 500)
        status = await axil_read(dut, 0x004)
        if not (status & 0x1):
            return
```

这段代码非常有代表性：
- `0x000` 写 `0x2` 就是 `CTRL.start=1`
- 后面轮询 `STATUS.busy`
- busy 清掉代表 sequencer 这一轮执行完

所以系统运行边界在软件侧也是可观测的。

### 7.7 为什么 `read_hw_params()` 很有价值

```python
def read_hw_params(dut):
    ub = dut.dut.tpu_inst.ub_inst.ub_memory
    w1_words = [int(ub[12 + i].value) & 0xFFFF for i in range(4)]
    ...
```

这说明测试不是只看输出分类，而是还能直接读 UB 里的参数区，看硬件内部参数更新结果。

也就是说，验证证据是分层的：
- 寄存器级
- 波形级
- 参数内存级
- loss 级
- 最终分类级

这就是项目说服力强的原因之一。

### 7.8 一句话总结

`test_tpu_soc_axil_train_convergence.py` 不是附属脚本，而是这整个项目“闭环成立”的最终证明文件。

---

## 8. 把 6 个文件串成“一轮训练”

现在把它们连起来：

### Step 1 软件准备

`scheduler.py` 根据模型规格生成：
- `ub_map`
- `schedule`
- `imem`

### Step 2 Host 装载

测试通过 `axil_write()`、`load_all_data_axil()`、`imem_load()` 把：
- 参数/输入/标签装进 UB
- 指令装进 IMEM

### Step 3 Frontend 启动

`tpu_frontend_axil.sv` 收到 `CTRL.start` 后：
- 把 `pc` 置零
- 取 `imem[0]`
- `seq_running=1`
- 同时拉起 `ub_wr_ptr_restore_out`

### Step 4 顶层桥接

`tpu_soc.sv` 把：
- `ub_rd_start`
- `ub_ptr_sel`
- `sys_switch`
- `vpu_data_pathway`
- `ub_wr_ptr_restore`
这些语义信号送进 `tpu_inst`

### Step 5 Core 执行

`tpu.sv` 中：
- UB 发 input/weight/bias/Y/H/old params
- systolic 做 forward/backward/outer product
- VPU 做激活、loss、导数路径
- VPU 结果重新写回 UB

### Step 6 参数更新

`unified_buffer_v3.sv` 中：
- 读旧 bias / 旧 weight
- 接收梯度流
- gradient_descent 算更新值
- 原地写回 `ub_memory`

### Step 7 验证

`test_tpu_soc_axil_train_convergence.py`：
- 轮询状态
- 看 loss 下降
- 看最终 XOR 分类
- 必要时读回 UB 参数区

这就是整个项目“来龙去脉”的代码化版本。

---

## 9. 这套源码里最该记住的 10 句话

1. `tpu_soc.sv` 不是计算模块，而是系统桥接层。
2. `tpu_frontend_axil.sv` 不只是寄存器壳，而是控制中枢。
3. `start_pulse` 同时意味着正式运行和 `wr_ptr_restore`。
4. `wait_after` 真正靠 `vpu_drain` 收边界。
5. `scheduler.py` 输出的是阶段级硬件动作脚本，不是抽象 IR。
6. `ptr_sel` 是 UB 数据语义选择器，不只是地址修饰。
7. `tpu.sv` 是执行数据流的组合点。
8. UB 不只是 memory，而是训练数据中枢。
9. gradient descent 在 UB 内做，说明更新路径已经系统内闭环。
10. `test_tpu_soc_axil_train_convergence.py` 是项目成立的最终证据文件。

---

## 10. 你怎么用这份文档

如果你现在的目标是理解项目，而不是背 PPT，我建议这样用：

1. 先看 `01_main_8p.pptx`
2. 再读 `05_project_explainer_zh.md`
3. 然后读这份 `源码精讲版`
4. 最后直接打开源码文件对着看

如果你现在的目标是准备面试：

1. 先用 `06_interview_walkthrough_zh.md` 讲顺 8 页
2. 再用这份 `源码精讲版` 补充你能接住追问的底层依据
3. 最后用 `07_study_guide_zh.md` 做考前复习

最后一句提醒：
**这项目最难的地方不是某一行 RTL，而是这 6 个文件最后能拼成一条完整训练闭环。**
