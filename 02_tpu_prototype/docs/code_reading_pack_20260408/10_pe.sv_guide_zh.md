# `pe.sv` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/pe.sv`

这份文档只讲 `pe.sv`。
如果你想真正看懂 2x2 systolic array，最好的办法不是先看 `systolic.sv`，而是先看单个 PE。

因为阵列里的所有关键机制，单 PE 里都已经有了：
- valid 传播
- input 传播
- psum 累加
- shadow/active weight
- switch 生效边界

---

## 1. 先给这个文件定性

这个 PE 不是一个“纯乘法器”，而是一个带状态的阵列节点。

它内部至少有三类状态：
- 当前 active weight
- 后台 inactive weight
- 当前一拍的 valid / switch / output 流动

所以它的职责不是只做 `a*b`，而是：
**在阵列时序里完成 MAC，并把 input / weight / valid / switch 正确传播给下游。**

---

## 2. 输入输出方向要先看懂

North 方向进来的是：
- `pe_psum_in`
- `pe_weight_in`
- `pe_accept_w_in`

West 方向进来的是：
- `pe_input_in`
- `pe_valid_in`
- `pe_switch_in`
- `pe_enabled`

输出则分别往：
- South 送 `pe_psum_out / pe_weight_out`
- East 送 `pe_input_out / pe_valid_out / pe_switch_out`

这说明这个 PE 已经按 systolic 的空间方向来设计了：
- input 往右流
- weight 往下流
- psum 往下累加
- valid 和 switch 也一起传播

---

## 3. 乘加核心其实不复杂

真正做算术的是两步：

```systemverilog
fxp_mul mult (... weight_reg_active ...)
fxp_add adder (... pe_psum_in ...)
```

也就是说：
1. 当前输入乘 active weight
2. 再和从上面来的 partial sum 累加

这一点很重要，因为它说明：
- `pe_weight_in` 并不是直接参与当前拍乘法
- 真正参与乘法的是 `weight_reg_active`

这为后面的 shadow/active 机制打基础。

---

## 4. 为什么有 active 和 inactive 两套 weight

这是整个 PE 里最关键的设计之一。

```systemverilog
logic signed [15:0] weight_reg_active;
logic signed [15:0] weight_reg_inactive;
```

含义是：
- `inactive` 用来先装新权重
- `active` 才是真正参与当前计算的权重

然后：
- `pe_accept_w_in` 来时，把新权重写进 `inactive`
- `pe_switch_in` 来时，再把 `inactive` 复制到 `active`

所以这个 PE 支持一种很重要的阵列语义：
**先装 shadow weight，再在明确边界统一切换生效。**

这也是为什么 `sys_switch` 在系统里这么关键。

---

## 5. `pe_accept_w_in` 和 `pe_switch_in` 各自管什么

两者千万不要混：

### `pe_accept_w_in`
表示：
- 这一拍允许从上方接收新 weight
- 新 weight 写进 `inactive`
- 同时继续向下传播 `pe_weight_out`

### `pe_switch_in`
表示：
- 当前应该把后台 `inactive` 复制到前台 `active`
- 从这一拍之后，新 active weight 才会真正参与 MAC

所以一句话：
- `accept_w` 负责“装”
- `switch` 负责“生效”

---

## 6. valid 传播为什么也重要

```systemverilog
pe_valid_out <= pe_valid_in;
```

这说明 valid 不是局部信号，而是 systolic 波前的一部分。

它的作用是：
- 告诉下游，这一拍来的 input / psum 是有效的
- 控制何时真正更新 `pe_input_out` 和 `pe_psum_out`

这也是为什么后面 Frontend 和验证都很关心波形里的 valid 边界。

---

## 7. `pe_enabled` 为什么存在

这个信号允许阵列按列裁剪。

如果当前 tile 的 `col_size` 没有用满全部列，就可以通过 `pe_enabled` 关掉某些 PE 的外部输出行为。

这在当前 2x2 原型里很实用，因为：
- 某些层/某些 tile 不一定总是满 2 列
- 如果还让所有 PE 都照常吐输出，会把无意义数据带到后级

所以 `pe_enabled` 是阵列适配 tile 形状的重要手段。

---

## 8. 这个文件真正想表达的设计哲学

这个 PE 不是为了做“最大性能单元”，而是为了做“当前原型里容易验证、容易理解、支持 shadow/active 权重切换的阵列单元”。

所以你会看到它的重点不在复杂优化，而在：
- 明确的 valid 传播
- 明确的 switch 生效边界
- 明确的 weight 装载和计算分离

这和整个项目“先把系统闭环跑通”的思路是一致的。

---

## 一页总结

如果你只记 `pe.sv` 的 5 个点，就记：

1. 它是带状态的阵列节点，不是纯乘法器。
2. 当前乘法用的是 `weight_reg_active`，不是输入口直接进来的 weight。
3. `pe_accept_w_in` 负责装 shadow weight。
4. `pe_switch_in` 负责让 shadow weight 生效。
5. valid / input / psum / weight / switch 都会沿阵列继续传播。

最后一句话：
**`pe.sv` 的价值，是把“装权重”和“用权重计算”分开，从而让整个 systolic array 能按阶段安全切换权重。**
