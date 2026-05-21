# 飞腾杯 Stage2 `NET_ID=3` CNN Frontend 成果说明

时间：`2026-05-21`

## 1. 这份成果包怎么找

这次目录按角色拆开了，顶层直接对应：

1. `00_先看这里`
   目录导航和总说明。
2. `01_SoC总览文档`
   整体架构、状态、算法拆分说明。
3. `02_SoC顶层与分流`
   SoC 顶层、shared SRAM、`real_wrapper` 分流。
4. `03_TPU_fullcore主路径`
   原有 TPU fullcore 计算路径。
5. `04_CNN前端_NET_ID3_主线`
   新接回主工程的 `NET_ID=3` CNN front-end RTL。
6. `05_CPU软件_runtime`
   CPU 侧 descriptor、runtime、frontend demo 软件。
7. `06_CNN实验线_lab`
   从骨架到完整 front-end 的原型演进线。
8. `07_数据与程序支撑`
   preload、golden、stage2 程序、检查脚本。
9. `08_整体验证入口`
   focused 回归、CPU boot 回归和稳定回归入口。

## 2. 当前已经完成

- `tpu_stage2_real_wrapper` 已支持 `net_id` peek + dispatch。
- `NET_ID=3` 已接到新的 `tpu_stage2_cnn_frontend_wrapper`。
- CNN front-end 已实现：
  - `conv1 + relu + maxpool2`
  - `film`
  - `conv2 + film + relu + maxpool2`
  - `conv3 + relu + maxpool2`
  - `conv4 + relu + global mean`
  - 输出 `cnn_out[256]`
- 主工程 focused wrapper 回归已通过：

```text
[TB][PASS] NET_ID=3 real-wrapper regression passed in 24422797 cycles
```

- CPU 软件/runtime 已能正式发起 `NET_ID=3`：
  - 构造 descriptor
  - 等待真实完成
  - 标记 `cnn_out` ready
  - 接到 classifier 融合输入
- CPU boot focused 回归已通过：

```text
[TB] CPU top-level stage2 CPU-front-end NET_ID=3 boot test passed
classifier final output = fe2d01ca feaf01eb
simulation time = 287716755000 ps
```

- 更新后的 `stable regression` 已通过，并已包含 `stage2_cpu_boot_cpu_frontend_net3`：

```text
[REG] PASS  stage2_cpu_boot_cpu_frontend_net3
[REG] PASS  stable stage2 regression suite
```

- raw preprocess + `NET_ID=3` 长回归已通过：

```text
[TB] CPU top-level stage2 raw preprocess + NET_ID=3 boot test passed
classifier final output = fe4a01cf fecb01f2
simulation time = 573652935000 ps
```

- raw 路基线已经拆开：
  - `breath_cpu_frontend_q8_8_expected.{json,svh}` 保留算法 / software fixed-point 参考
  - `breath_cpu_frontend_q8_8_rtl_expected.{json,svh}` 固化 raw `NET_ID=3` 长回归验证过的 fullcore RTL 基线
- raw 路差异点已经单独整理：
  - `docs/stage2_raw_net3_baseline_diff_20260520.md`
- raw 路现在还有一个独立 precheck 入口：
  - `run_breath_cpu_frontend_q8_8_rtl_precheck.sh`
- 现在已经补了一条 focused UVM smoke：
  - `run_vcs_tpu_stage2_real_wrapper_net3_uvm.sh`
- 这条 UVM smoke 已实跑通过：

```text
NET_ID=3 wrapper observation passed, input_checksum=b052ae78 param_checksum=72921f70
NET_ID=3 UVM smoke finished
simulation time = 244228115000 ps
```

- raw 双基线策略已经正式定成：
  - `staged_dual_baseline_rtl_signoff`
- 对应说明文档：
  - `docs/stage2_net3_uvm_methodology_20260521.md`
  - `docs/stage2_raw_net3_dual_baseline_policy_20260521.md`
- 主工程现在还有一个 `NET_ID=3` 专用交付入口：
  - `run_vcs_stage2_net3_delivery.sh`
- 这条专用交付入口已经实跑通过：

```text
[NET3] PASS  raw_cpu_frontend_rtl_precheck
[NET3] PASS  tpu_stage2_real_wrapper_net3_uvm
[NET3] PASS  tpu_stage2_real_wrapper_net3
[NET3] PASS  stage2_regression_stable
[NET3] PASS  stage2_cpu_boot_cpu_frontend_raw_net3_soak
[NET3] PASS  stage2 NET_ID=3 delivery bundle
```

- `extended/soak` 整套回归已通过：

```text
[REG] PASS  stage2_cpu_boot_cpu_frontend_raw_net3_soak
[REG] PASS  extended/soak stage2 regression suite
```

这次 `extended` 通过时，raw `NET_ID=3` 已经不只检查 `cnn_out` 和 final output，也会检查
`mlp_key / mlp_other / classifier_l2` 关键 watchpoint。

## 3. 现在还没完成什么

- raw preprocess 路虽然已经定成“阶段性保留双基线”，但还没进入单基线收敛阶段。
- 还没把更完整的覆盖统计和更多 golden 检查补齐。
- 当前硬件化到的是 `signal/feature -> CNN/FiLM -> cnn_out[256]`，不是完整 raw preprocess 全链路。

## 4. 建议下一步

1. 把 raw 路 UVM 扩到 watchpoint 层，形成 `signoff` 和 `audit` 双 scoreboard。
2. 明确 `NET_ID=3 fixture` 和 `raw_net3` 的软件程序打包与交付方式。
3. 继续补更完整的覆盖统计和更多 golden 检查。
4. 在 fullcore-faithful 模型准备好之后，再评估是否退出双基线。
