# 呼吸识别 CPU+TPU 验证状态（首版 2026-04-19，更新至 2026-05-05）

补充说明：

- `2026-05-18` 新增 `NET_ID=3` CNN front-end 主工程集成状态，单独记录在 `docs/stage2_net3_cnn_frontend_status_20260518.md`。
- 这份文档仍以 `NET_ID=0/1/2` 的稳定 MLP/Classifier 主线和 CPU-front-end 总体验证口径为主。

## 验证口径

当前验证分成三条线，不再把 CPU 软件 CNN 的长 RTL 仿真作为主线完成标准。

1. `TPU MLP/Classifier RTL 验证`
   - 目标：证明 TPU 上的 packed Q8.8 Linear/MLP/Classifier 子图能在 SoC 顶层 RTL 中跑通。
   - 输入：已知 feature/CNN fixture 或 demo fusion 输入。
   - 覆盖：CPU boot、descriptor、DMA fetch、shared SRAM、AXI arbiter、TPU compute、output writeback。
   - 状态：已通过。

2. `完整算法端到端验证`
   - 目标：证明 raw signal 到最终分类输出的完整算法链路和浮点/PyTorch golden 对齐。
   - 执行方式：软件/定点 golden 快速回归。
   - 覆盖：raw feature、scaler、CNN/FiLM、MLP/Classifier。
   - 状态：前 4 条测试样本已通过 fixed-point vs float argmax 对齐。

3. `完整算法全 RTL 验证`
   - 目标：CPU 在 RTL 中逐条执行 raw feature、scaler、CNN/FiLM，再调用 TPU 完成分类。
   - 状态：已验证进入 CPU CNN 阶段，但没有跑到最终输出。
   - 结论：该路径可用于定位集成问题，不适合作为当前主验证路径；CPU 软件 CNN 在 RTL 仿真中太慢。

## 关键修正

之前 Q8.8 MAC 的实现是每个乘积先 `>> 8` 再累加，深层网络误差被明显放大。已改成：

```text
acc_q16.16 = sum(x_q8.8 * w_q8.8) + (bias_q8.8 << 8)
out_q8.8  = round(acc_q16.16 >> 8)
```

同步修改了 TPU RTL compute stub、TPU Python golden、CPU-front-end Python golden 和 CPU-front-end C 实现。

## 当前 active fullcore 架构

当前主工程里稳定回归实际走的是这条活动路径：

```text
tpu_stage2_real_wrapper
  -> tpu_stage2_fullcore_wrapper
  -> tpu_frontend_local
  -> tpu
  -> UB / systolic / PE / VPU
  -> UB readback
  -> AXI writeback
```

这条路径当前已经不再结构性依赖：

- `tpu_soc`
- `tpu_frontend_axil`
- `control_unit`
- TPU 侧 `IMEM / CTRL.start / CTRL.step`

因此，当前稳定回归验证到的是“保留 `UB / PE / systolic / VPU` 原始协同语义的 SoC 前向主线”，而不是旧 bit-exact 路线里的外部后处理替代实现。

补充说明：`tpu_stage2_fullcore_semantics` 本地工作区在 `2026-05-05` 已进一步扩到 terminal-tile `transition MSE` 子集，也就是在最后一个 tile 上覆盖 `vpu_data_pathway=1111`、`Y` 从 scratch block 装载、结果仍经 `UB readback -> AXI writeback` 的 fullcore 语义。主工程当前稳定 SoC 回归尚未打开这类 descriptor flag，但同步后的共享 RTL 已通过回归，未打坏既有前向主线。

静态结构守卫命令：

```bash
python3 work/600_competition_5stage/scripts/check_fullcore_direct_core_structure.py
```

它会静态检查 active wrapper 路径里没有重新引入 `tpu_soc / tpu_frontend_axil / control_unit / step_exec` 等旧依赖。

## 已完成的 Stable RTL

### 真实参数预加载路径

命令：

```bash
cd work/600_competition_5stage/fpga/panda_soc_eva/tb
./run_vcs_stage2_cpu_boot_real_params.sh
```

结果：

- CPU boot 后发起全部 `21` 次 TPU launch。
- `NET_ID=0`：`MLP_KEY 2 -> 32 -> 64 -> 128 -> 64 -> 32`。
- `NET_ID=1`：`MLP_OTHER 6 -> 32 -> 32`。
- `NET_ID=2`：`CLASSIFIER 322 -> 256 -> 128 -> 64 -> 4`，其中 classifier 分块执行。
- 真实 Q8.8 预训练参数通过 `shared_sram_init_file` 预加载到 shared SRAM。
- 最终 classifier output（fullcore 语义基线）：

```text
0x015EFB3D 0xFDC5061D
```

- 说明：这些值对应的是保留 `UB / systolic / PE / VPU` 原始协同语义后的 fullcore wrapper 路线，不再沿用旧 bit-exact 路线的外部后处理基线。
- 2026-05-05 又在清理掉旧 `step_exec / IMEM / control_unit` 活动依赖后，重新跑过 `run_vcs_stage2_cpu_boot_real_params.sh` 与整套 `run_vcs_stage2_regression_stable.sh`，结果保持通过。

VCS 结果：

```text
[TB] cpu boot launched all twenty-one stages with real pretrained q8.8 params
[TB] CPU top-level stage2 real-param boot test passed
```

该验证说明 TPU 的 MLP/Classifier RTL 主链路已经闭合。它不验证 CPU 侧 raw feature/CNN 的 RTL 执行时间。

### Fixture CPU-front-end + 真实 wrapper 路径

命令：

```bash
cd work/600_competition_5stage/fpga/panda_soc_eva/tb
./run_vcs_stage2_cpu_boot_cpu_frontend.sh
```

