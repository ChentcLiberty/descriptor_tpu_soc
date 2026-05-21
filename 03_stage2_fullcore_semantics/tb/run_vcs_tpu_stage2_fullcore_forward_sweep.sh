#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
RTL_DIR=$(cd -- "$SCRIPT_DIR/../rtl" && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_fullcore_forward_sweep"
mkdir -p "$BUILD_DIR"
cd "$RTL_DIR"
vcs -full64 -sverilog -timescale=1ns/1ps -f filelist.f "$SCRIPT_DIR/tb_tpu_stage2_fullcore_forward_sweep.sv" -top tb_tpu_stage2_fullcore_forward_sweep -o "$BUILD_DIR/simv" -l "$BUILD_DIR/compile.log"
cd "$BUILD_DIR"
./simv -l sim.log
