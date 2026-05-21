#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_stage2_cpu_boot_cpu_frontend_raw"
SIMV="$BUILD_DIR/simv_stage2_cpu_boot_cpu_frontend_raw"

if [ ! -x "$SIMV" ]; then
  echo "[SOAK][ERR] sim-only raw soak build is missing: $SIMV"
  echo "[SOAK][ERR] run ./run_vcs_stage2_cpu_boot_cpu_frontend_raw.sh once first"
  exit 1
fi

echo "[SOAK] stage2_cpu_boot_cpu_frontend_raw_simonly: reusing existing simv without prep or rebuild."
echo "[SOAK] Use this only when the raw preload artifacts and program image are already up to date."

cd "$BUILD_DIR"
./simv_stage2_cpu_boot_cpu_frontend_raw "$@"
