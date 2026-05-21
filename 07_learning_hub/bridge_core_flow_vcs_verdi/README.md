# Bridge-to-Core Flow Verification

This directory contains a focused wrapper-level verification harness for
`bridge -> frontend_local -> tpu` data flow and control flow.

The intent is not to re-verify the entire SoC, but to isolate the fullcore
handoff boundary:

- `tpu_stage2_fullcore_bridge`
- `tpu_frontend_local`
- `tpu`

## Methodology

The testbench uses a directed, architecture-aware scenario that is small enough
to debug in Verdi but rich enough to exercise the important behavior.

### DUT

- `tpu_stage2_fullcore_wrapper`

### Stimulus class

- single descriptor launch
- `input_words = 2`
- `output_words = 2`
- `flags = TILE2X2_Q8_8 | RELU`

This is the smallest case that covers:

- descriptor fetch
- full input prefetch into `input_mem[]`
- two-level bridge loop: `output_word_idx x tile_word_idx`
- rebiasing with captured partial sums
- `1000 -> 1100` pathway transition on terminal tile
- frontend tile microsequence
- final UB readback and AXI writeback

## What is checked

### Control-flow checks

- bridge launches exactly 4 tiles
- bridge observes exactly 4 tile completions
- tile pathways are:
  - tile 0: `1000`
  - tile 1: `1100`
  - tile 2: `1000`
  - tile 3: `1100`
- `frontend_local` emits the expected significant events per tile:
  - weight read
  - `sys_switch`
  - bias read
  - input read
  - `tile_exec_done`

### Data-flow checks

- tile 1 uses tile 0 captured VPU output as rebias source
- bridge input fetch count matches descriptor
- bridge parameter fetch count matches the expected `output_words * (input_words*2 + 1)`
- final output words match the expected packed Q8.8 golden result

## Files

- `tb_bridge_core_flow.sv`
  - wrapper-level directed testbench
- `run_vcs_bridge_core_flow.sh`
  - compile and run with VCS
- `run_verdi_bridge_core_flow.sh`
  - open the generated waveform in Verdi

## Run

```bash
cd /home/jjt/soc/my_soc/tpu_soc_learning_hub_20260505/bridge_core_flow_vcs_verdi
./run_vcs_bridge_core_flow.sh
./run_verdi_bridge_core_flow.sh
```

## Waveform checkpoints

The most useful signals to inspect are:

- `dut.bridge_u.state_reg`
- `dut.bridge_u.output_word_idx_reg`
- `dut.bridge_u.tile_word_idx_reg`
- `dut.bridge_u.current_bias_word`
- `dut.tile_exec_valid`
- `dut.tile_exec_done`
- `dut.tile_exec_pathway`
- `dut.frontend_u.tile_step_idx`
- `dut.frontend_u.ub_ptr_sel_out`
- `dut.frontend_u.ub_rd_start_out`
- `dut.frontend_u.sys_switch_out`
- `dut.tpu_inst.ub_inst.*`
- `dut.sys_valid_out_21`
- `dut.sys_valid_out_22`
- `dut.vpu_valid_out_1`
- `dut.vpu_valid_out_2`
- `dut.vpu_data_out_1`
- `dut.vpu_data_out_2`
