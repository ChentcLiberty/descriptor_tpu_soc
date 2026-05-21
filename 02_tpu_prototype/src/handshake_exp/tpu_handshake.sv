`timescale 1ns/1ps
`default_nettype none

// Handshake experiment variant:
// Add a local ready-controlled skid stage between VPU writeback and UB writes.
// This does not backpressure the whole TPU yet; it only hardens the writeback boundary.
module tpu_handshake #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2,
    parameter int UNIFIED_BUFFER_DEPTH = 64
)(
    input logic clk,
    input logic rst,

    // Experimental writeback ready control
    input logic wb_ready_in,

    // UB wires (writing from host to UB)
    input logic [15:0] ub_wr_host_data_in [0:SYSTOLIC_ARRAY_WIDTH-1],
    input logic ub_wr_host_valid_in [0:SYSTOLIC_ARRAY_WIDTH-1],

    // UB wires (inputting reading instructions from host)
    input logic ub_rd_start_in,
    input logic ub_rd_transpose,
    input logic [8:0] ub_ptr_select,
    input logic [15:0] ub_rd_addr_in,
    input logic [15:0] ub_rd_row_size,
    input logic [15:0] ub_rd_col_size,

    // Learning rate
    input logic [15:0] learning_rate_in,

    // VPU data pathway
    input logic [3:0] vpu_data_pathway,

    input logic sys_switch_in,
    input logic [15:0] vpu_leak_factor_in,
    input logic [15:0] inv_batch_size_times_two_in,

    // Buffered VPU outputs (what the skid stage presents to UB)
    output logic [15:0] vpu_data_out_1,
    output logic [15:0] vpu_data_out_2,
    output logic vpu_valid_out_1,
    output logic vpu_valid_out_2,

    // Raw VPU outputs before local handshake hardening
    output logic [15:0] vpu_raw_data_out_1,
    output logic [15:0] vpu_raw_data_out_2,
    output logic vpu_raw_valid_out_1,
    output logic vpu_raw_valid_out_2,

    // Handshake debug signals
    output logic wb_ready_to_vpu_out,
    output logic wb_fire_out,
    output logic wb_holding_out,
    output logic wb_overflow_out,

    // Systolic array outputs
    output logic [15:0] sys_data_out_21,
    output logic [15:0] sys_data_out_22,
    output logic sys_valid_out_21,
    output logic sys_valid_out_22,

    // UB read data outputs (input/weight/bias)
    output logic [15:0] ub_rd_input_data_out_0,
    output logic [15:0] ub_rd_input_data_out_1,
    output logic ub_rd_input_valid_out_0,
    output logic ub_rd_input_valid_out_1,
    output logic [15:0] ub_rd_weight_data_out_0,
    output logic [15:0] ub_rd_weight_data_out_1,
    output logic ub_rd_weight_valid_out_0,
    output logic ub_rd_weight_valid_out_1
);
    logic [15:0] ub_wr_data_in [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic ub_wr_valid_in [0:SYSTOLIC_ARRAY_WIDTH-1];

    logic [15:0] ub_rd_col_size_out;
    logic ub_rd_col_size_valid_out;

    logic [15:0] ub_rd_bias_data_out_0;
    logic [15:0] ub_rd_bias_data_out_1;
    logic [15:0] ub_rd_Y_data_out_0;
    logic [15:0] ub_rd_Y_data_out_1;
    logic [15:0] ub_rd_H_data_out_0;
    logic [15:0] ub_rd_H_data_out_1;

    logic [15:0] vpu_raw_data_out [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic vpu_raw_valid_out [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic [15:0] vpu_skid_data_out [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic vpu_skid_valid_out [0:SYSTOLIC_ARRAY_WIDTH-1];

    assign ub_wr_data_in[0] = vpu_skid_data_out[0];
    assign ub_wr_data_in[1] = vpu_skid_data_out[1];
    assign ub_wr_valid_in[0] = vpu_skid_valid_out[0] && wb_ready_in;
    assign ub_wr_valid_in[1] = vpu_skid_valid_out[1] && wb_ready_in;

    assign vpu_data_out_1 = vpu_skid_data_out[0];
    assign vpu_data_out_2 = vpu_skid_data_out[1];
    assign vpu_valid_out_1 = vpu_skid_valid_out[0];
    assign vpu_valid_out_2 = vpu_skid_valid_out[1];

    assign vpu_raw_data_out_1 = vpu_raw_data_out[0];
    assign vpu_raw_data_out_2 = vpu_raw_data_out[1];
    assign vpu_raw_valid_out_1 = vpu_raw_valid_out[0];
    assign vpu_raw_valid_out_2 = vpu_raw_valid_out[1];

    unified_buffer #(
        .UNIFIED_BUFFER_WIDTH(UNIFIED_BUFFER_DEPTH),
        .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
    ) ub_inst(
        .clk(clk),
        .rst(rst),

        .ub_wr_data_in(ub_wr_data_in),
        .ub_wr_valid_in(ub_wr_valid_in),
        .ub_wr_host_data_in(ub_wr_host_data_in),
        .ub_wr_host_valid_in(ub_wr_host_valid_in),
        .ub_rd_start_in(ub_rd_start_in),
        .ub_rd_transpose(ub_rd_transpose),
        .ub_ptr_select(ub_ptr_select),
        .ub_rd_addr_in(ub_rd_addr_in),
        .ub_rd_row_size(ub_rd_row_size),
        .ub_rd_col_size(ub_rd_col_size),
        .learning_rate_in(learning_rate_in),
        .ub_rd_input_data_out_0(ub_rd_input_data_out_0),
        .ub_rd_input_data_out_1(ub_rd_input_data_out_1),
        .ub_rd_input_valid_out_0(ub_rd_input_valid_out_0),
        .ub_rd_input_valid_out_1(ub_rd_input_valid_out_1),
        .ub_rd_weight_data_out_0(ub_rd_weight_data_out_0),
        .ub_rd_weight_data_out_1(ub_rd_weight_data_out_1),
        .ub_rd_weight_valid_out_0(ub_rd_weight_valid_out_0),
        .ub_rd_weight_valid_out_1(ub_rd_weight_valid_out_1),
        .ub_rd_bias_data_out_0(ub_rd_bias_data_out_0),
        .ub_rd_bias_data_out_1(ub_rd_bias_data_out_1),
        .ub_rd_Y_data_out_0(ub_rd_Y_data_out_0),
        .ub_rd_Y_data_out_1(ub_rd_Y_data_out_1),
        .ub_rd_H_data_out_0(ub_rd_H_data_out_0),
        .ub_rd_H_data_out_1(ub_rd_H_data_out_1),
        .ub_rd_col_size_out(ub_rd_col_size_out),
        .ub_rd_col_size_valid_out(ub_rd_col_size_valid_out)
    );

    systolic systolic_inst (
        .clk(clk),
        .rst(rst),
        .sys_data_in_11(ub_rd_input_data_out_0),
        .sys_data_in_21(ub_rd_input_data_out_1),
        .sys_start(ub_rd_input_valid_out_0),
        .sys_data_out_21(sys_data_out_21),
        .sys_data_out_22(sys_data_out_22),
        .sys_valid_out_21(sys_valid_out_21),
        .sys_valid_out_22(sys_valid_out_22),
        .sys_weight_in_11(ub_rd_weight_data_out_0),
        .sys_weight_in_12(ub_rd_weight_data_out_1),
        .sys_accept_w_1(ub_rd_weight_valid_out_0),
        .sys_accept_w_2(ub_rd_weight_valid_out_1),
        .sys_switch_in(sys_switch_in),
        .ub_rd_col_size_in(ub_rd_col_size_out),
        .ub_rd_col_size_valid_in(ub_rd_col_size_valid_out)
    );

    vpu vpu_inst (
        .clk(clk),
        .rst(rst),
        .vpu_data_pathway(vpu_data_pathway),
        .vpu_data_in_1(sys_data_out_21),
        .vpu_data_in_2(sys_data_out_22),
        .vpu_valid_in_1(sys_valid_out_21),
        .vpu_valid_in_2(sys_valid_out_22),
        .bias_scalar_in_1(ub_rd_bias_data_out_0),
        .bias_scalar_in_2(ub_rd_bias_data_out_1),
        .lr_leak_factor_in(vpu_leak_factor_in),
        .Y_in_1(ub_rd_Y_data_out_0),
        .Y_in_2(ub_rd_Y_data_out_1),
        .inv_batch_size_times_two_in(inv_batch_size_times_two_in),
        .H_in_1(ub_rd_H_data_out_0),
        .H_in_2(ub_rd_H_data_out_1),
        .vpu_data_out_1(vpu_raw_data_out[0]),
        .vpu_data_out_2(vpu_raw_data_out[1]),
        .vpu_valid_out_1(vpu_raw_valid_out[0]),
        .vpu_valid_out_2(vpu_raw_valid_out[1])
    );

    vpu_ub_skid_stage #(
        .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH),
        .DATA_WIDTH(16)
    ) vpu_ub_skid_stage_inst (
        .clk(clk),
        .rst(rst),
        .data_in(vpu_raw_data_out),
        .valid_in(vpu_raw_valid_out),
        .ready_in(wb_ready_in),
        .ready_out(wb_ready_to_vpu_out),
        .data_out(vpu_skid_data_out),
        .valid_out(vpu_skid_valid_out),
        .fire_out(wb_fire_out),
        .holding_out(wb_holding_out),
        .overflow_out(wb_overflow_out)
    );

endmodule
