`timescale 1ns/1ps
`default_nettype none

// Pipeline experiment variant:
// Insert one register stage between VPU writeback outputs and UB write ports.
// Original src/tpu.sv is left untouched for baseline comparison.
module tpu_pipeline #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2,
    parameter int UNIFIED_BUFFER_DEPTH = 64
)(
    input logic clk,
    input logic rst,

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

    // Pipelined VPU outputs (data writeback)
    output logic [15:0] vpu_data_out_1,
    output logic [15:0] vpu_data_out_2,
    output logic vpu_valid_out_1,
    output logic vpu_valid_out_2,

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
    // UB internal wires (pipelined VPU writeback to UB)
    logic [15:0] ub_wr_data_in [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic ub_wr_valid_in [0:SYSTOLIC_ARRAY_WIDTH-1];

    // Number of columns in the matrix to send to systolic array
    logic [15:0] ub_rd_col_size_out;
    logic ub_rd_col_size_valid_out;

    // UB read data outputs (bias/Y/H for VPU)
    logic [15:0] ub_rd_bias_data_out_0;
    logic [15:0] ub_rd_bias_data_out_1;
    logic [15:0] ub_rd_Y_data_out_0;
    logic [15:0] ub_rd_Y_data_out_1;
    logic [15:0] ub_rd_H_data_out_0;
    logic [15:0] ub_rd_H_data_out_1;

    // Raw VPU writeback before the inserted register stage
    logic [15:0] vpu_raw_data_out [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic vpu_raw_valid_out [0:SYSTOLIC_ARRAY_WIDTH-1];

    // Registered writeback after the inserted stage
    logic [15:0] vpu_pipe_data_out [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic vpu_pipe_valid_out [0:SYSTOLIC_ARRAY_WIDTH-1];

    assign ub_wr_data_in[0] = vpu_pipe_data_out[0];
    assign ub_wr_data_in[1] = vpu_pipe_data_out[1];
    assign ub_wr_valid_in[0] = vpu_pipe_valid_out[0];
    assign ub_wr_valid_in[1] = vpu_pipe_valid_out[1];

    // Keep top-level observability aligned with what UB actually receives.
    assign vpu_data_out_1 = vpu_pipe_data_out[0];
    assign vpu_data_out_2 = vpu_pipe_data_out[1];
    assign vpu_valid_out_1 = vpu_pipe_valid_out[0];
    assign vpu_valid_out_2 = vpu_pipe_valid_out[1];

    unified_buffer #(
        .UNIFIED_BUFFER_WIDTH(UNIFIED_BUFFER_DEPTH),
        .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
    ) ub_inst(
        .clk(clk),
        .rst(rst),

        .ub_wr_data_in(ub_wr_data_in),
        .ub_wr_valid_in(ub_wr_valid_in),

        // Write ports from host to UB (for loading in parameters)
        .ub_wr_host_data_in(ub_wr_host_data_in),
        .ub_wr_host_valid_in(ub_wr_host_valid_in),

        // Read instruction input from instruction memory
        .ub_rd_start_in(ub_rd_start_in),
        .ub_rd_transpose(ub_rd_transpose),
        .ub_ptr_select(ub_ptr_select),
        .ub_rd_addr_in(ub_rd_addr_in),
        .ub_rd_row_size(ub_rd_row_size),
        .ub_rd_col_size(ub_rd_col_size),

        // Learning rate input
        .learning_rate_in(learning_rate_in),

        // Read ports from UB to left side of systolic array
        .ub_rd_input_data_out_0(ub_rd_input_data_out_0),
        .ub_rd_input_data_out_1(ub_rd_input_data_out_1),
        .ub_rd_input_valid_out_0(ub_rd_input_valid_out_0),
        .ub_rd_input_valid_out_1(ub_rd_input_valid_out_1),

        // Read ports from UB to top of systolic array
        .ub_rd_weight_data_out_0(ub_rd_weight_data_out_0),
        .ub_rd_weight_data_out_1(ub_rd_weight_data_out_1),
        .ub_rd_weight_valid_out_0(ub_rd_weight_valid_out_0),
        .ub_rd_weight_valid_out_1(ub_rd_weight_valid_out_1),

        // Read ports from UB to bias modules in VPU
        .ub_rd_bias_data_out_0(ub_rd_bias_data_out_0),
        .ub_rd_bias_data_out_1(ub_rd_bias_data_out_1),

        // Read ports from UB to loss modules (Y matrices) in VPU
        .ub_rd_Y_data_out_0(ub_rd_Y_data_out_0),
        .ub_rd_Y_data_out_1(ub_rd_Y_data_out_1),

        // Read ports from UB to activation derivative modules (H matrices) in VPU
        .ub_rd_H_data_out_0(ub_rd_H_data_out_0),
        .ub_rd_H_data_out_1(ub_rd_H_data_out_1),

        // Outputs to send number of columns to systolic array
        .ub_rd_col_size_out(ub_rd_col_size_out),
        .ub_rd_col_size_valid_out(ub_rd_col_size_valid_out)
    );

    systolic systolic_inst (
        .clk(clk),
        .rst(rst),

        // input signals from left side of systolic array
        .sys_data_in_11(ub_rd_input_data_out_0),
        .sys_data_in_21(ub_rd_input_data_out_1),
        .sys_start(ub_rd_input_valid_out_0),

        .sys_data_out_21(sys_data_out_21),
        .sys_data_out_22(sys_data_out_22),
        .sys_valid_out_21(sys_valid_out_21),
        .sys_valid_out_22(sys_valid_out_22),

        // input signals from top of systolic array
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

        // Inputs from systolic array
        .vpu_data_in_1(sys_data_out_21),
        .vpu_data_in_2(sys_data_out_22),
        .vpu_valid_in_1(sys_valid_out_21),
        .vpu_valid_in_2(sys_valid_out_22),

        // Inputs from UB
        .bias_scalar_in_1(ub_rd_bias_data_out_0),
        .bias_scalar_in_2(ub_rd_bias_data_out_1),
        .lr_leak_factor_in(vpu_leak_factor_in),
        .Y_in_1(ub_rd_Y_data_out_0),
        .Y_in_2(ub_rd_Y_data_out_1),
        .inv_batch_size_times_two_in(inv_batch_size_times_two_in),
        .H_in_1(ub_rd_H_data_out_0),
        .H_in_2(ub_rd_H_data_out_1),

        // Raw outputs before the inserted pipeline stage
        .vpu_data_out_1(vpu_raw_data_out[0]),
        .vpu_data_out_2(vpu_raw_data_out[1]),
        .vpu_valid_out_1(vpu_raw_valid_out[0]),
        .vpu_valid_out_2(vpu_raw_valid_out[1])
    );

    vpu_ub_pipe_stage #(
        .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH),
        .DATA_WIDTH(16)
    ) vpu_ub_pipe_stage_inst (
        .clk(clk),
        .rst(rst),
        .data_in(vpu_raw_data_out),
        .valid_in(vpu_raw_valid_out),
        .data_out(vpu_pipe_data_out),
        .valid_out(vpu_pipe_valid_out)
    );

endmodule
