# TPU SoC Learning Hub

这个目录不是新的实现工程，只是把当前最有用的两条线收成一个学习入口：

- `00_soc_main`
  - 完整 SoC 主工程：`Panda CPU + DMA + shared SRAM + TPU`
- `00_fullcore_lab`
  - fullcore 语义工作区：保留 `UB / PE / systolic / VPU` 原始协同语义

建议阅读顺序：

1. `01_validation_status.md`
   - 先建立整机视角，知道现在通过了什么、没通过什么
2. `02_soc_top.v`
   - 看 SoC 顶层怎么把 CPU、shared SRAM、TPU 接起来
3. `03_shared_mem.v`
   - 看 CPU master 和 TPU master 怎样共享 SRAM
4. `04_real_wrapper.v`
   - 看 SoC 顶层怎么挂载 TPU wrapper
5. `05_fullcore_wrapper.v`
   - 看 fullcore wrapper 的结构壳
6. `06_fullcore_bridge.v`
   - 看 descriptor / SRAM / TPU 核心语义怎么翻译
7. `07_fullcore_readme.md`
   - 看当前 fullcore 已覆盖到哪些语义
8. `08_direct_core_plan.md` + `09_direct_core_checklist.md`
   - 看后续还没完成的方向

边界：

- 这里是学习入口，不是新的 build 根目录
- 真正跑整机回归还是在 `00_soc_main`
- 真正改 fullcore 核心语义还是在 `00_fullcore_lab`

## 子模块阅读链

继续往下看可以按这条线：

- `10_frontend_local.v`
- `11_core_tpu.v`
- `12_core_unified_buffer_v3.v`
- `13_core_systolic.v`
- `14_core_pe.v`
- `15_core_vpu.v`
- `16_core_fixedpoint.v`
- `17_core_bias_parent.v`
- `18_core_loss_parent.v`
- `19_core_gradient_descent.v`

说明：

- 这几项已经是当前 active fullcore SoC 路径实际会接到的核心子模块
- 所以这里不是“摆着参考”，而是当前整机线真正连到的代码
