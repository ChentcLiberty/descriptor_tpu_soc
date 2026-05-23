# Mainline Docs Guide

This directory contains both the **current mainline documentation** and a few
older historical notes kept for context.

## Read first

Start with these files if you want the current integrated picture:

1. `ARCHITECTURE_OVERVIEW.md`
2. `VERIFICATION_OVERVIEW.md`
3. `SOFTWARE_OVERVIEW.md`
4. `stage2_net3_cnn_frontend_status_20260518.md`
5. `CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
6. `CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`
7. `stage2_net3_uvm_methodology_20260521.md`
8. `stage2_raw_net3_dual_baseline_policy_20260521.md`
9. `PRESENTATION_ASSETS.md`

## Current mainline summary

As of `2026-05-22`, the current `01_soc_mainline` path is:

- stage2 top fixed to `tpu_stage2_real_wrapper + real TPU`
- `NET_ID=0/1/2` dispatched to the fullcore TPU path
- `NET_ID=3` dispatched to the CNN frontend path
- legacy stub RTL/TB removed from the mainline
- obsolete top-level external TPU compatibility ports removed
- raw preprocess still executed on the CPU side

## Recommended document roles

- `stage2_net3_cnn_frontend_status_20260518.md`
  Primary status page for the integrated `NET_ID=3` line.
- `ARCHITECTURE_OVERVIEW.md`
  Short English architecture summary for the current mainline.
- `VERIFICATION_OVERVIEW.md`
  Short English verification summary for the current mainline.
- `SOFTWARE_OVERVIEW.md`
  Short English software/runtime summary for the current mainline.
- `CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
  Best starting point if you want the software-to-hardware story.
- `CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`
  Best starting point if you want the SoC/control/data-path story.
- `stage2_net3_uvm_methodology_20260521.md`
  Current UVM methodology note.
- `stage2_raw_net3_dual_baseline_policy_20260521.md`
  Current raw-path baseline/signoff policy.
- `stage2_raw_net3_baseline_diff_20260520.md`
  Current raw-path baseline difference note.
- `PRESENTATION_ASSETS.md`
  Explains which PPT/Markdown assets are source-controlled and which are
  regenerated/share-delivery artifacts.

## Historical notes

These files are useful, but they describe older phases and should not be read
as the current implementation contract:

- `stage2_rtl_progress_20260416.md`
- `cpu_tpu_breath_soc_plan_20260416.md`
- `cpu_tpu_breath_soc_impl_checklist_20260416.md`
- `breath_tpu_validation_status_20260419.md`

The talk-track docs above were refreshed to the current `2026-05-22` wording.
Some older planning/progress files remain historical snapshots by design.

## Supporting script files

These files generate the PPT/Markdown architecture materials:

- `render_breath_soc_rtl_arch_ppt.py`
- `render_breath_soc_rtl_arch_explained_ppt.py`
- `render_breath_soc_algo_to_tpu_flow_ppt.py`

They are documentation generators, not functional RTL sources.
