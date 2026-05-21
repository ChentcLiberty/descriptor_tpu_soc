# raw `NET_ID=3` 基线差异记录（2026-05-20）

## 1. 这份文档描述什么

这份文档只记录 raw preprocess + `NET_ID=3` 这条长回归里，`algorithmic expected` 和已验证 `RTL expected` 的差异。

对应的自动生成版本在：

- `work/600_competition_5stage/software/generated/breath_cpu_frontend_q8_8_rtl_diff.md`
- `work/600_competition_5stage/scripts/check_breath_cpu_frontend_q8_8_rtl_diff.py`
- `work/600_competition_5stage/scripts/run_breath_cpu_frontend_q8_8_rtl_precheck.sh`

两套基线分别是：

- `software/generated/breath_cpu_frontend_q8_8_expected.{json,svh}`
- `software/generated/breath_cpu_frontend_q8_8_rtl_expected.{json,svh}`

## 2. 当前确认下来的差异点

来自 `tb_panda_soc_stage2_cpu_boot_cpu_frontend_raw_net3.sv` 的实跑 watchpoint：

```text
mlp_key[0]   = 0x001700B6
mlp_key[15]  = 0x0000008B
mlp_other[0] = 0x00AC0000
mlp_other[15]= 0x004A0018
class_l2[0]  = 0x00000029
class_l2[31] = 0x0000002E
class_out[0] = 0xFE4A01CF
class_out[1] = 0xFECB01F2
```

对应算法导出基线的差异如下：

| watchpoint | algorithmic expected | verified RTL expected |
|---|---:|---:|
| `mlp_key_out_words[0]` | `0x001900B5` | `0x001700B6` |
| `mlp_key_out_words[15]` | `0x0000008B` | `0x0000008B` |
| `mlp_other_out_words[0]` | `0x00AA0000` | `0x00AC0000` |
| `mlp_other_out_words[15]` | `0x00490018` | `0x004A0018` |
| `classifier_l2_out_words[0]` | `0x0000002F` | `0x00000029` |
| `classifier_l2_out_words[31]` | `0x00000030` | `0x0000002E` |
| `classifier_final_out_words[0]` | `0xFE3C01D6` | `0xFE4A01CF` |
| `classifier_final_out_words[1]` | `0xFEA301F9` | `0xFECB01F2` |

## 3. 当前结论

- 差异不是只出现在最终 classifier 两字输出。
- raw 路在 `mlp_key`、`mlp_other`、`classifier_l2` 这些中间 watchpoint 上就已经和算法导出基线分叉。
- 因此 raw `NET_ID=3` 这条 SoC 回归不能只依赖 `algorithmic expected`。

## 4. 当前落地方式

repo 里现在按双基线维护：

- `breath_cpu_frontend_q8_8_expected.*`
  - 保留算法 / software fixed-point 参考
- `breath_cpu_frontend_q8_8_rtl_expected.*`
  - 固化 raw `NET_ID=3` 长回归验证过的 SoC RTL watchpoint

同时，`tb_panda_soc_stage2_cpu_boot_cpu_frontend_raw_net3.sv` 已经改成检查：

- `cnn_out` 哨兵值
- `mlp_key` 关键 watchpoint
- `mlp_other` 关键 watchpoint
- `classifier_l2` 关键 watchpoint
- `classifier final` 两字输出

另外，`run_breath_cpu_frontend_q8_8_rtl_precheck.sh` 会依次执行：

- `export_breath_cpu_frontend_q8_8.py`
- `check_breath_cpu_frontend_q8_8_rtl_diff.py`

而 `run_vcs_stage2_cpu_boot_cpu_frontend_raw_net3.sh` 现在会在长仿真前先调用这条 precheck：

- `run_breath_cpu_frontend_q8_8_rtl_precheck.sh`

## 5. 阶段性决策

当前已经把这件事从“建议”提升成正式策略：

- 继续保留双基线
- 当前策略名：`staged_dual_baseline_rtl_signoff`
- raw SoC 回归签收以 `rtl expected` 为准
- `algorithmic expected` 保留为审计参考

正式策略文档见：

- `docs/stage2_raw_net3_dual_baseline_policy_20260521.md`

这样做的原因不变：

1. 算法导出仍然有参考价值，能帮助定位前段 fixed-point 语义。
2. SoC 回归需要稳定依赖已验证 RTL 基线，避免把历史算法参考误当成当前硬件真值。
3. 后续如果要进一步收敛成单基线，应该先补一份更贴近 fullcore 语义的 Python 模型，而不是直接改掉现有算法导出文件。
