`timescale 1ns / 1ps
`default_nettype none

module cnn_frontend_engine #(
    parameter integer SIGNAL_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_SIGNAL_WORDS,
    parameter integer WEIGHT_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_WEIGHT_WORDS,
    parameter integer BIAS_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_BIAS_WORDS,
    parameter integer IN_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_IN_CH,
    parameter integer IN_LEN =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_IN_LEN,
    parameter integer OUT_CH =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_OUT_CH,
    parameter integer KERNEL =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_KERNEL,
    parameter integer PAD =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_PAD
) (
    input  wire clk,
    input  wire rst_n,
    input  wire soft_reset_pulse,

    input  wire signal_wr_valid,
    input  wire [((SIGNAL_WORDS <= 1) ? 1 : $clog2(SIGNAL_WORDS)) - 1:0] signal_wr_addr,
    input  wire [31:0] signal_wr_data,
    input  wire weight_wr_valid,
    input  wire [((WEIGHT_WORDS <= 1) ? 1 : $clog2(WEIGHT_WORDS)) - 1:0] weight_wr_addr,
    input  wire [31:0] weight_wr_data,
    input  wire bias_wr_valid,
    input  wire [((BIAS_WORDS <= 1) ? 1 : $clog2(BIAS_WORDS)) - 1:0] bias_wr_addr,
    input  wire [31:0] bias_wr_data,

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

    input  wire [((((OUT_CH * (IN_LEN / 2)) / 2) <= 1) ? 1 : $clog2((OUT_CH * (IN_LEN / 2)) / 2)) - 1:0] output_rd_addr,
    output wire [31:0] output_rd_data
);

    localparam integer POOLED_LEN = IN_LEN / 2;
    localparam integer OUTPUT_VALUES = OUT_CH * POOLED_LEN;
    localparam integer OUTPUT_WORDS = OUTPUT_VALUES / 2;

    localparam integer OUT_CH_AW = (OUT_CH <= 1) ? 1 : $clog2(OUT_CH);
    localparam integer POOLED_LEN_AW = (POOLED_LEN <= 1) ? 1 : $clog2(POOLED_LEN);
    localparam integer KERNEL_AW = (KERNEL <= 1) ? 1 : $clog2(KERNEL);

    reg [31:0] signal_words_mem [0:SIGNAL_WORDS-1];
    reg [31:0] weight_words_mem [0:WEIGHT_WORDS-1];
    reg [31:0] bias_words_mem [0:BIAS_WORDS-1];
    reg [31:0] output_words_mem [0:OUTPUT_WORDS-1];

    reg        busy_reg;
    reg        done_pulse_reg;
    reg        error_pulse_reg;
    reg [2:0]  phase_reg;
    reg [31:0] cycle_count_reg;

    reg [OUT_CH_AW-1:0]     oc_reg;
    reg [POOLED_LEN_AW-1:0] pool_pos_reg;
    reg                     pass_reg;
    reg [KERNEL_AW-1:0]     k_reg;
    reg signed [47:0]       acc_reg;
    reg signed [15:0]       y0_reg;

    reg signed [15:0] sample_q16;
    reg signed [15:0] weight_q16;
    reg signed [15:0] bias_q16;
    reg signed [15:0] conv_q16;
    reg signed [15:0] pooled_q16;
    reg signed [47:0] acc_next;

    integer input_pos_int;
    integer weight_idx_int;
    integer output_value_idx_int;
    integer output_word_idx_int;

    wire start_accept;
    wire bad_launch;
    wire [31:0] unused_feature_addr;
    wire [31:0] unused_output_addr;
    wire [31:0] unused_flags;

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

    function automatic signed [15:0] read_weight_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = weight_words_mem[value_idx >> 1];
            read_weight_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    function automatic signed [15:0] read_bias_q16;
        input integer value_idx;
        reg [31:0] word;
        begin
            word = bias_words_mem[value_idx >> 1];
            read_bias_q16 = unpack_q16(word, value_idx & 1);
        end
    endfunction

    assign start_ready = !busy_reg;
    assign start_accept = start_valid && start_ready;
    assign busy = busy_reg;
    assign done_pulse = done_pulse_reg;
    assign error_pulse = error_pulse_reg;
    assign phase_dbg = phase_reg;
    assign cycle_count_dbg = cycle_count_reg;
    assign output_rd_data = output_words_mem[output_rd_addr];

    assign bad_launch =
        (signal_addr == 32'd0) ||
        (scratch_addr == 32'd0) ||
        (input_words != SIGNAL_WORDS) ||
        (output_words == 32'd0);

    assign unused_feature_addr = feature_addr;
    assign unused_output_addr = output_addr;
    assign unused_flags = flags;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_reg        <= 1'b0;
            done_pulse_reg  <= 1'b0;
            error_pulse_reg <= 1'b0;
            phase_reg       <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_IDLE;
            cycle_count_reg <= 32'd0;
            oc_reg          <= {OUT_CH_AW{1'b0}};
            pool_pos_reg    <= {POOLED_LEN_AW{1'b0}};
            pass_reg        <= 1'b0;
            k_reg           <= {KERNEL_AW{1'b0}};
            acc_reg         <= 48'sd0;
            y0_reg          <= 16'sd0;
        end else begin
            if (signal_wr_valid) begin
                signal_words_mem[signal_wr_addr] <= signal_wr_data;
            end
            if (weight_wr_valid) begin
                weight_words_mem[weight_wr_addr] <= weight_wr_data;
            end
            if (bias_wr_valid) begin
                bias_words_mem[bias_wr_addr] <= bias_wr_data;
            end

            done_pulse_reg <= 1'b0;
            error_pulse_reg <= 1'b0;

            if (soft_reset_pulse) begin
                busy_reg        <= 1'b0;
                phase_reg       <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_IDLE;
                cycle_count_reg <= 32'd0;
                oc_reg          <= {OUT_CH_AW{1'b0}};
                pool_pos_reg    <= {POOLED_LEN_AW{1'b0}};
                pass_reg        <= 1'b0;
                k_reg           <= {KERNEL_AW{1'b0}};
                acc_reg         <= 48'sd0;
                y0_reg          <= 16'sd0;
            end else if (start_accept) begin
                if (bad_launch) begin
                    busy_reg        <= 1'b0;
                    error_pulse_reg <= 1'b1;
                    phase_reg       <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_IDLE;
                    cycle_count_reg <= 32'd0;
                end else begin
                    busy_reg        <= 1'b1;
                    phase_reg       <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_CONV12;
                    cycle_count_reg <= 32'd0;
                    oc_reg          <= {OUT_CH_AW{1'b0}};
                    pool_pos_reg    <= {POOLED_LEN_AW{1'b0}};
                    pass_reg        <= 1'b0;
                    k_reg           <= {KERNEL_AW{1'b0}};
                    bias_q16        = read_bias_q16(0);
                    acc_reg         <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                end
            end else if (busy_reg) begin
                cycle_count_reg <= cycle_count_reg + 32'd1;

                input_pos_int = (pool_pos_reg << 1) + pass_reg + k_reg - PAD;
                weight_idx_int = ((oc_reg * IN_CH) * KERNEL) + k_reg;
                acc_next = acc_reg;

                if ((input_pos_int >= 0) && (input_pos_int < IN_LEN)) begin
                    sample_q16 = read_signal_q16(input_pos_int);
                    weight_q16 = read_weight_q16(weight_idx_int);
                    acc_next = acc_reg + (sample_q16 * weight_q16);
                end

                if (k_reg == (KERNEL - 1)) begin
                    conv_q16 = sat_q16_s48(round_shift_s48(acc_next, 8));
                    if (conv_q16 < 0) begin
                        conv_q16 = 16'sd0;
                    end

                    if (!pass_reg) begin
                        y0_reg <= conv_q16;
                        pass_reg <= 1'b1;
                        k_reg <= {KERNEL_AW{1'b0}};
                        bias_q16 = read_bias_q16(oc_reg);
                        acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                    end else begin
                        pooled_q16 = (y0_reg >= conv_q16) ? y0_reg : conv_q16;
                        output_value_idx_int = (oc_reg * POOLED_LEN) + pool_pos_reg;
                        output_word_idx_int = output_value_idx_int >> 1;

                        if ((output_value_idx_int & 1) != 0) begin
                            output_words_mem[output_word_idx_int][31:16] <= pooled_q16;
                        end else begin
                            output_words_mem[output_word_idx_int][15:0] <= pooled_q16;
                        end

                        pass_reg <= 1'b0;
                        k_reg <= {KERNEL_AW{1'b0}};

                        if (pool_pos_reg == (POOLED_LEN - 1)) begin
                            pool_pos_reg <= {POOLED_LEN_AW{1'b0}};
                            if (oc_reg == (OUT_CH - 1)) begin
                                busy_reg       <= 1'b0;
                                done_pulse_reg <= 1'b1;
                                phase_reg      <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_DONE;
                            end else begin
                                oc_reg <= oc_reg + {{(OUT_CH_AW-1){1'b0}}, 1'b1};
                                bias_q16 = read_bias_q16(oc_reg + 1);
                                acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                            end
                        end else begin
                            pool_pos_reg <= pool_pos_reg + {{(POOLED_LEN_AW-1){1'b0}}, 1'b1};
                            bias_q16 = read_bias_q16(oc_reg);
                            acc_reg <= {{24{bias_q16[15]}}, bias_q16, 8'd0};
                        end
                    end
                end else begin
                    acc_reg <= acc_next;
                    k_reg <= k_reg + {{(KERNEL_AW-1){1'b0}}, 1'b1};
                end
            end else begin
                phase_reg <= tpu_stage2_cnn_frontend_pkg::CNN_PHASE_IDLE;
            end
        end
    end

endmodule

`default_nettype wire
