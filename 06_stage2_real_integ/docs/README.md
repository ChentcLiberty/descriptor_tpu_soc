# TPU Stage2 Real Integration

This workspace is an isolated bring-up area for replacing the stage2 DMA/compute stub with the real `tpu.sv` core without touching the dirty `CPU_Copetition_tpu_soc` worktree.

## Layout

- `rtl/stage2_stub/`
  - Unmodified copies of the current stage2 TPU stub RTL.
- `rtl/real_tpu/`
  - Copied TinyTPU core RTL dependency closure from `tpu-soc/src_axi`.
- `rtl/wrapper/`
  - New descriptor-compatible real TPU integration RTL.
- `tb/`
  - Local bring-up testbenches and run scripts.

## Architecture

- Keep the stage2 external protocol unchanged:
  - descriptor in shared SRAM
  - AXI master fetch by hardware
  - writeback by hardware
- Do not use `tpu_frontend_axil` in the SoC data path.
- Use `tpu.sv` as a direct execution engine under a descriptor-compatible wrapper.

`tpu.sv` is not a drop-in replacement for the existing stage2 `TPUDesc` semantics. The current bridge treats `tpu.sv` as a `2-feature MAC tile engine`:

- one 32-bit input word = two Q8.8 activations
- one 32-bit output word = two Q8.8 outputs
- params per output word = `input_words * 2 + 1`
- each input word drives one 2x2 tile on the real core
- wrapper-side logic accumulates partial sums across tiles
- wrapper-side logic applies final bias and ReLU

This preserves the stage2 software/runtime contract while keeping the real systolic core in the execution path.

## Implemented RTL

- `rtl/wrapper/tpu_stage2_tinytpu_exec.sv`
  - Buffers descriptor input/param streams.
  - Instantiates `tpu.sv` directly.
  - Loads UB in the layout required by the real systolic array.
  - Waits for full weight propagation and captures both output beats per tile.
- `rtl/wrapper/tpu_stage2_real_wrapper.sv`
  - Preserves the stage2 descriptor + AXI master shell.
  - Replaces the compute stub with the real TinyTPU execution block.
  - Handles descriptor fetch, input fetch, param fetch, exec start, and output writeback.

## Verification Status

Passed:

- `tb/tb_tpu_stage2_tinytpu_exec_compare.sv`
  - Direct compare against `tpu_mlp_compute_stub.v`.
  - Covers `single_tile_no_relu`, `multi_tile_no_relu`, `multi_tile_relu`.
- `tb/tb_tpu_stage2_real_wrapper.sv`
  - Full descriptor/AXI/shared-SRAM integration test.
  - Covers:
    - 2x2 packed Q8.8 tile output
    - 2-to-32 tiled output sweep
    - multi-input packed linear output
    - overlapping CPU background writes through shared SRAM
    - soft reset clearing status/counters
    - zero-address launch error path

Run commands:

- `tb/run_vcs_tpu_stage2_tinytpu_exec_compare.sh`
- `tb/run_vcs_tpu_stage2_real_wrapper.sh`

## Current Boundary

- This workspace is validated in isolation only.
- The original `panda_soc_stage2_base_top.v` is not modified yet.
- The implementation currently targets the stage2 packed linear Q8.8 path.
- End-to-end `MLP_KEY`, `MLP_OTHER`, and chunked `CLASSIFIER` software flow still need top-level integration and workload-level validation.
