#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"
./run_vcs_frontend_tpu_core_modes.sh
./run_vcs_tpu_core_backward_bias_update.sh
./run_vcs_unified_buffer_grad_update.sh
./run_vcs_tpu_training_timing_flow.sh
