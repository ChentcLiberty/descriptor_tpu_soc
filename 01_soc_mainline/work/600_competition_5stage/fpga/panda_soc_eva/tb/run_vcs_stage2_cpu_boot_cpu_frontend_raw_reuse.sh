#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_stage2_cpu_boot_cpu_frontend_raw"
PREP_SCRIPT="$WORK_DIR/scripts/prepare_breath_tpu_cpu_frontend_preload.py"
SIMV="$BUILD_DIR/simv_stage2_cpu_boot_cpu_frontend_raw"

if [ ! -x "$SIMV" ]; then
  echo "[SOAK][ERR] reusable raw soak build is missing: $SIMV"
  echo "[SOAK][ERR] run ./run_vcs_stage2_cpu_boot_cpu_frontend_raw.sh once first"
  exit 1
fi

echo "[SOAK] stage2_cpu_boot_cpu_frontend_raw_reuse: reusing existing VCS build."
echo "[SOAK] It refreshes raw preload/expected artifacts, then reruns the saved simv without recompiling."

python3 "$PREP_SCRIPT" --skip-linear-export

cd "$BUILD_DIR"
./simv_stage2_cpu_boot_cpu_frontend_raw "$@"
