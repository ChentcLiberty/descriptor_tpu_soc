# `v0.1.3-release-kit`

Public release-kit documentation update for `descriptor_tpu_soc`.

## What this tag captures

- a dedicated release/tag index (`RELEASE_INDEX.md`)
- a dedicated public docs entry page for the mainline docs
- refreshed mainline talk-track docs aligned to the `2026-05-22` wording
- presentation-asset guidance explaining which slide assets are regenerated,
  shared-bundle artifacts, or intentionally not committed

## Current mainline summary

The current `01_soc_mainline` path is:

- stage2 top fixed to `tpu_stage2_real_wrapper + real TPU`
- `NET_ID=0/1/2` dispatched to the fullcore TPU path
- `NET_ID=3` dispatched to the CNN frontend path
- legacy stub RTL/TB removed from the mainline
- obsolete top-level external TPU compatibility ports removed
- raw preprocess still executed on the CPU side

## Suggested reading path

1. `README.md`
2. `QUICKSTART.md`
3. `RELEASE_INDEX.md`
4. `01_soc_mainline/docs/README.md`
5. `01_soc_mainline/docs/stage2_net3_cnn_frontend_status_20260518.md`
6. `01_soc_mainline/docs/CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
7. `01_soc_mainline/docs/CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`

## Verification entry points

Run from:

```bash
cd 01_soc_mainline/work/600_competition_5stage/fpga/panda_soc_eva/tb
```

Main commands:

```bash
./run_vcs_stage2_net3_delivery.sh
./run_vcs_tpu_stage2_real_wrapper_net3_uvm.sh
./run_vcs_stage2_regression_stable.sh
./run_vcs_stage2_cpu_boot_cpu_frontend_raw_net3.sh
```

## Presentation asset note

The public repository keeps:

- generation scripts
- refreshed Markdown talk-track docs

The public repository intentionally does **not** bundle every generated binary
PPT artifact by default.

See:

- `01_soc_mainline/docs/PRESENTATION_ASSETS.md`

for the expected generated filenames and regeneration / shared-bundle notes.

## Boundary reminder

This tag improves release discoverability and documentation packaging. It does
**not** introduce a new RTL feature beyond the already-integrated mainline.
