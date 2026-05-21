#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SOC_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
WORK_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_stage2_cpu_boot_cpu_frontend_net3"
RTL_DIR="$SOC_DIR/rtl"
VERILOG_AXI_DIR="/home/jjt/soc/my_soc/verilog-axi/rtl"
DEMO_DIR="$WORK_DIR/software/test/breath_tpu_soc_demo"
DEMO_BIN="$DEMO_DIR/breath_tpu_soc_demo.bin"
GEN_IMEM="$WORK_DIR/scripts/gen_imem_init_roms.py"
IMEM_PREFIX="$WORK_DIR/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_net3_fixture/breath_tpu_soc_demo_cpu_frontend_net3_fixture_imem"

make -C "$DEMO_DIR" -B \
  TPU_RUNTIME_USE_MMIO=1 \
  TPU_RUNTIME_USE_EXPORTED_PARAMS_Q8_8=0 \
  TPU_RUNTIME_PARAM_POOL_PRELOADED=1 \
  BREATH_TPU_SOC_DEMO_USE_UART=0 \
  BREATH_TPU_SOC_USE_CPU_FRONTEND=1 \
  BREATH_TPU_SOC_USE_HW_CNN_FRONTEND=1 \
  BREATH_CPU_FRONTEND_USE_SW_CNN=0 \
  BREATH_CPU_FRONTEND_PREPROCESS_RAW=0

python3 "$GEN_IMEM" \
  --bin "$DEMO_BIN" \
  --out-prefix "$IMEM_PREFIX" \
  --start-addr 0x800

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
  "$SCRIPT_DIR/tb_panda_soc_stage2_cpu_boot_cpu_frontend_net3.sv"

vcs -full64 tb_panda_soc_stage2_cpu_boot_cpu_frontend_net3 -o simv_stage2_cpu_boot_cpu_frontend_net3
./simv_stage2_cpu_boot_cpu_frontend_net3 "$@"
