## Direct-Core Wrapper Plan (2026-05-04)

### 背景

当前 `tpu_stage2_fullcore_wrapper` 已经完成了 SoC 外层语义重构：

- 上层暴露 `descriptor + shared SRAM + launch/done`
- 下层不再走旧 `sys_psum_out + 外部 bias/relu/round` 路线
- 最终结果通过 `UB readback` 回写 shared SRAM

但当前实现仍保留了一层本地执行壳，用来承接 tile/step 级别的最小调度语义。

因此，当前版本的准确定义是：

- `SoC 外层 wrapper/bridge` 已重做
- `TinyTPU` 活动路径已缩成 `bridge -> tpu_frontend_local -> tpu`
- `tpu_soc / tpu_frontend_axil / control_unit / IMEM / CTRL.start-step` 已不再是活动依赖
- 当前只保留本地 `tile FSM + readback handshake` 这一层最小执行壳
- 当前验证通过的是“fullcore 前向推理子集 + SoC 主链路”

### 当前保留本地执行壳的原因

当前保留这层本地 tile/readback 执行壳不是功能错误，而是一个过渡实现选择：

1. 它允许 bridge 直接驱动当前 SoC 主线真正需要的 tile/readback 控制子集。
2. 它避免在同一阶段同时扩展更多 TinyTPU 语义和重写整套 core 执行时序。
3. 它保留了足够清晰的本地观测点，便于继续收集 `UB / systolic / VPU / UB readback` 这条前向主线的证据。

### 最终目标

最终目标不是长期依赖 `tpu_frontend_axil + IMEM + sequencer`，而是：

1. 保留 `tpu / unified_buffer / systolic / pe / vpu` 原始核心语义。
2. 去掉 reference frontend 岛对 SoC 集成的结构性依赖。
3. 让 stage2 wrapper 直接驱动 core 所需控制接口，或者只保留最小本地控制层。
4. 不再通过 AXI-Lite 写 `IMEM` 来间接执行每个 tile。

### 目标架构

目标架构分层如下：

- 上层：`descriptor + shared SRAM + AXI writeback + status`
- 中层：`stage2 direct-core bridge`
- 下层：`tpu core semantic island`
  - `unified_buffer_v3`
  - `systolic`
  - `pe`
  - `vpu`
  - 以及 `fixedpoint / loss / gradient / leaky / bias` 等原始依赖

目标状态下，不再例化：

- `tpu_soc`
- `tpu_frontend_axil`
- `control_unit`
- 对 SoC 路线而言的外部 `IMEM/sequencer` 依赖

### 分阶段计划

#### Phase 0: 冻结当前可用基线

目的：保留一个已跑通 SoC 的 fullcore 基线，避免后续去 frontend 改造时失去参照。

要求：

- `run_vcs_stage2_cpu_boot_real_params.sh` 保持通过
- `run_vcs_stage2_cpu_boot_cpu_frontend.sh` 保持通过
- `run_vcs_stage2_regression_stable.sh` 保持通过

#### Phase 1: 定义 direct-core 控制边界

目的：从当前 `frontend + IMEM` 路线中抽取出 core 真正需要的最小控制集合。

要澄清的接口：

- UB host write 时序
- UB read start / transpose / row / col / ptr-select
- `sys_switch` 的使用边界
- `vpu_data_pathway`、`learning_rate`、`inv_batch_size_times_two`、`leak_factor` 的生效点
- output 结果到底从 `VPU` 捕获、`UB Y` 读回、还是二者都保留观测

交付物：

- 一份 direct-core wrapper 的接口草图
- 当前 `IMEM` micro-sequence 到本地状态机动作的映射表

#### Phase 2: 移除 AXI-Lite frontend 依赖

目的：bridge 不再通过 AXI-Lite 寄存器去推动 TinyTPU 岛。

方向：

- 把 `UB_DATA / UB_PUSH / CTRL.start / CTRL.step / UB_RD_*` 这些 frontend 寄存器语义，转成本地硬连/本地状态机
- 去掉 `fe_aw* / fe_w* / fe_ar* / fe_r*` 这套中间 AXI-Lite 主机

完成标准：

- bridge 与 core 之间不再存在 AXI-Lite 事务
- SoC 主线输出与当前 fullcore 基线一致

#### Phase 3: 移除 IMEM / sequencer 依赖

目的：不再通过 `IMEM_ADDR / IMEM_W0 / IMEM_WE / IMEM_LEN / CTRL.start` 组织每个 tile 的执行。

方向：

- 把当前 9-step 左右的 micro-sequence 内联进 wrapper 本地状态机
- 保留执行顺序语义，不保留 reference frontend 的实现外壳

完成标准：

- wrapper 不再例化 `tpu_frontend_axil`
- wrapper 不再依赖 `control_unit` / `IMEM` / sequencer

