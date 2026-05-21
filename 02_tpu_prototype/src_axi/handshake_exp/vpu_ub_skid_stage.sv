`timescale 1ns/1ps
`default_nettype none

module vpu_ub_skid_stage #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2,
    parameter int DATA_WIDTH = 16
)(
    input logic clk,
    input logic rst,

    input logic [DATA_WIDTH-1:0] data_in [0:SYSTOLIC_ARRAY_WIDTH-1],
    input logic valid_in [0:SYSTOLIC_ARRAY_WIDTH-1],
    input logic ready_in,

    output logic ready_out,
    output logic [DATA_WIDTH-1:0] data_out [0:SYSTOLIC_ARRAY_WIDTH-1],
    output logic valid_out [0:SYSTOLIC_ARRAY_WIDTH-1],
    output logic fire_out,
    output logic holding_out,
    output logic overflow_out
);

    logic [DATA_WIDTH-1:0] hold_data [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic hold_valid [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic hold_active;

    logic [DATA_WIDTH-1:0] blocked_data [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic blocked_valid [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic blocked_active;

    logic input_valid_any;
    logic hold_valid_any;
    logic blocked_input_matches_snapshot;

    always_comb begin
        input_valid_any = 1'b0;
        hold_valid_any = 1'b0;
        blocked_input_matches_snapshot = 1'b1;

        for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
            input_valid_any |= valid_in[i];
            hold_valid_any |= hold_valid[i];

            if (valid_in[i] !== blocked_valid[i] || data_in[i] !== blocked_data[i]) begin
                blocked_input_matches_snapshot = 1'b0;
            end
        end
    end

    always_comb begin
        ready_out = !hold_active || ready_in;
        holding_out = hold_active;
        fire_out = ready_in && (hold_active ? hold_valid_any : input_valid_any);

        for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
            if (hold_active) begin
                data_out[i] = hold_data[i];
                valid_out[i] = hold_valid[i];
            end else begin
                data_out[i] = data_in[i];
                valid_out[i] = valid_in[i];
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            hold_active <= 1'b0;
            blocked_active <= 1'b0;
            overflow_out <= 1'b0;

            for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                hold_data[i] <= '0;
                hold_valid[i] <= 1'b0;
                blocked_data[i] <= '0;
                blocked_valid[i] <= 1'b0;
            end
        end else begin
            overflow_out <= 1'b0;

            if (hold_active) begin
                if (ready_in) begin
                    blocked_active <= 1'b0;
                    for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                        blocked_data[i] <= '0;
                        blocked_valid[i] <= 1'b0;
                    end

                    if (input_valid_any) begin
                        // Drain the held beat and immediately queue the waiting source beat.
                        for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                            hold_data[i] <= data_in[i];
                            hold_valid[i] <= valid_in[i];
                        end
                        hold_active <= 1'b1;
                    end else begin
                        hold_active <= 1'b0;
                        for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                            hold_data[i] <= '0;
                            hold_valid[i] <= 1'b0;
                        end
                    end
                end else if (input_valid_any) begin
                    if (!blocked_active) begin
                        // Snapshot the first source beat blocked by ready_out=0.
                        blocked_active <= 1'b1;
                        for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                            blocked_data[i] <= data_in[i];
                            blocked_valid[i] <= valid_in[i];
                        end
                    end else if (!blocked_input_matches_snapshot) begin
                        // Source changed an unaccepted beat while stalled.
                        overflow_out <= 1'b1;
                    end
                end else begin
                    blocked_active <= 1'b0;
                    for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                        blocked_data[i] <= '0;
                        blocked_valid[i] <= 1'b0;
                    end
                end
            end else if (!ready_in && input_valid_any) begin
                // Capture the first beat that missed the sink and hold it stable until ready returns.
                hold_active <= 1'b1;
                blocked_active <= 1'b0;
                for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                    hold_data[i] <= data_in[i];
                    hold_valid[i] <= valid_in[i];
                    blocked_data[i] <= '0;
                    blocked_valid[i] <= 1'b0;
                end
            end else begin
                blocked_active <= 1'b0;
                for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                    blocked_data[i] <= '0;
                    blocked_valid[i] <= 1'b0;
                end
            end
        end
    end

endmodule
