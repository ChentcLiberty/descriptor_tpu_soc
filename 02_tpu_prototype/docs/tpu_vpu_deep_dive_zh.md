# `vpu.sv` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/vpu.sv`

这份文档只讲 `vpu.sv`。
如果你想真正理解这个项目为什么不是单纯的矩阵乘推理 demo，而是训练闭环原型，这个文件必须看懂。

因为它负责的不是“再做一点后处理”，而是：
**把 systolic 输出接上 bias、激活、loss、导数这些训练语义路径。**

---

## 1. 先给这个文件定性

VPU 不是一个单算法模块，而是一个**pathway-controlled dataflow router**。

它里面串了几类子模块：
- bias
- leaky relu
- loss
- leaky relu derivative

然后通过 `vpu_data_pathway[3:0]` 决定当前要走哪些块。

所以 `vpu.sv` 的本质不是“实现某个固定算子”，而是：
**根据当前训练阶段，把 systolic 的输出送进正确的训练语义路径。**

---

## 2. 顶部注释已经把最关键的东西讲明白了

它列了 4 条 pathway：
- `0000`
- `1100`
- `1111`
- `0001`

你可以直接记成：
- `1100`：forward
- `1111`：transition / loss related
- `0001`：backward derivative
- `0000`：纯穿透 / update 相关路径

这一步很关键，因为你后面看 scheduler 和 control unit 时，会不断看到这些 4-bit 码。

---

## 3. 这个文件不是单纯吃 systolic 输出

它一方面吃来自 systolic 的：
- `vpu_data_in_1/2`
- `vpu_valid_in_1/2`

另一方面还吃来自 UB 的：
- `bias_scalar_in_*`
- `Y_in_*`
- `H_in_*`
- `inv_batch_size_times_two_in`
- `lr_leak_factor_in`

这说明 VPU 不是“阵列后的附属滤镜”。
它必须同时看到：
- 阵列算出来的值
- 训练阶段额外需要的语义输入

所以它是训练闭环的一部分，而不是可有可无的外挂。

---

## 4. 内部其实就是一条可裁剪流水

代码里先实例化了 4 类 parent module：
- `bias_parent`
- `leaky_relu_parent`
- `loss_parent`
- `leaky_relu_derivative_parent`

然后在一个大 `always @(*)` 里，根据 pathway bit 决定：
- 当前模块打开还是旁路
- 当前输出接到哪一级中间变量
- 最终 `vpu_data_out_* / vpu_valid_out_*` 从哪一级拿

这说明当前架构不是搞复杂 FSM，而是：
**通过路径位去裁剪同一条数据流。**

---

## 5. 每一位 pathway 大概在控制什么

### bit[3]
控制 bias 段是否使能。

### bit[2]
控制 leaky relu 段是否使能。

### bit[1]
控制 loss 段是否使能。

### bit[0]
控制 leaky relu derivative 段是否使能。

所以这 4 位不是随便编号，而是对应整条 VPU 流水上 4 段功能块的开关。

---

## 6. 为什么 `1111` 路径最特别

`1111` 路径意味着：
- 先 bias
- 再 leaky relu
- 再 loss
- 再 leaky relu derivative

它最特别的地方在于：
- 它不只是在往前算
- 还会把 `leaky relu` 阶段的 `H` 暂存下来
- 后面再喂给 derivative

代码里这个机制通过 `last_H_data_*` 这组 cache 实现。

这说明 transition 阶段不是简单的模块串联，而是带有“中间结果缓存再利用”的路径。

---

## 7. 为什么有 `last_H` cache

在 `loss` 开启时，代码会：
- 把 `leaky relu` 输出存进 `last_H_data_*`
- 再把它喂给 derivative 路径

原因是：
- derivative 不只看 loss 输出
- 还需要知道之前的激活 `H`

这说明 VPU 不只是纯 combinational route，而是带了小规模阶段上下文缓存。

这也是为什么 Frontend 需要等 `vpu_drain`，因为后级路径里不是“一拍出结果”那么简单。

---

## 8. 为什么说 `vpu_valid_out` 很重要

VPU 的输出 valid 不只是“这个模块有结果”。
在当前系统里，它还承担了：
**阶段完成证据**

因为 SoC 顶层把两路 `vpu_valid_out` OR 回 Frontend，Frontend 再据此形成 `vpu_drain`。

所以 `vpu_valid_out` 既是：
- 数据流上的 valid

也是：
- Sequencer 判断当前阶段是否真的吐干净的证据

这就是它在系统里比普通 valid 更重要的原因。

---

## 9. 为什么这个文件是“训练语义入口”

如果没有 VPU，系统只能做：
- 阵列 MAC
- 结果输出

有了 VPU 之后，系统才开始具备：
- bias
- 激活
- loss 相关路径
- derivative
- 某些 update 相关路径协同

也就是说，真正让这个项目从“矩阵乘原型”变成“训练闭环原型”的，不只是 UB 写回，还有 VPU 这层训练语义路径。

---

## 10. 后面如果继续深挖，应该看什么

如果你把 `vpu.sv` 看懂了，下一层再下钻这些文件：
- `bias_parent.sv`
- `leaky_relu_parent.sv`
- `loss_parent.sv`
- `leaky_relu_derivative_parent.sv`

第一次读源码时，不建议先从这些 child/parent 模块开始。
先把 `vpu.sv` 里的总路径语义看懂更重要。

---

## 一页总结

如果你只记 `vpu.sv` 的 5 个点，就记：

1. 它是 pathway-controlled 的训练语义数据流模块，不是简单后处理。
2. 它同时吃 systolic 输出和 UB 提供的 bias / Y / H 等语义输入。
3. `1100 / 1111 / 0001 / 0000` 分别对应不同训练阶段路径。
4. `1111` 路径里 `last_H` cache 很关键，因为 derivative 需要前面的激活信息。
5. `vpu_valid_out` 在当前系统里既是 valid，也是阶段完成证据。

最后一句话：
**`vpu.sv` 的价值，是把阵列输出接上真正的训练语义路径，从而让系统具备 forward、transition、backward 这些阶段能力。**
