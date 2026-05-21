#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
RTL_DIR=$(cd -- "$SCRIPT_DIR/../00_fullcore_lab/rtl" && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_tpu_core_backward_bias_update"
TB_FILE="$SCRIPT_DIR/tb_tpu_core_backward_bias_update.sv"

cd "$RTL_DIR"

if [[ -f "$BUILD_DIR/tb_tpu_core_backward_bias_update.fsdb" ]]; then
    verdi -sv -f filelist.f "$TB_FILE" -top tb_tpu_core_backward_bias_update -ssf "$BUILD_DIR/tb_tpu_core_backward_bias_update.fsdb"
elif [[ -f "$BUILD_DIR/tb_tpu_core_backward_bias_update.vcd" ]]; then
    verdi -sv -f filelist.f "$TB_FILE" -top tb_tpu_core_backward_bias_update -vcd "$BUILD_DIR/tb_tpu_core_backward_bias_update.vcd"
else
    echo "No waveform found in $BUILD_DIR"
    exit 1
fi
