#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

CPU_EXPORT_SCRIPT="$SCRIPT_DIR/export_breath_cpu_frontend_q8_8.py"
CPU_DIFF_CHECK_SCRIPT="$SCRIPT_DIR/check_breath_cpu_frontend_q8_8_rtl_diff.py"
RTL_DIFF_MD="$SCRIPT_DIR/../software/generated/breath_cpu_frontend_q8_8_rtl_diff.md"

echo "[PRECHECK] regenerate raw CPU-front-end expected files"
python3 "$CPU_EXPORT_SCRIPT"

echo "[PRECHECK] validate raw NET_ID=3 RTL diff allowlist"
python3 "$CPU_DIFF_CHECK_SCRIPT"

echo "[PRECHECK] PASS raw CPU-front-end RTL baseline precheck"
echo "[PRECHECK] policy: staged_dual_baseline_rtl_signoff"
echo "[PRECHECK] diff report: $RTL_DIFF_MD"
