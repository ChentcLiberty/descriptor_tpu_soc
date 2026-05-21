#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SOC_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_tpu_stage2_real_wrapper_net3"
RTL_DIR="$SOC_DIR/rtl"
VERILOG_AXI_DIR="/home/jjt/soc/my_soc/verilog-axi/rtl"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

export VCS_ARCH_OVERRIDE=linux

vlogan -full64 +v2k \
  "$RTL_DIR/apb_uart.v" \
  "$RTL_DIR/uart_rx_tx.v" \
  "$RTL_DIR/uart_tx.v" \
  "$RTL_DIR/uart_rx.v"

VFILES=$(find "$RTL_DIR" -maxdepth 1 -name '*.v' \
  ! -name 'apb_uart.v' \
  ! -name 'uart_rx_tx.v' \
  ! -name 'uart_tx.v' \
  ! -name 'uart_rx.v' | sort)

vlogan -full64 -sverilog \
  $VFILES \
  "$VERILOG_AXI_DIR/priority_encoder.v" \
  "$VERILOG_AXI_DIR/arbiter.v" \
  "$VERILOG_AXI_DIR/axi_interconnect.v" \
  "$VERILOG_AXI_DIR/axi_ram.v" \
  "$SCRIPT_DIR/tb_tpu_stage2_real_wrapper_net3.sv"

vcs -full64 tb_tpu_stage2_real_wrapper_net3 -o simv_tpu_stage2_real_wrapper_net3
./simv_tpu_stage2_real_wrapper_net3
