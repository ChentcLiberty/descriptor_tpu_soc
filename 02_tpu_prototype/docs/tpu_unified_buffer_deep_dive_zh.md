# `unified_buffer_v3.sv` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`

这份文档只讲 `unified_buffer_v3.sv`。
如果你真的想理解这个项目最难的工程点，这个文件必须吃透。
因为它不是一块普通 RAM，而是：
**整个 tiny-tpu 训练闭环里的数据中枢、读写仲裁点和参数更新落点。**

---

## 1. 先把这个文件的定位讲清楚

表面上看，它叫 `unified_buffer`。
但在这个项目里，它实际上承担了 6 件事：

1. Host 装载输入、标签、初始参数
2. 给 systolic 左边提供 input 流
3. 给 systolic 上边提供 weight 流
4. 给 VPU 提供 bias / Y / H 流
5. 接收 VPU 写回的激活或梯度
6. 在内部完成 gradient descent 更新并写回旧参数

所以这个模块的真实身份不是“buffer”，而是：
**多语义训练数据流的中枢。**

---

## 2. 为什么内部状态这么多

一眼看上去最吓人的，是这一大片内部寄存器：

```systemverilog
logic [15:0] wr_ptr;
logic [15:0] wr_ptr_base;

logic [15:0] rd_input_ptr;
logic signed [15:0] rd_weight_ptr;
logic [15:0] rd_bias_ptr;
logic [15:0] rd_Y_ptr;
logic [15:0] rd_H_ptr;
logic [15:0] rd_grad_bias_ptr;
logic [15:0] rd_grad_weight_ptr;
logic [15:0] grad_descent_ptr;
```

它们不是设计糟糕，而是因为这个模块内部其实住着多台“读写机”：
- input 读机
- weight 读机
- bias 读机
- Y 读机
- H 读机
- old bias / old weight 更新读机
- writeback 写机
- gradient_descent 写回写机

所以你第一眼不要把它当“简单 memory controller”，而要把它当“以同一块存储实现多语义训练流水的数据中枢”。

---

## 3. 顶部接口已经说明它为什么不普通

### 3.1 写口就有两类来源

```systemverilog
input logic [15:0] ub_wr_data_in [SYSTOLIC_ARRAY_WIDTH],
input logic ub_wr_valid_in [SYSTOLIC_ARRAY_WIDTH],

input logic [15:0] ub_wr_host_data_in [SYSTOLIC_ARRAY_WIDTH],
input logic ub_wr_host_valid_in [SYSTOLIC_ARRAY_WIDTH],
input logic ub_wr_ptr_restore_in,
```

这表示：
- 一类写来自 VPU/执行路径
- 一类写来自 Host/前端装载路径

换句话说，UB 同时面对“初始化装载”和“运行时写回”两类写流。

### 3.2 读口也不是一种读法

```systemverilog
input logic ub_rd_start_in,
input logic ub_rd_transpose,
input logic [8:0] ub_ptr_select,
input logic [15:0] ub_rd_addr_in,
input logic [15:0] ub_rd_row_size,
input logic [15:0] ub_rd_col_size,
```

这说明每次读都不是单纯给个地址，而是带着完整语义：
- 读什么类型的数据
- 从哪读
- 读几行几列
- 是否转置

所以它的读取不是“地址访问”，而是“阶段级数据流启动”。

---

## 4. `ub_ptr_select` 是理解 UB 的第一钥匙

### 4.1 指令启动时的 case 分发

最值得看的就是读命令初始化：

```systemverilog
if (ub_rd_start_in) begin
    case (ub_ptr_select)
        0: begin ... end
        1: begin ... end
        2: begin ... end
        3: begin ... end
        4: begin ... end
        5: begin ... end
        6: begin ... end
    endcase
end
```

它们分别对应：

- `0`：input
- `1`：weight
- `2`：bias
- `3`：Y
- `4`：H
- `5`：old bias for update
- `6`：old weight for update

这说明同一块 `ub_memory` 会被不同执行单元以不同语义访问。

所以 `ptr_select` 的本质不是“小字段修饰地址”，而是：
**告诉 UB 这次我要启动哪一种数据流。**

### 4.2 这和编译器怎么对应

`scheduler.py` 里 `_ub_read()` 生成的就是：

```python
"ub_ptr_select": ptr_sel,
```

也就是说，软件侧 stage 命令和 UB 内部 case 分发是一一对上的。

这是整个项目软件到硬件对齐最关键的一环之一。

---

## 5. `wr_ptr` / `wr_ptr_base` / `restore` 是第二钥匙

### 5.1 这段必须背下来

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

### 5.2 这段到底解决什么问题

