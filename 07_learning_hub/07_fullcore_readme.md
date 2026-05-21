## TPU Stage2 Full-Core Semantics

这个工作区用于一条新的集成路线：

- 保留 TinyTPU 计算核心原始语义
- 允许重做 stage2 外围 frontend / bridge / descriptor 适配层
- 不再沿用当前 `tpu_stage2_tinytpu_exec` 那条“直接取 `sys_psum_out` 并在外部做 bias/relu/round”的路径

### 设计边界

必须保持原始语义的核心文件：

- `rtl/core/tpu.sv`
- `rtl/core/unified_buffer_v3.sv`
- `rtl/core/systolic.sv`
- `rtl/core/pe.sv`
- `rtl/core/vpu.sv`

以及这些核心依赖：

- `rtl/core/fixedpoint.sv`
- `rtl/core/gradient_descent.sv`
- `rtl/core/bias_*`
- `rtl/core/leaky_relu_*`
- `rtl/core/loss_*`

参考前端文件保存在：

- `rtl/reference/tpu_frontend_axil.sv`
- `rtl/reference/control_unit.sv`
- `rtl/reference/tpu_soc.sv`

### 当前目标

新的 stage2 桥接层应满足：

1. 对上层仍暴露 stage2 `descriptor + shared SRAM + launch/done` 语义
2. 对下层完整驱动 TinyTPU 原始核心语义：
   - `UB -> systolic/PE -> VPU -> UB`
3. 不在核心外部重做 bias / relu / rounding
4. 不直接消费 `sys_psum_out_*` 作为最终推理输出语义

### 当前目录结构

- `rtl/core`
  - 原始核心语义文件，仅作为完整核心保留区
- `rtl/reference`
  - 原始 AXI-Lite 前端/SoC 封装参考
- `rtl/bridge`
  - 新的 stage2 bridge/front-end 开发区
- `tb`
  - 这条 full-core 路线自己的最小验证
- `rtl/soc_dropin`
  - 面向 `CPU_Copetition_tpu_soc` 的平铺 drop-in 包
  - 文件名/后缀按主工程 `rtl/*.v` 编译习惯整理，可直接对照替换
- `docs/direct_core_wrapper_plan_20260504`
  - 记录 direct-core wrapper 的迁移过程
  - 记录当前仅保留本地 `tile/readback FSM` 执行壳这一边界

### 这条路线与当前主工程的关系

主工程里现有的 bit-exact 路线可作为“stage2 ABI 已打通”的参考；
但它不作为这条 full-core-semantics 路线的最终实现。

### 当前已落地

- `rtl/bridge/tinytpu_frontend_pkg.sv`
  - 固化 TinyTPU frontend 寄存器地址、控制位、UB/指令编码函数
- `rtl/bridge/tpu_stage2_fullcore_wrapper.sv`
  - 固定 stage2 drop-in wrapper 端口
- `rtl/bridge/tpu_stage2_real_wrapper.v`
  - SoC 兼容模块名壳，保持与主工程现用 `tpu_stage2_real_wrapper` 相同端口/参数形态，内部直接例化 full-core wrapper
  - 当前 wrapper 已直接例化 `tpu_frontend_local + tpu`
  - 不再结构性依赖 `tpu_soc`
  - 把 `vpu_data_out_* / vpu_valid_out_*` 回接给 bridge 做 tile 累积捕获
  - 把 `ub_rd_y_data_out_* / ub_rd_y_valid_out_*` 回接给 bridge 做最终结果 UB 读回
  - 支持 bridge 在 output-word 批次之间本地复位原始 TinyTPU 岛
- `rtl/bridge/tpu_stage2_fullcore_bridge.sv`
  - 已实现 8-word descriptor 读取
  - 已实现 shared-SRAM input/param fetch
  - 已实现本地 `cmd/rsp` 方式驱动 frontend 语义
  - 已实现一个最小前向 packed-linear 子集：`input_words>=1, output_words>=1, TILE2X2_Q8_8`
  - 对每个 output word，bridge 都会重新复位核心、装载 input/weight/bias，并通过本地 `tile_exec + readback_exec` 执行壳完成逐 tile 计算；当 `input_words>1` 时，上一 tile 捕获到的 `vpu_data_out_*` 会作为下一 tile 的 bias 继续回灌累积
