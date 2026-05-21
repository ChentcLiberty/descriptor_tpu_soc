#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

run_case() {
  local name="$1"
  local cmd="$2"
  echo "[REG] START ${name}"
  (cd "$SCRIPT_DIR" && "$cmd")
  echo "[REG] PASS  ${name}"
}

run_case "stage2_regression_stable" ./run_vcs_stage2_regression_stable.sh
run_case "stage2_cpu_boot_cpu_frontend_raw_net3_soak" ./run_vcs_stage2_cpu_boot_cpu_frontend_raw_net3.sh

echo "[REG] PASS  extended/soak stage2 regression suite"
