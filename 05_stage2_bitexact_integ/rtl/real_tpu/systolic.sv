`timescale 1ns/1ps
`default_nettype none

module systolic #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2,
    parameter int PSUM_WIDTH = 48
)(
    input logic clk,
    input logic rst,

    // input signals from left side of systolic array
    input logic signed [15:0] sys_data_in_11,
    input logic signed [15:0] sys_data_in_21,
    input logic sys_start,

    output logic signed [15:0] sys_data_out_21,
    output logic signed [15:0] sys_data_out_22,
    output logic signed [PSUM_WIDTH-1:0] sys_psum_out_21,
    output logic signed [PSUM_WIDTH-1:0] sys_psum_out_22,
    output wire sys_valid_out_21,
    output wire sys_valid_out_22,

    // input signals from top of systolic array
    input logic signed [15:0] sys_weight_in_11,
    input logic signed [15:0] sys_weight_in_12,
    input logic sys_accept_w_1,
    input logic sys_accept_w_2,

    input logic sys_switch_in,

    input logic [15:0] ub_rd_col_size_in,
    input logic ub_rd_col_size_valid_in
);

    logic signed [15:0] pe_input_out_11;
    logic signed [15:0] pe_input_out_21;

    logic signed [PSUM_WIDTH-1:0] pe_psum_out_11;
    logic signed [PSUM_WIDTH-1:0] pe_psum_out_12;

    logic signed [15:0] pe_weight_out_11;
    logic signed [15:0] pe_weight_out_12;

    logic pe_switch_out_11;
    logic pe_switch_out_12;

    wire pe_valid_out_11;
    wire pe_valid_out_12;

    logic [1:0] pe_enabled;

    localparam signed [PSUM_WIDTH-1:0] Q8_8_ROUND_BIAS = {{(PSUM_WIDTH-8){1'b0}}, 8'd128};
    localparam signed [PSUM_WIDTH-1:0] Q8_8_MAX_VALUE  = {{(PSUM_WIDTH-16){1'b0}}, 16'h7fff};
    localparam signed [PSUM_WIDTH-1:0] Q8_8_MIN_VALUE  = {{(PSUM_WIDTH-16){1'b1}}, 16'h8000};

    function automatic signed [15:0] q8_8_round_sat;
        input signed [PSUM_WIDTH-1:0] value;
        reg signed [PSUM_WIDTH-1:0] rounded;
        begin
            if(value >= 0) begin
                rounded = (value + Q8_8_ROUND_BIAS) >>> 8;
            end else begin
                rounded = -(((-value) + Q8_8_ROUND_BIAS) >>> 8);
            end

            if(rounded > Q8_8_MAX_VALUE) begin
                q8_8_round_sat = 16'sh7fff;
            end else if(rounded < Q8_8_MIN_VALUE) begin
                q8_8_round_sat = 16'sh8000;
            end else begin
                q8_8_round_sat = rounded[15:0];
            end
        end
    endfunction

    pe #(
        .DATA_WIDTH(16),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) pe11 (
        .clk(clk),
        .rst(rst),
        .pe_enabled(pe_enabled[0]),
        .pe_valid_in(sys_start),
        .pe_valid_out(pe_valid_out_11),
        .pe_accept_w_in(sys_accept_w_1),
        .pe_switch_in(sys_switch_in),
        .pe_switch_out(pe_switch_out_11),
        .pe_input_in(sys_data_in_11),
        .pe_psum_in('0),
        .pe_weight_in(sys_weight_in_11),
        .pe_input_out(pe_input_out_11),
        .pe_psum_out(pe_psum_out_11),
        .pe_weight_out(pe_weight_out_11)
    );

    pe #(
        .DATA_WIDTH(16),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) pe12 (
        .clk(clk),
        .rst(rst),
        .pe_enabled(pe_enabled[1]),
        .pe_valid_in(pe_valid_out_11),
        .pe_valid_out(pe_valid_out_12),
        .pe_accept_w_in(sys_accept_w_2),
        .pe_switch_in(pe_switch_out_11),
        .pe_switch_out(pe_switch_out_12),
        .pe_input_in(pe_input_out_11),
        .pe_psum_in('0),
        .pe_weight_in(sys_weight_in_12),
        .pe_input_out(),
        .pe_psum_out(pe_psum_out_12),
        .pe_weight_out(pe_weight_out_12)
    );

    pe #(
        .DATA_WIDTH(16),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) pe21 (
        .clk(clk),
        .rst(rst),
        .pe_enabled(pe_enabled[0]),
        .pe_valid_in(pe_valid_out_11),
        .pe_valid_out(sys_valid_out_21),
        .pe_accept_w_in(sys_accept_w_1),
        .pe_switch_in(pe_switch_out_11),
        .pe_switch_out(),
        .pe_input_in(sys_data_in_21),
        .pe_psum_in(pe_psum_out_11),
        .pe_weight_in(pe_weight_out_11),
        .pe_input_out(pe_input_out_21),
        .pe_psum_out(sys_psum_out_21),
        .pe_weight_out()
    );

    pe #(
        .DATA_WIDTH(16),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) pe22 (
        .clk(clk),
        .rst(rst),
        .pe_enabled(pe_enabled[1]),
        .pe_valid_in(pe_valid_out_12),
        .pe_valid_out(sys_valid_out_22),
        .pe_accept_w_in(sys_accept_w_2),
        .pe_switch_in(pe_switch_out_12),
        .pe_switch_out(),
        .pe_input_in(pe_input_out_21),
        .pe_psum_in(pe_psum_out_12),
        .pe_weight_in(pe_weight_out_12),
        .pe_input_out(),
        .pe_psum_out(sys_psum_out_22),
        .pe_weight_out()
    );

    always_comb begin
        sys_data_out_21 = q8_8_round_sat(sys_psum_out_21);
        sys_data_out_22 = q8_8_round_sat(sys_psum_out_22);
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            pe_enabled <= '0;
        end else begin
            if(ub_rd_col_size_valid_in) begin
                pe_enabled <= (1 << ub_rd_col_size_in) - 1;
            end
        end
    end

endmodule