- `rtl/bridge/tpu_frontend_local.sv`
  - 本地化替代了 `tpu_frontend_axil` 的 AXI-Lite 壳
  - 直接由本地 tile/readback 状态机发出 `sys_switch / ub_rd / UB host write` 等核心控制
  - 当前 wrapper 已不再结构性依赖 `tpu_frontend_axil`、`control_unit`、`IMEM` 或 `CTRL.start/step`
  - 当前活动路径里保留的最小执行壳只有 `cmd/rsp + tile_exec + readback_exec`

### 当前最小支持范围

当前 bridge 支持：

- `desc_flags[16] = TILE2X2_Q8_8`
- `input_words >= 1`
- `output_words >= 1`
- 前向路径：
  - `flags[0] = 0` 时走 `1000`，即 bias only
  - `flags[0] = 1` 时默认走 `1100`，即 ReLU 语义（`TPU_FE_REG_LEAK = 0`）
    - 只有当 `flags[24] = 1` 且 `desc_scratch_addr != 0` 时，bridge 才会从 shared SRAM 额外读取 1 个 word，并把其低 16 bit 作为 Q8.8 leak factor 写入 `TPU_FE_REG_LEAK`
- `transition MSE` 终结 tile 子集：
  - 当 `flags[25] = 1` 时，最后一个 tile 的 `vpu_data_pathway` 会切到 `1111`
  - 当前要求 `flags[0] = 1`、`flags[24] = 0`、`desc_scratch_addr != 0`
  - `desc_scratch_addr` 在该模式下不再表示 leak-factor 指针，而是每个 output word 对应 1 个 `Y` word 的 shared-SRAM 基址
  - bridge 会先把该 `Y` word 推到 UB `Y` 口，再以 `inv_batch_size_times_two = 16'h0100` 触发终结 tile 的 transition/loss 语义
  - 结果最终仍然走 `UB readback -> AXI writeback`，只是终结 tile 的 output readback 地址从 `UB[8:9]` 顺延到 `UB[10:11]`

不满足这个子集时，bridge 会直接报 `status_error`。

### 已验证结果

已通过：

- `vcs -full64 -sverilog -timescale=1ns/1ps -f rtl/filelist.f -top tpu_stage2_fullcore_wrapper`
  - full-core wrapper 路线可通过静态编译/elab
- `tb/run_vcs_tpu_stage2_fullcore_wrapper_smoke.sh`
  - 单 input-word smoke 通过
  - 日志结果：`done=1 error=0 out0=ff000240 out1=fe800200 in_cnt=1 param_cnt=6`
- `tb/run_vcs_tpu_stage2_fullcore_exec_compare.sh`
  - 已覆盖并通过 `single_tile_no_relu`、`multi_tile_no_relu`、`multi_tile_relu`、`single_tile_transition_relu`、`multi_tile_transition_relu`
  - 日志结果：
    - `single_tile_no_relu: done=1 error=0 out0=ff000240 out1=fe800200 in_cnt=1 param_cnt=6`
    - `multi_tile_no_relu: done=1 error=0 out0=ff800400 out1=0100fb00 in_cnt=3 param_cnt=14`
    - `multi_tile_relu: done=1 error=0 out0=00000200 out1=00000400 in_cnt=2 param_cnt=10`
    - `single_tile_transition_relu: done=1 error=0 out0=ff800140 out1=ff800100 in_cnt=1 param_cnt=6`
    - `multi_tile_transition_relu: done=1 error=0 out0=ff800100 out1=ff800300 in_cnt=2 param_cnt=10`
- `tb/run_vcs_tpu_stage2_fullcore_leaky_compare.sh`
  - 已覆盖并通过 `single_tile_leaky_half`、`multi_tile_leaky_quarter`
  - 日志结果：
    - `single_tile_leaky_half: done=1 error=0 out0=ff800240 out1=ff400200 in_cnt=1 param_cnt=6`
    - `multi_tile_leaky_quarter: done=1 error=0 out0=ffe00400 out1=0100fec0 in_cnt=3 param_cnt=14`
