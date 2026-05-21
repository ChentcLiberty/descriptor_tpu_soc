#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/tb/sim_build_vcs_cnn_frontend_smoke"

mkdir -p "$BUILD_DIR"

cd "$ROOT_DIR"

vcs -full64 -sverilog -timescale=1ns/1ps \
  -f "$ROOT_DIR/rtl/filelist.f" \
  "$ROOT_DIR/tb/tb_tpu_stage2_cnn_frontend_smoke_v3.sv" \
  -top tb_tpu_stage2_cnn_frontend_smoke \
  -o "$BUILD_DIR/simv"

"$BUILD_DIR/simv"
