# Quick Start

This repository is broad. If you only care about the current integrated path,
start in `01_soc_mainline`.

## 1. Read first

Recommended order:

1. `README.md`
2. `01_soc_mainline/docs/stage2_net3_cnn_frontend_status_20260518.md`
3. `01_soc_mainline/docs/stage2_net3_uvm_methodology_20260521.md`
4. `01_soc_mainline/docs/stage2_raw_net3_dual_baseline_policy_20260521.md`

## 2. Current integrated deliverable

The current deliverable path is:

```text
CPU preprocess / fixture
-> descriptor launch
-> stage2 real wrapper
-> NET_ID=3 hardware CNN frontend
-> classifier
```

The main verification entry directory is:

`01_soc_mainline/work/600_competition_5stage/fpga/panda_soc_eva/tb`

## 3. Main commands

Run from:

```bash
cd 01_soc_mainline/work/600_competition_5stage/fpga/panda_soc_eva/tb
```

### Full public delivery bundle

```bash
./run_vcs_stage2_net3_delivery.sh
```

This bundle covers:

- raw CPU-front-end RTL precheck
- focused `NET_ID=3` real-wrapper UVM smoke
- focused `NET_ID=3` directed wrapper regression
- stable regression suite
- raw preprocess + `NET_ID=3` soak regression

### Focused wrapper checks

```bash
./run_vcs_tpu_stage2_real_wrapper_net3.sh
./run_vcs_tpu_stage2_real_wrapper_net3_uvm.sh
```

### CPU boot focused path

```bash
./run_vcs_stage2_cpu_boot_cpu_frontend_net3.sh
```

### Raw preprocess path

```bash
./run_vcs_stage2_cpu_boot_cpu_frontend_raw_net3.sh
```

### Stable regression

```bash
./run_vcs_stage2_regression_stable.sh
```

## 4. Where to look in code

### SoC mainline

- `01_soc_mainline/work/600_competition_5stage/fpga/panda_soc_eva/rtl/`
- `01_soc_mainline/work/600_competition_5stage/software/`

Key files for the current path:

- `.../rtl/tpu_stage2_real_wrapper.v`
- `.../rtl/tpu_stage2_cnn_frontend_wrapper.v`
- `.../rtl/tpu_stage2_cnn_frontend_v3_engine.v`
- `.../software/include/tpu_desc.h`
- `.../software/lib/tpu_runtime.c`

### Standalone CNN frontend evolution

- `04_stage2_cnn_frontend_lab/`

### Fullcore semantics route

- `03_stage2_fullcore_semantics/`

### Early standalone TPU prototype

- `02_tpu_prototype/`

## 5. Verification methodology notes

The raw path currently uses a staged dual-baseline policy:

- `rtl_expected`: signoff baseline for SoC regressions
- `algorithmic expected`: audit/reference baseline

Read:

- `01_soc_mainline/docs/stage2_raw_net3_dual_baseline_policy_20260521.md`
- `01_soc_mainline/docs/stage2_raw_net3_baseline_diff_20260520.md`

## 6. Tool assumptions

These scripts assume an environment with the relevant simulator/toolchain
already installed and available, especially for VCS-based flows.

This public repository does not bundle local toolchains or proprietary simulator
installations.
