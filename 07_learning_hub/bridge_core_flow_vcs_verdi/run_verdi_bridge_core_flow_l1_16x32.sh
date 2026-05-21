#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
RTL_DIR=$(cd -- "$SCRIPT_DIR/../00_fullcore_lab/rtl" && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_bridge_core_flow_l1_16x32"
TB_FILE="$SCRIPT_DIR/tb_bridge_core_flow_l1_16x32.sv"

cd "$RTL_DIR"

if [[ -f "$BUILD_DIR/tb_bridge_core_flow_l1_16x32.fsdb" ]]; then
    verdi -sv -f filelist.f "$TB_FILE" -top tb_bridge_core_flow_l1_16x32 -ssf "$BUILD_DIR/tb_bridge_core_flow_l1_16x32.fsdb"
elif [[ -f "$BUILD_DIR/tb_bridge_core_flow_l1_16x32.vcd" ]]; then
    verdi -sv -f filelist.f "$TB_FILE" -top tb_bridge_core_flow_l1_16x32 -vcd "$BUILD_DIR/tb_bridge_core_flow_l1_16x32.vcd"
else
    echo "No waveform found in $BUILD_DIR"
    exit 1
fi
