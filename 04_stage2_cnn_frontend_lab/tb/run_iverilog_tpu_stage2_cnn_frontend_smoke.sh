#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/tb/sim_build_iverilog_cnn_frontend_smoke"

mkdir -p "$BUILD_DIR"

iverilog -g2012 \
  -o "$BUILD_DIR/tb_tpu_stage2_cnn_frontend_smoke.out" \
  -f "$ROOT_DIR/rtl/filelist.f" \
  "$ROOT_DIR/tb/tb_tpu_stage2_cnn_frontend_smoke_v3.sv"

vvp "$BUILD_DIR/tb_tpu_stage2_cnn_frontend_smoke.out"
