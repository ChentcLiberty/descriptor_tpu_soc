# SoC Drop-In Package

这个目录是给 `CPU_Copetition_tpu_soc` 准备的平铺 RTL 包。

目标：
- 适配主工程 `rtl/*.v` 的编译习惯
- 保持 full-core TinyTPU 语义
- 让 `tpu_stage2_real_wrapper` 可直接替换主工程现有 real-wrapper 入口

## 替换主工程现有文件

- `tpu_stage2_real_wrapper.v`
- `tpu.v`
- `unified_buffer_v3.v`
- `systolic.v`
- `pe.v`
- `vpu.v`

## 作为新增依赖带入主工程的文件

- `fixedpoint.v`
- `gradient_descent.v`
- `bias_child.v`
- `bias_parent.v`
- `leaky_relu_child.v`
- `leaky_relu_parent.v`
- `leaky_relu_derivative_child.v`
- `leaky_relu_derivative_parent.v`
- `loss_child.v`
- `loss_parent.v`
- `control_unit.v`
- `tpu_frontend_local.v`
- `tinytpu_frontend_pkg.v`
- `tpu_stage2_fullcore_bridge.v`
- `tpu_stage2_fullcore_wrapper.v`

## 本地验证

已通过：
- `tb/run_vcs_tpu_stage2_soc_dropin_smoke.sh`

这说明这个平铺包本身可以按 `*.v` 方式独立编译并跑最小 smoke。
## 当前结构状态

当前 `soc_dropin` 包已经同步到与 `rtl/bridge` 相同的 wrapper 形态：

- `tpu_stage2_fullcore_wrapper.v` 不再例化 `tpu_soc`
- `tpu_stage2_fullcore_wrapper.v` 不再例化 `tpu_frontend_axil`
- 执行路径已经变成：
  - `tpu_stage2_fullcore_bridge -> tpu_frontend_local -> tpu`

当前仍保留：

- `control_unit.v`
- `IMEM/sequencer` 语义

所以它现在是“去 `tpu_soc` / 去 `tpu_frontend_axil` 的 drop-in 包”，还不是“完全去 frontend / 去 IMEM”的最终形态。

当前 `tb/run_vcs_tpu_stage2_soc_dropin_smoke.sh` 的编译入口也已经显式排除了 legacy `tpu_soc.v` / `tpu_frontend_axil.v`，避免验证时又把旧壳子混回 active build list。
