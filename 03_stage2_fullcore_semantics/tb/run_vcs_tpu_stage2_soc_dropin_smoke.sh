#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DROPIN_DIR="$ROOT_DIR/rtl/soc_dropin"
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_soc_dropin_smoke"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

VFILES=$(find "$DROPIN_DIR" -maxdepth 1 -name '*.v' ! -name 'tpu_frontend_axil.v' ! -name 'tpu_soc.v' | sort)

export VCS_ARCH_OVERRIDE=linux
vlogan -full64 -sverilog   $VFILES   "$SCRIPT_DIR/tb_tpu_stage2_fullcore_wrapper_smoke.sv"

vcs -full64 tb_tpu_stage2_fullcore_wrapper_smoke -o simv
./simv
