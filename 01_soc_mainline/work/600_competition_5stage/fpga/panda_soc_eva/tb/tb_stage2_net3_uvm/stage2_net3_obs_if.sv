`ifndef __STAGE2_NET3_OBS_IF_SV
`define __STAGE2_NET3_OBS_IF_SV

interface stage2_net3_obs_if(input logic clk);

    logic rst_n;

    logic        status_busy;
    logic        status_done;
    logic        status_error;
    logic [31:0] desc_net_id_reg;
    logic [31:0] desc_input_addr_reg;
    logic [31:0] desc_output_addr_reg;
    logic [31:0] desc_scratch_addr_reg;
    logic [31:0] desc_input_words_reg;
    logic [31:0] desc_output_words_reg;
    logic [31:0] input_fetch_word_count_reg;
    logic [31:0] input_checksum_reg;
    logic [31:0] param_fetch_word_count_reg;
    logic [31:0] param_checksum_reg;

    logic [31:0] signal_word0;
    logic [31:0] feature_word0;

    logic [31:0] output_word0;
    logic [31:0] output_word7;
    logic [31:0] output_word31;
    logic [31:0] output_word63;
    logic [31:0] output_word95;
    logic [31:0] output_word127;

endinterface

`endif
