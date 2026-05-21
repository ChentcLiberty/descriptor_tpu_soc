#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/jjt/soc/my_soc/tpu_stage2_bitexact_integ
SIMV=/tmp/tpu_stage2_bitexact_exec_compare_simv

export VCS_ARCH_OVERRIDE=linux

vlogan -full64 -sverilog -timescale=1ns/1ps   -f "$ROOT/rtl/filelist.f"   "$ROOT/rtl/stage2_stub/tpu_mlp_compute_stub.v"   "$ROOT/tb/tb_tpu_stage2_tinytpu_exec_compare.sv"

vcs -full64 -sverilog -timescale=1ns/1ps   -top tb_tpu_stage2_tinytpu_exec_compare   -f "$ROOT/rtl/filelist.f"   "$ROOT/rtl/stage2_stub/tpu_mlp_compute_stub.v"   "$ROOT/tb/tb_tpu_stage2_tinytpu_exec_compare.sv"   -o "$SIMV"

"$SIMV"
