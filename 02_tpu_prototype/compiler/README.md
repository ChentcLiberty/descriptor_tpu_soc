# Compiler Scaffold

This directory holds the first compiler/scheduler scaffold for the current
`tiny-tpu` prototype.

Current scope:

- `model_type = mlp`
- two linear layers
- fixed-point spec metadata
- current `2x2 / 2-lane` tiny-tpu-compatible schedule generation
- stage-level command emission, not cycle-accurate waveform driving yet

Layout:

- `model_specs/`: seed model specs
- `ub_allocator.py`: tensor shape inference plus UB allocation
- `scheduler.py`: stage-level schedule generation for the current tiny-tpu flow

Recommended usage:

```bash
python3 compiler/ub_allocator.py compiler/model_specs/mlp_2_2_1_q8_8.json
python3 compiler/scheduler.py compiler/model_specs/mlp_2_2_1_q8_8.json
```

Near-term next steps:

1. Keep the schedule output aligned with the current testbench-driven flow.
2. Add a thin translator from the emitted command list to cocotb/testbench control.
3. Generalize from the current 2-layer MLP to tiled wider MLPs.
4. Add a second lowering path for 1D CNN, likely starting from `im2col + GEMM`.
