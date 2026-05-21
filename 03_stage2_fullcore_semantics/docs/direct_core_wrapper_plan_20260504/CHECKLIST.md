## Direct-Core Wrapper Checklist

### 当前状态

- [x] SoC 外层 `stage2 real wrapper` 已切到 fullcore 路线
- [x] `real_params` 主线通过
- [x] `fixture cpu_frontend` 主线通过
- [x] 稳定回归总入口通过
- [x] 最终结果走 `UB readback -> AXI writeback`
- [x] 不再依赖 `tpu_soc`
- [x] 不再依赖 `tpu_frontend_axil`
- [x] 不再依赖 `control_unit`
- [x] 不再依赖 `IMEM/sequencer`

### Phase 1

- [x] 列出当前 bridge 写入 frontend 的全部寄存器语义
- [x] 列出当前 IMEM micro-sequence 对 core 的动作映射
- [x] 整理 direct-core wrapper 最小接口草图

### Phase 2

- [x] 去掉 bridge 到 frontend 的 AXI-Lite 写通道
- [x] 去掉 bridge 到 frontend 的 AXI-Lite 读通道
- [x] 本地化 UB write / UB read 控制

### Phase 3

- [x] 本地化 sequencer 状态机
- [x] 去掉 IMEM 指令装载流程
- [x] 去掉 `CTRL.start/step` 依赖

### Phase 4

- [x] 回归 `wrapper_smoke`
- [x] 回归 `exec_compare`
- [x] 回归 `leaky_compare`
- [x] 回归 `forward_sweep`
- [x] 扩到 terminal-tile `transition MSE` 子集（`flags[25]` / `1111` pathway / `Y` from scratch）
- [x] 回归 `stage2_cpu_boot_real_params`
- [x] 回归 `stage2_cpu_boot_cpu_frontend`
- [x] 回归 `stage2_regression_stable`
- [ ] 扩到更广的 `loss / inv_batch / Y-layout` 组合
- [ ] 扩到 `lr_d / gradient-descent / 训练路径`
