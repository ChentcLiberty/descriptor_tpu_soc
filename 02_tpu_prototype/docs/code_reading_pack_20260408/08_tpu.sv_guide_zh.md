# `tpu.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu.sv`

这份文档按源码行号解释 `tpu.sv`。
它的重点不是复杂控制，而是让你看清楚：
**这一个文件如何把 UB、systolic、VPU 组合成真正的执行核心闭环。**

---

## [4-53] 顶层接口：这就是执行核心对外的系统边界

这一段端口很能说明 `tpu.sv` 的定位。

输入分成四类：
1. Host -> UB 写入
2. UB 读流控制字段
3. 训练参数
4. VPU pathway / switch

输出分成三类：
1. VPU 写回结果
2. systolic 输出
3. UB 读出的 input/weight 流

所以这个文件本质上不是控制器，而是：
**执行核心的数据通路组合层。**

---

## [55-74] VPU 写回先回 UB：训练闭环最核心的一跳

```systemverilog
logic [15:0] ub_wr_data_in [0:SYSTOLIC_ARRAY_WIDTH-1];
logic ub_wr_valid_in [0:SYSTOLIC_ARRAY_WIDTH-1];
...
assign ub_wr_data_in[0] = vpu_data_out_1;
assign ub_wr_data_in[1] = vpu_data_out_2;
assign ub_wr_valid_in[0] = vpu_valid_out_1;
assign ub_wr_valid_in[1] = vpu_valid_out_2;
```

这几行非常重要。
因为它说明：
- 执行路径产生的激活/梯度
- 不是丢到模块外就结束
- 而是重新写回 UB

这就是为什么我一直说这不是推理 demo，而是训练闭环。
没有这几行，就没有后续 `H1 / dZ2 / dZ1 / updated params` 在系统里的连续流转。

---

## [76-128] `ub_inst`：执行核心真正的数据中枢入口

```systemverilog
unified_buffer #( ... ) ub_inst ( ... );
```

这里连接的其实就是整个项目的数据主场：

### 写入口
- `ub_wr_data_in / ub_wr_valid_in`：来自 VPU 写回
- `ub_wr_host_data_in / ub_wr_host_valid_in`：来自 Host 初始装载
- `ub_wr_ptr_restore_in`：来自 Frontend 的运行边界恢复

### 读控制
- `ub_rd_start_in`
- `ub_rd_transpose`
- `ub_ptr_select`
- `ub_rd_addr_in`
- `ub_rd_row_size`
- `ub_rd_col_size`

### 输出给执行单元
- input 流给 systolic 左边界
- weight 流给 systolic 上边界
- bias/Y/H 流给 VPU
- `ub_rd_col_size_out` 给 systolic 做内部控制

这说明 `tpu.sv` 并不自己生成数据，它依赖 UB 把所有训练语义的数据流组织出来。

---

## [130-155] `systolic_inst`：PE 阵列真正的乘加核心

```systemverilog
systolic systolic_inst (
    .sys_data_in_11(ub_rd_input_data_out_0),
    .sys_data_in_21(ub_rd_input_data_out_1),
    .sys_start(ub_rd_input_valid_out_0),
    ...
    .sys_weight_in_11(ub_rd_weight_data_out_0),
    .sys_weight_in_12(ub_rd_weight_data_out_1),
    .sys_accept_w_1(ub_rd_weight_valid_out_0),
    .sys_accept_w_2(ub_rd_weight_valid_out_1),
    .sys_switch_in(sys_switch_in),
    .ub_rd_col_size_in(ub_rd_col_size_out),
    .ub_rd_col_size_valid_in(ub_rd_col_size_valid_out)
);
```

这段把阵列输入分得很清楚：
- 左边界送 input
- 上边界送 weight
- `sys_switch_in` 控制 shadow -> active
- `ub_rd_col_size_*` 告诉阵列当前 tile/shape 语义

