#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
RTL_DIR=$(cd -- "$SCRIPT_DIR/../00_fullcore_lab/rtl" && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_tpu_core_backward_bias_update"

mkdir -p "$BUILD_DIR"
cd "$RTL_DIR"

EXTRA_VCS_ARGS=("-debug_access+all")
if [[ -n "${VERDI_HOME:-}" ]] && [[ -f "$VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab" ]] && [[ -f "$VERDI_HOME/share/PLI/VCS/LINUX64/pli.a" ]]; then
    EXTRA_VCS_ARGS+=("+define+ENABLE_FSDB")
    EXTRA_VCS_ARGS+=("-P" "$VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab" "$VERDI_HOME/share/PLI/VCS/LINUX64/pli.a")
fi

vcs -full64 -sverilog -timescale=1ns/1ps \
    -f filelist.f \
    "$SCRIPT_DIR/tb_tpu_core_backward_bias_update.sv" \
    -top tb_tpu_core_backward_bias_update \
    "${EXTRA_VCS_ARGS[@]}" \
    -o "$BUILD_DIR/simv" \
    -l "$BUILD_DIR/compile.log"

cd "$BUILD_DIR"
./simv -l sim.log
