# Stage2 `NET_ID=3` CNN Frontend 集成状态（更新至 2026-05-21）

## 1. 这份文档描述什么

这份文档只描述主工程 [`CPU_Copetition_tpu_soc`](../CPU_Copetition_tpu_soc) 中新增的 `NET_ID=3` 路径，也就是：

```text
CPU / TPU_CTRL
  -> descriptor.launch
  -> tpu_stage2_real_wrapper
     -> net_id peek / dispatch
     -> NET_ID=3 -> CNN frontend wrapper
     -> NET_ID!=3 -> 原 fullcore wrapper
```

它不是一个新 SoC，也不是并列的新项目，而是主工程里新增的一个 TPU task 类型。

## 2. 当前已经完成的内容

### 2.1 主工程 RTL 已接入 `NET_ID=3` 分流

新增并接入了以下 RTL：

- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_stage2_cnn_frontend_pkg.v`
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_stage2_cnn_frontend_v3_engine.v`
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_stage2_cnn_frontend_wrapper.v`

并在：

- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_stage2_real_wrapper.v`

中新增 descriptor 首 word peek + dispatch。

当前 `tpu_stage2_real_wrapper` 的行为是：

```text
launch + desc_base
  -> 先读 descriptor[0] = net_id
  -> if net_id == 3:
         走 tpu_stage2_cnn_frontend_wrapper
     else:
         走原 tpu_stage2_fullcore_wrapper
```

这样做的目的有两个：

1. 不修改 `panda_soc_stage2_base_top` 对 `tpu_stage2_real_wrapper` 的现有顶层接口。
2. 不打坏现有 `NET_ID=0/1/2` 的稳定 fullcore 路径。

### 2.2 `NET_ID=3` 当前硬件语义

`NET_ID=3` 路径当前走的是“前端 CNN/FiLM 硬件化”。

输入和参数组织：

- `signal` 从 descriptor 的 `input_addr` 读取
- `feature` 从固定地址 `0x6012_1000` 读取
- `conv1/conv2/conv3/conv4/film` 参数从固定 exported Q8.8 地址读取
- `phase1` 中间结果写回 descriptor 的 `scratch_addr`
- `final cnn_out[256]` 写回 descriptor 的 `output_addr`

当前 engine 已真实实现：

```text
conv1 + relu + maxpool2
-> film
-> conv2 + film + relu + maxpool2
-> conv3 + relu + maxpool2
-> conv4 + relu + global mean
-> final cnn_out[256]
```

### 2.3 主工程 focused VCS 回归已通过

新增验证入口：

- `work/600_competition_5stage/fpga/panda_soc_eva/tb/tb_tpu_stage2_real_wrapper_net3.sv`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_tpu_stage2_real_wrapper_net3.sh`

这条回归的验证口径是：

```text
tpu_stage2_real_wrapper
  -> NET_ID=3 dispatch
  -> tpu_stage2_cnn_frontend_wrapper
  -> panda_soc_shared_mem_subsys
  -> shared SRAM preload from breath_cpu_frontend_q8_8.mem
```

验证时使用主工程现成导出的真实 preload：

- `work/600_competition_5stage/fpga/stage2_programs/breath_cpu_frontend_q8_8/breath_cpu_frontend_q8_8.mem`

当前已检查：

- `desc_net_id/input_addr/output_addr/scratch_addr/input_words/output_words` 解析正确
- `input_fetch_word_count = 504`
- `param_fetch_word_count = 71168`
- 输出 buffer 的多个哨兵值与 exported Q8.8 golden 对齐

本次 VCS 实跑结果：

```text
[TB][PASS] NET_ID=3 real-wrapper regression passed in 24422797 cycles
```

### 2.3b `NET_ID=3` focused UVM smoke 已引入并实跑通过

新增 UVM 验证入口：

- `work/600_competition_5stage/fpga/panda_soc_eva/tb/tb_stage2_net3_uvm/`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_tpu_stage2_real_wrapper_net3_uvm.sh`