结果：

- `tb_panda_soc_stage2_cpu_boot_cpu_frontend.sv` 已显式打开 `.USE_TPU_REAL_WRAPPER(1)`。
- CPU boot 后发起全部 `21` 次 TPU launch。
- CPU 程序镜像使用 `breath_tpu_soc_demo_cpu_frontend_fixture`，shared SRAM 通过 `breath_cpu_frontend_q8_8.mem` 预加载。
- 这里的“程序镜像”是 CPU boot 所需 IMEM 内容，不是 TPU frontend/control 的 `IMEM`；TPU 活动路径当前已经不再依赖 `tpu_frontend_axil / control_unit / IMEM`。
- 该路径保留 CPU 侧的 front-end 启动方式，但用 fixture 跳过 raw feature/CNN 软件长路径，只验证 CPU 控制、descriptor、DMA/shared SRAM 和真实 TPU wrapper 的闭环。

VCS 结果：

```text
[TB] cpu boot launched all twenty-one stages with fixture CPU-front-end path
[TB] CPU top-level stage2 fixture CPU-front-end boot test passed
```

当前 fixture watchpoint（fullcore 语义基线）：

```text
MLP_KEY_OUT[0]   = 0x001700B6
MLP_KEY_OUT[15]  = 0x0000008B
MLP_OTHER_OUT[0] = 0x00AE0000
MLP_OTHER_OUT[15]= 0x004A001C
CLASS_L2_OUT[0]  = 0x00000028
CLASS_L2_OUT[31] = 0x00000035
CLASS_OUT[0]     = 0xFE3A01D2
CLASS_OUT[1]     = 0xFEA701E1
```

说明：`check_breath_cpu_frontend_fixture.py` 仍先复用旧的软件 linear golden 流程生成完整数组，但回归判定使用的是经 SoC RTL 实测确认的 fullcore watchpoint 基线，不再沿用旧 bit-exact 路线的期望常量。

该验证说明“真实 TPU wrapper 已接入 CPU-front-end fixture 路径”这一状态已经闭合，可作为当前稳定 RTL 回归的一部分。

## 端到端算法 Golden 现状

完整 fixed-point vs float 对比命令：

```bash
python3 work/600_competition_5stage/scripts/check_breath_cpu_frontend_float_compare.py --loader torchzip
```

前 4 条样本结果：

```text
sample 0 label=2 float_pred=2 fixed_pred=2 match_float=yes final=0xFE3C01D6 0xFEA301F9
sample 1 label=1 float_pred=1 fixed_pred=1 match_float=yes final=0x0603F935 0xFD16F6DE
sample 2 label=0 float_pred=0 fixed_pred=0 match_float=yes final=0xFE8803A0 0xFF88FE98
sample 3 label=2 float_pred=2 fixed_pred=2 match_float=yes final=0xFD5AFF07 0xFDFF065D
```

多样本定点回归命令：

```bash
python3 work/600_competition_5stage/scripts/check_breath_cpu_frontend_q8_8_samples.py --loader torchzip
```

该回归同样通过前 4 条样本，且 feature/signal clip count 均为 0。

单样本 CPU-front-end preload 已更新：

- 样本：`sample_index=0`
- 标签：`2`
- CPU CNN first4：

```text
0x0022000E 0x00700008 0x004A0056 0x0094009E
```

- 最终 classifier output：

```text
0xFE3C01D6 0xFEA301F9
```

## 慢 RTL（raw CPU-front-end）验证到的位置

命令：

```bash
cd work/600_competition_5stage/fpga/panda_soc_eva/tb
./run_vcs_stage2_cpu_boot_cpu_frontend_raw.sh
```

已验证内容：

- shared SRAM 中的 raw signal、scaler、CNN/FiLM 参数可被 CPU 访问。
- CPU raw feature 提取已经执行到能准备 MLP 输入。
- TPU 已经观察到前 `7` 次 launch：
  - `MLP_KEY` 5 层
  - `MLP_OTHER` 2 层
- 第 7 次 launch 后 CPU 进入 `frontend_conv_at`，即 CNN/FiLM 软件卷积内核。
- 仿真跑到约 `347M cycles` 后仍在 CNN 卷积内核中推进，非死锁。

结论：

- 这条路径和 fixture CPU-front-end 稳定回归分开维护，用于单独定位 raw signal/scaler/CNN 软件段问题。
- 这条路径证明 CPU front-end 接入方式有效。
- 这条路径没有证明完整 raw-sample RTL 端到端最终输出。
- 性能瓶颈明确在 CPU 软件 CNN/FiLM；后续要完整硬件化或加速，应优先考虑下沉 CNN/FiLM 到 TPU/VPU/CNN 单元。

## 当前判断

当前主线可以按以下标准推进：

1. 稳定 RTL 回归：以 `run_vcs_stage2_regression_stable.sh` 作为总入口，内部覆盖 `run_vcs_stage2_top_smoke.sh`、`run_vcs_stage2_cpu_boot.sh`、`run_vcs_stage2_cpu_boot_cpu_frontend.sh`、`run_vcs_stage2_cpu_boot_real_params.sh`，当前已整套通过；其中后两条都已经切到 fullcore 语义基线。
2. 完整算法正确性：以 fixed-point vs float 软件 golden 做快速端到端回归，当前前 4 条测试样本已通过。
3. `run_vcs_stage2_cpu_boot_cpu_frontend_raw.sh` 作为 raw 前端软件段诊断路径单独维护，不作为当前主验收路径。
4. 完整算法性能：不要依赖 CPU 软件 CNN 的 RTL 长仿真，后续通过 CNN/FiLM 下沉或专用单元解决。
