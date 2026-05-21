# `tpu_soc.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_soc.sv`

这份文档按源码行号解释 `tpu_soc.sv`。
它的重点不是算法，而是：
**这个顶层为什么说明项目已经从“裸核原型”变成了“主机可控 SoC 原型”。**

---

## [4-11] 文件头注释：顶层定位直接写明了

这里最关键的两句是：
- `Wraps tpu_frontend_axil + tpu`
- `CPU controls TPU via AXI-Lite`

这说明这个文件从设计目的上就不是“再包装一下”，而是要把：
- Host
- Frontend
- TPU core
真正接成一个 AXI-Lite 可控加速器。

所以如果你要一句话概括 `tpu_soc.sv`：
**它是系统桥接层，不是算法层。**

---

## [13-52] 顶层端口：SoC 的外部边界在这里定义

这一段主要有两类接口：

1. AXI-Lite slave
- `aw* / w* / b* / ar* / r*`

2. 对外可观测输出
- `vpu_data_out_*`
- `vpu_valid_out_*`
- `sys_data_out_21/22`
- `sys_valid_out_21/22`

这说明：
- Host 是通过标准 AXI-Lite 入口控制系统
- 同时系统还把关键执行结果暴露出来，便于观察和验证

也就是说，这个顶层不是封死的黑盒，而是：
**可控、可观测的系统外壳。**

---

## [54-84] 前端和 core 之间的内部桥接信号

这一段最值得注意的是这两组：

### host write 相关
- `ub_wr_host_data_0/1`
- `ub_wr_host_valid_0/1`
- `ub_wr_ptr_restore`

### 控制语义相关
- `sys_switch`
- `ub_rd_start`
- `ub_rd_transpose`
- `ub_rd_col_size`
- `ub_rd_row_size`
- `ub_rd_addr`
- `ub_ptr_sel`
- `vpu_data_pathway`
- `inv_batch_size_times_two`
- `vpu_leak_factor`
- `learning_rate`

这些信号本质上就是：
**Frontend 生成的系统控制语义，在顶层中转后送给 TPU core。**

所以 `tpu_soc` 的价值不是“做逻辑运算”，而是“做语义桥接”。

---

## [60-66] host write lane 桥接：为什么标量要转成数组

```systemverilog
logic [15:0] ub_wr_host_data [0:SYSTOLIC_ARRAY_WIDTH-1];
logic        ub_wr_host_valid [0:SYSTOLIC_ARRAY_WIDTH-1];
assign ub_wr_host_data[0]  = ub_wr_host_data_0;
assign ub_wr_host_data[1]  = ub_wr_host_data_1;
assign ub_wr_host_valid[0] = ub_wr_host_valid_0;
assign ub_wr_host_valid[1] = ub_wr_host_valid_1;
```

这里的意义很实际：
- Frontend 暴露的是 lane0/lane1 标量端口
- `tpu.sv` 侧接口是 unpacked array
- 顶层在这里做格式适配

这说明 `tpu_soc` 还承担了接口整形的角色。

换句话说，它不是“直连”，而是“带接口适配的桥接”。

---

## [86-139] Frontend 实例：系统控制链从这里开始

```systemverilog
tpu_frontend_axil #( ... ) frontend ( ... );
```

这一段最关键的不是实例化本身，而是它把：
- AXI-Lite 全部总线口
- `tpu_vpu_valid_in`
- host write 输出
- sequencer/control 输出

全都接起来了。

### [117] `tpu_vpu_valid_in`

```systemverilog
.tpu_vpu_valid_in (vpu_valid_out_1 | vpu_valid_out_2),
```

这句很重要，因为它说明：
- 前端判断阶段结束要看 VPU valid drain
- 而这个证据来自 core 输出
- 所以顶层要把 core 的 valid OR 回送给 Frontend

这就是完整闭环的一部分：
**前端发命令，core 执行，core 再把“执行结束证据”反馈给前端。**

### [122-138] 前端输出

这里接出的就是：
- host 写 UB
- `wr_ptr_restore`
- `sys_switch`
- UB 读流控制字段
- VPU 路径字段
- 训练超参数

这些信号正是后续 `tpu_inst` 真正要消费的控制语义。

---

## [141-188] TPU core 实例：系统执行链从这里开始

```systemverilog
tpu #( ... ) tpu_inst ( ... );
```

这里最该关注的是：
- 前端出来的所有控制字段都在这里被送进 `tpu_inst`
- `tpu_inst` 再往 UB / systolic / VPU 分发

这段连接体现的是：
**`tpu_soc` 是把前端控制链和执行核心链真正焊起来的那一层。**

### [152-154] host write / restore

```systemverilog
.ub_wr_host_data_in         (ub_wr_host_data),
.ub_wr_host_valid_in        (ub_wr_host_valid),
.ub_wr_ptr_restore_in       (ub_wr_ptr_restore),
```

这表明 Host 初始装载路径和 `start -> restore` 路径，最终都落到 UB。

### [156-161] 窄信号到宽接口的零扩展

```systemverilog
.ub_ptr_select              ({6'h0, ub_ptr_sel}),
.ub_rd_addr_in              ({10'h0, ub_rd_addr}),
.ub_rd_row_size             ({12'h0, ub_rd_row_size}),
.ub_rd_col_size             ({14'h0, ub_rd_col_size}),
```

这一段很有代表性。
说明：
- Frontend 输出的是当前项目足够用的窄控制字段
- TPU core/UB 接口保留了更宽的表达能力
- 顶层负责做桥接适配

所以 `tpu_soc` 还是“接口宽度/语义兼容层”。

### [163-168] 训练超参数和路径语义

```systemverilog
.learning_rate_in           (learning_rate),
.vpu_data_pathway           (vpu_data_pathway),
.sys_switch_in              (sys_switch),
.vpu_leak_factor_in         (vpu_leak_factor),
.inv_batch_size_times_two_in(inv_batch_size_times_two),
```

这说明前端不是只给地址和 start，而是把：
- 学习率
- VPU pathway
- switch
- leak
- inv batch
这些训练语义一起送进 core。

所以它已经不是“命令触发器”，而是一套完整训练控制面。

---

## [170-187] 对外观测端口：为什么说这个 SoC 顶层是可观测的

这里把：
- VPU data/valid
- systolic 输出 data/valid
- UB 读 input/weight 输出
都接出来了。

这意味着：
- 顶层不是纯黑盒
- 验证和波形观察有足够抓手
- 所以你才能做 PPT 里的波形证据页和时序分析页

这也是系统工程很重要的一点：
**不是只要能跑，还要能观测和定位。**

---

## 一页总结

如果你只想记 `tpu_soc.sv` 的 6 个点，就记：

1. 行 `4-11`：它从设计目标上就是 `frontend + tpu` 的 SoC 包装层。
2. 行 `13-52`：定义了 Host AXI-Lite 和对外可观测输出这两个系统边界。
3. 行 `54-84`：定义了前端和 core 之间最关键的控制语义桥接信号。
4. 行 `60-66`：做了 host write lane 的接口适配。
5. 行 `86-139`：把 Frontend 接进系统，并用 `vpu_valid_out` 反馈阶段完成证据。
6. 行 `141-188`：把前端的控制语义真正送进 TPU core，并做必要的宽度适配。

最后一句话：
**`tpu_soc.sv` 的价值，不是实现算法，而是让 Host、Frontend、TPU core 第一次形成一个可控、可观测、可验证的完整系统顶层。**