这条 UVM 用例当前采用的是最小被动式结构：

```text
top preload/launch
-> passive monitor
-> observation transaction
-> strict scoreboard
```

当前严格检查：

- descriptor 解析
- input/param fetch count
- preload sentinel
- output sentinel

本次 VCS UVM smoke 实跑结果：

```text
NET_ID=3 wrapper observation passed, input_checksum=b052ae78 param_checksum=72921f70
NET_ID=3 UVM smoke finished
simulation time = 244228115000 ps
```

方法学说明已单独整理在：

- `docs/stage2_net3_uvm_methodology_20260521.md`

### 2.4 CPU boot 主线已能正式发起 `NET_ID=3`

软件/runtime 已补齐：

- `work/600_competition_5stage/software/include/tpu_desc.h`
- `work/600_competition_5stage/software/include/tpu_runtime.h`
- `work/600_competition_5stage/software/lib/tpu_runtime.c`
- `work/600_competition_5stage/software/test/breath_tpu_soc_demo/breath_cpu_frontend.c`
- `work/600_competition_5stage/software/test/breath_tpu_soc_demo/breath_cpu_frontend.h`
- `work/600_competition_5stage/software/test/breath_tpu_soc_demo/main.c`
- `work/600_competition_5stage/software/test/breath_tpu_soc_demo/Makefile`

当前 CPU 软件已经能：

```text
prepare frontend input
-> build NET_ID=3 descriptor
-> wait real completion
-> mark cnn_out ready
-> feed classifier fusion input
```

这一步还同时修了一个 runtime 侧问题：

- `tpu_wait_done()` 现在会先等到 `BUSY` 或观察到旧 `DONE` 清掉，再接受新一轮 `DONE`

这样避免了 `NET_ID=3` 长任务被前一轮残留 `DONE` 误判为已完成。

### 2.5 CPU boot `NET_ID=3` focused 回归已通过

新增验证入口：

- `work/600_competition_5stage/fpga/panda_soc_eva/tb/tb_panda_soc_stage2_cpu_boot_cpu_frontend_net3.sv`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_stage2_cpu_boot_cpu_frontend_net3.sh`

这条回归使用：

```text
CPU boot
-> breath_tpu_soc_demo
-> launch 5x MLP_KEY + 2x MLP_OTHER + 1x NET_ID=3 + 14x CLASSIFIER
-> classifier final output
```

当前已检查：

- launch 次序共 22 次
- 第 8 次 launch 的 `net_id == 3`
- `NET_ID=3` descriptor 的 `input/output/input_words/output_words`
- `mlp_key/mlp_other` 旧路径输出哨兵值
- `cnn_out[256]` 多个哨兵值
- classifier 最终两字输出

本次 VCS 实跑结果：

```text
[TB] CPU top-level stage2 CPU-front-end NET_ID=3 boot test passed
classifier final output = fe2d01ca feaf01eb
simulation time = 287716755000 ps
```

### 2.6 `NET_ID=3` 已进入 stable regression 且整套通过

更新后：

- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_stage2_regression_stable.sh`

已经把下面这条用例纳入固定回归：

- `stage2_cpu_boot_cpu_frontend_net3`

本次整套 `stable regression` 实跑结果为：

```text
[REG] PASS  stage2_cpu_boot_cpu_frontend_net3
[REG] PASS  stable stage2 regression suite
```

### 2.7 raw preprocess + `NET_ID=3` 长回归已通过

新增验证入口：