#### Phase 4: 扩展非前向语义

目的：在 direct-core 架构稳定后，再扩展更多 TinyTPU 原始语义。

优先顺序：

1. 更完整的 scratch/workspace 协议
2. 从当前 terminal-tile `transition MSE` 子集继续扩到更广的 `loss / inv_batch / Y-layout` 组合
3. `lr_d` / gradient-descent / 训练路径
4. 其他非当前 SoC 主线必需的控制模式

### Phase 1 输出文件

- `PHASE1_FRONTEND_REGISTER_SEMANTICS.md`
  - 当前 bridge 实际用到的 frontend 寄存器语义抽取表
- `PHASE1_IMEM_MICROSEQUENCE_MAP.md`
  - 当前 9-step IMEM micro-sequence 到 core 动作的映射表
- `PHASE1_DIRECT_CORE_INTERFACE_SKETCH.md`
  - direct-core wrapper 的最小接口草图和状态机建议

### 当前推进状态

截至 `2026-05-05`，Phase 3 已经落地，Phase 4 也已经向前迈出第一步：在保住 SoC 主线的前提下，把 fullcore 语义从纯前向子集扩到 terminal-tile `transition MSE` 子集。

当前已落地并通过回归的 Phase 4 最小扩展是：

- 新增 `flags[25]` 控制的 terminal-tile `1111` pathway
- `desc_scratch_addr` 在该模式下解释成 per-output-word 的 `Y` block 基址
- `inv_batch_size_times_two` 先固定到 `16'h0100`，只覆盖最小 `MSE` 终结语义
- 结果仍走 `UB readback -> AXI writeback`，没有回退到 bridge 外部取 `sys_psum_out_*`

同时，Phase 3 的 direct-core 化已经在 `tpu_stage2_fullcore_semantics` 工作区落地，并且本地与整机回归都已通过：

- `tpu_stage2_fullcore_wrapper.sv` 不再例化 `tpu_soc`
- `tpu_stage2_fullcore_wrapper.sv` 不再例化 `tpu_frontend_axil`
- `tpu_stage2_fullcore_wrapper.sv` 不再结构性依赖 `control_unit`
- bridge 与执行岛之间已不再走 `fe_aw* / fe_w* / fe_b* / fe_ar* / fe_r*` 这套 AXI-Lite 事务
- 新增 `rtl/bridge/tpu_frontend_local.sv`
  - 把 frontend 对外接口收敛成本地 `cmd/rsp + tile_exec + readback_exec` 握手
  - 直接由本地 tile/readback 状态机发出 `sys_switch / ub_rd / UB host write` 等核心控制
- 当前执行路径已经变成：
  - `bridge -> tpu_frontend_local -> tpu`

这一阶段通过的本地回归：

- `tb/run_vcs_tpu_stage2_fullcore_wrapper_smoke.sh`
- `tb/run_vcs_tpu_stage2_fullcore_exec_compare.sh`
- `tb/run_vcs_tpu_stage2_fullcore_leaky_compare.sh`
- `tb/run_vcs_tpu_stage2_fullcore_forward_sweep.sh`

这一阶段通过的整机回归：

- `run_vcs_stage2_cpu_boot_real_params.sh`
- `run_vcs_stage2_cpu_boot_cpu_frontend.sh`
- `run_vcs_stage2_regression_stable.sh`

因此，当前还保留的结构性依赖只剩一项大类：

- 本地 `tile/readback FSM` 执行壳

### 风险

1. 当前 bridge 已经依赖 reference frontend 帮忙完成若干时序收敛；直接驱动 core 后，时序边界会暴露。
2. 多 tile 累积当前仍依赖 `captured vpu_data_out -> next tile bias` 的外部暂存语义，直接 core 化后要重新确认这个边界是否继续保留。
3. 直接去掉 frontend 后，如果没有同步建立新的观测点，调试难度会明显上升。

### 验收标准

当下面 4 条同时满足时，才可认为“已完成 direct-core wrapper 改造”：

1. `tpu_stage2_fullcore_wrapper` 不再依赖 `tpu_frontend_axil` / `IMEM` / sequencer。
2. `CPU_Copetition_tpu_soc` 中 `real_params` 和 `fixture cpu_frontend` 两条主回归保持通过。
3. 最终结果仍通过 `UB` 或等价核心内存语义读回，不回退到 `sys_psum_out` 外部后处理。
4. 保留 `UB / PE / systolic / VPU` 原始协同语义。

### 补充计划

- `PHASE4_TRAINING_PATH_PLAN_20260510.md`
  - 记录从当前前向/transition 主线继续扩到 `0001 / gradient_descent / 最小训练闭环` 的分阶段计划
  - 明确下一步先从 `rtl/bridge/tpu_frontend_local.sv` 开始看
