# Stage2 `NET_ID=3` UVM 验证方法学落地说明（2026-05-21）

## 1. 为什么现在引入 UVM

到 `2026-05-20` 为止，`NET_ID=3` 这条线已经有：

- focused directed wrapper 回归
- CPU boot focused 回归
- stable regression
- raw preprocess soak 回归

这些回归已经足够证明功能闭环，但验证结构还是偏“定制 testbench + 手工检查点”。

因此这一步引入 UVM 的目标不是重写全部 testbench，而是先把 `NET_ID=3` 的 focused case 迁到一个最小可运行、可扩展的方法学框架里。

## 2. 这次落下来的 UVM 范围

本次只覆盖：

```text
tpu_stage2_real_wrapper
  -> descriptor peek / dispatch
  -> NET_ID=3 cnn_frontend wrapper
  -> shared SRAM preload / readback
```

对应入口：

- `work/600_competition_5stage/fpga/panda_soc_eva/tb/tb_stage2_net3_uvm/`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_tpu_stage2_real_wrapper_net3_uvm.sh`

当前没有引入 active AXI UVM agent，也没有把整条 raw CPU boot 长回归直接改成 UVM。

这是刻意的分阶段做法：

1. 先把 `NET_ID=3` focused case 用 passive UVM 跑通。
2. 先验证 monitor / scoreboard / objection / result handoff 这套结构是稳的。
3. 再把 raw 路观察点和更长链路迁进去。

## 3. 当前 UVM 结构

```text
top module
  -> preload mem / pulse launch
  -> obs_if
  -> run_test(Stage2Net3RealWrapperSmokeTest)

UVM env
  -> monitor
     - 等 status_done/status_error
     - 采 desc/fetch/checksum/output 哨兵值
  -> scoreboard
     - 比对 NET_ID=3 focused golden
     - 触发 checked_ev
  -> test
     - raise objection
     - wait checked_ev or timeout
```

关键文件：

- `tb_stage2_net3_uvm/stage2_net3_obs_if.sv`
- `tb_stage2_net3_uvm/transactions.sv`
- `tb_stage2_net3_uvm/monitors.sv`
- `tb_stage2_net3_uvm/scoreboards.sv`
- `tb_stage2_net3_uvm/envs.sv`
- `tb_stage2_net3_uvm/test_cases.sv`
- `tb_stage2_net3_uvm/tb_tpu_stage2_real_wrapper_net3_uvm.sv`

## 4. 当前检查口径

scoreboard 当前会严格检查：

- `desc_net_id_reg == 3`
- `desc_input_addr_reg == 0x60120000`
- `desc_output_addr_reg == 0x60122000`
- `desc_scratch_addr_reg == 0x60100000`
- `desc_input_words_reg == 500`
- `desc_output_words_reg == 128`
- `input_fetch_word_count_reg == 504`
- `param_fetch_word_count_reg == 71168`
- `signal_word0 == 0xFF65FF66`
- `feature_word0 == 0x008EFF18`
- `output[0/7/31/63/95/127]` 的 focused golden

也会打印：

- `input_checksum`
- `param_checksum`

## 5. 本次实跑结果

本次 VCS UVM smoke 已实跑通过：

```text
NET_ID=3 wrapper observation passed, input_checksum=b052ae78 param_checksum=72921f70
NET_ID=3 UVM smoke finished
simulation time = 244228115000 ps
```

这条时间点和现有 directed focused case 对齐，说明当前 UVM smoke 没有引入新的行为偏差。

## 6. 这套方法学接下来怎么扩

建议按三步扩：

1. `passive focused`：
   现在已完成。用于稳住 `real_wrapper -> cnn_frontend` focused 语义。
2. `passive raw-watchpoint`：
   在 raw CPU boot 路上引入 UVM monitor / scoreboard，把 `cnn_out / mlp_key / mlp_other / classifier_l2 / final output` 的观察和比较组件化。
3. `dual-scoreboard`：
   raw 路同时挂两类 scoreboard：
   - `rtl_signoff_scoreboard`
   - `algorithmic_audit_scoreboard`

## 7. 当前结论

当前 UVM 的定位不是替换现有长回归，而是给 `NET_ID=3` 建一个可扩展的验证骨架。

也就是说，短期内 repo 会同时保留：

- directed focused TB
- UVM focused smoke
- CPU boot/stable/extended 长回归

这三层各自承担不同职责，而不是二选一。
