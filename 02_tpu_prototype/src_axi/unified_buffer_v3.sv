// Unified Buffer V3 - Synthesis-compliant version
// Changes from V2:
// 1. always @(...) → always_ff @(...) for sequential logic
// 2. Local variable t_ptr moved to module scope
// 3. Added default case to ub_ptr_select case statement
// 4. Debug signals wrapped in `ifdef SIMULATION
// 5. Fixed bit-width consistency (0 → 1'b0)

`timescale 1ns/1ps
`default_nettype none

module unified_buffer #(
    parameter int UNIFIED_BUFFER_WIDTH = 128,
    parameter int SYSTOLIC_ARRAY_WIDTH = 2
)(
    input logic clk,
    input logic rst,

    // Write ports from VPU to UB
    input logic [15:0] ub_wr_data_in [SYSTOLIC_ARRAY_WIDTH],
    input logic ub_wr_valid_in [SYSTOLIC_ARRAY_WIDTH],

    // Write ports from host to UB (for loading in parameters)
    input logic [15:0] ub_wr_host_data_in [SYSTOLIC_ARRAY_WIDTH],
    input logic ub_wr_host_valid_in [SYSTOLIC_ARRAY_WIDTH],
    input logic ub_wr_ptr_restore_in,

    // Read instruction input from instruction memory
    input logic ub_rd_start_in,
    input logic ub_rd_transpose,
    input logic [8:0] ub_ptr_select,
    input logic [15:0] ub_rd_addr_in,
    input logic [15:0] ub_rd_row_size,
    input logic [15:0] ub_rd_col_size,

    // Learning rate input
    input logic [15:0] learning_rate_in,

    // Read ports from UB to left side of systolic array
    output logic [15:0] ub_rd_input_data_out_0,
    output logic [15:0] ub_rd_input_data_out_1,
    output logic ub_rd_input_valid_out_0,
    output logic ub_rd_input_valid_out_1,

    // Read ports from UB to top of systolic array
    output logic [15:0] ub_rd_weight_data_out_0,
    output logic [15:0] ub_rd_weight_data_out_1,
    output logic ub_rd_weight_valid_out_0,
    output logic ub_rd_weight_valid_out_1,

    // Read ports from UB to bias modules in VPU
    output logic [15:0] ub_rd_bias_data_out_0,
    output logic [15:0] ub_rd_bias_data_out_1,

    // Read ports from UB to loss modules (Y matrices) in VPU
    output logic [15:0] ub_rd_Y_data_out_0,
    output logic [15:0] ub_rd_Y_data_out_1,

    // Read ports from UB to activation derivative modules (H matrices) in VPU
    output logic [15:0] ub_rd_H_data_out_0,
    output logic [15:0] ub_rd_H_data_out_1,

    // Outputs to send number of columns to systolic array
    output logic [15:0] ub_rd_col_size_out,
    output logic ub_rd_col_size_valid_out
);

    logic [15:0] ub_memory [0:UNIFIED_BUFFER_WIDTH-1];

    // Fix #4: Debug signals wrapped in ifdef SIMULATION