所以你可以把这段直接理解成：
**UB 负责供数，systolic 负责乘加和波前传播。**

### 一个很容易忽略的点

```systemverilog
.sys_start(ub_rd_input_valid_out_0)
```

这说明阵列启动直接依赖 UB input valid，而不是另起一条全局 start。
也就是说，阵列启动时机和 UB 数据波前是直接绑定的。

这正是“UB 发数和 PE 时序对齐”的源码根基之一。

---

## [157-184] `vpu_inst`：训练路径单元，不是附属后处理

```systemverilog
vpu vpu_inst (
    .vpu_data_pathway(vpu_data_pathway),
    .vpu_data_in_1(sys_data_out_21),
    .vpu_data_in_2(sys_data_out_22),
    .vpu_valid_in_1(sys_valid_out_21),
    .vpu_valid_in_2(sys_valid_out_22),
    .bias_scalar_in_1(ub_rd_bias_data_out_0),
    .bias_scalar_in_2(ub_rd_bias_data_out_1),
    .lr_leak_factor_in(vpu_leak_factor_in),
    .Y_in_1(ub_rd_Y_data_out_0),
    .Y_in_2(ub_rd_Y_data_out_1),
    .inv_batch_size_times_two_in(inv_batch_size_times_two_in),
    .H_in_1(ub_rd_H_data_out_0),
    .H_in_2(ub_rd_H_data_out_1),
    .vpu_data_out_1(vpu_data_out_1),
    .vpu_data_out_2(vpu_data_out_2),
    .vpu_valid_out_1(vpu_valid_out_1),
    .vpu_valid_out_2(vpu_valid_out_2)
);
```

这段最重要的认知是：
- VPU 不是阵列后的“随手处理一下”
- 它吃的不只是 systolic 输出
- 还同时吃 bias、Y、H、leak、inv_batch 等训练语义输入

所以 VPU 是一个真正的训练路径单元：
- `1100` forward
- `1111` transition/loss
- `0001` backward derivative

这些路径码之所以有意义，就是因为这一段接口把训练所需的所有输入都接齐了。

---

## [71-74 + 179-183] 为什么 `tpu.sv` 真正闭成环了

把两段合起来看：

```systemverilog
assign ub_wr_data_in[0] = vpu_data_out_1;
assign ub_wr_data_in[1] = vpu_data_out_2;
...
.vpu_data_out_1(vpu_data_out_1),
.vpu_data_out_2(vpu_data_out_2),
.vpu_valid_out_1(vpu_valid_out_1),
.vpu_valid_out_2(vpu_valid_out_2)
```

这说明系统内部形成了：
- UB -> systolic -> VPU -> UB

这就是完整的数据闭环。

而且这个闭环里还同时容纳：
- Host 初始装载
- shadow/active 权重切换
- VPU 路径切换
- learning rate / leak / inv batch 参数

所以 `tpu.sv` 虽然代码不长，但它是整个训练执行核心真正的组合中心。

---

## 一页总结

如果你只想记 `tpu.sv` 的 6 个点，就记：

1. 行 `4-53`：定义了执行核心的系统边界，输入是控制和数据，输出是结果和中间流。
2. 行 `55-74`：VPU 写回先回 UB，这是训练闭环最核心的一跳。
3. 行 `76-128`：`ub_inst` 是整个执行核心的数据中枢入口。
4. 行 `130-155`：`systolic_inst` 只管阵列乘加和波前传播，不负责全局控制。
5. 行 `157-184`：`vpu_inst` 是训练路径单元，不是附属后处理。
6. 行 `71-74 + 179-183`：整个系统在这个文件里真正形成 `UB -> systolic -> VPU -> UB` 数据闭环。

最后一句话：
**`tpu.sv` 的价值，不是实现复杂控制，而是把 UB、PE 阵列、VPU 三块真正接成一个可执行训练闭环的核心数据通路。**
