`timescale 1ns / 1ps
`default_nettype none

module tpu_stage2_tinytpu_exec #(
    parameter integer INPUT_MEM_WORDS  = 256,
    parameter integer PARAM_MEM_WORDS  = 8192,
    parameter integer OUTPUT_MEM_WORDS = 256,
    parameter integer TINYTPU_UB_DEPTH = 16,
    parameter integer WAIT_VALID_LIMIT = 64
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear_pulse,
    input  wire        exec_start_pulse,

    input  wire [31:0] net_id,
    input  wire [31:0] flags,
    input  wire [31:0] input_words,
    input  wire [31:0] output_words,

    input  wire        input_word_valid,
    input  wire [31:0] input_word,
    input  wire        param_word_valid,
    input  wire [31:0] param_word,

    input  wire [31:0] output_word_index,

    output reg         exec_busy,
    output reg         exec_done,
    output reg         exec_error,

    output reg  [31:0] input_word_count,
    output reg  [31:0] input_checksum,
    output reg  [31:0] input_last_word,
    output reg  [31:0] param_word_count,
    output reg  [31:0] param_checksum,
    output reg  [31:0] param_last_word,
    output wire [31:0] output_word
);

    localparam integer TPU_DESC_F_RELU_BIT         = 0;
    localparam integer TPU_DESC_F_TILE2X2_Q8_8_BIT = 16;

    localparam [4:0]
        EX_IDLE         = 5'd0,
        EX_CORE_RESET   = 5'd1,
        EX_LOAD_X0      = 5'd2,
        EX_LOAD_X1      = 5'd3,
        EX_LOAD_W00     = 5'd4,
        EX_LOAD_W10     = 5'd5,
        EX_LOAD_W01     = 5'd6,
        EX_LOAD_W11     = 5'd7,
        EX_ISSUE_WREAD  = 5'd8,
        EX_WAIT_WLOAD   = 5'd9,
        EX_SWITCH       = 5'd10,
        EX_WAIT_SW0     = 5'd11,
        EX_WAIT_SW1     = 5'd12,
        EX_ISSUE_INPUT  = 5'd13,
        EX_WAIT_VALID   = 5'd14,
        EX_STORE_TILE   = 5'd15,
        EX_STORE_OUTPUT = 5'd16,
        EX_NEXT_OUTPUT  = 5'd17,
        EX_FINISH       = 5'd18,
        EX_FAIL         = 5'd19;

    reg [4:0] exec_state_reg;

    reg [31:0] input_mem [0:INPUT_MEM_WORDS-1];
    reg [31:0] param_mem [0:PARAM_MEM_WORDS-1];
    reg [31:0] output_mem[0:OUTPUT_MEM_WORDS-1];

    integer mem_idx;

    reg [31:0] out_word_idx_reg;
    reg [31:0] tile_word_idx_reg;
    reg [31:0] wait_counter_reg;

    reg signed [31:0] accum0_reg;
    reg signed [31:0] accum1_reg;
    reg               tile_seen_out0_reg;
    reg               tile_seen_out1_reg;

    reg        core_rst_pulse;
    reg [15:0] ub_wr_host_data_in [0:1];
    reg        ub_wr_host_valid_in[0:1];
    reg        ub_wr_ptr_restore_in;
    reg        ub_rd_start_in;
    reg        ub_rd_transpose;
    reg [8:0]  ub_ptr_select;
    reg [15:0] ub_rd_addr_in;
    reg [15:0] ub_rd_row_size;
    reg [15:0] ub_rd_col_size;
    reg [15:0] learning_rate_in;
    reg [3:0]  vpu_data_pathway;
    reg        sys_switch_in;
    reg [15:0] vpu_leak_factor_in;
    reg [15:0] inv_batch_size_times_two_in;

    wire [15:0] vpu_data_out_1;
    wire [15:0] vpu_data_out_2;
    wire        vpu_valid_out_1;
    wire        vpu_valid_out_2;
    wire [15:0] sys_data_out_21;
    wire [15:0] sys_data_out_22;
    wire        sys_valid_out_21;
    wire        sys_valid_out_22;
    wire [15:0] ub_rd_input_data_out_0;
    wire [15:0] ub_rd_input_data_out_1;
    wire        ub_rd_input_valid_out_0;
    wire        ub_rd_input_valid_out_1;
    wire [15:0] ub_rd_weight_data_out_0;
    wire [15:0] ub_rd_weight_data_out_1;
    wire        ub_rd_weight_valid_out_0;
    wire        ub_rd_weight_valid_out_1;

    wire        core_rst;
    reg  [31:0] tile_stride_words_comb;
    reg  [31:0] tile_param_base_comb;
    reg  [31:0] tile_param_word0_comb;
    reg  [31:0] tile_param_word1_comb;
    reg  [31:0] tile_bias_word_comb;
    reg  signed [31:0] final_accum0_comb;
    reg  signed [31:0] final_accum1_comb;
    reg  signed [15:0] final_word0_comb;
    reg  signed [15:0] final_word1_comb;
    reg  [31:0] final_output_word_comb;

    assign core_rst = (~rst_n) | clear_pulse | core_rst_pulse;

    function signed [15:0] sat_q8_8_16;
        input signed [31:0] value;
        begin
            if(value > 32'sd32767) begin
                sat_q8_8_16 = 16'sh7fff;
            end else if(value < -32'sd32768) begin
                sat_q8_8_16 = 16'sh8000;
            end else begin
                sat_q8_8_16 = value[15:0];
            end
        end
    endfunction

    wire [31:0] param_words_needed;
    assign param_words_needed = output_words * ((input_words << 1) + 32'd1);

    assign output_word = (output_word_index < OUTPUT_MEM_WORDS) ? output_mem[output_word_index] : 32'd0;

    always @(*) begin
        tile_stride_words_comb = (input_words << 1) + 32'd1;
        tile_param_base_comb   = out_word_idx_reg * tile_stride_words_comb;
        tile_param_word0_comb  = 32'd0;
        tile_param_word1_comb  = 32'd0;
        tile_bias_word_comb    = 32'd0;

        if((tile_param_base_comb + (tile_word_idx_reg << 1)) < PARAM_MEM_WORDS) begin
            tile_param_word0_comb = param_mem[tile_param_base_comb + (tile_word_idx_reg << 1)];
        end

        if((tile_param_base_comb + (tile_word_idx_reg << 1) + 32'd1) < PARAM_MEM_WORDS) begin
            tile_param_word1_comb = param_mem[tile_param_base_comb + (tile_word_idx_reg << 1) + 32'd1];
        end

        if((tile_param_base_comb + (input_words << 1)) < PARAM_MEM_WORDS) begin
            tile_bias_word_comb = param_mem[tile_param_base_comb + (input_words << 1)];
        end

        final_accum0_comb = accum0_reg + $signed({{16{tile_bias_word_comb[15]}}, tile_bias_word_comb[15:0]});
        final_accum1_comb = accum1_reg + $signed({{16{tile_bias_word_comb[31]}}, tile_bias_word_comb[31:16]});

        if(flags[TPU_DESC_F_RELU_BIT] && (final_accum0_comb < 32'sd0)) begin
            final_word0_comb = 16'sd0;
        end else begin
            final_word0_comb = sat_q8_8_16(final_accum0_comb);
        end

        if(flags[TPU_DESC_F_RELU_BIT] && (final_accum1_comb < 32'sd0)) begin
            final_word1_comb = 16'sd0;
        end else begin
            final_word1_comb = sat_q8_8_16(final_accum1_comb);
        end

        final_output_word_comb = {final_word1_comb[15:0], final_word0_comb[15:0]};
    end

    tpu #(
        .SYSTOLIC_ARRAY_WIDTH(2),
        .UNIFIED_BUFFER_DEPTH(TINYTPU_UB_DEPTH)
    ) real_tpu_u (
        .clk(clk),
        .rst(core_rst),
        .ub_wr_host_data_in(ub_wr_host_data_in),
        .ub_wr_host_valid_in(ub_wr_host_valid_in),
        .ub_wr_ptr_restore_in(ub_wr_ptr_restore_in),
        .ub_rd_start_in(ub_rd_start_in),
        .ub_rd_transpose(ub_rd_transpose),
        .ub_ptr_select(ub_ptr_select),
        .ub_rd_addr_in(ub_rd_addr_in),
        .ub_rd_row_size(ub_rd_row_size),
        .ub_rd_col_size(ub_rd_col_size),
        .learning_rate_in(learning_rate_in),
        .vpu_data_pathway(vpu_data_pathway),
        .sys_switch_in(sys_switch_in),
        .vpu_leak_factor_in(vpu_leak_factor_in),
        .inv_batch_size_times_two_in(inv_batch_size_times_two_in),
        .vpu_data_out_1(vpu_data_out_1),
        .vpu_data_out_2(vpu_data_out_2),
        .vpu_valid_out_1(vpu_valid_out_1),
        .vpu_valid_out_2(vpu_valid_out_2),
        .sys_data_out_21(sys_data_out_21),
        .sys_data_out_22(sys_data_out_22),
        .sys_valid_out_21(sys_valid_out_21),
        .sys_valid_out_22(sys_valid_out_22),
        .ub_rd_input_data_out_0(ub_rd_input_data_out_0),
        .ub_rd_input_data_out_1(ub_rd_input_data_out_1),
        .ub_rd_input_valid_out_0(ub_rd_input_valid_out_0),
        .ub_rd_input_valid_out_1(ub_rd_input_valid_out_1),
        .ub_rd_weight_data_out_0(ub_rd_weight_data_out_0),
        .ub_rd_weight_data_out_1(ub_rd_weight_data_out_1),
        .ub_rd_weight_valid_out_0(ub_rd_weight_valid_out_0),
        .ub_rd_weight_valid_out_1(ub_rd_weight_valid_out_1)
    );

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            exec_state_reg   <= EX_IDLE;
            exec_busy        <= 1'b0;
            exec_done        <= 1'b0;
            exec_error       <= 1'b0;
            input_word_count <= 32'd0;
            input_checksum   <= 32'd0;
            input_last_word  <= 32'd0;
            param_word_count <= 32'd0;
            param_checksum   <= 32'd0;
            param_last_word  <= 32'd0;
            out_word_idx_reg <= 32'd0;
            tile_word_idx_reg <= 32'd0;
            wait_counter_reg <= 32'd0;
            accum0_reg       <= 32'sd0;
            accum1_reg       <= 32'sd0;
            tile_seen_out0_reg <= 1'b0;
            tile_seen_out1_reg <= 1'b0;
            core_rst_pulse   <= 1'b0;
            ub_wr_ptr_restore_in <= 1'b0;
            ub_rd_start_in   <= 1'b0;
            ub_rd_transpose  <= 1'b0;
            ub_ptr_select    <= 9'd0;
            ub_rd_addr_in    <= 16'd0;
            ub_rd_row_size   <= 16'd0;
            ub_rd_col_size   <= 16'd0;
            learning_rate_in <= 16'd0;
            vpu_data_pathway <= 4'b0000;
            sys_switch_in    <= 1'b0;
            vpu_leak_factor_in <= 16'd0;
            inv_batch_size_times_two_in <= 16'd0;
            ub_wr_host_data_in[0]  <= 16'd0;
            ub_wr_host_data_in[1]  <= 16'd0;
            ub_wr_host_valid_in[0] <= 1'b0;
            ub_wr_host_valid_in[1] <= 1'b0;
            for(mem_idx = 0; mem_idx < INPUT_MEM_WORDS; mem_idx = mem_idx + 1) begin
                input_mem[mem_idx] <= 32'd0;
            end
            for(mem_idx = 0; mem_idx < PARAM_MEM_WORDS; mem_idx = mem_idx + 1) begin
                param_mem[mem_idx] <= 32'd0;
            end
            for(mem_idx = 0; mem_idx < OUTPUT_MEM_WORDS; mem_idx = mem_idx + 1) begin
                output_mem[mem_idx] <= 32'd0;
            end
        end else if(clear_pulse) begin
            exec_state_reg   <= EX_IDLE;
            exec_busy        <= 1'b0;
            exec_done        <= 1'b0;
            exec_error       <= 1'b0;
            input_word_count <= 32'd0;
            input_checksum   <= 32'd0;
            input_last_word  <= 32'd0;
            param_word_count <= 32'd0;
            param_checksum   <= 32'd0;
            param_last_word  <= 32'd0;
            out_word_idx_reg <= 32'd0;
            tile_word_idx_reg <= 32'd0;
            wait_counter_reg <= 32'd0;
            accum0_reg       <= 32'sd0;
            accum1_reg       <= 32'sd0;
            tile_seen_out0_reg <= 1'b0;
            tile_seen_out1_reg <= 1'b0;
            core_rst_pulse   <= 1'b0;
            ub_wr_ptr_restore_in <= 1'b0;
            ub_rd_start_in   <= 1'b0;
            ub_rd_transpose  <= 1'b0;
            ub_ptr_select    <= 9'd0;
            ub_rd_addr_in    <= 16'd0;
            ub_rd_row_size   <= 16'd0;
            ub_rd_col_size   <= 16'd0;
            learning_rate_in <= 16'd0;
            vpu_data_pathway <= 4'b0000;
            sys_switch_in    <= 1'b0;
            vpu_leak_factor_in <= 16'd0;
            inv_batch_size_times_two_in <= 16'd0;
            ub_wr_host_data_in[0]  <= 16'd0;
            ub_wr_host_data_in[1]  <= 16'd0;
            ub_wr_host_valid_in[0] <= 1'b0;
            ub_wr_host_valid_in[1] <= 1'b0;
            for(mem_idx = 0; mem_idx < INPUT_MEM_WORDS; mem_idx = mem_idx + 1) begin
                input_mem[mem_idx] <= 32'd0;
            end
            for(mem_idx = 0; mem_idx < PARAM_MEM_WORDS; mem_idx = mem_idx + 1) begin
                param_mem[mem_idx] <= 32'd0;
            end
            for(mem_idx = 0; mem_idx < OUTPUT_MEM_WORDS; mem_idx = mem_idx + 1) begin
                output_mem[mem_idx] <= 32'd0;
            end
        end else begin
            core_rst_pulse          <= 1'b0;
            ub_wr_ptr_restore_in    <= 1'b0;
            ub_rd_start_in          <= 1'b0;
            ub_rd_transpose         <= 1'b0;
            ub_ptr_select           <= 9'd0;
            ub_rd_addr_in           <= 16'd0;
            ub_rd_row_size          <= 16'd0;
            ub_rd_col_size          <= 16'd0;
            sys_switch_in           <= 1'b0;
            ub_wr_host_valid_in[0]  <= 1'b0;
            ub_wr_host_valid_in[1]  <= 1'b0;
            exec_done               <= 1'b0;
            learning_rate_in        <= 16'd0;
            vpu_data_pathway        <= 4'b0000;
            vpu_leak_factor_in      <= 16'd0;
            inv_batch_size_times_two_in <= 16'd0;

            if(input_word_valid) begin
                input_word_count <= input_word_count + 32'd1;
                input_checksum   <= input_checksum + input_word;
                input_last_word  <= input_word;
                if(input_word_count < INPUT_MEM_WORDS) begin
                    input_mem[input_word_count] <= input_word;
                end
            end

            if(param_word_valid) begin
                param_word_count <= param_word_count + 32'd1;
                param_checksum   <= param_checksum + param_word;
                param_last_word  <= param_word;
                if(param_word_count < PARAM_MEM_WORDS) begin
                    param_mem[param_word_count] <= param_word;
                end
            end

            case(exec_state_reg)
                EX_IDLE: begin
                    exec_busy <= 1'b0;
                    if(exec_start_pulse) begin
                        exec_done  <= 1'b0;
                        exec_error <= 1'b0;
                        out_word_idx_reg  <= 32'd0;
                        tile_word_idx_reg <= 32'd0;
                        wait_counter_reg  <= 32'd0;
                        accum0_reg        <= 32'sd0;
                        accum1_reg        <= 32'sd0;
                        tile_seen_out0_reg <= 1'b0;
                        tile_seen_out1_reg <= 1'b0;

                        if(!flags[TPU_DESC_F_TILE2X2_Q8_8_BIT] ||
                           (input_words == 32'd0) ||
                           (output_words == 32'd0) ||
                           (input_words > INPUT_MEM_WORDS) ||
                           (output_words > OUTPUT_MEM_WORDS) ||
                           (param_words_needed > PARAM_MEM_WORDS) ||
                           (param_word_count < param_words_needed)) begin
                            exec_error     <= 1'b1;
                            exec_state_reg <= EX_FAIL;
                        end else begin
                            exec_busy      <= 1'b1;
                            exec_state_reg <= EX_CORE_RESET;
                        end
                    end
                end

                EX_CORE_RESET: begin
                    core_rst_pulse <= 1'b1;
                    exec_state_reg <= EX_LOAD_X0;
                end

                EX_LOAD_X0: begin
                    ub_wr_host_data_in[0]  <= input_mem[tile_word_idx_reg][15:0];
                    ub_wr_host_valid_in[0] <= 1'b1;
                    exec_state_reg         <= EX_LOAD_X1;
                end

                EX_LOAD_X1: begin
                    ub_wr_host_data_in[0]  <= input_mem[tile_word_idx_reg][31:16];
                    ub_wr_host_valid_in[0] <= 1'b1;
                    exec_state_reg         <= EX_LOAD_W00;
                end

                EX_LOAD_W00: begin
                    ub_wr_host_data_in[1]  <= tile_param_word0_comb[15:0];
                    ub_wr_host_data_in[0]  <= tile_param_word0_comb[31:16];
                    ub_wr_host_valid_in[1] <= 1'b1;
                    ub_wr_host_valid_in[0] <= 1'b1;
                    exec_state_reg         <= EX_LOAD_W10;
                end

                EX_LOAD_W10: begin
                    ub_wr_host_data_in[1]  <= tile_param_word1_comb[15:0];
                    ub_wr_host_data_in[0]  <= tile_param_word1_comb[31:16];
                    ub_wr_host_valid_in[1] <= 1'b1;
                    ub_wr_host_valid_in[0] <= 1'b1;
                    exec_state_reg         <= EX_ISSUE_WREAD;
                end

                EX_LOAD_W01: begin
                    exec_state_reg <= EX_ISSUE_WREAD;
                end

                EX_LOAD_W11: begin
                    exec_state_reg <= EX_ISSUE_WREAD;
                end

                EX_ISSUE_WREAD: begin
                    ub_rd_start_in  <= 1'b1;
                    ub_rd_transpose <= 1'b1;
                    ub_ptr_select   <= 9'd1;
                    ub_rd_addr_in   <= 16'd2;
                    ub_rd_row_size  <= 16'd2;
                    ub_rd_col_size  <= 16'd2;
                    wait_counter_reg <= 32'd0;
                    exec_state_reg  <= EX_WAIT_WLOAD;
                end

                EX_WAIT_WLOAD: begin
                    if(wait_counter_reg >= 32'd3) begin
                        exec_state_reg <= EX_SWITCH;
                    end else begin
                        wait_counter_reg <= wait_counter_reg + 32'd1;
                    end
                end

                EX_SWITCH: begin
                    sys_switch_in   <= 1'b1;
                    exec_state_reg  <= EX_WAIT_SW0;
                end

                EX_WAIT_SW0: begin
                    exec_state_reg <= EX_WAIT_SW1;
                end

                EX_WAIT_SW1: begin
                    exec_state_reg <= EX_ISSUE_INPUT;
                end

                EX_ISSUE_INPUT: begin
                    ub_rd_start_in  <= 1'b1;
                    ub_rd_transpose <= 1'b0;
                    ub_ptr_select   <= 9'd0;
                    ub_rd_addr_in   <= 16'd0;
                    ub_rd_row_size  <= 16'd1;
                    ub_rd_col_size  <= 16'd2;
                    wait_counter_reg   <= 32'd0;
                    tile_seen_out0_reg <= 1'b0;
                    tile_seen_out1_reg <= 1'b0;
                    exec_state_reg    <= EX_WAIT_VALID;
                end

                EX_WAIT_VALID: begin
                    if(vpu_valid_out_1 && !tile_seen_out0_reg) begin
                        accum0_reg <= accum0_reg + $signed({{16{vpu_data_out_1[15]}}, vpu_data_out_1});
                        tile_seen_out0_reg <= 1'b1;
                    end

                    if(vpu_valid_out_2 && !tile_seen_out1_reg) begin
                        accum1_reg <= accum1_reg + $signed({{16{vpu_data_out_2[15]}}, vpu_data_out_2});
                        tile_seen_out1_reg <= 1'b1;
                    end

                    if((tile_seen_out0_reg || vpu_valid_out_1) &&
                       (tile_seen_out1_reg || vpu_valid_out_2)) begin
                        exec_state_reg <= EX_STORE_TILE;
                    end else if(wait_counter_reg >= WAIT_VALID_LIMIT) begin
                        exec_error     <= 1'b1;
                        exec_busy      <= 1'b0;
                        exec_state_reg <= EX_FAIL;
                    end else begin
                        wait_counter_reg <= wait_counter_reg + 32'd1;
                    end
                end

                EX_STORE_TILE: begin
                    if(tile_word_idx_reg + 32'd1 >= input_words) begin
                        exec_state_reg <= EX_STORE_OUTPUT;
                    end else begin
                        tile_word_idx_reg <= tile_word_idx_reg + 32'd1;
                        exec_state_reg    <= EX_CORE_RESET;
                    end
                end

                EX_STORE_OUTPUT: begin
                    output_mem[out_word_idx_reg] <= final_output_word_comb;
                    exec_state_reg               <= EX_NEXT_OUTPUT;
                end

                EX_NEXT_OUTPUT: begin
                    if(out_word_idx_reg + 32'd1 >= output_words) begin
                        exec_busy      <= 1'b0;
                        exec_done      <= 1'b1;
                        exec_state_reg <= EX_FINISH;
                    end else begin
                        out_word_idx_reg  <= out_word_idx_reg + 32'd1;
                        tile_word_idx_reg <= 32'd0;
                        accum0_reg        <= 32'sd0;
                        accum1_reg        <= 32'sd0;
                        tile_seen_out0_reg <= 1'b0;
                        tile_seen_out1_reg <= 1'b0;
                        exec_state_reg    <= EX_CORE_RESET;
                    end
                end

                EX_FINISH: begin
                    exec_state_reg <= EX_IDLE;
                end

                EX_FAIL: begin
                    exec_busy      <= 1'b0;
                    exec_state_reg <= EX_IDLE;
                end

                default: begin
                    exec_state_reg <= EX_IDLE;
                end
             endcase
         end
     end
 
 endmodule
 
 `default_nettype wire
