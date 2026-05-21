# tpu-soc

整理后的 TPU-SoC 工作目录，包含当前已验证通过的 tiny-tpu RTL/AXI SoC 工程、项目文档，以及独立归档的简历与面试材料。

## Top-Level Layout

- `src/`: 原始 TPU RTL 与本地修复实现
- `src_axi/`: AXI-Lite SoC RTL 路径
- `compiler/`: UB 分配、scheduler、指令编码与 `imem.hex`
- `test/`: cocotb testbench、AXI e2e、directed H1 bench
- `docs/`: 项目说明、综合复盘、集成图与答辩材料
- `career/`: 简历、投递说明、面试复习资料
- `archive/`: 历史备份与保留材料
- `sim_build/`, `waveforms/`, `results.xml`: 当前构建/回归产物
- `Makefile`: 测试入口
- `env_setup.sh`: 本机环境脚本副本

## Verified Status

- Commit `2b3253b`: 修复 UB weight read hold-cycle 覆盖 `PE22` 的问题
- Commit `dcfe551`: 扩展 AXI e2e，覆盖 `H1 + dZ2 + dZ1 + UB writeback/update`
- Directed VCS bench: `H1 8/8 PASS`
- AXI cocotb e2e (`make test_tpu_soc_axil_e2e`): `41/41 PASS`
- AXI cocotb train convergence (`make test_tpu_soc_axil_train_convergence`): `PASS`，12 epoch 后 `loss 0.2529 -> 0.1777`，最终预测 `(0,1,1,0)`

## Key Docs

- `docs/DIRECTORY_MAP.md`
- `docs/PROJECT_INTRO.md`
- `docs/AXI_SOC_FULL_SUMMARY.md`
- `docs/INTERVIEW_REVIEW_GUIDE.md`
- `docs/tpu_soc_integration_zh.png`
- `career/resume/简历投递排版注意事项.md`
- `career/interview_prep/README.md`

## Notes

- 当前 AXI 全局参数通过寄存器配置：`0x050=LEAK_FACTOR`、`0x054=INV_BATCH_N2`、`0x058=LEARNING_RATE`。
- `sim_build/`、`waveforms/`、`results.xml` 仍保留在根目录，是为了不打断现有 `Makefile`、dump tb 和波形查看流程。
- 若要在本机复现 iverilog+cocotb 回归，通常需要先：
  `source env_setup.sh && export PATH=/home/jjt/miniconda3/envs/claude_env/bin:$PATH`
