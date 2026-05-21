# TPU Stage2 CNN Frontend Lab

这个目录用于单独推进 `CPU front-end / CNN` 的后续方案，不混入现有 `tpu_stage2_real_integ`、`tpu_stage2_bitexact_integ`、`tpu_stage2_fullcore_semantics` 三条主线。

当前目标：

- 评估哪些开源 RTL / SoC 项目适合借鉴
- 明确哪些部分适合直接复用，哪些部分只适合参考结构
- 为现有 `descriptor + shared SRAM + launch/done + real wrapper` 主线设计最小 `CNN/front-end` 扩展

目录约定：

- `docs/`: 调研记录、方案比较、接口草图
- `rtl/`: 新增前端/CNN 相关 RTL 草稿
- `tb/`: 局部验证 testbench
- `refs/`: 引用索引、待跟踪项目名单

当前结论方向：

- 不建议导入整套大项目替换现有 SoC
- 优先在现有主线中新增小而专用的 `cnn_frontend` / `conv_film_frontend` 模块
- 外部项目优先借鉴 `window/buffer/MAC pipeline` 与 `AXI/DMA glue`

当前实现状态：

- 已有 `tpu_stage2_cnn_frontend_wrapper_v3.sv`
- 已有 `cnn_frontend_engine_v3.sv`
- 当前已落地并验证：
  - descriptor 读取
  - `signal + feature + conv1 + conv2 + conv3 + conv4 + film` 参数块读取
  - `conv1 + relu + maxpool2` 顺序定点数据通路
  - `film(2->hidden->2*out_ch)` 顺序定点数据通路
  - `conv2 + film + relu + maxpool2` 顺序定点数据通路
  - `conv3 + relu + maxpool2` 顺序定点数据通路
  - `conv4 + relu + global mean` 顺序定点数据通路
  - phase1 结果写回 `scratch_addr`
  - final `cnn_out` 结果写回 `output_addr`
- 当前局部验证：
  - `tb/run_vcs_tpu_stage2_cnn_frontend_smoke.sh`
  - 小尺寸参数化用例已通过 `phase1 + final output` 数值比对
