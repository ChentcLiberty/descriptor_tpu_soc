#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "[REG] START stage2_cpu_boot_cpu_frontend_raw_soak"
(cd "$SCRIPT_DIR" && ./run_vcs_stage2_cpu_boot_cpu_frontend_raw.sh)
echo "[REG] PASS  stage2_cpu_boot_cpu_frontend_raw_soak"