- `tb/run_vcs_tpu_stage2_fullcore_forward_sweep.sh`
  - 已覆盖并通过 112 个 deterministic forward case
  - 扫描范围：`input_words=1..7`、`output_words=1..4`，以及 4 种 activation mode
    - `flags[0]=0`
    - `flags[0]=1, scratch_addr=0`（ReLU）
    - `flags[0]=1, scratch_addr!=0, leak=0x0040`
    - `flags[0]=1, scratch_addr!=0, leak=0x0080`
  - 结果：`[PASS] tb_tpu_stage2_fullcore_forward_sweep complete cases=112`

这说明下面这条链已经真实闭合：

`descriptor fetch -> input/param fetch -> local frontend cmd/rsp -> local tile/readback FSM -> tpu -> UB -> systolic -> VPU -> UB -> UB readback -> AXI writeback`

### 关键修正

多 tile 累积最初失败，不是因为“上一 tile 输出回灌为下一 tile bias”这个思路本身错误，而是因为 bias scalar 在 unified buffer 里按波前吐出后，被过早清零了：

- 在 2-input / 2-output 回归里，第二个 tile 的 `bias_rd` 比 `sys_valid_out_*` 早约 4 个周期结束
- 因此 VPU 实际看到的是“纯第二个 tile 的 systolic 输出”，而不是“第二个 tile 输出 + 上一个 tile 的累积结果”
- 把 bias 读口改成“读到某列 scalar 后保持到下一次 reset/新 bias 读”为止后，single-input、multi-input、以及 ReLU 打开场景都回到了 stage2 已验证 ABI 的数学期望值

补充说明：当前 `desc_scratch_addr` 已经分成两个最小 fullcore 扩展用法：

- `flags[24] = 1` 时，按 shared-SRAM leak-factor 指针解释，已覆盖 `leak in {0x0000, 0x0040, 0x0080}`
- `flags[25] = 1` 时，按 transition `Y` block 基址解释，每个 output word 消耗 1 个 `Y` word

两种扩展当前不能叠加；未设置对应扩展 flag 时，`desc_scratch_addr` 继续保持主 SoC 的 scratch 语义。

### 当前边界

当前已经验证的是 `forward packed-linear + leaky-ReLU + terminal-tile transition MSE` 子集，其中 deterministic sweep 已覆盖：

- `input_words=1..7`
- `output_words=1..4`
- `flags[0]=0` 的 bias-only 路径
- `flags[0]=1, scratch_addr=0` 的 ReLU 语义
- `flags[0]=1, flags[24]=1, scratch_addr!=0` 且 `leak in {0x0040, 0x0080}` 的非零 leaky-ReLU 语义
- `flags[0]=1, flags[25]=1, desc_scratch_addr!=0` 的 terminal-tile `1111` transition MSE 语义

当前 `transition MSE` ABI 仍然是最小子集：

- 只覆盖终结 tile 的 `1111` pathway
- `inv_batch_size_times_two` 目前固定为 `16'h0100`
- `desc_scratch_addr` 只支持最简单的“每个 output word 对应 1 个 Y word”协议

仍未覆盖：

- 其他非零 leak factor 取值的更大范围扫描
- 更广的 `inv_batch_size_times_two` / `Y` 布局扫描
- backward-only / `lr_d` / gradient-descent / 训练路径
- `flags[24]` 与 `flags[25]` 组合使用
- 更大矩阵尺寸或超出当前 bridge `MAX_INPUT_WORDS=256` 的 descriptor 形状
- 更进一步减少 bridge 对“上一 tile 的 `vpu_data_out_*` 回灌成下一 tile bias”这层外部暂存依赖

如果后续要把这条 full-core 路线扩到更完整的 TinyTPU 语义，下一步优先补这些回归覆盖，而不是再回退到 bridge 外部累积。
