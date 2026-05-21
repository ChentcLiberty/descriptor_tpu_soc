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

run_case "stage2_top_smoke" ./run_vcs_stage2_top_smoke.sh
run_case "stage2_cpu_boot" ./run_vcs_stage2_cpu_boot.sh
run_case "stage2_cpu_boot_cpu_frontend" ./run_vcs_stage2_cpu_boot_cpu_frontend.sh
run_case "stage2_cpu_boot_cpu_frontend_net3" ./run_vcs_stage2_cpu_boot_cpu_frontend_net3.sh
run_case "stage2_cpu_boot_real_params" ./run_vcs_stage2_cpu_boot_real_params.sh

echo "[REG] PASS  stable stage2 regression suite"