Host 一开始会把：
- `X`
- `Y`
- `W1`
- `B1`
- `W2`
- `B2`
装进 UB。

训练过程中，VPU 又会写回：
- `H1`
- `dZ2`
- `dZ1`
- 更新后的参数

如果没有边界恢复机制，运行时写回就可能把静态区踩掉。

### 5.3 这个机制的完整语义

它的语义是：

1. Host 写入时，`wr_ptr` 前进
2. 同时把静态区尾部记在 `wr_ptr_base`
3. 每次新一轮 `start`，Frontend 拉起 `ub_wr_ptr_restore_out`
4. UB 把 `wr_ptr` 拉回 `wr_ptr_base`
5. 本轮写回区重新从静态区后面开始

这就是为什么 PPT 要专门做一页 `wr_ptr / base / restore`。
这不是小实现细节，而是整个训练闭环成立的基础。

---

## 6. host 写和 VPU 写为什么能共存

### 6.1 写地址不是简单自增，而是按 lane 计算

```systemverilog
always_comb begin
    wr_ptr_next = wr_ptr;
    for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
        wr_lane_addr[j] = wr_ptr_next;
        if (ub_wr_valid_in[j] || ub_wr_host_valid_in[j]) begin
            wr_ptr_next = wr_ptr_next + 1;
        end
    end
end
```

这说明：
- 写指针前进不是固定每拍加 1
- 而是根据 lane 是否真的 valid 决定
- 每个 lane 在当前拍有自己的目标地址

### 6.2 真正写 memory 的逻辑

```systemverilog
for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
    if (ub_wr_valid_in[j]) begin
        ub_memory[wr_lane_addr[j]] <= ub_wr_data_in[j];
    end else if (ub_wr_host_valid_in[j]) begin
        ub_memory[wr_lane_addr[j]] <= ub_wr_host_data_in[j];
    end
end
```

这里体现的是优先级：
- 同一 lane 同一拍如果 VPU 写 valid 存在，优先写运行时数据
- 否则才写 Host 数据

这说明 UB 不是两个完全隔离的写通道，而是统一写入一个地址空间。

---

## 7. input 读流：为什么像左边界波前

### 7.1 指针推进很直观

```systemverilog
rd_input_ptr_next = rd_input_ptr;
...
rd_input_ptr_next = rd_input_ptr_next + 1;
```

input 更像顺序流，从左侧送入阵列。

### 7.2 为什么有 transpose 版本

```systemverilog
if(ub_rd_transpose) begin
    rd_input_row_size <= ub_rd_col_size;
    rd_input_col_size <= ub_rd_row_size;
end else begin
    rd_input_row_size <= ub_rd_row_size;
    rd_input_col_size <= ub_rd_col_size;
end
```

这表示 input 读流本身也支持转置语义。
虽然在当前主线里更常见的是 weight transpose，但这个接口本身保留了更通用的矩阵块流能力。

### 7.3 为什么最后要 hold 一拍

```systemverilog
else if (rd_input_time_counter + 1 == rd_input_row_size + rd_input_col_size) begin
    // Hold cycle: preserve outputs from last active cycle
```

这里的 hold cycle 说明 input 流的最后一拍需要在系统里保持一下，帮助后级稳定采样。

这也是“时序对齐不是抽象概念”的一个具体例子。

---

## 8. weight 读流：为什么比 input 更复杂

### 8.1 weight 读流的指针不是简单加一

看这段：

```systemverilog
if(rd_weight_transpose) begin
    ...
    rd_weight_ptr_next = rd_weight_ptr_next + rd_weight_skip_size;
end else begin
    ...
    rd_weight_ptr_next = rd_weight_ptr_next - rd_weight_skip_size;
end
```

这说明 weight 流不是普通顺序读，而是为了适配：
- 顶部装权重
- 行列映射
- transpose/non-transpose 两种模式

所以 weight 路径天然比 input 路径复杂。

### 8.2 `ub_rd_col_size_out` 为什么要单独送出去

```systemverilog
ub_rd_col_size_out <= ub_rd_row_size;   // transpose case
...
ub_rd_col_size_out <= ub_rd_col_size;   // normal case
```

这意味着 systolic 阵列不仅需要 weight 数据本身，还需要知道当前这批权重对应多少列，方便阵列内部控制。

所以 UB 在送 weight 时，不是纯 data plane，还顺带承担了 shape/control plane 的一部分。

### 8.3 为什么 weight 不能像 input 一样 hold valid

源码里直接写了注释：

```systemverilog
// Do not hold weight valids high for an extra cycle.
// The systolic loader samples on every asserted valid,
// so preserving the final pulse overwrites PE22 with the last lane1 weight.
```