- `work/600_competition_5stage/fpga/panda_soc_eva/tb/tb_panda_soc_stage2_cpu_boot_cpu_frontend_raw_net3.sv`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_stage2_cpu_boot_cpu_frontend_raw_net3.sh`

这条回归的口径是：

```text
raw signal preload
-> CPU raw preprocess
-> NET_ID=3 CNN front-end hardware task
-> 14x classifier launches
```

当前已检查：

- raw preprocess 确实把 `feature/signal` 写到 `0x60121000 / 0x60120000`
- launch 次序共 22 次，且第 8 次 launch 的 `net_id == 3`
- `NET_ID=3` descriptor 的 `input/output/scratch/input_words/output_words`
- `cnn_out[256]` 多个哨兵值与 raw Q8.8 golden 对齐
- `mlp_key/mlp_other/classifier_l2` 关键 watchpoint 与 raw RTL 基线对齐
- classifier 最终两字输出与单独固化的 raw fullcore RTL 基线对齐

本次 VCS 实跑结果：

```text
[TB] CPU top-level stage2 raw preprocess + NET_ID=3 boot test passed
classifier final output = fe4a01cf fecb01f2
simulation time = 573652935000 ps
```

这条用例当前定位为：

- `extended/soak` 级别回归
- 验证 raw preprocess 与 `NET_ID=3` 硬件前端的整合闭环

它没有被纳入 `stable`，原因是 raw 路的历史 classifier golden 仍存在数值漂移。当前 repo 已把这件事拆成两套基线：

- `breath_cpu_frontend_q8_8_expected.{json,svh}`：算法 / software fixed-point 导出基线
- `breath_cpu_frontend_q8_8_rtl_expected.{json,svh}`：raw `NET_ID=3` 长回归验证过的 fullcore RTL 基线

这样 raw `NET_ID=3` TB 不再依赖手写常量，也不会把“算法参考值”和“RTL 验证基线”混在一起。

raw 路关键差异点已经单独整理在：

- `docs/stage2_raw_net3_baseline_diff_20260520.md`
- `work/600_competition_5stage/software/generated/breath_cpu_frontend_q8_8_rtl_diff.md`

当前还新增了一个基线守护脚本：

- `work/600_competition_5stage/scripts/check_breath_cpu_frontend_q8_8_rtl_diff.py`
- `work/600_competition_5stage/scripts/run_breath_cpu_frontend_q8_8_rtl_precheck.sh`

当前还新增了一个 `NET_ID=3` 专用交付入口：

- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_stage2_net3_delivery.sh`

raw 双基线的阶段性策略也已经正式固定为：

- `staged_dual_baseline_rtl_signoff`

策略文档见：

- `docs/stage2_raw_net3_dual_baseline_policy_20260521.md`

### 2.8 `extended/soak` 整套回归已实跑通过

更新后：

- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_stage2_regression_extended.sh`

已经按下面的结构运行：

```text
stage2_regression_stable
-> stage2_cpu_boot_cpu_frontend_raw_net3_soak
```

本次 `extended/soak` 套件实跑结果为：

```text
[REG] PASS  stage2_cpu_boot_cpu_frontend_raw_net3_soak
[REG] PASS  extended/soak stage2 regression suite
```

这次通过时，raw `NET_ID=3` 用例已经在检查：

- `cnn_out` 哨兵值
- `mlp_key` 关键 watchpoint
- `mlp_other` 关键 watchpoint
- `classifier_l2` 关键 watchpoint
- `classifier final` 两字输出

### 2.9 `NET_ID=3` 专用交付入口已实跑通过

新增入口：

- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_stage2_net3_delivery.sh`

这条入口当前会顺序运行：

```text
raw_cpu_frontend_rtl_precheck
-> tpu_stage2_real_wrapper_net3_uvm
-> tpu_stage2_real_wrapper_net3
-> stage2_regression_stable
-> stage2_cpu_boot_cpu_frontend_raw_net3_soak
```

本次整套实跑结果为：

```text
[NET3] PASS  raw_cpu_frontend_rtl_precheck
[NET3] PASS  tpu_stage2_real_wrapper_net3_uvm
[NET3] PASS  tpu_stage2_real_wrapper_net3
[NET3] PASS  stage2_regression_stable
[NET3] PASS  stage2_cpu_boot_cpu_frontend_raw_net3_soak
[NET3] PASS  stage2 NET_ID=3 delivery bundle
```

