#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
RTL_DIR=$(cd -- "$SCRIPT_DIR/../00_fullcore_lab/rtl" && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_frontend_tpu_core_modes"
TB_FILE="$SCRIPT_DIR/tb_frontend_tpu_core_modes.sv"

cd "$RTL_DIR"

if [[ -f "$BUILD_DIR/tb_frontend_tpu_core_modes.fsdb" ]]; then
    verdi -sv -f filelist.f "$TB_FILE" -top tb_frontend_tpu_core_modes -ssf "$BUILD_DIR/tb_frontend_tpu_core_modes.fsdb"
elif [[ -f "$BUILD_DIR/tb_frontend_tpu_core_modes.vcd" ]]; then
    verdi -sv -f filelist.f "$TB_FILE" -top tb_frontend_tpu_core_modes -vcd "$BUILD_DIR/tb_frontend_tpu_core_modes.vcd"
else
    echo "No waveform found in $BUILD_DIR"
    exit 1
fi
