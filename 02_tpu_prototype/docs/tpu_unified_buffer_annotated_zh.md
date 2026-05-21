# `unified_buffer_v3.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`

这份文档是给你对着源码逐段看的。
重点不是再讲“UB 很重要”，而是直接标出：哪几段在解决什么问题，为什么是整个训练闭环的关键。

---

## [19-37] 顶部接口：它一开始就不是普通 RAM

这一段端口已经说明它和普通 SRAM wrapper 不同：

- `ub_wr_data_in / ub_wr_valid_in`：运行时写回入口
- `ub_wr_host_data_in / ub_wr_host_valid_in`：Host 装载入口
- `ub_wr_ptr_restore_in`：运行边界恢复控制
- `ub_rd_start_in / ub_ptr_select / ub_rd_addr_in / row / col / transpose`：阶段级读流入口
- `learning_rate_in`：训练更新参数入口

如果一个 buffer 模块既有 Host 写、执行路径写、阶段级读流、训练更新参数，那它就已经不是“内存块”，而是“数据中枢”。

---

## [68-72] `ub_memory` 和 debug 区：真正的数据都在这里流转

```systemverilog
logic [15:0] ub_memory [0:UNIFIED_BUFFER_WIDTH-1];
```

后面所有：
- host 装载
- 中间结果写回
- old params 读取
- update 写回
最后都围着这块 `ub_memory` 转。

所以从系统角度看，`ub_memory` 就是这套 tiny-tpu 训练原型的公共数据场。

---

## [94-158] 内部状态：为什么这文件看起来像住了半个控制器

这段变量最多，但也是最能说明问题的一段。

### [94-96] 写指针

- `wr_ptr`
- `wr_ptr_next`
- `wr_ptr_base`

这一组是 host/static 区和运行时写回区边界管理的基础。

### [99-148] 各类读机

- `rd_input_*`
- `rd_weight_*`
- `rd_bias_*`
- `rd_Y_*`
- `rd_H_*`
- `rd_grad_bias_*`
- `rd_grad_weight_*`

这说明 UB 内部不是“一个读口多用”，而是维护了多组带时间计数的逻辑视图。

### [150-161] gradient descent 状态

- `value_old_in`
- `grad_descent_valid_in`
- `value_updated_out`
- `grad_descent_done_out`
- `grad_descent_ptr`
- `grad_bias_or_weight`

这一组直接说明更新逻辑就在 UB 内部。

如果你只想抓一句：
**这段状态定义说明 UB 已经不是被动存储，而是多语义训练数据流的内部控制点。**

---

## [177-190] `gradient_descent` 实例：更新路径系统内闭环的铁证

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

这段意味着：
- 梯度直接从运行时写回流 `ub_wr_data_in` 来
- 旧值从 UB memory 里读
- 学习率也是前端传下来的系统参数
- 更新值不出模块，直接又写回 UB

所以这套设计不是“软件算梯度，硬件只做 forward”，而是：
**参数更新也在 RTL 系统内部完成。**

---

## [214-236] `grad_descent_valid_in`：这里藏着一个关键 bug 修复点

```systemverilog
if ((rd_grad_bias_row_size != 0 || rd_grad_bias_col_size != 0) &&
    (rd_grad_bias_time_counter + 1 < rd_grad_bias_row_size + rd_grad_bias_col_size)) begin
    ...
end else if (rd_grad_weight_time_counter < rd_grad_weight_row_size + rd_grad_weight_col_size) begin
    // Weight updates need the final systolic beat as well.
    // ... "+1 <" drops the last lane1 update for W2 and W1 column 2.
```

这一段说明：
- bias update 和 weight update 的 valid 条件并不一样
- 尤其 weight update，最后一个 systolic beat 也必须接住
- 这里曾经真实出现过“最后一个 lane 更新丢失”的 bug

所以这段不是小优化，而是训练路径是否完整的关键。

---

## [221-300] 指针组合逻辑：UB 真正的“内部交通规则”

### [221-230] 写地址生成

```systemverilog
wr_ptr_next = wr_ptr;
for (...) begin
    wr_lane_addr[j] = wr_ptr_next;
    if (ub_wr_valid_in[j] || ub_wr_host_valid_in[j])
        wr_ptr_next = wr_ptr_next + 1;
end
```

它说明写地址不是简单每拍加一，而是：
- 按 lane 是否真的 valid 决定
- host 写和运行时写共用一套地址前进逻辑

### [232-303] input / weight / Y / H / grad weight 的 per-lane 地址生成

这几段最重要的认知不是公式，而是：
- input 更像左边界顺序流
- weight 更像顶部装载，且要考虑 transpose
- Y/H 也是各自独立的读流
- old weight update 读流又是一条单独的路径

这说明 UB 不是“地址 + 数据”，而是“多种矩阵流的 lane 级地址调度器”。

---

## [316-323] bias preload 相位：一个很工程化的时序补偿

```systemverilog
rd_grad_bias_value_phase = rd_grad_bias_time_counter;
if (rd_grad_bias_started || ub_wr_valid_in[0] || ub_wr_valid_in[1]) begin
    rd_grad_bias_value_phase = rd_grad_bias_time_counter + 1;
end
```

这段对应源码里的注释：bias old values 要比梯度消费时机早一拍准备。

这说明 bias 更新并不是数学上“grad 来了减一下”这么简单，而是：
- 旧 bias 值
- 梯度到达
- update 单元消费
三者之间存在拍次错位

这段就是为了解这个时序错位。

---

