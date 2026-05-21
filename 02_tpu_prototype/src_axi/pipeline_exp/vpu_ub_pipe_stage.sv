`timescale 1ns/1ps
`default_nettype none

module vpu_ub_pipe_stage #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2,
    parameter int DATA_WIDTH = 16
)(
    input logic clk,
    input logic rst,

    input logic [DATA_WIDTH-1:0] data_in [0:SYSTOLIC_ARRAY_WIDTH-1],
    input logic valid_in [0:SYSTOLIC_ARRAY_WIDTH-1],

    output logic [DATA_WIDTH-1:0] data_out [0:SYSTOLIC_ARRAY_WIDTH-1],
    output logic valid_out [0:SYSTOLIC_ARRAY_WIDTH-1]
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                data_out[i] <= '0;
                valid_out[i] <= 1'b0;
            end
        end else begin
            for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                data_out[i] <= data_in[i];
                valid_out[i] <= valid_in[i];
            end
        end
    end

endmodule
