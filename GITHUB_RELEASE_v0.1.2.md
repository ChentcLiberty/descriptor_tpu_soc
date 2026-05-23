# `v0.1.2-doc-index`

Public documentation polish release for `descriptor_tpu_soc`.

## What this tag captures

- public repo top-level docs aligned to the `2026-05-22` mainline wording
- refreshed mainline talk-track guides for:
  - software/descriptor/task-launch story
  - SoC/control/data-path story
- public `01_soc_mainline/docs/README.md` index
- public `RELEASE_NOTES_v0.1.1.md`

## Current mainline status

The current `01_soc_mainline` path is:

- stage2 top fixed to `tpu_stage2_real_wrapper + real TPU`
- `NET_ID=0/1/2` dispatched to the fullcore TPU path
- `NET_ID=3` dispatched to the CNN frontend path
- legacy stub RTL/TB removed from the mainline
- obsolete top-level external TPU compatibility ports removed
- raw preprocess still executed on the CPU side

## Read first

1. `README.md`
2. `QUICKSTART.md`
3. `01_soc_mainline/docs/README.md`
4. `01_soc_mainline/docs/stage2_net3_cnn_frontend_status_20260518.md`
5. `01_soc_mainline/docs/CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
6. `01_soc_mainline/docs/CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`

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

## Important boundary

This tag improves public documentation and discoverability. It does **not**
introduce a new RTL feature or a new regression semantic change beyond what was
already present on `main`.

## Notes on presentation assets

The repository keeps the PPT/Markdown generation scripts, but intentionally does
not bundle all generated binary presentation assets.

See:

- `01_soc_mainline/docs/PRESENTATION_ASSETS.md`

for the expected generated filenames and regeneration notes.
