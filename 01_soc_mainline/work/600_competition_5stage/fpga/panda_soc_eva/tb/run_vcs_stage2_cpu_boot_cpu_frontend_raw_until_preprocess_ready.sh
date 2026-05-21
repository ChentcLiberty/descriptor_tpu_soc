#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"
./run_vcs_stage2_cpu_boot_cpu_frontend_raw_simonly.sh +tb_stop_on_frontend_preprocess_ready "$@"
