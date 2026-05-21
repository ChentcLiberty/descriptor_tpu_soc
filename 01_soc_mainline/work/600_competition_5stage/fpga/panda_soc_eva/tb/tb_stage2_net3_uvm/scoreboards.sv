`timescale 1ns / 1ps

`ifndef __STAGE2_NET3_UVM_SCOREBOARDS_SV
`define __STAGE2_NET3_UVM_SCOREBOARDS_SV

`include "transactions.sv"

class Stage2Net3WrapperScoreboard extends uvm_component;

    localparam [31:0] DESC_NET_ID_EXPECTED = 32'd3;
    localparam [31:0] SIGNAL_BASE_ADDR     = 32'h6012_0000;
    localparam [31:0] OUTPUT_BASE_ADDR     = 32'h6012_2000;
    localparam [31:0] SCRATCH_BASE_ADDR    = 32'h6010_0000;
    localparam [31:0] SIGNAL_WORDS         = 32'd500;
    localparam [31:0] OUTPUT_WORDS         = 32'd128;
    localparam [31:0] INPUT_FETCH_WORDS    = 32'd504;
    localparam [31:0] PARAM_FETCH_WORDS    = 32'd71168;

    uvm_analysis_imp #(Stage2Net3WrapperObs, Stage2Net3WrapperScoreboard) obs_imp;
    uvm_event checked_ev;
    bit received_obs;

    `uvm_component_utils(Stage2Net3WrapperScoreboard)

    function new(string name = "Stage2Net3WrapperScoreboard", uvm_component parent = null);
        super.new(name, parent);
        this.obs_imp = new("obs_imp", this);
        this.checked_ev = new("checked_ev");
        this.received_obs = 1'b0;
    endfunction

    function void expect_eq32(string field_name, bit [31:0] actual, bit [31:0] expected);
        if(actual !== expected)
            `uvm_fatal(
                "NET3_UVM_SCB",
                $sformatf("%s mismatch: expected=%08x actual=%08x", field_name, expected, actual)
            )
    endfunction

    virtual function void write(Stage2Net3WrapperObs obs);
        this.received_obs = 1'b1;

        if(obs.status_error)
            `uvm_fatal("NET3_UVM_SCB", "status_error asserted in NET_ID=3 wrapper observation")

        this.expect_eq32("desc_net_id_reg", obs.desc_net_id_reg, DESC_NET_ID_EXPECTED);
        this.expect_eq32("desc_input_addr_reg", obs.desc_input_addr_reg, SIGNAL_BASE_ADDR);
        this.expect_eq32("desc_output_addr_reg", obs.desc_output_addr_reg, OUTPUT_BASE_ADDR);
        this.expect_eq32("desc_scratch_addr_reg", obs.desc_scratch_addr_reg, SCRATCH_BASE_ADDR);
        this.expect_eq32("desc_input_words_reg", obs.desc_input_words_reg, SIGNAL_WORDS);
        this.expect_eq32("desc_output_words_reg", obs.desc_output_words_reg, OUTPUT_WORDS);
        this.expect_eq32("input_fetch_word_count_reg", obs.input_fetch_word_count_reg, INPUT_FETCH_WORDS);
        this.expect_eq32("param_fetch_word_count_reg", obs.param_fetch_word_count_reg, PARAM_FETCH_WORDS);
        this.expect_eq32("signal_word0", obs.signal_word0, 32'hFF65_FF66);
        this.expect_eq32("feature_word0", obs.feature_word0, 32'h008E_FF18);
        this.expect_eq32("output_word0", obs.output_word0, 32'h0022_000E);
        this.expect_eq32("output_word7", obs.output_word7, 32'h000B_006C);
        this.expect_eq32("output_word31", obs.output_word31, 32'h00CE_0029);
        this.expect_eq32("output_word63", obs.output_word63, 32'h0076_0087);
        this.expect_eq32("output_word95", obs.output_word95, 32'h008F_001B);
        this.expect_eq32("output_word127", obs.output_word127, 32'h002F_0026);

        `uvm_info(
            "NET3_UVM_SCB",
            $sformatf(
                "NET_ID=3 wrapper observation passed, input_checksum=%08x param_checksum=%08x",
                obs.input_checksum_reg,
                obs.param_checksum_reg
            ),
            UVM_LOW
        )
        this.checked_ev.trigger();
    endfunction

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if(!this.received_obs)
            `uvm_fatal("NET3_UVM_SCB", "scoreboard did not receive any NET_ID=3 wrapper observation")
    endfunction

endclass

`endif
