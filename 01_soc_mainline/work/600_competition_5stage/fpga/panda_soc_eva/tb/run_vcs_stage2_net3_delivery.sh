#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
CPU_PRECHECK_SCRIPT="$WORK_DIR/scripts/run_breath_cpu_frontend_q8_8_rtl_precheck.sh"

run_case() {
  local name="$1"
  shift
  echo "[NET3] START ${name}"
  (cd "$SCRIPT_DIR" && "$@")
  echo "[NET3] PASS  ${name}"
}

run_case "raw_cpu_frontend_rtl_precheck" bash "$CPU_PRECHECK_SCRIPT"
run_case "tpu_stage2_real_wrapper_net3_uvm" bash ./run_vcs_tpu_stage2_real_wrapper_net3_uvm.sh
run_case "tpu_stage2_real_wrapper_net3" ./run_vcs_tpu_stage2_real_wrapper_net3.sh
run_case "stage2_regression_stable" ./run_vcs_stage2_regression_stable.sh
run_case "stage2_cpu_boot_cpu_frontend_raw_net3_soak" env BREATH_CPU_FRONTEND_SKIP_PRECHECK=1 ./run_vcs_stage2_cpu_boot_cpu_frontend_raw_net3.sh

echo "[NET3] PASS  stage2 NET_ID=3 delivery bundle"
