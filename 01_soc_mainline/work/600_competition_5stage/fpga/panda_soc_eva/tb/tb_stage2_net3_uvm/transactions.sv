`timescale 1ns / 1ps

`ifndef __STAGE2_NET3_UVM_TRANSACTIONS_SV
`define __STAGE2_NET3_UVM_TRANSACTIONS_SV

`include "uvm_macros.svh"

import uvm_pkg::*;

class Stage2Net3WrapperObs extends uvm_sequence_item;

    bit        status_error;
    bit [31:0] desc_net_id_reg;
    bit [31:0] desc_input_addr_reg;
    bit [31:0] desc_output_addr_reg;
    bit [31:0] desc_scratch_addr_reg;
    bit [31:0] desc_input_words_reg;
    bit [31:0] desc_output_words_reg;
    bit [31:0] input_fetch_word_count_reg;
    bit [31:0] input_checksum_reg;
    bit [31:0] param_fetch_word_count_reg;
    bit [31:0] param_checksum_reg;

    bit [31:0] signal_word0;
    bit [31:0] feature_word0;

    bit [31:0] output_word0;
    bit [31:0] output_word7;
    bit [31:0] output_word31;
    bit [31:0] output_word63;
    bit [31:0] output_word95;
    bit [31:0] output_word127;

    `uvm_object_utils_begin(Stage2Net3WrapperObs)
        `uvm_field_int(status_error, UVM_ALL_ON)
        `uvm_field_int(desc_net_id_reg, UVM_ALL_ON)
        `uvm_field_int(desc_input_addr_reg, UVM_ALL_ON)
        `uvm_field_int(desc_output_addr_reg, UVM_ALL_ON)
        `uvm_field_int(desc_scratch_addr_reg, UVM_ALL_ON)
        `uvm_field_int(desc_input_words_reg, UVM_ALL_ON)
        `uvm_field_int(desc_output_words_reg, UVM_ALL_ON)
        `uvm_field_int(input_fetch_word_count_reg, UVM_ALL_ON)
        `uvm_field_int(input_checksum_reg, UVM_ALL_ON)
        `uvm_field_int(param_fetch_word_count_reg, UVM_ALL_ON)
        `uvm_field_int(param_checksum_reg, UVM_ALL_ON)
        `uvm_field_int(signal_word0, UVM_ALL_ON)
        `uvm_field_int(feature_word0, UVM_ALL_ON)
        `uvm_field_int(output_word0, UVM_ALL_ON)
        `uvm_field_int(output_word7, UVM_ALL_ON)
        `uvm_field_int(output_word31, UVM_ALL_ON)
        `uvm_field_int(output_word63, UVM_ALL_ON)
        `uvm_field_int(output_word95, UVM_ALL_ON)
        `uvm_field_int(output_word127, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "Stage2Net3WrapperObs");
        super.new(name);
    endfunction

endclass

`endif
