#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/jjt/soc/my_soc/tpu_stage2_real_integ
SIMV=/tmp/tpu_stage2_real_wrapper_tb_simv
SOC_RTL=/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/panda_soc_eva/rtl
AXI_RTL=/home/jjt/soc/my_soc/verilog-axi/rtl

export VCS_ARCH_OVERRIDE=linux

vlogan -full64 -sverilog -timescale=1ns/1ps   "$AXI_RTL/priority_encoder.v"   "$AXI_RTL/arbiter.v"   "$AXI_RTL/axi_interconnect.v"   "$AXI_RTL/axi_ram.v"   "$SOC_RTL/panda_soc_shared_mem_subsys.v"   -f "$ROOT/rtl/filelist.f"   "$ROOT/tb/tb_tpu_stage2_real_wrapper.sv"

vcs -full64 -sverilog -timescale=1ns/1ps   tb_tpu_stage2_real_wrapper   -o "$SIMV"

"$SIMV"
