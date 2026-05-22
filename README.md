# descriptor_tpu_soc

Descriptor-driven RISC-V + TPU SoC for breath-recognition workloads.

这个仓库是从当前工作区整理出来的公开代码包，重点保留了主线 SoC、TPU 原型、`NET_ID=3` 硬件 CNN front-end、阶段性集成实验线，以及支撑这些工作的关键文档和验证脚本。

## Current status

As of `2026-05-22`, the mainline in `01_soc_mainline` has already reached:

- Panda RISC-V SoC + descriptor-driven TPU task launch
- shared-SRAM data exchange and real stage2 wrapper integration
- `NET_ID=3` hardware CNN frontend integrated back into the main SoC
- CPU boot path for `NET_ID=3`
- stable regression coverage for the `NET_ID=3` mainline
- raw preprocess + `NET_ID=3` extended/soak regression
- focused UVM smoke for the `NET_ID=3` wrapper path
- stub-free stage2 top fixed to the real TPU path
- legacy stub RTL/TB removed from the mainline tree
- internal execution/debug naming normalized to `tpu_exec_*`
- obsolete external TPU compatibility ports removed from the stage2 top
- refreshed architecture and algorithm talk-track docs aligned to the `2026-05-22` real-wrapper / `NET_ID=3` mainline wording

The current raw-path signoff policy is `staged_dual_baseline_rtl_signoff`:

- `rtl_expected` is the signoff baseline for raw SoC regressions
- `algorithmic expected` is kept as audit/reference

## Repository layout

```text
descriptor_tpu_soc/
├── 01_soc_mainline
│   ├── docs
│   └── work/600_competition_5stage
├── 02_tpu_prototype
├── 03_stage2_fullcore_semantics
├── 04_stage2_cnn_frontend_lab
├── 05_stage2_bitexact_integ
├── 06_stage2_real_integ
├── 07_learning_hub
└── third_party/verilog-axi
```

### `01_soc_mainline`

The main competition SoC line.

- `docs/`
  Current status, refreshed architecture/algorithm talk-track docs, validation notes, delivery notes, and UVM/baseline policy docs.
- `work/600_competition_5stage/software/`
  CPU runtime, descriptor definitions, demo software, generated expected data.
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/`
  SoC top, shared memory subsystem, TPU control path, real wrapper, `NET_ID=3` CNN frontend integration, and UVM TB collateral.
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/`
  Directed, CPU boot, regression, raw soak, and delivery-bundle scripts.

Start here if you want the latest integrated system.

Important current mainline note:

- `01_soc_mainline` no longer keeps a selectable descriptor/compute stub path in the stage2 top.
- The current integrated path is fixed to the real TPU wrapper + real TPU execution flow.

Recommended entry documents:

- `01_soc_mainline/docs/stage2_net3_cnn_frontend_status_20260518.md`
- `01_soc_mainline/docs/stage2_net3_uvm_methodology_20260521.md`
- `01_soc_mainline/docs/stage2_raw_net3_dual_baseline_policy_20260521.md`
- `01_soc_mainline/docs/CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`
- `01_soc_mainline/docs/CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`

### `02_tpu_prototype`

Early TPU prototype line derived from the standalone TPU project.

- AXI-Lite frontend
- IMEM/sequencer path
- TPU core prototype
- prototype docs and compiler/test collateral

Use this directory when you want to study the earlier standalone TPU architecture before the full Panda SoC integration.

### `03_stage2_fullcore_semantics`

Stage2 fullcore semantics bring-up line.

- bridge/core/reference/soc_dropin RTL
- focused wrapper and exec-compare TBs
- docs for the fullcore semantics route

This is the main reference for the real/fullcore execution semantics work that later informed the SoC mainline.

### `04_stage2_cnn_frontend_lab`

Standalone lab for the hardware CNN/FiLM frontend that later became `NET_ID=3`.

- isolated RTL evolution from wrapper v1/v2/v3
- local smoke TBs
- design notes and open-source shortlist

Use this directory if you want to understand the CNN frontend work in isolation before it was merged back into the main SoC.

### `05_stage2_bitexact_integ`

Bit-exact integration route for earlier stage2 wrapper work.

### `06_stage2_real_integ`

Real-TPU integration route for earlier stage2 wrapper work.

### `07_learning_hub`

Curated learning hub and reading path for the SoC/fullcore/core stack.

- read order
- extracted core files
- lightweight verification entry scripts

### `third_party/verilog-axi`

Third-party AXI library retained as a dependency/reference.

Please keep the original authorship and license terms from this subtree.

## What is intentionally excluded

This public package intentionally excludes:

- local toolchains and upstream mirrors
- VCS build products such as `sim_build*`, `csrc`, `.daidir`
- wave/debug databases
- local `.git` histories from subprojects
- presentation-only interview materials

The goal is to keep the repository source-oriented and readable.

## Public repo docs

- `QUICKSTART.md`
  Fast entry for the current `NET_ID=3` mainline and verification flow.
- `RELEASE_NOTES_v0.1.0.md`
  First public snapshot notes for the `NET_ID=3` delivery state.
- `RELEASE_NOTES_v0.1.1.md`
  Follow-up public doc refresh notes aligned to the `2026-05-22` mainline wording.
- `01_soc_mainline/docs/README.md`
  Entry page for the current mainline docs and historical-note boundaries.
- `THIRD_PARTY_NOTICES.md`
  Third-party attribution notes for retained external code.

## Suggested reading order

1. `01_soc_mainline/docs/stage2_net3_cnn_frontend_status_20260518.md`
2. `01_soc_mainline/docs/CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
3. `01_soc_mainline/docs/CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`
4. `04_stage2_cnn_frontend_lab/README.md`
5. `03_stage2_fullcore_semantics/docs/README.md`
6. `02_tpu_prototype/README.md`

## Notes

- This repository is a curated export from an active workspace, not a clean-room rewrite.
- Some directories preserve historical evolution on purpose because the development path itself is useful context.
- If you only care about the current deliverable path, stay inside `01_soc_mainline`.
- As of the latest mainline update, the stage2 top-level external TPU compatibility ports were removed and the integration path is intentionally narrower and clearer.
