## Phase 4 Training Path Plan (2026-05-10)

### 目的

把当前 `fullcore` 路线从：

- `forward packed-linear`
- `leaky-ReLU`
- terminal-tile `transition MSE`

扩到最小可用训练主线：

- hidden-layer `backward-only` (`0001`)
- `lr_d`
- `gradient_descent`
- updated weight / bias writeback

当前这份计划只定义“最小训练闭环”，不追求一次覆盖全部 TinyTPU 训练语义。

### 当前边界

当前 SoC 主线已经具备：

- `bridge -> tpu_frontend_local -> tpu`
- `descriptor fetch -> input/param fetch -> UB preload -> tile exec -> UB readback -> AXI writeback`
- `1000 / 1100 / 1111` 三类已落地前向/transition 调度

当前 SoC 主线仍缺：

- `tile_exec` 对 `H` 的调度入口
- `0001` backward 路径的完整执行壳
- gradient / parameter update 的上层触发协议
- updated parameter 的 shared-SRAM writeback
- 对训练路径的 deterministic regression

### 为什么先不直接做“完整训练”

因为当前 direct-core 路线首先要保住：

1. `UB / systolic / VPU / UB readback` 这条主链路
2. 现有 forward/transition 回归
3. stage2 SoC 的 `descriptor + shared SRAM + status` ABI

训练扩展会同时增加：

- `H / Y / gradient / updated parameter` 的 workspace 协议
- `frontend_local` 的本地调度状态数
- `bridge` 的 descriptor 解释和 writeback 分支
- 回归矩阵规模和 golden 复杂度

因此训练扩展必须分阶段推进。

### 最小落地目标

先只打通下面这个闭环：

1. output layer 继续使用当前 terminal-tile `1111` 生成梯度相关输出
2. hidden layer 支持 `0001` backward-only 路径
3. UB 支持读取旧参数和梯度，触发 `gradient_descent`
4. updated bias / weight 能写回 UB
5. bridge 能把 updated bias / weight 从 UB 写回 shared SRAM

不在第一阶段内强求：

- 更复杂的 `Y-layout`
- 任意 `inv_batch_size_times_two`
- 多层网络级联训练调度
- 完整 scratch/workspace 复用优化

### 最少要改的文件

#### 1. `rtl/bridge/tpu_frontend_local.sv`

当前问题：

- `tile_exec` 只携带 `input/weight/bias/Y`
- 没有 `H` 地址
- 没有训练/update 模式调度

最少改动：

- 新增 `tile_exec_h_addr`
- 新增训练相关模式位，区分：
  - forward/transition tile
  - backward tile
  - grad-bias update
  - grad-weight update
- 把当前 `step0..step9` 扩成可覆盖：
  - `WEIGHT -> H -> INPUT` 的 `0001` 调度
  - `grad_bias` / `grad_weight` 的 UB 读触发

#### 2. `rtl/bridge/tpu_stage2_fullcore_wrapper.sv`

当前问题：

- wrapper 只在 bridge/front-end/tpu 三者之间透传前向接口
- 只把 `ub_rd_y_*` 回接给 bridge

最少改动：

- 透传 `tile_exec_h_addr`
- 透传训练/update 模式控制
- 暴露更通用的 readback 或 update 完成观测
- 必要时把 `ub_rd_H_*` 或 update 结果也带回 bridge

#### 3. `rtl/core/tpu.sv`

当前问题：

- 内部已经有 `H`、`gradient_descent` 相关连接能力
- 但 wrapper 侧没有把这些能力组织成训练主线可用接口

最少改动：

- 评估是否需要向上暴露：
  - `ub_rd_H_*`
  - gradient update 结果/完成信号
- 如果上层坚持只走 UB readback，则至少要保证训练结果能稳定落到可读 UB 地址

#### 4. `rtl/core/unified_buffer_v3.sv`

当前问题：

- 已支持 `ptr_select=4/5/6`，但没有成为当前 SoC 主线 ABI

最少改动：

- 固化 `H` 读的时序与保持语义
- 固化 `grad_bias / grad_weight` update 启动条件
- 明确 update 结果写回 UB 的地址协议
- 增加便于 bridge/frontend 收敛的完成观测点

#### 5. `rtl/bridge/tpu_stage2_fullcore_bridge.sv`

当前问题：

- 当前 descriptor 只支持前向/transition 最小子集
- 当前状态机只做 input/param fetch、tile exec、output writeback

最少改动：

- 扩展 descriptor / flags 协议，增加训练模式
- 定义 `H / Y / grad / updated-param` 的 shared-SRAM 布局
- 增加 backward tile 发起分支
- 增加 grad/update 分支
- 增加 updated weight / bias 的 AXI writeback 分支

### 建议阶段

#### Step A: 先打通 `0001 backward-only`

目标：

- 不碰参数更新
- 只让 `frontend_local + wrapper + tpu` 跑通 `H + input -> lr_d`

验收：

- 本地 TB 能稳定输出 hidden-layer delta

#### Step B: 再打通 UB 内参数更新

目标：

- 用 UB 现有 `ptr_select=5/6` 路径驱动 `gradient_descent`
- 让 updated value 稳定回写 UB

验收：

- 本地 TB 能比较 old/new parameter

#### Step C: 最后接回 bridge 和 shared SRAM

目标：

- bridge 能把训练结果写回 shared SRAM
- 形成最小 SoC 训练闭环

验收：

- 新增 stage2 训练 smoke regression

### 新回归建议

至少新增 3 组：

1. `tb_tpu_stage2_fullcore_backward_smoke.sv`
   - 只验 `0001`
2. `tb_tpu_stage2_fullcore_update_smoke.sv`
   - 只验 gradient descent 写回 UB
3. `tb_tpu_stage2_fullcore_train_step_smoke.sv`
   - 验一轮最小 `forward -> backward -> update`

### 下一步先看哪个代码

下一步先看：

- `00_fullcore_lab/rtl/bridge/tpu_frontend_local.sv`

原因：

1. 它是当前 SoC 主线和训练语义之间最薄、也是最关键的缺口。
2. 训练现在不是“core 没能力”，而是“本地执行壳没把 `H/backward/update` 调起来”。
3. 先把这里看明白，再看 `unified_buffer_v3.sv` 的 `ptr_select=4/5/6`，你就会清楚训练到底差哪几步。

建议阅读顺序：

1. `rtl/bridge/tpu_frontend_local.sv`
2. `rtl/core/unified_buffer_v3.sv`
3. `rtl/core/tpu.sv`
4. `rtl/bridge/tpu_stage2_fullcore_wrapper.sv`
5. `rtl/bridge/tpu_stage2_fullcore_bridge.sv`

### 你接下来阅读时只回答这 4 个问题

1. `frontend_local` 现在为什么只能稳定调前向/transition？
2. `H` 要从哪里读，什么时候读？
3. `gradient_descent` 的输入 old value / gradient / lr 分别从哪里来？
4. update 完成后，结果最终该如何从 UB 回到 shared SRAM？
