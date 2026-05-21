`timescale 1ns/1ps
`default_nettype none

module pe #(
    parameter int DATA_WIDTH = 16,
    parameter int PSUM_WIDTH = 48
) (
    input logic clk,
    input logic rst,

    // North wires of PE
    input logic signed [PSUM_WIDTH-1:0] pe_psum_in,
    input logic signed [DATA_WIDTH-1:0] pe_weight_in,
    input logic pe_accept_w_in,

    // West wires of PE
    input logic signed [DATA_WIDTH-1:0] pe_input_in,
    input logic pe_valid_in,
    input logic pe_switch_in,
    input logic pe_enabled,

    // South wires of the PE
    output logic signed [PSUM_WIDTH-1:0] pe_psum_out,
    output logic signed [DATA_WIDTH-1:0] pe_weight_out,

    // East wires of the PE
    output logic signed [DATA_WIDTH-1:0] pe_input_out,
    output logic pe_valid_out,
    output logic pe_switch_out
);

    logic signed [DATA_WIDTH-1:0] weight_reg_active;
    logic signed [DATA_WIDTH-1:0] weight_reg_inactive;
    wire signed [(2*DATA_WIDTH)-1:0] mult_out_full;
    wire signed [PSUM_WIDTH-1:0] mult_out_ext;
    wire signed [PSUM_WIDTH-1:0] mac_out;

    assign mult_out_full = $signed(pe_input_in) * $signed(weight_reg_active);
    assign mult_out_ext = {{(PSUM_WIDTH-(2*DATA_WIDTH)){mult_out_full[(2*DATA_WIDTH)-1]}}, mult_out_full};
    assign mac_out = $signed(pe_psum_in) + $signed(mult_out_ext);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pe_input_out <= '0;
            weight_reg_active <= '0;
            weight_reg_inactive <= '0;
            pe_valid_out <= 1'b0;
            pe_weight_out <= '0;
            pe_switch_out <= 1'b0;
            pe_psum_out <= '0;
        end else if (!pe_enabled) begin
            pe_input_out <= '0;
            pe_valid_out <= 1'b0;
            pe_psum_out <= '0;
        end else begin
            pe_valid_out <= pe_valid_in;
            pe_switch_out <= pe_switch_in;

            if (pe_switch_in) begin
                weight_reg_active <= weight_reg_inactive;
            end

            if (pe_accept_w_in) begin
                weight_reg_inactive <= pe_weight_in;
                pe_weight_out <= pe_weight_in;
            end else begin
                pe_weight_out <= '0;
            end

            if (pe_valid_in) begin
                pe_input_out <= pe_input_in;
                pe_psum_out <= mac_out;
            end else begin
                pe_psum_out <= '0;
            end
        end
    end

endmodule
