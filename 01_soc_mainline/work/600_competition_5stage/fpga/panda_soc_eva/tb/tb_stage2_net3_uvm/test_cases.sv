`timescale 1ns / 1ps

`ifndef __STAGE2_NET3_UVM_TEST_CASES_SV
`define __STAGE2_NET3_UVM_TEST_CASES_SV

`include "envs.sv"

class Stage2Net3RealWrapperSmokeTest extends uvm_test;

    Stage2Net3WrapperEnv env;

    `uvm_component_utils(Stage2Net3RealWrapperSmokeTest)

    function new(string name = "Stage2Net3RealWrapperSmokeTest", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        this.env = Stage2Net3WrapperEnv::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        phase.raise_objection(this);
        fork
            begin
                this.env.scb.checked_ev.wait_trigger();
            end
            begin
                #400_000_000;
                `uvm_fatal("NET3_UVM_TEST", "timeout waiting for NET_ID=3 UVM smoke observation")
            end
        join_any
        disable fork;
        phase.drop_objection(this);
    endtask

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("NET3_UVM_TEST", "NET_ID=3 UVM smoke finished", UVM_LOW)
    endfunction

endclass

`endif