`ifdef SIMULATION
    logic [15:0] dbg_wr_host_data_0, dbg_wr_host_data_1;
    logic        dbg_wr_host_valid_0, dbg_wr_host_valid_1;
    logic [15:0] dbg_wr_data_0, dbg_wr_data_1;
    logic        dbg_wr_valid_0, dbg_wr_valid_1;
    assign dbg_wr_host_data_0  = ub_wr_host_data_in[0];
    assign dbg_wr_host_data_1  = ub_wr_host_data_in[1];
    assign dbg_wr_host_valid_0 = ub_wr_host_valid_in[0];
    assign dbg_wr_host_valid_1 = ub_wr_host_valid_in[1];
    assign dbg_wr_data_0  = ub_wr_data_in[0];
    assign dbg_wr_data_1  = ub_wr_data_in[1];
    assign dbg_wr_valid_0 = ub_wr_valid_in[0];
    assign dbg_wr_valid_1 = ub_wr_valid_in[1];
`endif

    logic [15:0] ub_rd_input_data_out [SYSTOLIC_ARRAY_WIDTH];
    logic ub_rd_input_valid_out [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] ub_rd_weight_data_out [SYSTOLIC_ARRAY_WIDTH];
    logic ub_rd_weight_valid_out [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] ub_rd_bias_data_out [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] ub_rd_Y_data_out [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] ub_rd_H_data_out [SYSTOLIC_ARRAY_WIDTH];

    logic [15:0] wr_ptr;
    logic [15:0] wr_ptr_next;
    logic [15:0] wr_ptr_base;

    // Internal logic for reading inputs from UB to left side of systolic array
    logic [15:0] rd_input_ptr;
    logic [15:0] rd_input_ptr_next;
    logic [15:0] rd_input_row_size;
    logic [15:0] rd_input_col_size;
    logic [15:0] rd_input_time_counter;
    logic rd_input_transpose;

    // Internal logic for reading weights from UB to top of systolic array
    logic signed [15:0] rd_weight_ptr;
    logic signed [15:0] rd_weight_ptr_next;
    logic [15:0] rd_weight_row_size;
    logic [15:0] rd_weight_col_size;
    logic [15:0] rd_weight_time_counter;
    logic rd_weight_transpose;
    logic [15:0] rd_weight_skip_size;

    // Internal logic for bias inputs from UB to bias modules in VPU
    logic [15:0] rd_bias_ptr;
    logic [15:0] rd_bias_row_size;
    logic [15:0] rd_bias_col_size;
    logic [15:0] rd_bias_time_counter;

    // Internal logic for Y inputs from UB to loss modules in VPU
    logic [15:0] rd_Y_ptr;
    logic [15:0] rd_Y_ptr_next;
    logic [15:0] rd_Y_row_size;
    logic [15:0] rd_Y_col_size;
    logic [15:0] rd_Y_time_counter;

    // Internal logic for H inputs from UB to activation derivative modules in VPU
    logic [15:0] rd_H_ptr;
    logic [15:0] rd_H_ptr_next;
    logic [15:0] rd_H_row_size;
    logic [15:0] rd_H_col_size;
    logic [15:0] rd_H_time_counter;

    // Internal logic for bias gradient descent inputs
    logic [15:0] rd_grad_bias_ptr;
    logic [15:0] rd_grad_bias_row_size;
    logic [15:0] rd_grad_bias_col_size;
    logic [15:0] rd_grad_bias_time_counter;
    logic rd_grad_bias_started;
    logic [15:0] rd_grad_bias_value_phase;

    // Internal logic for weight gradient descent inputs
    logic [15:0] rd_grad_weight_ptr;
    logic [15:0] rd_grad_weight_ptr_next;
    logic [15:0] rd_grad_weight_row_size;
    logic [15:0] rd_grad_weight_col_size;
    logic [15:0] rd_grad_weight_time_counter;

    // Internal logic for gradient descent
    logic [15:0] value_old_in [SYSTOLIC_ARRAY_WIDTH];
    logic grad_descent_valid_in [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] value_updated_out [SYSTOLIC_ARRAY_WIDTH];
    logic grad_descent_done_out [SYSTOLIC_ARRAY_WIDTH];

    // Where to write gradients to UB
    logic [15:0] grad_descent_ptr;
    logic [15:0] grad_descent_ptr_next;

    // Whether the gradients are biases or weights (0 for biases, 1 for weights)
    logic grad_bias_or_weight;

    // Combinational offset signals for multi-lane address calculation
    logic [15:0] wr_lane_addr [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] rd_input_lane_addr [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] rd_input_lane_addr_t [SYSTOLIC_ARRAY_WIDTH];
    logic signed [15:0] rd_weight_lane_addr [SYSTOLIC_ARRAY_WIDTH];
    logic signed [15:0] rd_weight_lane_addr_t [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] rd_Y_lane_addr [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] rd_H_lane_addr [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] rd_gw_lane_addr [SYSTOLIC_ARRAY_WIDTH];
    logic [15:0] gd_wr_lane_addr [SYSTOLIC_ARRAY_WIDTH];

    // Fix #2: Local variable t_ptr moved to module scope
    logic [15:0] t_ptr;

    genvar i;
    generate
        for (i=0; i<SYSTOLIC_ARRAY_WIDTH; i++) begin : gradient_descent_gen
            gradient_descent gradient_descent_inst (
                .clk(clk),
                .rst(rst),
                .lr_in(learning_rate_in),
                .grad_in(ub_wr_data_in[i]),
                .value_old_in(value_old_in[i]),
                .grad_descent_valid_in(grad_descent_valid_in[i]),
                .grad_bias_or_weight(grad_bias_or_weight),
                .value_updated_out(value_updated_out[i]),
                .grad_descent_done_out(grad_descent_done_out[i])
            );
        end
    endgenerate

    // Port assignments
    assign ub_rd_input_data_out_0 = ub_rd_input_data_out[0];
    assign ub_rd_input_data_out_1 = ub_rd_input_data_out[1];
    assign ub_rd_input_valid_out_0 = ub_rd_input_valid_out[0];
    assign ub_rd_input_valid_out_1 = ub_rd_input_valid_out[1];

    assign ub_rd_weight_data_out_0 = ub_rd_weight_data_out[0];
    assign ub_rd_weight_data_out_1 = ub_rd_weight_data_out[1];
    assign ub_rd_weight_valid_out_0 = ub_rd_weight_valid_out[0];
    assign ub_rd_weight_valid_out_1 = ub_rd_weight_valid_out[1];

    assign ub_rd_bias_data_out_0 = ub_rd_bias_data_out[0];
    assign ub_rd_bias_data_out_1 = ub_rd_bias_data_out[1];

    assign ub_rd_Y_data_out_0 = ub_rd_Y_data_out[0];
    assign ub_rd_Y_data_out_1 = ub_rd_Y_data_out[1];

    assign ub_rd_H_data_out_0 = ub_rd_H_data_out[0];
    assign ub_rd_H_data_out_1 = ub_rd_H_data_out[1];

    // Gradient descent valid signal generation
    always_comb begin
        for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
            grad_descent_valid_in[j] = 1'b0;
        end

        if ((rd_grad_bias_row_size != 0 || rd_grad_bias_col_size != 0) &&
            (rd_grad_bias_time_counter + 1 < rd_grad_bias_row_size + rd_grad_bias_col_size)) begin
            for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                if (rd_grad_bias_time_counter >= j &&
                    rd_grad_bias_time_counter < rd_grad_bias_row_size + j &&
                    j < rd_grad_bias_col_size) begin
                    grad_descent_valid_in[j] = ub_wr_valid_in[j];
                end
            end
        end else if (rd_grad_weight_time_counter < rd_grad_weight_row_size + rd_grad_weight_col_size) begin
            // Weight updates need the final systolic beat as well. The current
            // counter is already one cycle ahead of the accepted output wavefront,
            // so "+1 <" drops the last lane1 update for W2 and W1 column 2.
            for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                grad_descent_valid_in[j] = ub_wr_valid_in[j];
            end
        end
    end

    // ============ COMBINATIONAL LOGIC FOR PTR CALCULATIONS ============

    // wr_ptr_next and per-lane write addresses
    always_comb begin
        wr_ptr_next = wr_ptr;
        for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
            wr_lane_addr[j] = wr_ptr_next;
            if (ub_wr_valid_in[j] || ub_wr_host_valid_in[j]) begin
                wr_ptr_next = wr_ptr_next + 1;
            end
        end
    end

    // rd_input_ptr_next and per-lane read addresses (untransposed)
    always_comb begin
        rd_input_ptr_next = rd_input_ptr;
        for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
            rd_input_lane_addr[j] = rd_input_ptr_next;
            if (rd_input_time_counter < rd_input_row_size + rd_input_col_size &&
                rd_input_time_counter >= j && rd_input_time_counter < rd_input_row_size + j && j < rd_input_col_size) begin
                rd_input_ptr_next = rd_input_ptr_next + 1;
            end
        end
    end

    // Fix #2: rd_input per-lane read addresses (transposed) - no local variable
    always_comb begin
        t_ptr = rd_input_ptr;
        for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
            rd_input_lane_addr_t[j] = t_ptr;
            if (rd_input_time_counter < rd_input_row_size + rd_input_col_size &&
                rd_input_time_counter >= j && rd_input_time_counter < rd_input_row_size + j && j < rd_input_col_size) begin
                t_ptr = t_ptr + 1;
            end
        end
    end

    // rd_weight_ptr_next and per-lane read addresses
    always_comb begin
        rd_weight_ptr_next = rd_weight_ptr;
        if (rd_weight_time_counter < rd_weight_row_size + rd_weight_col_size) begin
            if(rd_weight_transpose) begin
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    rd_weight_lane_addr_t[j] = rd_weight_ptr_next;
                    if(rd_weight_time_counter >= j && rd_weight_time_counter < rd_weight_row_size + j && j < rd_weight_col_size) begin
                        rd_weight_ptr_next = rd_weight_ptr_next + rd_weight_skip_size;
                    end
                end
                rd_weight_ptr_next = rd_weight_ptr_next - rd_weight_skip_size - 1;
            end else begin
                for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
                    rd_weight_lane_addr[j] = rd_weight_ptr_next;
                    if(rd_weight_time_counter >= j && rd_weight_time_counter < rd_weight_row_size + j && j < rd_weight_col_size) begin
                        rd_weight_ptr_next = rd_weight_ptr_next - rd_weight_skip_size;
                    end
                end
                rd_weight_ptr_next = rd_weight_ptr_next + rd_weight_skip_size + 1;
            end
        end
    end

    // rd_Y_ptr_next and per-lane read addresses
    always_comb begin
        rd_Y_ptr_next = rd_Y_ptr;
        for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
            rd_Y_lane_addr[j] = rd_Y_ptr_next;
            if (rd_Y_time_counter < rd_Y_row_size + rd_Y_col_size &&
                rd_Y_time_counter >= j && rd_Y_time_counter < rd_Y_row_size + j && j < rd_Y_col_size) begin
                rd_Y_ptr_next = rd_Y_ptr_next + 1;
            end
        end
    end

    // rd_H_ptr_next and per-lane read addresses
    always_comb begin
        rd_H_ptr_next = rd_H_ptr;
        for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
            rd_H_lane_addr[j] = rd_H_ptr_next;
            if (rd_H_time_counter < rd_H_row_size + rd_H_col_size &&
                rd_H_time_counter >= j && rd_H_time_counter < rd_H_row_size + j && j < rd_H_col_size) begin
                rd_H_ptr_next = rd_H_ptr_next + 1;
            end
        end
    end

    // rd_grad_weight_ptr_next and per-lane read addresses
    always_comb begin
        rd_grad_weight_ptr_next = rd_grad_weight_ptr;
        for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
            rd_gw_lane_addr[j] = rd_grad_weight_ptr_next;
            if (rd_grad_weight_time_counter < rd_grad_weight_row_size + rd_grad_weight_col_size &&
                rd_grad_weight_time_counter >= j && rd_grad_weight_time_counter < rd_grad_weight_row_size + j && j < rd_grad_weight_col_size) begin
                rd_grad_weight_ptr_next = rd_grad_weight_ptr_next + 1;
            end
        end
    end

    // Bias update old values are consumed by gradient_descent one cycle later, so preload
    // the next bias wavefront once the derivative stream has started.
    always_comb begin
        rd_grad_bias_value_phase = rd_grad_bias_time_counter;
        if (rd_grad_bias_started || ub_wr_valid_in[0] || ub_wr_valid_in[1]) begin
            rd_grad_bias_value_phase = rd_grad_bias_time_counter + 1;
        end
    end

    // grad_descent_ptr_next and per-lane write addresses
    always_comb begin
        grad_descent_ptr_next = grad_descent_ptr;
        if (grad_bias_or_weight) begin
            for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
                gd_wr_lane_addr[j] = grad_descent_ptr_next;
                if (grad_descent_done_out[j]) begin
                    grad_descent_ptr_next = grad_descent_ptr_next + 1;
                end
            end
        end else begin
            for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                gd_wr_lane_addr[j] = grad_descent_ptr + j;
            end
        end
    end

    // ============ SEQUENTIAL LOGIC ============
    // Fix #1: always → always_ff
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all memory to 0
            for (int j = 0; j < UNIFIED_BUFFER_WIDTH; j++) begin
                ub_memory[j] <= '0;
            end

            // Set internal registers to 0
            for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                ub_rd_input_data_out[j] <= '0;
                ub_rd_input_valid_out[j] <= '0;
                ub_rd_weight_data_out[j] <= '0;
                ub_rd_weight_valid_out[j] <= '0;
                ub_rd_bias_data_out[j] <= '0;
                ub_rd_Y_data_out[j] <= '0;
                ub_rd_H_data_out[j] <= '0;
                value_old_in[j] <= '0;
            end

            wr_ptr <= '0;
            wr_ptr_base <= '0;

            rd_input_ptr <= '0;
            rd_input_row_size <= '0;
            rd_input_col_size <= '0;
            rd_input_time_counter <= '0;
            rd_input_transpose <= '0;

            rd_weight_ptr <= '0;
            rd_weight_row_size <= '0;
            rd_weight_col_size <= '0;
            rd_weight_time_counter <= '0;
            rd_weight_transpose <= '0;
            rd_weight_skip_size <= '0;
            ub_rd_col_size_out <= '0;
            ub_rd_col_size_valid_out <= '0;
            grad_bias_or_weight <= '0;
            grad_descent_ptr <= '0;

            rd_bias_ptr <= '0;
            rd_bias_row_size <= '0;
            rd_bias_col_size <= '0;
            rd_bias_time_counter <= '0;
            rd_grad_bias_started <= 1'b0;

            rd_Y_ptr <= '0;
            rd_Y_row_size <= '0;
            rd_Y_col_size <= '0;
            rd_Y_time_counter <= '0;

            rd_H_ptr <= '0;
            rd_H_row_size <= '0;
            rd_H_col_size <= '0;
            rd_H_time_counter <= '0;

            rd_grad_bias_ptr <= '0;
            rd_grad_bias_row_size <= '0;
            rd_grad_bias_col_size <= '0;
            rd_grad_bias_time_counter <= '0;

            rd_grad_weight_ptr <= '0;
            rd_grad_weight_row_size <= '0;
            rd_grad_weight_col_size <= '0;
            rd_grad_weight_time_counter <= '0;
        end else begin
            // READ COMMAND INITIALIZATION
            if (ub_rd_start_in) begin
                // Fix #3: Added default case
                case (ub_ptr_select)
                    0: begin
                        rd_input_transpose <= ub_rd_transpose;
                        rd_input_ptr <= ub_rd_addr_in;

                        if(ub_rd_transpose) begin
                            rd_input_row_size <= ub_rd_col_size;
                            rd_input_col_size <= ub_rd_row_size;
                        end else begin
                            rd_input_row_size <= ub_rd_row_size;
                            rd_input_col_size <= ub_rd_col_size;
                        end

                        rd_input_time_counter <= '0;
                    end
                    1: begin
                        rd_weight_transpose <= ub_rd_transpose;

                        if(ub_rd_transpose) begin
                            rd_weight_row_size <= ub_rd_col_size;
                            rd_weight_col_size <= ub_rd_row_size;
                            rd_weight_ptr <= ub_rd_addr_in + ub_rd_col_size - 1;
                            ub_rd_col_size_out <= ub_rd_row_size;
                        end else begin
                            rd_weight_row_size <= ub_rd_row_size;
                            rd_weight_col_size <= ub_rd_col_size;
                            rd_weight_ptr <= ub_rd_addr_in + ub_rd_row_size*ub_rd_col_size - ub_rd_col_size;
                            ub_rd_col_size_out <= ub_rd_col_size;
                        end

                        rd_weight_skip_size <= ub_rd_col_size + 1;
                        rd_weight_time_counter <= '0;
                        ub_rd_col_size_valid_out <= 1'b1;
                    end
                    2: begin
                        rd_bias_ptr <= ub_rd_addr_in;
                        rd_bias_row_size <= ub_rd_row_size;
                        rd_bias_col_size <= ub_rd_col_size;
                        rd_bias_time_counter <= '0;
                    end
                    3: begin
                        rd_Y_ptr <= ub_rd_addr_in;
                        rd_Y_row_size <= ub_rd_row_size;
                        rd_Y_col_size <= ub_rd_col_size;
                        rd_Y_time_counter <= '0;
                    end
                    4: begin
                        rd_H_ptr <= ub_rd_addr_in;
                        rd_H_row_size <= ub_rd_row_size;
                        rd_H_col_size <= ub_rd_col_size;
                        rd_H_time_counter <= '0;
                    end
                    5: begin
                        rd_grad_bias_ptr <= ub_rd_addr_in;
                        rd_grad_bias_row_size <= ub_rd_row_size;
                        rd_grad_bias_col_size <= ub_rd_col_size;
                        rd_grad_bias_time_counter <= '0;
                        rd_grad_bias_started <= 1'b0;
                        grad_bias_or_weight <= 1'b0;
                        grad_descent_ptr <= ub_rd_addr_in;
                    end
                    6: begin
                        rd_grad_weight_ptr <= ub_rd_addr_in;
                        rd_grad_weight_row_size <= ub_rd_row_size;
                        rd_grad_weight_col_size <= ub_rd_col_size;
                        rd_grad_weight_time_counter <= '0;
                        grad_bias_or_weight <= 1'b1;
                        grad_descent_ptr <= ub_rd_addr_in;
                    end
                    default: ;  // Fix #3: explicit default for 9-bit selector
                endcase
            end

            // WRITING LOGIC (host and VPU writes)
            for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
                if (ub_wr_valid_in[j]) begin
                    ub_memory[wr_lane_addr[j]] <= ub_wr_data_in[j];
                end else if (ub_wr_host_valid_in[j]) begin
                    ub_memory[wr_lane_addr[j]] <= ub_wr_host_data_in[j];
                end
            end
            if (ub_wr_host_valid_in[0] || ub_wr_host_valid_in[1]) begin
                wr_ptr_base <= wr_ptr_next;
            end
            if (ub_wr_ptr_restore_in) begin
                wr_ptr <= wr_ptr_base;
            end else begin
                wr_ptr <= wr_ptr_next;
            end

            // WRITING LOGIC (gradient descent to UB)
            for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
                if (grad_descent_done_out[j]) begin
                    ub_memory[gd_wr_lane_addr[j]] <= value_updated_out[j];
                end
            end
            // Preserve the freshly loaded base pointer on the update start cycle.
            if (!(ub_rd_start_in && (ub_ptr_select == 5 || ub_ptr_select == 6))) begin
                grad_descent_ptr <= grad_descent_ptr_next;
            end

    // ============ READING LOGIC (Input) ============
            if (rd_input_time_counter + 1 < rd_input_row_size + rd_input_col_size) begin
                if(rd_input_transpose) begin
                    for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                        if(rd_input_time_counter >= j && rd_input_time_counter < rd_input_row_size + j && j < rd_input_col_size) begin
                            ub_rd_input_valid_out[j] <= 1'b1;
                            ub_rd_input_data_out[j] <= ub_memory[rd_input_lane_addr_t[j]];
                        end else begin
                            ub_rd_input_valid_out[j] <= 1'b0;
                            ub_rd_input_data_out[j] <= '0;
                        end
                    end
                end else begin
                    for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
                        if(rd_input_time_counter >= j && rd_input_time_counter < rd_input_row_size + j && j < rd_input_col_size) begin
                            ub_rd_input_valid_out[j] <= 1'b1;
                            ub_rd_input_data_out[j] <= ub_memory[rd_input_lane_addr[j]];
                        end else begin
                            ub_rd_input_valid_out[j] <= 1'b0;
                            ub_rd_input_data_out[j] <= '0;
                        end
                    end
                end
                rd_input_ptr <= rd_input_ptr_next;
                rd_input_time_counter <= rd_input_time_counter + 1;
            end else if (rd_input_time_counter + 1 == rd_input_row_size + rd_input_col_size) begin
                // Hold cycle: preserve outputs from last active cycle
                rd_input_time_counter <= rd_input_time_counter + 1;
            end else if (!(ub_rd_start_in && ub_ptr_select == 0)) begin
                // Reset after hold cycle
                rd_input_ptr <= 0;
                rd_input_row_size <= 0;
                rd_input_col_size <= 0;
                rd_input_time_counter <= '0;
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    ub_rd_input_valid_out[j] <= 1'b0;
                    ub_rd_input_data_out[j] <= '0;
                end
            end

            // ============ READING LOGIC (Weight) ============
            // Fix #5: 0 → 1'b0 for bit-width consistency
            if (rd_weight_time_counter + 1 < rd_weight_row_size + rd_weight_col_size) begin
                if(rd_weight_transpose) begin
                    for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                        if(rd_weight_time_counter >= j && rd_weight_time_counter < rd_weight_row_size + j && j < rd_weight_col_size) begin
                            ub_rd_weight_valid_out[j] <= 1'b1;
                            ub_rd_weight_data_out[j] <= ub_memory[rd_weight_lane_addr_t[j]];
                        end else begin
                            ub_rd_weight_valid_out[j] <= 1'b0;
                            ub_rd_weight_data_out[j] <= '0;
                        end
                    end
                end else begin
                    for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
                        if(rd_weight_time_counter >= j && rd_weight_time_counter < rd_weight_row_size + j && j < rd_weight_col_size) begin
                            ub_rd_weight_valid_out[j] <= 1'b1;
                            ub_rd_weight_data_out[j] <= ub_memory[rd_weight_lane_addr[j]];
                        end else begin
                            ub_rd_weight_valid_out[j] <= 1'b0;
                            ub_rd_weight_data_out[j] <= '0;
                        end
                    end
                end
                rd_weight_ptr <= rd_weight_ptr_next;
                rd_weight_time_counter <= rd_weight_time_counter + 1;
            end else if (rd_weight_time_counter + 1 == rd_weight_row_size + rd_weight_col_size) begin
                // Do not hold weight valids high for an extra cycle. The systolic
                // loader samples on every asserted valid, so preserving the final
                // pulse overwrites PE22 with the last lane1 weight.
                rd_weight_time_counter <= rd_weight_time_counter + 1;
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    ub_rd_weight_valid_out[j] <= 1'b0;
                    ub_rd_weight_data_out[j] <= '0;
                end
            end else if (!(ub_rd_start_in && ub_ptr_select == 1)) begin
                // Reset after hold cycle
                rd_weight_ptr <= 0;
                rd_weight_row_size <= 0;
                rd_weight_col_size <= 0;
                rd_weight_time_counter <= '0;
                ub_rd_col_size_valid_out <= 1'b0;
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    ub_rd_weight_valid_out[j] <= 1'b0;
                    ub_rd_weight_data_out[j] <= '0;
                end
            end

            // ============ READING LOGIC (Bias) ============
            if (rd_bias_time_counter + 1 < rd_bias_row_size + rd_bias_col_size) begin
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    if(rd_bias_time_counter >= j && rd_bias_time_counter < rd_bias_row_size + j && j < rd_bias_col_size) begin
                        ub_rd_bias_data_out[j] <= ub_memory[rd_bias_ptr + j];
                    end else begin
                        ub_rd_bias_data_out[j] <= '0;
                    end
                end
                rd_bias_time_counter <= rd_bias_time_counter + 1;
            end else if (rd_bias_time_counter + 1 == rd_bias_row_size + rd_bias_col_size) begin
                // Hold cycle: preserve outputs from last active cycle
                rd_bias_time_counter <= rd_bias_time_counter + 1;
            end else if (!(ub_rd_start_in && ub_ptr_select == 2)) begin
                // Reset after hold cycle
                rd_bias_ptr <= 0;
                rd_bias_row_size <= 0;
                rd_bias_col_size <= 0;
                rd_bias_time_counter <= '0;
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    ub_rd_bias_data_out[j] <= '0;
                end
            end

            // ============ READING LOGIC (Y) ============
            if (rd_Y_time_counter + 1 < rd_Y_row_size + rd_Y_col_size) begin
                for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
                    if(rd_Y_time_counter >= j && rd_Y_time_counter < rd_Y_row_size + j && j < rd_Y_col_size) begin
                        ub_rd_Y_data_out[j] <= ub_memory[rd_Y_lane_addr[j]];
                    end else begin
                        ub_rd_Y_data_out[j] <= '0;
                    end
                end
                rd_Y_ptr <= rd_Y_ptr_next;
                rd_Y_time_counter <= rd_Y_time_counter + 1;
            end else if (rd_Y_time_counter + 1 == rd_Y_row_size + rd_Y_col_size) begin
                // Hold cycle: preserve outputs from last active cycle
                rd_Y_time_counter <= rd_Y_time_counter + 1;
            end else if (!(ub_rd_start_in && ub_ptr_select == 3)) begin
                // Reset after hold cycle
                rd_Y_ptr <= 0;
                rd_Y_row_size <= 0;
                rd_Y_col_size <= 0;
                rd_Y_time_counter <= '0;
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    ub_rd_Y_data_out[j] <= '0;
                end
            end

            // ============ READING LOGIC (H) ============
            if (rd_H_time_counter + 1 < rd_H_row_size + rd_H_col_size) begin
                for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
                    if(rd_H_time_counter >= j && rd_H_time_counter < rd_H_row_size + j && j < rd_H_col_size) begin
                        ub_rd_H_data_out[j] <= ub_memory[rd_H_lane_addr[j]];
                    end else begin
                        ub_rd_H_data_out[j] <= '0;
                    end
                end
                rd_H_ptr <= rd_H_ptr_next;
                rd_H_time_counter <= rd_H_time_counter + 1;
            end else if (rd_H_time_counter + 1 == rd_H_row_size + rd_H_col_size) begin
                // Hold cycle: preserve outputs from last active cycle
                rd_H_time_counter <= rd_H_time_counter + 1;
            end else if (!(ub_rd_start_in && ub_ptr_select == 4)) begin
                // Reset after hold cycle
                rd_H_ptr <= 0;
                rd_H_row_size <= 0;
                rd_H_col_size <= 0;
                rd_H_time_counter <= '0;
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    ub_rd_H_data_out[j] <= '0;
                end
            end

            // ============ READING LOGIC (Gradient Descent) ============
            if (rd_grad_bias_time_counter < rd_grad_bias_row_size + rd_grad_bias_col_size) begin
                // Bias update can be armed before dZ1 returns. Start the fixed wavefront
                // on the first observed gradient beat, then advance every cycle so late
                // duplicate valid beats do not corrupt the accumulated bias value.
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    if(rd_grad_bias_value_phase >= j && rd_grad_bias_value_phase < rd_grad_bias_row_size + j && j < rd_grad_bias_col_size) begin
                        value_old_in[j] <= ub_memory[rd_grad_bias_ptr + j];
                    end else begin
                        value_old_in[j] <= '0;
                    end
                end
                if (!rd_grad_bias_started) begin
                    if (ub_wr_valid_in[0] || ub_wr_valid_in[1]) begin
                        rd_grad_bias_started <= 1'b1;
                        rd_grad_bias_time_counter <= rd_grad_bias_time_counter + 1;
                    end
                end else begin
                    rd_grad_bias_time_counter <= rd_grad_bias_time_counter + 1;
                end
            end else if (rd_grad_weight_time_counter + 1 < rd_grad_weight_row_size + rd_grad_weight_col_size) begin
                // Weight: for loop decrements (lane1 first)
                for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
                    if(rd_grad_weight_time_counter >= j && rd_grad_weight_time_counter < rd_grad_weight_row_size + j && j < rd_grad_weight_col_size) begin
                        value_old_in[j] <= ub_memory[rd_gw_lane_addr[j]];
                    end else begin
                        value_old_in[j] <= '0;
                    end
                end
                rd_grad_weight_ptr <= rd_grad_weight_ptr_next;
                rd_grad_weight_time_counter <= rd_grad_weight_time_counter + 1;
            end else if (rd_grad_weight_time_counter + 1 == rd_grad_weight_row_size + rd_grad_weight_col_size) begin
                // Weight hold cycle: preserve outputs
                rd_grad_weight_time_counter <= rd_grad_weight_time_counter + 1;
            end else if (!(ub_rd_start_in && (ub_ptr_select == 5 || ub_ptr_select == 6))) begin
                // Reset after hold cycle
                rd_grad_bias_row_size <= 0;
                rd_grad_bias_col_size <= 0;
                rd_grad_bias_time_counter <= '0;
                rd_grad_bias_started <= 1'b0;
                rd_grad_weight_ptr <= 0;
                rd_grad_weight_row_size <= 0;
                rd_grad_weight_col_size <= 0;
                rd_grad_weight_time_counter <= '0;
                for (int j = 0; j < SYSTOLIC_ARRAY_WIDTH; j++) begin
                    value_old_in[j] <= '0;
                end
            end
        end
    end

endmodule