## [326-340] `grad_descent_ptr_next`：bias 和 weight 两种更新写法不同

```systemverilog
if (grad_bias_or_weight) begin
    ... grad_descent_ptr_next = grad_descent_ptr_next + 1;
end else begin
    gd_wr_lane_addr[j] = grad_descent_ptr + j;
end
```

这里的关键是：
- bias update 和 weight update 在写回地址推进方式上不同
- weight 类更新按完成 beat 前进
- bias 类更新更像固定 lane 对应固定位置

所以这里再次体现：bias update 和 weight outer-product update 不是一回事，不能用一个统一时序强行糊过去。

---

## [344-420] reset / 初始化：为什么这文件状态这么重

这一长段 reset 说明了一个事实：

- UB 内部维护了大量“当前阶段读流状态”
- 一次 reset 不只是清 memory
- 还要清：input/weight/bias/Y/H/update 各类指针和时间计数

也就是说，这个模块在行为上已经非常接近一个“小数据引擎”。

---

## [420-482] `ub_rd_start_in` 的 case：软件 `ptr_select` 在这里落地

这是整个文件最该精读的一段。

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

对应关系是：
- `0` input
- `1` weight
- `2` bias
- `3` Y
- `4` H
- `5` old bias for update
- `6` old weight for update

所以 `scheduler.py` 里 `_ub_read(... ptr_sel=...)` 的语义，最终就在这里变成具体启动哪一种内部读流。

这是 software schedule 和 RTL 数据流真正接起来的地方。

---

## [485-500] host 写 / VPU 写 / `wr_ptr_base` / `restore`

这一段是 PPT 那页 `wr_ptr / base / restore` 的源码本体。

```systemverilog
if (ub_wr_valid_in[j])
    ub_memory[wr_lane_addr[j]] <= ub_wr_data_in[j];
else if (ub_wr_host_valid_in[j])
    ub_memory[wr_lane_addr[j]] <= ub_wr_host_data_in[j];
...
if (ub_wr_host_valid_in[0] || ub_wr_host_valid_in[1])
    wr_ptr_base <= wr_ptr_next;
if (ub_wr_ptr_restore_in)
    wr_ptr <= wr_ptr_base;
else
    wr_ptr <= wr_ptr_next;
```

这段做了三件事：
1. 统一处理 host 写和执行路径写
2. 记录静态装载区边界 `wr_ptr_base`
3. 每轮 `start` 时恢复写指针

如果没有这段，训练过程中的写回很容易踩坏最初装进去的参数和数据区。

---

## [503-512] update 写回到 UB：参数更新真正落地的位置

```systemverilog
if (grad_descent_done_out[j]) begin
    ub_memory[gd_wr_lane_addr[j]] <= value_updated_out[j];
end
```

这几行就是“参数更新最后真的写回到哪里”的答案：
直接写回 `ub_memory`。

所以当你说“这项目是训练闭环”时，不是抽象意义，而是源码里真有这一拍。

---

## [515-542] input 读流：为什么最后一拍会 hold

```systemverilog
if (rd_input_time_counter + 1 < rd_input_row_size + rd_input_col_size) begin
    ...
end else if (rd_input_time_counter + 1 == rd_input_row_size + rd_input_col_size) begin
    // Hold cycle
```

这一段说明 input 流的最后一拍会保留一下，给后级稳定采样。

所以“UB 到 PE 时序对齐”不是 PPT 里的说法，而是这里非常具体的 `hold cycle` 逻辑。

---

## [545-583] weight 读流：为什么最后一拍不能像 input 那样 hold

源码里直接说了：

```systemverilog
// Do not hold weight valids high for an extra cycle.
// ... preserving the final pulse overwrites PE22 with the last lane1 weight.
```

这段特别值钱，因为它说明：
- input 和 weight 都是数据流
- 但它们对“最后一拍”的时序需求不同
- weight 如果 hold，阵列会把最后一个权重重复采样，造成错误覆盖

这正是系统工程和算法描述最大的区别：
算法看起来都只是“送矩阵”，真正实现时每条流的尾拍语义都可能不同。

---

## [622-742] bias / Y / H / gradient 读流：VPU 三条子路径都依赖 UB

这段是 VPU 相关读流主体：

- [622-641] bias
- [644-664] Y
- [667-687] H
- [690-742] gradient descent old-value feed

这一段说明：
- VPU 不是黑盒后处理
- 它依赖 UB 给它提供 bias、Y、H、old params 多种流
- UB 因此不仅服务阵列，也同时服务训练路径单元 VPU

这就是为什么我一直强调 UB 是系统级中枢，而不是“阵列前面的内存”。

---

## 一页总结

如果你只想记这份文件最关键的 8 个落点，就记：

1. 行 `19-37`：它从接口上就已经不是普通 RAM。
2. 行 `94-158`：它内部维护了多类读机和更新状态。
3. 行 `177-190`：gradient descent 直接实例化在 UB 内。
4. 行 `214-236`：这里藏着更新路径最后一拍 bug 修复逻辑。
5. 行 `221-340`：这是所有 lane 地址和 pointer 交通规则。
6. 行 `420-482`：`ptr_select` 在这里真正落成不同语义读流。
7. 行 `485-500`：`wr_ptr_base / restore` 保住静态参数区边界。
8. 行 `545-583`：weight 流尾拍不能乱 hold，这是时序对齐的关键证据。

最后一句话：
**这个文件最难的地方不是“读写 memory”，而是把多种训练语义的数据流、更新流和边界时序，全部在同一块 UB 里对齐。**
