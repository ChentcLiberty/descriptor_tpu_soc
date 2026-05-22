# Release Notes: `v0.1.1-doc-refresh`

Date: `2026-05-22`

This tag captures the public documentation refresh after the original
`v0.1.0-net3-delivery` snapshot.

## Scope

This is a documentation-focused follow-up release. It does **not** introduce a
new functional RTL feature. Instead, it makes the public repository wording and
entry points match the current mainline status more accurately.

## Main updates

- Refreshed the public top-level docs to match the `2026-05-22` mainline state.
- Updated the two main talk-track guides in `01_soc_mainline/docs/`:
  - `CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`
  - `CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
- Clarified that the current stage2 mainline is:
  - fixed to `tpu_stage2_real_wrapper + real TPU`
  - `NET_ID=0/1/2` -> fullcore TPU
  - `NET_ID=3` -> CNN frontend
- Clarified that:
  - legacy stub RTL/TB is no longer part of the mainline
  - obsolete top-level external TPU compatibility ports were removed
  - raw preprocess still remains on the CPU side
- Added a public docs entry page:
  - `01_soc_mainline/docs/README.md`

## What did not change

- No new RTL feature was added in this release.
- No new regression semantics were introduced in this release.
- The raw-path dual-baseline policy remains `staged_dual_baseline_rtl_signoff`.
- The current UVM scope remains a focused entry point, not the final raw
  signoff scoreboard closure.

## Recommended reading order

1. `README.md`
2. `QUICKSTART.md`
3. `01_soc_mainline/docs/README.md`
4. `01_soc_mainline/docs/stage2_net3_cnn_frontend_status_20260518.md`
5. `01_soc_mainline/docs/CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
6. `01_soc_mainline/docs/CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`

## Boundary reminder

The repository is still a curated export from an active workspace:

- it preserves historical subprojects intentionally
- it excludes local toolchains and heavy simulator build artifacts
- it keeps both current-mainline docs and older historical notes, which should
  be read with their dates in mind