### 2.10 raw 双基线是否长期保留，当前已经有正式决定

截至 `2026-05-21`，当前决定不是“马上砍掉双基线”，而是：

```text
短期保留双基线
signoff 以 rtl expected 为准
algorithmic expected 继续作为 audit/reference
```

也就是说：

- `software/generated/breath_cpu_frontend_q8_8_rtl_expected.*`
  - 负责 raw SoC 回归签收
- `software/generated/breath_cpu_frontend_q8_8_expected.*`
  - 负责算法审计与模型收敛参考

这不是永久状态。退出双基线、收敛到单一模型的条件已在下面文档里写清楚：

- `docs/stage2_raw_net3_dual_baseline_policy_20260521.md`

## 3. 现在这条新路径在整个 SoC 里处于什么位置

当前主工程可以按下面的任务分层理解：

```text
NET_ID=0/1/2
  -> 原 fullcore wrapper
  -> MLP / classifier 主线

NET_ID=3
  -> 新 CNN frontend wrapper
  -> 生成 cnn_out[256]
```

所以，`NET_ID=3` 的意义不是“替代整个 TPU”，而是把原来 CPU 软件执行的 CNN/FiLM 前端切出一条硬件路径。

## 4. 已完成但要特别说明的边界

### 4.1 已完成的是“前端 CNN task 集成”

本次完成的是：

- `NET_ID=3` 在主工程 wrapper 层可被识别
- 真实 shared SRAM / AXI / descriptor 路径可跑
- 前端 CNN/FiLM 可在 RTL 中生成 `cnn_out[256]`

### 4.2 现在还没完成的是“更大覆盖面的正式纳管”

现在已经完成：

- CPU 软件 / runtime 正式发出 `NET_ID=3` descriptor
- `tb_panda_soc_stage2_cpu_boot_*` 路径里让 CPU 真正调起了这条新任务
- `NET_ID=3 cnn_out[256]` 已接入 classifier 融合输入
- `run_vcs_stage2_regression_stable.sh` 已纳入 `stage2_cpu_boot_cpu_frontend_net3`
- 更新后的 `stable regression` 已实跑通过
- raw preprocess + `NET_ID=3` 长回归已实跑通过，但仍停留在 `extended/soak`

当前还没完成的事：

- 决定 `BREATH_TPU_SOC_USE_HW_CNN_FRONTEND` 在哪些 program / fixture 里作为默认路径
- 把 raw 路 UVM 从 focused smoke 扩到 watchpoint 层
- 把更完整的 golden / 覆盖统计补齐

### 4.3 还没有完成 raw preprocess 硬件化

当前 `NET_ID=3` 读取的是已经标准化好的：

- `signal`
- `feature`

所以它还不覆盖：

- raw signal feature extract
- scaler / raw preprocess 全链路硬件化

换句话说，当前硬件化到的是“CNN/FiLM front-end”，不是“raw signal -> final output” 全链路。

## 5. 推荐的后续计划

建议按下面顺序推进：

1. 把 raw 路 UVM 扩到 watchpoint 层，形成 `rtl_signoff_scoreboard + algorithmic_audit_scoreboard`。
2. 明确 software program 打包方式，让 `NET_ID=3 fixture` 和 `raw_net3` 都成为固定交付入口。
3. 继续补更完整的 golden / 覆盖统计。
4. 在 fullcore-faithful 模型准备好之后，再评估是否退出双基线。

## 6. 当前状态一句话结论

截至 `2026-05-21`，主工程已经完成：

```text
NET_ID=3 在 stage2 real wrapper 中可分流、
可通过真实 shared SRAM preload 跑通 CNN front-end、
CPU boot 软件可真实发起这条任务、
focused directed/UVM regression 都已通过、
raw 路双基线策略也已经正式收口成 staged signoff 口径。
```

当前剩下的主要工作已经不是功能打通，而是把 raw 路 UVM 扩到更长链路、继续补覆盖，并在模型成熟后决定是否退出双基线。
