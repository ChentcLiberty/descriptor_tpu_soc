`timescale 1ns / 1ps

`ifndef __STAGE2_NET3_UVM_MONITORS_SV
`define __STAGE2_NET3_UVM_MONITORS_SV

`include "transactions.sv"

class Stage2Net3WrapperMonitor extends uvm_monitor;

    virtual stage2_net3_obs_if obs_vif;
    uvm_analysis_port #(Stage2Net3WrapperObs) obs_ap;

    `uvm_component_utils(Stage2Net3WrapperMonitor)

    function new(string name = "Stage2Net3WrapperMonitor", uvm_component parent = null);
        super.new(name, parent);
        this.obs_ap = new("obs_ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if(!uvm_config_db #(virtual stage2_net3_obs_if)::get(this, "", "obs_vif", this.obs_vif))
            `uvm_fatal("NET3_UVM_MON", "failed to get stage2_net3_obs_if")
    endfunction

    virtual task run_phase(uvm_phase phase);
        Stage2Net3WrapperObs obs;

        super.run_phase(phase);

        @(posedge this.obs_vif.clk iff (this.obs_vif.rst_n && (this.obs_vif.status_done || this.obs_vif.status_error)));

        obs = Stage2Net3WrapperObs::type_id::create("obs");
        obs.status_error = this.obs_vif.status_error;
        obs.desc_net_id_reg = this.obs_vif.desc_net_id_reg;
        obs.desc_input_addr_reg = this.obs_vif.desc_input_addr_reg;
        obs.desc_output_addr_reg = this.obs_vif.desc_output_addr_reg;
        obs.desc_scratch_addr_reg = this.obs_vif.desc_scratch_addr_reg;
        obs.desc_input_words_reg = this.obs_vif.desc_input_words_reg;
        obs.desc_output_words_reg = this.obs_vif.desc_output_words_reg;
        obs.input_fetch_word_count_reg = this.obs_vif.input_fetch_word_count_reg;
        obs.input_checksum_reg = this.obs_vif.input_checksum_reg;
        obs.param_fetch_word_count_reg = this.obs_vif.param_fetch_word_count_reg;
        obs.param_checksum_reg = this.obs_vif.param_checksum_reg;
        obs.signal_word0 = this.obs_vif.signal_word0;
        obs.feature_word0 = this.obs_vif.feature_word0;
        obs.output_word0 = this.obs_vif.output_word0;
        obs.output_word7 = this.obs_vif.output_word7;
        obs.output_word31 = this.obs_vif.output_word31;
        obs.output_word63 = this.obs_vif.output_word63;
        obs.output_word95 = this.obs_vif.output_word95;
        obs.output_word127 = this.obs_vif.output_word127;

        this.obs_ap.write(obs);
        `uvm_info("NET3_UVM_MON", "captured NET_ID=3 wrapper observation", UVM_LOW)
    endtask

endclass

`endif
