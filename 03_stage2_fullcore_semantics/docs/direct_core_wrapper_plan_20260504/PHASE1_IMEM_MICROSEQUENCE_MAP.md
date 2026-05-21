## Phase 1 - IMEM Micro-Sequence To Core Action Map

### 目的

这份文档把当前 forward tile 里使用的 IMEM micro-sequence 展开成“每一步对 core 做了什么”，为后续去 IMEM / 去 sequencer 提供一一对应的替换表。

### 当前 IMEM 长度

- `IMEM_LEN = 9`
- 每个 output-word / tile 都会重装一次这 9 条指令

### 当前 9-step 序列

#### Step 0

指令：`UB_RD weight, addr=2, row=2, col=2, transpose=1, ptr=WEIGHT, pathway=0000`

作用：

- 从 UB weight 区读出 2x2 权重矩阵
- 把权重送到 systolic 顶部输入
- `pathway=0000`，这一步只是装填权重，不触发最终前向路径

#### Step 1

指令：`NOP`

作用：

- 给权重/内部流水预留一个空拍

#### Step 2

指令：`NOP`

作用：

- 继续给流水和 shadow/active 缓冲切换前的准备留拍

#### Step 3

指令：`NOP`

作用：

- 继续留拍

#### Step 4

指令：`SWITCH`

作用：

- 触发 systolic `sys_switch_in`
- 把权重从 shadow buffer 切换到 active buffer

#### Step 5

指令：`NOP`

作用：

- 给 switch 后的内部传播留拍

#### Step 6

指令：`NOP`

作用：

- 继续留拍

#### Step 7

指令：`UB_RD bias, addr=6, row=1, col=2, transpose=0, ptr=BIAS, pathway=current_tile_pathway`

作用：

- 从 UB bias 区读出当前 tile 的 2 个 bias scalar
- 把 bias 标量送入 VPU
- `pathway` 在这里第一次带入真正的前向模式：
  - 非最后一 tile：固定 `1000`
  - 最后一 tile：`1000` 或 `1100`

#### Step 8

指令：`UB_RD input, addr=0, row=1, col=2, transpose=0, ptr=INPUT, pathway=current_tile_pathway, wait=1`

作用：

- 从 UB input 区读出当前 tile 的 2 个 input scalar
- 把 input 送入 systolic 左侧
- 和已装填的 weight、bias 一起触发一次 tile 级前向执行
- `wait=1` 让 sequencer 在 VPU drain 前停住

### 当前 readback 序列

readback 不属于上面的 9-step IMEM，而是单独走：

1. `INSTR_W0 = UB_RD Y, addr=8, row=1, col=2, ptr=Y, pathway=0000`
2. `CTRL.step = 1`
3. 等待 `ub_rd_y_valid_out_0/1`
4. 把 `{Y1, Y0}` 组合成最终 32-bit output word

### tile 之间的额外外层语义

当前 IMEM 之外，bridge 还做了两件重要的外层动作：

1. 在每个 tile 之前重新 `core_reset_req`
2. 在 `input_words > 1` 时，把上一 tile 捕获到的 `vpu_data_out_*` 作为下一 tile 的 `bias` 回灌

因此，direct-core 版本不能只复制 9 条 IMEM 动作，还必须同时保留这两层 wrapper 语义。

### direct-core 替代表

- `UB_RD weight` -> 本地发起一次 `ub_rd_start`，`ptr_select=WEIGHT`
- `NOP` -> 本地等待若干拍，或在更懂内部时序后压缩
- `SWITCH` -> 本地拉一次 `sys_switch_in`
- `UB_RD bias` -> 本地发起一次 `ub_rd_start`，`ptr_select=BIAS`，并带上当前 `vpu_data_pathway`
- `UB_RD input(wait)` -> 本地发起一次 `ub_rd_start`，`ptr_select=INPUT`，并等待当前 tile 计算完成
- `UB_RD Y(step)` -> 本地发起一次 `ub_rd_start`，`ptr_select=Y`，等待 `ub_rd_Y_valid_out_*`

### 结论

当前 IMEM 对 direct-core 改造最大的价值，不是“必须永远保留它”，而是：

- 它已经把当前前向子集真正需要的执行顺序固定下来了
- 后续 direct-core wrapper 可以按这张表逐项本地化，不必重新猜 TinyTPU 需要什么顺序
