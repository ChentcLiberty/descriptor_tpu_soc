# Architecture Overview

This document is the shortest useful architecture summary for the current
`01_soc_mainline` integration path.

If you only want one mental model before diving into RTL or software, read this
file first.

## 1. System intent

The current mainline is a **descriptor-driven RISC-V + TPU SoC** for a
breath-recognition workload.

At a high level:

- a Panda RISC-V CPU prepares tasks
- task metadata is written into shared SRAM as descriptors
- a TPU-side stage2 wrapper fetches descriptors and data
- execution is dispatched to one of two real hardware paths
- results are written back to shared SRAM

This is no longer a stub-top integration.

## 2. Current top-level split

The current `01_soc_mainline` execution split is:

```text
CPU raw preprocess / fixture preparation
-> descriptor launch via TPU_CTRL
-> tpu_stage2_real_wrapper
   -> NET_ID=3  -> CNN frontend path
   -> NET_ID!=3 -> fullcore TPU path
-> shared SRAM writeback
-> CPU observes / chains the next stage
```

More concretely:

- `NET_ID=3` is the hardware CNN frontend path
- `NET_ID=0/1/2` are dispatched to the fullcore TPU/classifier path

## 3. Control plane

The control plane is intentionally small and software-visible.

Main pieces:

- `cpu_tpu_axil_splitter.v`
- `tpu_ctrl_axil_regs.v`

The CPU interacts with TPU execution through MMIO registers:

- `CTRL`
- `STATUS`
- `MODE`
- `NET_ID`
- `DESC_LO` / `DESC_HI`
- `PERF_CYCLE`

The CPU does **not** directly drive TPU-internal datapath wires.
It launches work by:

1. preparing blobs in shared SRAM
2. writing an 8-word descriptor
3. writing `DESC_LO`
4. asserting `CTRL.START`

## 4. Data plane

The data plane is centered on shared SRAM.

Main pieces:

- `panda_soc_shared_mem_subsys.v`
- `tpu_stage2_real_wrapper.v`

The important idea is that both CPU and TPU-side execution consume the same
descriptor-based memory contract:

- `input_addr`
- `output_addr`
- `param_addr`
- `scratch_addr`
- `input_words`
- `output_words`
- `flags`

The stage2 real wrapper acts as the TPU-side AXI master for fetching task data
and writing results back.

## 5. Execution paths

### CNN frontend path

Main entry:

- `tpu_stage2_cnn_frontend_wrapper.v`

This path corresponds to `NET_ID=3`.

Current role:

- consume `signal` / `feature` / frontend parameters from shared SRAM
- execute CNN frontend stages in hardware
- write `cnn_out[256]` and scratch intermediates back

This is the path that replaced the earlier “reserved CNN frontend” idea with an
actual integrated hardware task.

### Fullcore TPU path

Main entry:

- `tpu_stage2_fullcore_wrapper.v`

This path corresponds to `NET_ID=0/1/2`.

Current role:

- execute the fullcore TPU/classifier-side path
- consume descriptor-driven task blobs from shared SRAM
- write classifier-related outputs back

## 6. Software role

The CPU side is still important.

Relevant files:

- `software/include/tpu_desc.h`
- `software/lib/tpu_runtime.c`
- `software/test/breath_tpu_soc_demo/`

The CPU currently still handles:

- raw preprocess
- feature / signal preparation
- descriptor construction
- launch sequencing
- result polling and chaining

Important boundary:

- the current system is **not** raw end-to-end full hardware
- raw preprocess still remains on the CPU side

## 7. Verification shape

The current public verification story is layered:

- focused directed wrapper checks
- focused UVM smoke for the `NET_ID=3` wrapper path
- CPU boot regression for the `NET_ID=3` mainline
- stable regression inclusion
- raw preprocess + `NET_ID=3` soak path

The raw path currently uses:

- `rtl_expected` as the signoff baseline
- `algorithmic expected` as the audit/reference baseline

See:

- `stage2_net3_cnn_frontend_status_20260518.md`
- `stage2_net3_uvm_methodology_20260521.md`
- `stage2_raw_net3_dual_baseline_policy_20260521.md`

## 8. Historical boundary

Older documents in this tree still describe earlier stub-oriented phases.
Those files are preserved intentionally, but they are **not** the current
implementation contract.

For the current implementation contract, prefer:

1. `ARCHITECTURE_OVERVIEW.md`
2. `stage2_net3_cnn_frontend_status_20260518.md`
3. `CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
4. `CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`
