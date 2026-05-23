# Verification Overview

This file is the shortest useful verification summary for the current
`01_soc_mainline` path.

If `ARCHITECTURE_OVERVIEW.md` tells you **what the system is**, this file tells
you **how the current public repo proves it works**.

## 1. Verification layers

The current public verification story is intentionally layered rather than
collapsed into a single test.

The main layers are:

1. focused directed wrapper checks
2. focused UVM smoke for the `NET_ID=3` wrapper path
3. CPU boot regression for the integrated mainline
4. stable regression inclusion
5. raw preprocess + `NET_ID=3` soak / extended coverage

These layers coexist on purpose.

## 2. Focused directed wrapper checks

Primary intent:

- prove that `tpu_stage2_real_wrapper` correctly peeks `net_id`
- prove that `NET_ID=3` dispatch reaches the CNN frontend path
- prove that descriptor-driven shared-SRAM fetch/writeback behavior is correct

Representative entry:

- `run_vcs_tpu_stage2_real_wrapper_net3.sh`

This is the most direct way to validate:

- descriptor decode
- fetch counts
- sentinel outputs
- basic wrapper-path correctness

## 3. Focused UVM smoke

Primary intent:

- establish a reusable verification methodology skeleton
- keep the initial UVM scope small and trustworthy

Representative entry:

- `run_vcs_tpu_stage2_real_wrapper_net3_uvm.sh`

Current scope:

- passive observation
- strict scoreboard checks for the focused `NET_ID=3` wrapper case

This is **not** yet the final raw-path UVM closure.
It is the beginning of a maintainable structure.

## 4. CPU boot integrated path

Primary intent:

- prove that the software/runtime path really launches the integrated hardware
  path
- prove that the mainline is not merely an isolated wrapper demo

Representative entry:

- `run_vcs_stage2_cpu_boot_cpu_frontend_net3.sh`

This layer validates the chain:

```text
CPU boot
-> software launch/runtime
-> descriptor creation
-> stage2 real wrapper
-> NET_ID=3 CNN frontend
-> classifier continuation
-> final observed output
```

## 5. Stable regression

Primary intent:

- keep the current integrated `NET_ID=3` path inside the default trusted suite

Representative entry:

- `run_vcs_stage2_regression_stable.sh`

This matters because it means the new path is no longer only a one-off directed
demo; it has been adopted into the regular stable regression flow.

## 6. Raw preprocess soak / extended path

Primary intent:

- validate the longer path that starts from CPU-side raw preprocess rather than
  only pre-arranged fixture data

Representative entries:

- `run_vcs_stage2_cpu_boot_cpu_frontend_raw_net3.sh`
- `run_vcs_stage2_regression_extended.sh`

Important boundary:

- raw preprocess still runs on the CPU side
- this is not raw end-to-end full hardware

## 7. Delivery bundle

Primary public umbrella entry:

- `run_vcs_stage2_net3_delivery.sh`

This bundles the major public signoff-style entry points together:

- raw CPU-front-end precheck
- focused UVM smoke
- focused directed wrapper regression
- stable regression
- raw soak path

This is the closest thing to a public one-command “show me the current
integrated verification story” entry.

## 8. Raw-path baseline policy

The raw path currently uses a staged dual-baseline policy:

- `rtl_expected`
- `algorithmic expected`

Their roles are intentionally different:

- `rtl_expected` is the signoff baseline for raw SoC regressions
- `algorithmic expected` remains the audit/reference baseline

See:

- `stage2_raw_net3_dual_baseline_policy_20260521.md`
- `stage2_raw_net3_baseline_diff_20260520.md`

## 9. Methodology direction

The current direction is:

- keep directed + UVM + CPU-boot + regression layers together
- expand UVM gradually into raw watchpoint coverage
- preserve dual-baseline governance until a better unified model is ready

This means the repo is currently optimized for:

- current confidence
- explainability
- incremental maintainability

not for pretending that every verification layer has already been unified.

## 10. Recommended verification reading order

1. `VERIFICATION_OVERVIEW.md`
2. `stage2_net3_cnn_frontend_status_20260518.md`
3. `stage2_net3_uvm_methodology_20260521.md`
4. `stage2_raw_net3_dual_baseline_policy_20260521.md`
5. `stage2_raw_net3_baseline_diff_20260520.md`
