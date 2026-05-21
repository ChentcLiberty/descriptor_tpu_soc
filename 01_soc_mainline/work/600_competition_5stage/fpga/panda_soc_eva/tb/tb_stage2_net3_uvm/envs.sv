`timescale 1ns / 1ps

`ifndef __STAGE2_NET3_UVM_ENVS_SV
`define __STAGE2_NET3_UVM_ENVS_SV

`include "monitors.sv"
`include "scoreboards.sv"

class Stage2Net3WrapperEnv extends uvm_env;

    Stage2Net3WrapperMonitor mon;
    Stage2Net3WrapperScoreboard scb;

    `uvm_component_utils(Stage2Net3WrapperEnv)

    function new(string name = "Stage2Net3WrapperEnv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        this.mon = Stage2Net3WrapperMonitor::type_id::create("mon", this);
        this.scb = Stage2Net3WrapperScoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        this.mon.obs_ap.connect(this.scb.obs_imp);
    endfunction

endclass

`endif
