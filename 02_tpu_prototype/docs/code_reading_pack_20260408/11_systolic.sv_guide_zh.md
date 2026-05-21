# `systolic.sv` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/systolic.sv`

这份文档只讲 `systolic.sv`。
它的任务不是重新定义乘法，而是把 4 个 PE 组合成当前 tiny-tpu 的 2x2 阵列，并正确传播：
- input
- weight
- psum
- valid
- switch

---

## 1. 先给这个文件定性

`pe.sv` 解决的是“一个节点怎么工作”。
`systolic.sv` 解决的是“4 个节点怎么连成阵列并形成波前”。

所以看这个文件时，重点不是算术，而是连线语义和传播方向。

---

## 2. 阵列的边界接口先要看懂

左边界输入：
- `sys_data_in_11`
- `sys_data_in_21`
- `sys_start`

上边界权重：
- `sys_weight_in_11`
- `sys_weight_in_12`
- `sys_accept_w_1`
- `sys_accept_w_2`

控制信号：
- `sys_switch_in`
- `ub_rd_col_size_in`
- `ub_rd_col_size_valid_in`

输出：
- `sys_data_out_21`
- `sys_data_out_22`
- `sys_valid_out_21`
- `sys_valid_out_22`

这个边界已经说明了阵列的角色：
- 从左边吃输入
- 从上边吃权重
- 从底部吐出结果

---

## 3. 4 个 PE 的位置关系必须先在脑子里画出来

它实际上就是：
- `pe11` 左上
- `pe12` 右上
- `pe21` 左下
- `pe22` 右下

然后：
- 左上 `pe11` 吃第一路 input 和第一列 weight
- 右上 `pe12` 吃从 `pe11` 传过去的 input 和第二列 weight
- 左下 `pe21` 吃第二路 input，以及从 `pe11` 往下传的 psum / weight
- 右下 `pe22` 吃从 `pe21` 往右传的 input，以及从 `pe12` 往下传的 psum / weight

所以这个阵列不是“4 个 PE 并列”，而是一个真正有空间方向和依赖关系的 2x2 波前结构。

---

## 4. input、weight、psum 的传播方向

### input
从左向右流：
- `sys_data_in_* -> pe11/pe21 -> pe_input_out_* -> pe12/pe22`

### weight
从上向下流：
- `sys_weight_in_* -> pe11/pe12 -> pe_weight_out_* -> pe21/pe22`

### psum
从上往下累加：
- 顶行从 `0` 开始
- 顶行输出的 psum 再喂给底行

这就是最经典的 systolic 语义：
- input 横向传播
- weight 纵向传播
- psum 纵向累加

---

## 5. valid 波前为什么看起来是“斜着走”的

看 valid 连接会发现：
- `pe11` 的 valid 输出喂给 `pe12`
- 也喂给 `pe21`
- `pe12` 的 valid 输出再喂给 `pe22`

这表示 valid 不是单纯横向或纵向，而是跟着阵列波前一起推进。

换句话说：
**valid 的传播路径，本质上就是“这波计算波前现在走到哪里了”。**

这也是你后面看波形页时最该关注的东西之一。

---

## 6. `sys_switch_in` 为什么也要沿阵列传播

`sys_switch_in` 从左上进入，不是只给一个 PE 用，而是要沿阵列逐步传给下游 PE。

原因很直接：
- 每个 PE 都有自己的 active/inactive weight
- 阵列要在正确边界把 shadow weight 统一切成 active
- 所以 switch 也必须像一类阵列控制波前一样传播

这说明当前设计不是全局广播立即生效，而是沿阵列结构传播控制语义。

---

## 7. `ub_rd_col_size_in` 的作用是什么

这一段很关键：

```systemverilog
if(ub_rd_col_size_valid_in) begin
    pe_enabled <= (1 << ub_rd_col_size_in) - 1;
end
```

它的作用是：
- 根据当前 tile 的列宽，决定启用几列 PE

这在 2x2 原型里很重要，因为有时候：
- 数据实际只需要 1 列
- 但阵列物理上有 2 列

如果不做这个 enable 控制，多出来的列会继续参与无意义传播。

所以这一步体现的是：
**阵列形状和当前工作负载 shape 对齐。**

---

## 8. 这个文件为什么不复杂但很关键

`systolic.sv` 本身代码不算长，也没太多复杂状态。
但它非常关键，因为它把这些局部语义第一次拼成了阵列级行为：
- 单 PE MAC
- shadow/active 切换
- input/weight/psum/valid/switch 的传播
- 按列裁剪

所以它的价值不在“功能多”，而在“把空间结构真正搭起来”。

---

## 一页总结

如果你只记 `systolic.sv` 的 5 个点，就记：

1. 它是 4 个 PE 的空间组合层。
2. input 从左往右，weight 从上往下，psum 从上往下累加。
3. valid 跟着波前推进，不是随便拉一根线。
4. `sys_switch` 也沿阵列传播，用来统一切换 active weight。
5. `ub_rd_col_size` 用来按当前 tile 实际列宽启停 PE 列。

最后一句话：
**`systolic.sv` 的价值，是把单个 PE 的局部语义拼成了一个真正能跑波前计算的 2x2 阵列。**
