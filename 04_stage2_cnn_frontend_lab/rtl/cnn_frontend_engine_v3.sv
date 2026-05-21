`timescale 1ns / 1ps
`default_nettype none

module cnn_frontend_engine_v3 #(
    parameter integer SIGNAL_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_SIGNAL_WORDS,
    parameter integer FEATURE_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FEATURE_WORDS,
    parameter integer CONV1_WEIGHT_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_WEIGHT_WORDS,
    parameter integer CONV1_BIAS_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_BIAS_WORDS,
    parameter integer CONV2_WEIGHT_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_WEIGHT_WORDS,
    parameter integer CONV2_BIAS_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_BIAS_WORDS,
    parameter integer CONV3_WEIGHT_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV3_WEIGHT_WORDS,
    parameter integer CONV3_BIAS_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV3_BIAS_WORDS,
    parameter integer CONV4_WEIGHT_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV4_WEIGHT_WORDS,
    parameter integer CONV4_BIAS_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV4_BIAS_WORDS,
    parameter integer FILM_L0_W_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L0_W_WORDS,
    parameter integer FILM_L0_B_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L0_B_WORDS,
    parameter integer FILM_L2_W_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L2_W_WORDS,
    parameter integer FILM_L2_B_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L2_B_WORDS,
    parameter integer CONV1_IN_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_IN_CH,
    parameter integer CONV1_IN_LEN =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_IN_LEN,
    parameter integer CONV1_OUT_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_OUT_CH,
    parameter integer CONV1_KERNEL =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_KERNEL,
    parameter integer CONV1_PAD =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_PAD,
    parameter integer CONV2_IN_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_IN_CH,
    parameter integer CONV2_IN_LEN =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_IN_LEN,
    parameter integer CONV2_OUT_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_OUT_CH,
    parameter integer CONV2_KERNEL =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_KERNEL,
    parameter integer CONV2_PAD =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_PAD,
    parameter integer CONV3_IN_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV3_IN_CH,
    parameter integer CONV3_IN_LEN =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV3_IN_LEN,
    parameter integer CONV3_OUT_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV3_OUT_CH,
    parameter integer CONV3_KERNEL =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV3_KERNEL,
    parameter integer CONV3_PAD =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV3_PAD,
    parameter integer CONV4_IN_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV4_IN_CH,
    parameter integer CONV4_IN_LEN =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV4_IN_LEN,
    parameter integer CONV4_OUT_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV4_OUT_CH,
    parameter integer CONV4_KERNEL =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV4_KERNEL,
    parameter integer CONV4_PAD =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV4_PAD,
    parameter integer FILM_HIDDEN_VALUES =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_HIDDEN_VALUES,
    parameter integer FILM_OUT_VALUES =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_OUT_VALUES
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        soft_reset_pulse,

    input  wire        signal_wr_valid,
    input  wire [15:0] signal_wr_addr,
    input  wire [31:0] signal_wr_data,
    input  wire        feature_wr_valid,
    input  wire [15:0] feature_wr_addr,
    input  wire [31:0] feature_wr_data,
    input  wire        conv1_weight_wr_valid,
    input  wire [15:0] conv1_weight_wr_addr,
    input  wire [31:0] conv1_weight_wr_data,
    input  wire        conv1_bias_wr_valid,
    input  wire [15:0] conv1_bias_wr_addr,
    input  wire [31:0] conv1_bias_wr_data,
    input  wire        conv2_weight_wr_valid,
    input  wire [15:0] conv2_weight_wr_addr,
    input  wire [31:0] conv2_weight_wr_data,
    input  wire        conv2_bias_wr_valid,
    input  wire [15:0] conv2_bias_wr_addr,
    input  wire [31:0] conv2_bias_wr_data,
    input  wire        conv3_weight_wr_valid,
    input  wire [15:0] conv3_weight_wr_addr,
    input  wire [31:0] conv3_weight_wr_data,
    input  wire        conv3_bias_wr_valid,
    input  wire [15:0] conv3_bias_wr_addr,
    input  wire [31:0] conv3_bias_wr_data,
    input  wire        conv4_weight_wr_valid,
    input  wire [15:0] conv4_weight_wr_addr,
    input  wire [31:0] conv4_weight_wr_data,
    input  wire        conv4_bias_wr_valid,
    input  wire [15:0] conv4_bias_wr_addr,
    input  wire [31:0] conv4_bias_wr_data,
    input  wire        film_l0_weight_wr_valid,
    input  wire [15:0] film_l0_weight_wr_addr,
    input  wire [31:0] film_l0_weight_wr_data,
    input  wire        film_l0_bias_wr_valid,
    input  wire [15:0] film_l0_bias_wr_addr,
    input  wire [31:0] film_l0_bias_wr_data,
    input  wire        film_l2_weight_wr_valid,
    input  wire [15:0] film_l2_weight_wr_addr,
    input  wire [31:0] film_l2_weight_wr_data,
    input  wire        film_l2_bias_wr_valid,
    input  wire [15:0] film_l2_bias_wr_addr,
    input  wire [31:0] film_l2_bias_wr_data,

    input  wire        start_valid,
    output wire        start_ready,
    input  wire [31:0] signal_addr,
    input  wire [31:0] feature_addr,
    input  wire [31:0] output_addr,
    input  wire [31:0] scratch_addr,
    input  wire [31:0] input_words,
    input  wire [31:0] output_words,
    input  wire [31:0] flags,

    output wire        busy,
    output wire        done_pulse,
    output wire        error_pulse,
    output wire [2:0]  phase_dbg,
    output wire [31:0] cycle_count_dbg,

    input  wire [1:0]  output_rd_bank,
    input  wire [15:0] output_rd_addr,
    output wire [31:0] output_rd_data
);

    localparam integer CONV1_POOLED_LEN = CONV1_IN_LEN / 2;
    localparam integer CONV2_POOLED_LEN = CONV2_IN_LEN / 2;
    localparam integer CONV3_POOLED_LEN = CONV3_IN_LEN / 2;
    localparam integer PHASE1_VALUES = CONV1_OUT_CH * CONV1_POOLED_LEN;
    localparam integer PHASE1_WORDS = PHASE1_VALUES / 2;
    localparam integer PHASE2_VALUES = CONV2_OUT_CH * CONV2_POOLED_LEN;
    localparam integer PHASE2_WORDS = PHASE2_VALUES / 2;
    localparam integer PHASE3_VALUES = CONV3_OUT_CH * CONV3_POOLED_LEN;
    localparam integer PHASE3_WORDS = PHASE3_VALUES / 2;
    localparam integer FINAL_WORDS = CONV4_OUT_CH / 2;

    localparam [2:0] EST_IDLE  = 3'd0;
    localparam [2:0] EST_CONV1 = 3'd1;
    localparam [2:0] EST_FILM0 = 3'd2;
    localparam [2:0] EST_FILM2 = 3'd3;
    localparam [2:0] EST_CONV2 = 3'd4;
    localparam [2:0] EST_CONV3 = 3'd5;
    localparam [2:0] EST_CONV4 = 3'd6;

    reg [31:0] signal_words_mem [0:SIGNAL_WORDS-1];
    reg [31:0] feature_words_mem [0:FEATURE_WORDS-1];
    reg [31:0] conv1_weight_words_mem [0:CONV1_WEIGHT_WORDS-1];
    reg [31:0] conv1_bias_words_mem [0:CONV1_BIAS_WORDS-1];
    reg [31:0] conv2_weight_words_mem [0:CONV2_WEIGHT_WORDS-1];
    reg [31:0] conv2_bias_words_mem [0:CONV2_BIAS_WORDS-1];
    reg [31:0] conv3_weight_words_mem [0:CONV3_WEIGHT_WORDS-1];
    reg [31:0] conv3_bias_words_mem [0:CONV3_BIAS_WORDS-1];
    reg [31:0] conv4_weight_words_mem [0:CONV4_WEIGHT_WORDS-1];
    reg [31:0] conv4_bias_words_mem [0:CONV4_BIAS_WORDS-1];
    reg [31:0] film_l0_weight_words_mem [0:FILM_L0_W_WORDS-1];
    reg [31:0] film_l0_bias_words_mem [0:FILM_L0_B_WORDS-1];
    reg [31:0] film_l2_weight_words_mem [0:FILM_L2_W_WORDS-1];
    reg [31:0] film_l2_bias_words_mem [0:FILM_L2_B_WORDS-1];
    reg [31:0] phase1_words_mem [0:PHASE1_WORDS-1];
    reg [31:0] phase2_words_mem [0:PHASE2_WORDS-1];
    reg [31:0] phase3_words_mem [0:PHASE3_WORDS-1];
    reg [31:0] final_words_mem [0:FINAL_WORDS-1];

    reg signed [15:0] film_hidden_mem [0:FILM_HIDDEN_VALUES-1];
    reg signed [15:0] film_out_mem [0:FILM_OUT_VALUES-1];

    reg        busy_reg;
    reg        done_pulse_reg;
    reg        error_pulse_reg;
    reg [2:0]  phase_reg;
    reg [31:0] cycle_count_reg;
    reg [2:0]  exec_state_reg;

    reg [15:0] conv1_oc_reg;
    reg [15:0] conv1_pool_reg;
    reg        conv1_pass_reg;
    reg [15:0] conv1_k_reg;
    reg signed [47:0] conv1_acc_reg;
    reg signed [15:0] conv1_y0_reg;

    reg [15:0] film0_oc_reg;
    reg [15:0] film0_i_reg;
    reg signed [47:0] film0_acc_reg;

    reg [15:0] film2_oc_reg;
    reg [15:0] film2_i_reg;
    reg signed [47:0] film2_acc_reg;

    reg [15:0] conv2_oc_reg;
    reg [15:0] conv2_pool_reg;
    reg        conv2_pass_reg;
    reg [15:0] conv2_ic_reg;
    reg [15:0] conv2_k_reg;
    reg signed [47:0] conv2_acc_reg;
    reg signed [15:0] conv2_y0_reg;

    reg [15:0] conv3_oc_reg;
    reg [15:0] conv3_pool_reg;
    reg        conv3_pass_reg;
    reg [15:0] conv3_ic_reg;
    reg [15:0] conv3_k_reg;
    reg signed [47:0] conv3_acc_reg;
    reg signed [15:0] conv3_y0_reg;

    reg [15:0] conv4_oc_reg;
    reg [15:0] conv4_pos_reg;
    reg [15:0] conv4_ic_reg;
    reg [15:0] conv4_k_reg;
    reg signed [47:0] conv4_acc_reg;
    reg signed [47:0] conv4_sum_reg;

    reg signed [15:0] data_q16;
    reg signed [15:0] weight_q16;
    reg signed [15:0] bias_q16;
    reg signed [15:0] out_q16;
    reg signed [15:0] gamma_q16;
    reg signed [15:0] beta_q16;
    reg signed [31:0] scale_q16;
    reg signed [47:0] acc_next;
    reg signed [47:0] mod_next;

    integer idx_int;
    integer input_pos_int;
    integer weight_idx_int;
    integer output_value_idx_int;
    integer output_word_idx_int;

    wire start_accept;
    wire bad_launch;

    function automatic signed [15:0] unpack_q16;
        input [31:0] word;
        input integer half_sel;
        begin
            if (half_sel != 0) begin
                unpack_q16 = word[31:16];
            end else begin
                unpack_q16 = word[15:0];
            end
        end
    endfunction

    function automatic signed [15:0] sat_q16_s48;
        input signed [47:0] value;
        begin
            if (value > 48'sd32767) begin
                sat_q16_s48 = 16'sd32767;
            end else if (value < -48'sd32768) begin
                sat_q16_s48 = -16'sd32768;
            end else begin
                sat_q16_s48 = value[15:0];
            end
        end
    endfunction

    function automatic signed [47:0] round_shift_s48;
        input signed [47:0] value;
        input integer shift;
        reg signed [47:0] add;
        begin
            if (shift <= 0) begin
                round_shift_s48 = value;
            end else begin
                add = 48'sd1 <<< (shift - 1);
                if (value >= 0) begin
                    round_shift_s48 = (value + add) >>> shift;
                end else begin
                    round_shift_s48 = -(((-value) + add) >>> shift);
                end
            end
        end
    endfunction

    function automatic signed [15:0] read_signal_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = signal_words_mem[value_idx >> 1];
            read_signal_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_feature_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = feature_words_mem[value_idx >> 1];
            read_feature_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_conv1_weight_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = conv1_weight_words_mem[value_idx >> 1];
            read_conv1_weight_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_conv1_bias_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = conv1_bias_words_mem[value_idx >> 1];
            read_conv1_bias_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_phase1_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = phase1_words_mem[value_idx >> 1];
            read_phase1_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_conv2_weight_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = conv2_weight_words_mem[value_idx >> 1];
            read_conv2_weight_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_conv2_bias_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = conv2_bias_words_mem[value_idx >> 1];
            read_conv2_bias_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_conv3_weight_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = conv3_weight_words_mem[value_idx >> 1];
            read_conv3_weight_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_conv3_bias_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = conv3_bias_words_mem[value_idx >> 1];
            read_conv3_bias_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_conv4_weight_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = conv4_weight_words_mem[value_idx >> 1];
            read_conv4_weight_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_conv4_bias_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = conv4_bias_words_mem[value_idx >> 1];
            read_conv4_bias_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_phase2_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = phase2_words_mem[value_idx >> 1];
            read_phase2_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_phase3_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = phase3_words_mem[value_idx >> 1];
            read_phase3_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_film_l0_weight_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = film_l0_weight_words_mem[value_idx >> 1];
            read_film_l0_weight_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_film_l0_bias_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = film_l0_bias_words_mem[value_idx >> 1];
            read_film_l0_bias_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_film_l2_weight_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = film_l2_weight_words_mem[value_idx >> 1];
            read_film_l2_weight_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_film_l2_bias_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = film_l2_bias_words_mem[value_idx >> 1];
            read_film_l2_bias_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    assign start_ready = !busy_reg;
    assign start_accept = start_valid && start_ready;
    assign busy = busy_reg;
    assign done_pulse = done_pulse_reg;
    assign error_pulse = error_pulse_reg;
    assign phase_dbg = phase_reg;
    assign cycle_count_dbg = cycle_count_reg;

    assign output_rd_data =
        (output_rd_bank == 2'd0) ? phase1_words_mem[output_rd_addr] :
        (output_rd_bank == 2'd1) ? phase2_words_mem[output_rd_addr] :
        (output_rd_bank == 2'd2) ? phase3_words_mem[output_rd_addr] :
        final_words_mem[output_rd_addr];

    assign bad_launch =
        (signal_addr == 32'd0) ||
        (feature_addr == 32'd0) ||
        (output_addr == 32'd0) ||
        (scratch_addr == 32'd0) ||
        (input_words != SIGNAL_WORDS) ||
        (output_words == 32'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_reg        <= 1'b0;
            done_pulse_reg  <= 1'b0;
            error_pulse_reg <= 1'b0;
            phase_reg       <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_IDLE;
            cycle_count_reg <= 32'd0;
            exec_state_reg  <= EST_IDLE;
            conv1_oc_reg    <= 16'd0;
            conv1_pool_reg  <= 16'd0;
            conv1_pass_reg  <= 1'b0;
            conv1_k_reg     <= 16'd0;
            conv1_acc_reg   <= 48'sd0;
            conv1_y0_reg    <= 16'sd0;
            film0_oc_reg    <= 16'd0;
            film0_i_reg     <= 16'd0;
            film0_acc_reg   <= 48'sd0;
            film2_oc_reg    <= 16'd0;
            film2_i_reg     <= 16'd0;
            film2_acc_reg   <= 48'sd0;
            conv2_oc_reg    <= 16'd0;
            conv2_pool_reg  <= 16'd0;
            conv2_pass_reg  <= 1'b0;
            conv2_ic_reg    <= 16'd0;
            conv2_k_reg     <= 16'd0;
            conv2_acc_reg   <= 48'sd0;
            conv2_y0_reg    <= 16'sd0;
            conv3_oc_reg    <= 16'd0;
            conv3_pool_reg  <= 16'd0;
            conv3_pass_reg  <= 1'b0;
            conv3_ic_reg    <= 16'd0;
            conv3_k_reg     <= 16'd0;
            conv3_acc_reg   <= 48'sd0;
            conv3_y0_reg    <= 16'sd0;
            conv4_oc_reg    <= 16'd0;
            conv4_pos_reg   <= 16'd0;
            conv4_ic_reg    <= 16'd0;
            conv4_k_reg     <= 16'd0;
            conv4_acc_reg   <= 48'sd0;
            conv4_sum_reg   <= 48'sd0;
        end else begin
            if (signal_wr_valid) begin
                signal_words_mem[signal_wr_addr] <= signal_wr_data;
            end
            if (feature_wr_valid) begin
                feature_words_mem[feature_wr_addr] <= feature_wr_data;
            end
            if (conv1_weight_wr_valid) begin
                conv1_weight_words_mem[conv1_weight_wr_addr] <= conv1_weight_wr_data;
            end
            if (conv1_bias_wr_valid) begin
                conv1_bias_words_mem[conv1_bias_wr_addr] <= conv1_bias_wr_data;
            end
            if (conv2_weight_wr_valid) begin
                conv2_weight_words_mem[conv2_weight_wr_addr] <= conv2_weight_wr_data;
            end
            if (conv2_bias_wr_valid) begin
                conv2_bias_words_mem[conv2_bias_wr_addr] <= conv2_bias_wr_data;
            end
            if (conv3_weight_wr_valid) begin
                conv3_weight_words_mem[conv3_weight_wr_addr] <= conv3_weight_wr_data;
            end
            if (conv3_bias_wr_valid) begin
                conv3_bias_words_mem[conv3_bias_wr_addr] <= conv3_bias_wr_data;
            end
            if (conv4_weight_wr_valid) begin
                conv4_weight_words_mem[conv4_weight_wr_addr] <= conv4_weight_wr_data;
            end
            if (conv4_bias_wr_valid) begin
                conv4_bias_words_mem[conv4_bias_wr_addr] <= conv4_bias_wr_data;
            end
            if (film_l0_weight_wr_valid) begin
                film_l0_weight_words_mem[film_l0_weight_wr_addr] <= film_l0_weight_wr_data;
            end
            if (film_l0_bias_wr_valid) begin
                film_l0_bias_words_mem[film_l0_bias_wr_addr] <= film_l0_bias_wr_data;
            end
            if (film_l2_weight_wr_valid) begin
                film_l2_weight_words_mem[film_l2_weight_wr_addr] <= film_l2_weight_wr_data;
            end
            if (film_l2_bias_wr_valid) begin
                film_l2_bias_words_mem[film_l2_bias_wr_addr] <= film_l2_bias_wr_data;
            end

            done_pulse_reg <= 1'b0;
            error_pulse_reg <= 1'b0;

            if (soft_reset_pulse) begin
                busy_reg        <= 1'b0;
                phase_reg       <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_IDLE;
                cycle_count_reg <= 32'd0;
                exec_state_reg  <= EST_IDLE;
                conv4_sum_reg   <= 48'sd0;
            end else if (start_accept) begin
                if (bad_launch) begin
                    busy_reg        <= 1'b0;
                    error_pulse_reg <= 1'b1;
                    phase_reg       <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_IDLE;
                    cycle_count_reg <= 32'd0;
                    exec_state_reg  <= EST_IDLE;
                end else begin
                    busy_reg        <= 1'b1;
                    phase_reg       <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_CONV12;
                    cycle_count_reg <= 32'd0;
                    exec_state_reg  <= EST_CONV1;
                    conv1_oc_reg    <= 16'd0;
                    conv1_pool_reg  <= 16'd0;
                    conv1_pass_reg  <= 1'b0;
                    conv1_k_reg     <= 16'd0;
                    bias_q16        = read_conv1_bias_q16(0);
                    conv1_acc_reg   <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                end
            end else if (busy_reg) begin
                cycle_count_reg <= cycle_count_reg + 32'd1;

                case (exec_state_reg)
                    EST_CONV1: begin
                        input_pos_int = (conv1_pool_reg << 1) + conv1_pass_reg + conv1_k_reg - CONV1_PAD;
                        weight_idx_int = ((conv1_oc_reg * CONV1_IN_CH) * CONV1_KERNEL) + conv1_k_reg;
                        acc_next = conv1_acc_reg;

                        if ((input_pos_int >= 0) && (input_pos_int < CONV1_IN_LEN)) begin
                            data_q16 = read_signal_q16(input_pos_int);
                            weight_q16 = read_conv1_weight_q16(weight_idx_int);
                            acc_next = conv1_acc_reg + (data_q16 * weight_q16);
                        end

                        if (conv1_k_reg == (CONV1_KERNEL - 1)) begin
                            out_q16 = sat_q16_s48(round_shift_s48(acc_next, 8));
                            if (out_q16 < 0) begin
                                out_q16 = 16'sd0;
                            end

                            if (!conv1_pass_reg) begin
                                conv1_y0_reg <= out_q16;
                                conv1_pass_reg <= 1'b1;
                                conv1_k_reg <= 16'd0;
                                bias_q16 = read_conv1_bias_q16(conv1_oc_reg);
                                conv1_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                            end else begin
                                if (conv1_y0_reg >= out_q16) begin
                                    out_q16 = conv1_y0_reg;
                                end
                                output_value_idx_int = (conv1_oc_reg * CONV1_POOLED_LEN) + conv1_pool_reg;
                                output_word_idx_int = output_value_idx_int >> 1;
                                if ((output_value_idx_int & 1) != 0) begin
                                    phase1_words_mem[output_word_idx_int][31:16] <= out_q16;
                                end else begin
                                    phase1_words_mem[output_word_idx_int][15:0] <= out_q16;
                                end

                                conv1_pass_reg <= 1'b0;
                                conv1_k_reg <= 16'd0;

                                if (conv1_pool_reg == (CONV1_POOLED_LEN - 1)) begin
                                    conv1_pool_reg <= 16'd0;
                                    if (conv1_oc_reg == (CONV1_OUT_CH - 1)) begin
                                        exec_state_reg <= EST_FILM0;
                                        phase_reg <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_PRELOAD;
                                        film0_oc_reg <= 16'd0;
                                        film0_i_reg <= 16'd0;
                                        bias_q16 = read_film_l0_bias_q16(0);
                                        film0_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                    end else begin
                                        conv1_oc_reg <= conv1_oc_reg + 16'd1;
                                        bias_q16 = read_conv1_bias_q16(conv1_oc_reg + 1);
                                        conv1_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                    end
                                end else begin
                                    conv1_pool_reg <= conv1_pool_reg + 16'd1;
                                    bias_q16 = read_conv1_bias_q16(conv1_oc_reg);
                                    conv1_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                end
                            end
                        end else begin
                            conv1_acc_reg <= acc_next;
                            conv1_k_reg <= conv1_k_reg + 16'd1;
                        end
                    end

                    EST_FILM0: begin
                        idx_int = (film0_oc_reg * 2) + film0_i_reg;
                        acc_next = film0_acc_reg +
                            (read_feature_q16(film0_i_reg) * read_film_l0_weight_q16(idx_int));

                        if (film0_i_reg == 1) begin
                            out_q16 = sat_q16_s48(round_shift_s48(acc_next, 8));
                            if (out_q16 < 0) begin
                                out_q16 = 16'sd0;
                            end
                            film_hidden_mem[film0_oc_reg] <= out_q16;

                            if (film0_oc_reg == (FILM_HIDDEN_VALUES - 1)) begin
                                exec_state_reg <= EST_FILM2;
                                film2_oc_reg <= 16'd0;
                                film2_i_reg <= 16'd0;
                                bias_q16 = read_film_l2_bias_q16(0);
                                film2_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                            end else begin
                                film0_oc_reg <= film0_oc_reg + 16'd1;
                                film0_i_reg <= 16'd0;
                                bias_q16 = read_film_l0_bias_q16(film0_oc_reg + 1);
                                film0_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                            end
                        end else begin
                            film0_acc_reg <= acc_next;
                            film0_i_reg <= film0_i_reg + 16'd1;
                        end
                    end

                    EST_FILM2: begin
                        idx_int = (film2_oc_reg * FILM_HIDDEN_VALUES) + film2_i_reg;
                        acc_next = film2_acc_reg +
                            (film_hidden_mem[film2_i_reg] * read_film_l2_weight_q16(idx_int));

                        if (film2_i_reg == (FILM_HIDDEN_VALUES - 1)) begin
                            out_q16 = sat_q16_s48(round_shift_s48(acc_next, 8));
                            film_out_mem[film2_oc_reg] <= out_q16;

                            if (film2_oc_reg == (FILM_OUT_VALUES - 1)) begin
                                exec_state_reg <= EST_CONV2;
                                phase_reg <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_CONV12;
                                conv2_oc_reg <= 16'd0;
                                conv2_pool_reg <= 16'd0;
                                conv2_pass_reg <= 1'b0;
                                conv2_ic_reg <= 16'd0;
                                conv2_k_reg <= 16'd0;
                                bias_q16 = read_conv2_bias_q16(0);
                                conv2_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                            end else begin
                                film2_oc_reg <= film2_oc_reg + 16'd1;
                                film2_i_reg <= 16'd0;
                                bias_q16 = read_film_l2_bias_q16(film2_oc_reg + 1);
                                film2_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                            end
                        end else begin
                            film2_acc_reg <= acc_next;
                            film2_i_reg <= film2_i_reg + 16'd1;
                        end
                    end

                    EST_CONV2: begin
                        input_pos_int = (conv2_pool_reg << 1) + conv2_pass_reg + conv2_k_reg - CONV2_PAD;
                        weight_idx_int =
                            (((conv2_oc_reg * CONV2_IN_CH) + conv2_ic_reg) * CONV2_KERNEL) + conv2_k_reg;
                        acc_next = conv2_acc_reg;

                        if ((input_pos_int >= 0) && (input_pos_int < CONV2_IN_LEN)) begin
                            idx_int = (conv2_ic_reg * CONV2_IN_LEN) + input_pos_int;
                            data_q16 = read_phase1_q16(idx_int);
                            weight_q16 = read_conv2_weight_q16(weight_idx_int);
                            acc_next = conv2_acc_reg + (data_q16 * weight_q16);
                        end

                        if (conv2_k_reg == (CONV2_KERNEL - 1)) begin
                            if (conv2_ic_reg == (CONV2_IN_CH - 1)) begin
                                out_q16 = sat_q16_s48(round_shift_s48(acc_next, 8));
                                gamma_q16 = film_out_mem[conv2_oc_reg];
                                beta_q16 = film_out_mem[CONV2_OUT_CH + conv2_oc_reg];
                                scale_q16 = 32'sd256 + gamma_q16;
                                mod_next = round_shift_s48(scale_q16 * out_q16, 8) + beta_q16;
                                out_q16 = sat_q16_s48(mod_next);
                                if (out_q16 < 0) begin
                                    out_q16 = 16'sd0;
                                end

                                if (!conv2_pass_reg) begin
                                    conv2_y0_reg <= out_q16;
                                    conv2_pass_reg <= 1'b1;
                                    conv2_ic_reg <= 16'd0;
                                    conv2_k_reg <= 16'd0;
                                    bias_q16 = read_conv2_bias_q16(conv2_oc_reg);
                                    conv2_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                end else begin
                                    if (conv2_y0_reg >= out_q16) begin
                                        out_q16 = conv2_y0_reg;
                                    end
                                    output_value_idx_int = (conv2_oc_reg * CONV2_POOLED_LEN) + conv2_pool_reg;
                                    output_word_idx_int = output_value_idx_int >> 1;
                                    if ((output_value_idx_int & 1) != 0) begin
                                        phase2_words_mem[output_word_idx_int][31:16] <= out_q16;
                                    end else begin
                                        phase2_words_mem[output_word_idx_int][15:0] <= out_q16;
                                    end

                                    conv2_pass_reg <= 1'b0;
                                    conv2_ic_reg <= 16'd0;
                                    conv2_k_reg <= 16'd0;

                                    if (conv2_pool_reg == (CONV2_POOLED_LEN - 1)) begin
                                        conv2_pool_reg <= 16'd0;
                                        if (conv2_oc_reg == (CONV2_OUT_CH - 1)) begin
                                            exec_state_reg <= EST_CONV3;
                                            phase_reg <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_CONV34;
                                            conv3_oc_reg <= 16'd0;
                                            conv3_pool_reg <= 16'd0;
                                            conv3_pass_reg <= 1'b0;
                                            conv3_ic_reg <= 16'd0;
                                            conv3_k_reg <= 16'd0;
                                            bias_q16 = read_conv3_bias_q16(0);
                                            conv3_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                        end else begin
                                            conv2_oc_reg <= conv2_oc_reg + 16'd1;
                                            bias_q16 = read_conv2_bias_q16(conv2_oc_reg + 1);
                                            conv2_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                        end
                                    end else begin
                                        conv2_pool_reg <= conv2_pool_reg + 16'd1;
                                        bias_q16 = read_conv2_bias_q16(conv2_oc_reg);
                                        conv2_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                    end
                                end
                            end else begin
                                conv2_ic_reg <= conv2_ic_reg + 16'd1;
                                conv2_k_reg <= 16'd0;
                                conv2_acc_reg <= acc_next;
                            end
                        end else begin
                            conv2_k_reg <= conv2_k_reg + 16'd1;
                            conv2_acc_reg <= acc_next;
                        end
                    end

                    EST_CONV3: begin
                        input_pos_int = (conv3_pool_reg << 1) + conv3_pass_reg + conv3_k_reg - CONV3_PAD;
                        weight_idx_int =
                            (((conv3_oc_reg * CONV3_IN_CH) + conv3_ic_reg) * CONV3_KERNEL) + conv3_k_reg;
                        acc_next = conv3_acc_reg;

                        if ((input_pos_int >= 0) && (input_pos_int < CONV3_IN_LEN)) begin
                            idx_int = (conv3_ic_reg * CONV3_IN_LEN) + input_pos_int;
                            data_q16 = read_phase2_q16(idx_int);
                            weight_q16 = read_conv3_weight_q16(weight_idx_int);
                            acc_next = conv3_acc_reg + (data_q16 * weight_q16);
                        end

                        if (conv3_k_reg == (CONV3_KERNEL - 1)) begin
                            if (conv3_ic_reg == (CONV3_IN_CH - 1)) begin
                                out_q16 = sat_q16_s48(round_shift_s48(acc_next, 8));
                                if (out_q16 < 0) begin
                                    out_q16 = 16'sd0;
                                end

                                if (!conv3_pass_reg) begin
                                    conv3_y0_reg <= out_q16;
                                    conv3_pass_reg <= 1'b1;
                                    conv3_ic_reg <= 16'd0;
                                    conv3_k_reg <= 16'd0;
                                    bias_q16 = read_conv3_bias_q16(conv3_oc_reg);
                                    conv3_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                end else begin
                                    if (conv3_y0_reg >= out_q16) begin
                                        out_q16 = conv3_y0_reg;
                                    end
                                    output_value_idx_int = (conv3_oc_reg * CONV3_POOLED_LEN) + conv3_pool_reg;
                                    output_word_idx_int = output_value_idx_int >> 1;
                                    if ((output_value_idx_int & 1) != 0) begin
                                        phase3_words_mem[output_word_idx_int][31:16] <= out_q16;
                                    end else begin
                                        phase3_words_mem[output_word_idx_int][15:0] <= out_q16;
                                    end

                                    conv3_pass_reg <= 1'b0;
                                    conv3_ic_reg <= 16'd0;
                                    conv3_k_reg <= 16'd0;

                                    if (conv3_pool_reg == (CONV3_POOLED_LEN - 1)) begin
                                        conv3_pool_reg <= 16'd0;
                                        if (conv3_oc_reg == (CONV3_OUT_CH - 1)) begin
                                            exec_state_reg <= EST_CONV4;
                                            conv4_oc_reg <= 16'd0;
                                            conv4_pos_reg <= 16'd0;
                                            conv4_ic_reg <= 16'd0;
                                            conv4_k_reg <= 16'd0;
                                            conv4_sum_reg <= 48'sd0;
                                            bias_q16 = read_conv4_bias_q16(0);
                                            conv4_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                        end else begin
                                            conv3_oc_reg <= conv3_oc_reg + 16'd1;
                                            bias_q16 = read_conv3_bias_q16(conv3_oc_reg + 1);
                                            conv3_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                        end
                                    end else begin
                                        conv3_pool_reg <= conv3_pool_reg + 16'd1;
                                        bias_q16 = read_conv3_bias_q16(conv3_oc_reg);
                                        conv3_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                    end
                                end
                            end else begin
                                conv3_ic_reg <= conv3_ic_reg + 16'd1;
                                conv3_k_reg <= 16'd0;
                                conv3_acc_reg <= acc_next;
                            end
                        end else begin
                            conv3_k_reg <= conv3_k_reg + 16'd1;
                            conv3_acc_reg <= acc_next;
                        end
                    end

                    EST_CONV4: begin
                        input_pos_int = conv4_pos_reg + conv4_k_reg - CONV4_PAD;
                        weight_idx_int =
                            (((conv4_oc_reg * CONV4_IN_CH) + conv4_ic_reg) * CONV4_KERNEL) + conv4_k_reg;
                        acc_next = conv4_acc_reg;

                        if ((input_pos_int >= 0) && (input_pos_int < CONV4_IN_LEN)) begin
                            idx_int = (conv4_ic_reg * CONV4_IN_LEN) + input_pos_int;
                            data_q16 = read_phase3_q16(idx_int);
                            weight_q16 = read_conv4_weight_q16(weight_idx_int);
                            acc_next = conv4_acc_reg + (data_q16 * weight_q16);
                        end

                        if (conv4_k_reg == (CONV4_KERNEL - 1)) begin
                            if (conv4_ic_reg == (CONV4_IN_CH - 1)) begin
                                out_q16 = sat_q16_s48(round_shift_s48(acc_next, 8));
                                if (out_q16 < 0) begin
                                    out_q16 = 16'sd0;
                                end
                                mod_next = conv4_sum_reg + out_q16;

                                if (conv4_pos_reg == (CONV4_IN_LEN - 1)) begin
                                    out_q16 = sat_q16_s48(mod_next / CONV4_IN_LEN);
                                    output_value_idx_int = conv4_oc_reg;
                                    output_word_idx_int = output_value_idx_int >> 1;
                                    if ((output_value_idx_int & 1) != 0) begin
                                        final_words_mem[output_word_idx_int][31:16] <= out_q16;
                                    end else begin
                                        final_words_mem[output_word_idx_int][15:0] <= out_q16;
                                    end

                                    conv4_sum_reg <= 48'sd0;
                                    conv4_pos_reg <= 16'd0;
                                    conv4_ic_reg <= 16'd0;
                                    conv4_k_reg <= 16'd0;

                                    if (conv4_oc_reg == (CONV4_OUT_CH - 1)) begin
                                        busy_reg <= 1'b0;
                                        done_pulse_reg <= 1'b1;
                                        phase_reg <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_DONE;
                                        exec_state_reg <= EST_IDLE;
                                    end else begin
                                        conv4_oc_reg <= conv4_oc_reg + 16'd1;
                                        bias_q16 = read_conv4_bias_q16(conv4_oc_reg + 1);
                                        conv4_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                    end
                                end else begin
                                    conv4_sum_reg <= mod_next;
                                    conv4_pos_reg <= conv4_pos_reg + 16'd1;
                                    conv4_ic_reg <= 16'd0;
                                    conv4_k_reg <= 16'd0;
                                    bias_q16 = read_conv4_bias_q16(conv4_oc_reg);
                                    conv4_acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                                end
                            end else begin
                                conv4_ic_reg <= conv4_ic_reg + 16'd1;
                                conv4_k_reg <= 16'd0;
                                conv4_acc_reg <= acc_next;
                            end
                        end else begin
                            conv4_k_reg <= conv4_k_reg + 16'd1;
                            conv4_acc_reg <= acc_next;
                        end
                    end

                    default: begin
                        exec_state_reg <= EST_IDLE;
                    end
                endcase
            end else begin
                phase_reg <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_IDLE;
                exec_state_reg <= EST_IDLE;
            end
        end
    end

endmodule

`default_nettype wire