这句话非常关键。
它说明：
- input 最后一拍 hold 是合理的
- weight 如果 hold，反而会导致阵列重复采最后一拍权重
- 最终覆盖错误位置的 PE shadow/active 值

这就是为什么 PPT 里专门讲了“UB 读时序和 PE 计算时序对齐”。

---

## 9. bias / Y / H 读流：为什么又是三种不同语义

后半段可以看到三组逻辑：

```systemverilog
// READING LOGIC (Bias)
// READING LOGIC (Y)
// READING LOGIC (H)
```

它们的共同点是：
- 都从 `ub_memory` 读
- 都按 wavefront/time_counter 推进

但语义完全不同：
- bias 给 VPU bias 模块
- Y 给 loss 路径
- H 给 activation derivative 路径

这说明 UB 真正服务的不是一个后级，而是同时服务 systolic 和 VPU 的多条训练子路径。

---

## 10. gradient descent 这块为什么说明项目已经不是推理 demo

### 10.1 文件里直接实例化了 gradient_descent

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

它说明更新路径是系统内完成的：
- 执行路径产生梯度
- UB 读旧参数
- gradient_descent 算新参数
- 再写回 UB

这不是把梯度扔回软件再更新，而是在 RTL 系统内部闭环完成训练更新。

### 10.2 bias update 和 weight update 不是一回事

源码专门把两种更新分开处理：

- `rd_grad_bias_*`
- `rd_grad_weight_*`
- `grad_bias_or_weight`

说明 bias update 和 weight outer-product update 在时间结构上不同，不能混成一个简单路径。

### 10.3 `grad_descent_ptr` 的意义

```systemverilog
if (!(ub_rd_start_in && (ub_ptr_select == 5 || ub_ptr_select == 6))) begin
    grad_descent_ptr <= grad_descent_ptr_next;
end
```

这句说明 update 写回区也有自己的写指针管理，而且要避免在刚启动更新那一拍覆盖 freshly loaded base pointer。

这正是很典型的工程细节：
项目里真正难的往往不是公式，而是边界拍次序。

---

## 11. bias update 为什么要 preload old values

这段注释非常值得记：

```systemverilog
// Bias update old values are consumed by gradient_descent one cycle later, so preload
// the next bias wavefront once the derivative stream has started.
```

这说明 bias 更新并不是“梯度一来就直接减”，而是：
- 旧 bias 值和梯度到达的时间存在相对拍次关系
- 所以需要提前 preload 下一波 old values

也就是说，bias update 本质上也是一个精细的时序对齐问题。

---

## 12. weight update 的 bug 修复痕迹为什么很重要

源码这段注释很值钱：

```systemverilog
// Weight updates need the final systolic beat as well.
// The current counter is already one cycle ahead of the accepted output wavefront,
// so "+1 <" drops the last lane1 update for W2 and W1 column 2.
```

这段说明：
- 设计不是一次就全对
- 项目里真的遇到过“最后一个 lane 更新丢失”的训练边界 bug
- 最后是靠重新审视 `time_counter` 和 wavefront 接受关系修掉的

这类注释恰恰说明你做的是工程项目，不是拼一堆 happy-path 模块。

---

## 13. 这个文件和 PPT 各页怎么对应

这个文件几乎对应了附录里半套内容：

1. `Unified Buffer 设计`
2. `wr_ptr / base / restore`
3. `UB 读流与 PE 时序对齐`
4. `UB 内梯度下降更新`

换句话说，如果你能把这个文件讲懂，这 4 页其实就是同一件事的四个角度：
- 存什么
- 怎么读
- 怎么不踩静态区
- 怎么做更新

---

## 14. 你最该记住的 10 个点

1. UB 不是普通 SRAM，而是多语义训练数据中枢。
2. `ptr_select` 决定这次读流到底在读什么语义。
3. `wr_ptr_base / restore` 保证运行时写回不踩静态参数区。
4. Host 写和 VPU 写共享一个地址空间。
5. input 流像左边界顺序波前。
6. weight 流比 input 更复杂，因为要支持顶部装载和 transpose。
7. input 的最后一拍可以 hold，weight 的最后一拍不能乱 hold。
8. bias / Y / H 都要从 UB 读，但语义完全不同。
9. gradient descent 在 UB 内完成，说明训练更新已经系统内闭环。
10. 这个文件里的时序注释，本身就是项目工程难点的最好证据。

---

## 15. 最后一句话

如果只让我用一句话概括 `unified_buffer_v3.sv`，那就是：

**它把一块存储器变成了 tiny-tpu 训练闭环里的数据中枢、时序对齐点和参数更新落点。**
