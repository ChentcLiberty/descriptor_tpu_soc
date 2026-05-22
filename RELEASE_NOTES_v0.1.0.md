# Release Notes: `v0.1.0-net3-delivery`

Date: `2026-05-21`

This is the first public snapshot of the `descriptor_tpu_soc` repository.

## Scope

This release packages the current descriptor-driven SoC line together with the
historical TPU/stage2 supporting projects that explain how the mainline evolved.

The center of gravity is:

- `01_soc_mainline`

## Main delivered state

- Panda RISC-V SoC + descriptor-driven TPU task launch
- shared-SRAM data exchange with stage2 real wrapper integration
- `NET_ID=3` hardware CNN frontend integrated back into the main SoC
- CPU boot launch path for `NET_ID=3`
- focused directed wrapper regression
- focused UVM smoke for `NET_ID=3`
- stable regression inclusion for the `NET_ID=3` mainline
- raw preprocess + `NET_ID=3` extended/soak path
- public delivery bundle entry script

## Included top-level modules

- `01_soc_mainline`
- `02_tpu_prototype`
- `03_stage2_fullcore_semantics`
- `04_stage2_cnn_frontend_lab`
- `05_stage2_bitexact_integ`
- `06_stage2_real_integ`
- `07_learning_hub`
- `third_party/verilog-axi`

## Verification entry points

Primary public commands:

```bash
cd 01_soc_mainline/work/600_competition_5stage/fpga/panda_soc_eva/tb
./run_vcs_stage2_net3_delivery.sh
./run_vcs_tpu_stage2_real_wrapper_net3_uvm.sh
./run_vcs_stage2_regression_stable.sh
./run_vcs_stage2_cpu_boot_cpu_frontend_raw_net3.sh
```

## Known boundary

- The public tree intentionally excludes local toolchains, heavy simulator build
  directories, and workspace-only mirrors.
- The raw path still uses `staged_dual_baseline_rtl_signoff` rather than a
  single fully unified reference model.
- The current UVM content is a focused entry point, not yet the final full raw
  scoreboard closure.

## Recommended next step

1. Expand UVM from focused wrapper smoke into raw watchpoint scoreboards.
2. Continue tightening raw baseline governance around the dual-baseline policy.
3. Add coverage-driven signoff metrics for the `NET_ID=3` path.

## Post-release mainline cleanup note

After `v0.1.0-net3-delivery`, the active mainline continued to tighten the
stage2 integration path:

- legacy descriptor/compute stub RTL/TB was removed from the mainline
- internal stage2 observability names were normalized to `tpu_exec_*`
- obsolete external TPU compatibility ports were removed from the stage2 top
- architecture and algorithm talk-track docs were refreshed to the `2026-05-22` real-wrapper / `NET_ID=3` mainline wording

These changes are part of the ongoing workspace history and may exist on the
default branch beyond the `v0.1.0-net3-delivery` tag.
