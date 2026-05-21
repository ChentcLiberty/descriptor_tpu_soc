`timescale 1ns / 1ps
`default_nettype none

module tpu_stage2_cnn_frontend_wrapper #(
    parameter [2:0]  AXI_SIZE_WORD        = 3'b010,
    parameter [31:0] EXPECTED_NET_ID      = tpu_stage2_cnn_frontend_pkg::STAGE2_NET_ID_CNN1D,
    parameter [31:0] EXPECTED_INPUT_WORDS = tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_SIGNAL_WORDS,
    parameter [31:0] EXPECTED_OUTPUT_WORDS =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FINAL_OUTPUT_WORDS,
    parameter [31:0] FEATURE_ADDR_FIXED   =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_DEFAULT_FEATURE_ADDR,
    parameter [31:0] CONV1_W_BASE         =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_WEIGHT_BASE,
    parameter [31:0] CONV1_B_BASE         =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_BIAS_BASE,
    parameter integer SIGNAL_WORDS        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_SIGNAL_WORDS,
    parameter integer WEIGHT_WORDS        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_WEIGHT_WORDS,
    parameter integer BIAS_WORDS          =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_BIAS_WORDS,
    parameter integer CONV1_IN_CH         =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_IN_CH,
    parameter integer CONV1_IN_LEN        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_IN_LEN,
    parameter integer CONV1_OUT_CH        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_OUT_CH,
    parameter integer CONV1_KERNEL        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_KERNEL,
    parameter integer CONV1_PAD           =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_PAD
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        launch_pulse,
    input  wire        soft_reset_pulse,
    input  wire [31:0] desc_base_addr,

    output wire        status_busy,
    output wire        status_done,
    output wire        status_error,

    output wire [31:0] desc_net_id_reg,
    output wire [31:0] desc_input_addr_reg,
    output wire [31:0] desc_output_addr_reg,
    output wire [31:0] desc_param_addr_reg,
    output wire [31:0] desc_scratch_addr_reg,
    output wire [31:0] desc_input_words_reg,
    output wire [31:0] desc_output_words_reg,
    output wire [31:0] desc_flags_reg,

    output wire [31:0] input_fetch_word_count_reg,
    output wire [31:0] input_checksum_reg,
    output wire [31:0] input_last_word_reg,
    output wire [31:0] param_fetch_word_count_reg,
    output wire [31:0] param_checksum_reg,
    output wire [31:0] param_last_word_reg,

    output wire [31:0] m_axi_araddr,
    output wire [1:0]  m_axi_arburst,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [3:0]  m_axi_arcache,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    output wire [31:0] m_axi_awaddr,
    output wire [1:0]  m_axi_awburst,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [3:0]  m_axi_awcache,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready
);

    localparam integer POOLED_LEN = CONV1_IN_LEN / 2;
    localparam integer PHASE1_SCRATCH_WORDS = (CONV1_OUT_CH * POOLED_LEN) / 2;

    localparam integer SIGNAL_WORD_AW = (SIGNAL_WORDS <= 1) ? 1 : $clog2(SIGNAL_WORDS);
    localparam integer WEIGHT_WORD_AW = (WEIGHT_WORDS <= 1) ? 1 : $clog2(WEIGHT_WORDS);
    localparam integer BIAS_WORD_AW = (BIAS_WORDS <= 1) ? 1 : $clog2(BIAS_WORDS);
    localparam integer SCRATCH_WORD_AW = (PHASE1_SCRATCH_WORDS <= 1) ? 1 : $clog2(PHASE1_SCRATCH_WORDS);

    localparam [3:0] ST_IDLE         = 4'd0;
    localparam [3:0] ST_DESC_AR      = 4'd1;
    localparam [3:0] ST_DESC_R       = 4'd2;
    localparam [3:0] ST_SIGNAL_AR    = 4'd3;
    localparam [3:0] ST_SIGNAL_R     = 4'd4;
    localparam [3:0] ST_WEIGHT_AR    = 4'd5;
    localparam [3:0] ST_WEIGHT_R     = 4'd6;
    localparam [3:0] ST_BIAS_AR      = 4'd7;
    localparam [3:0] ST_BIAS_R       = 4'd8;
    localparam [3:0] ST_VALIDATE     = 4'd9;
    localparam [3:0] ST_ENGINE_START = 4'd10;
    localparam [3:0] ST_ENGINE_WAIT  = 4'd11;
    localparam [3:0] ST_WB_AW        = 4'd12;
    localparam [3:0] ST_WB_W         = 4'd13;
    localparam [3:0] ST_WB_B         = 4'd14;

    reg [3:0]  state_reg;
    reg [2:0]  desc_fetch_idx_reg;
    reg        status_busy_reg;
    reg        status_done_reg;
    reg        status_error_reg;
    reg [31:0] desc_net_id_reg_r;
    reg [31:0] desc_input_addr_reg_r;
    reg [31:0] desc_output_addr_reg_r;
    reg [31:0] desc_param_addr_reg_r;
    reg [31:0] desc_scratch_addr_reg_r;
    reg [31:0] desc_input_words_reg_r;
    reg [31:0] desc_output_words_reg_r;
    reg [31:0] desc_flags_reg_r;

    reg [31:0] input_fetch_word_count_reg_r;
    reg [31:0] input_checksum_reg_r;
    reg [31:0] input_last_word_reg_r;
    reg [31:0] param_fetch_word_count_reg_r;
    reg [31:0] param_checksum_reg_r;
    reg [31:0] param_last_word_reg_r;

    reg [SIGNAL_WORD_AW-1:0] signal_idx_reg;
    reg [WEIGHT_WORD_AW-1:0] weight_idx_reg;
    reg [BIAS_WORD_AW-1:0]   bias_idx_reg;
    reg [SCRATCH_WORD_AW-1:0] write_idx_reg;

    wire       engine_start_valid;
    wire       engine_start_ready;
    wire       engine_busy;
    wire       engine_done_pulse;
    wire       engine_error_pulse;
    wire [2:0] engine_phase_dbg;
    wire [31:0] engine_cycle_count_dbg;
    wire [31:0] engine_output_rd_data;
    wire       desc_invalid;
    wire       signal_wr_valid;
    wire       weight_wr_valid;
    wire       bias_wr_valid;
    wire [31:0] araddr_desc;
    wire [31:0] araddr_signal;
    wire [31:0] araddr_weight;
    wire [31:0] araddr_bias;
    wire [31:0] awaddr_writeback;
    wire       read_resp_fire;
    wire       write_resp_ok;

    assign status_busy = status_busy_reg;
    assign status_done = status_done_reg;
    assign status_error = status_error_reg;

    assign desc_net_id_reg = desc_net_id_reg_r;
    assign desc_input_addr_reg = desc_input_addr_reg_r;
    assign desc_output_addr_reg = desc_output_addr_reg_r;
    assign desc_param_addr_reg = desc_param_addr_reg_r;
    assign desc_scratch_addr_reg = desc_scratch_addr_reg_r;
    assign desc_input_words_reg = desc_input_words_reg_r;
    assign desc_output_words_reg = desc_output_words_reg_r;
    assign desc_flags_reg = desc_flags_reg_r;

    assign input_fetch_word_count_reg = input_fetch_word_count_reg_r;
    assign input_checksum_reg = input_checksum_reg_r;
    assign input_last_word_reg = input_last_word_reg_r;
    assign param_fetch_word_count_reg = param_fetch_word_count_reg_r;
    assign param_checksum_reg = param_checksum_reg_r;
    assign param_last_word_reg = param_last_word_reg_r;

    assign araddr_desc = desc_base_addr + {27'd0, desc_fetch_idx_reg, 2'b00};
    assign araddr_signal = desc_input_addr_reg_r + ({24'd0, signal_idx_reg} << 2);
    assign araddr_weight = CONV1_W_BASE + ({24'd0, weight_idx_reg} << 2);
    assign araddr_bias = CONV1_B_BASE + ({24'd0, bias_idx_reg} << 2);
    assign awaddr_writeback = desc_scratch_addr_reg_r + ({19'd0, write_idx_reg} << 2);

    assign m_axi_araddr  =
        (state_reg == ST_DESC_AR)   ? araddr_desc   :
        (state_reg == ST_SIGNAL_AR) ? araddr_signal :
        (state_reg == ST_WEIGHT_AR) ? araddr_weight :
        araddr_bias;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = AXI_SIZE_WORD;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arvalid =
        (state_reg == ST_DESC_AR)   ||
        (state_reg == ST_SIGNAL_AR) ||
        (state_reg == ST_WEIGHT_AR) ||
        (state_reg == ST_BIAS_AR);

    assign m_axi_rready =
        (state_reg == ST_DESC_R)   ||
        (state_reg == ST_SIGNAL_R) ||
        (state_reg == ST_WEIGHT_R) ||
        (state_reg == ST_BIAS_R);

    assign m_axi_awaddr  = awaddr_writeback;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = AXI_SIZE_WORD;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awvalid = (state_reg == ST_WB_AW);
    assign m_axi_bready  = (state_reg == ST_WB_B);
    assign m_axi_wdata   = engine_output_rd_data;
    assign m_axi_wstrb   = 4'hF;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wvalid  = (state_reg == ST_WB_W);

    assign signal_wr_valid = (state_reg == ST_SIGNAL_R) && read_resp_fire;
    assign weight_wr_valid = (state_reg == ST_WEIGHT_R) && read_resp_fire;
    assign bias_wr_valid   = (state_reg == ST_BIAS_R) && read_resp_fire;

    assign engine_start_valid = (state_reg == ST_ENGINE_START);

    assign desc_invalid =
        (desc_net_id_reg_r != EXPECTED_NET_ID) ||
        (desc_input_addr_reg_r == 32'd0) ||
        (desc_scratch_addr_reg_r == 32'd0) ||
        (desc_input_words_reg_r != EXPECTED_INPUT_WORDS) ||
        (desc_output_words_reg_r != EXPECTED_OUTPUT_WORDS);

    assign read_resp_fire = m_axi_rvalid && m_axi_rready && (m_axi_rresp == 2'b00) && m_axi_rlast;
    assign write_resp_ok = m_axi_bvalid && m_axi_bready && (m_axi_bresp == 2'b00);

    cnn_frontend_engine #(
        .SIGNAL_WORDS(SIGNAL_WORDS),
        .WEIGHT_WORDS(WEIGHT_WORDS),
        .BIAS_WORDS(BIAS_WORDS),
        .IN_CH(CONV1_IN_CH),
        .IN_LEN(CONV1_IN_LEN),
        .OUT_CH(CONV1_OUT_CH),
        .KERNEL(CONV1_KERNEL),
        .PAD(CONV1_PAD)
    ) engine_u (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset_pulse(soft_reset_pulse),
        .signal_wr_valid(signal_wr_valid),
        .signal_wr_addr(signal_idx_reg),
        .signal_wr_data(m_axi_rdata),
        .weight_wr_valid(weight_wr_valid),
        .weight_wr_addr(weight_idx_reg),
        .weight_wr_data(m_axi_rdata),
        .bias_wr_valid(bias_wr_valid),
        .bias_wr_addr(bias_idx_reg),
        .bias_wr_data(m_axi_rdata),
        .start_valid(engine_start_valid),
        .start_ready(engine_start_ready),
        .signal_addr(desc_input_addr_reg_r),
        .feature_addr(FEATURE_ADDR_FIXED),
        .output_addr(desc_output_addr_reg_r),
        .scratch_addr(desc_scratch_addr_reg_r),
        .input_words(desc_input_words_reg_r),
        .output_words(desc_output_words_reg_r),
        .flags(desc_flags_reg_r),
        .busy(engine_busy),
        .done_pulse(engine_done_pulse),
        .error_pulse(engine_error_pulse),
        .phase_dbg(engine_phase_dbg),
        .cycle_count_dbg(engine_cycle_count_dbg),
        .output_rd_addr(write_idx_reg),
        .output_rd_data(engine_output_rd_data)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg                 <= ST_IDLE;
            desc_fetch_idx_reg        <= 3'd0;
            status_busy_reg           <= 1'b0;
            status_done_reg           <= 1'b0;
            status_error_reg          <= 1'b0;
            desc_net_id_reg_r         <= 32'd0;
            desc_input_addr_reg_r     <= 32'd0;
            desc_output_addr_reg_r    <= 32'd0;
            desc_param_addr_reg_r     <= 32'd0;
            desc_scratch_addr_reg_r   <= 32'd0;
            desc_input_words_reg_r    <= 32'd0;
            desc_output_words_reg_r   <= 32'd0;
            desc_flags_reg_r          <= 32'd0;
            input_fetch_word_count_reg_r <= 32'd0;
            input_checksum_reg_r <= 32'd0;
            input_last_word_reg_r <= 32'd0;
            param_fetch_word_count_reg_r <= 32'd0;
            param_checksum_reg_r <= 32'd0;
            param_last_word_reg_r <= 32'd0;
            signal_idx_reg <= {SIGNAL_WORD_AW{1'b0}};
            weight_idx_reg <= {WEIGHT_WORD_AW{1'b0}};
            bias_idx_reg <= {BIAS_WORD_AW{1'b0}};
            write_idx_reg <= {SCRATCH_WORD_AW{1'b0}};
        end else begin
            if (soft_reset_pulse) begin
                state_reg                 <= ST_IDLE;
                desc_fetch_idx_reg        <= 3'd0;
                status_busy_reg           <= 1'b0;
                status_done_reg           <= 1'b0;
                status_error_reg          <= 1'b0;
                input_fetch_word_count_reg_r <= 32'd0;
                input_checksum_reg_r <= 32'd0;
                input_last_word_reg_r <= 32'd0;
                param_fetch_word_count_reg_r <= 32'd0;
                param_checksum_reg_r <= 32'd0;
                param_last_word_reg_r <= 32'd0;
                signal_idx_reg <= {SIGNAL_WORD_AW{1'b0}};
                weight_idx_reg <= {WEIGHT_WORD_AW{1'b0}};
                bias_idx_reg <= {BIAS_WORD_AW{1'b0}};
                write_idx_reg <= {SCRATCH_WORD_AW{1'b0}};
            end else begin
                case (state_reg)
                    ST_IDLE: begin
                        status_busy_reg <= 1'b0;
                        if (launch_pulse) begin
                            status_done_reg <= 1'b0;
                            status_error_reg <= 1'b0;
                            input_fetch_word_count_reg_r <= 32'd0;
                            input_checksum_reg_r <= 32'd0;
                            input_last_word_reg_r <= 32'd0;
                            param_fetch_word_count_reg_r <= 32'd0;
                            param_checksum_reg_r <= 32'd0;
                            param_last_word_reg_r <= 32'd0;

                            if (desc_base_addr == 32'd0) begin
                                status_error_reg <= 1'b1;
                            end else begin
                                status_busy_reg <= 1'b1;
                                desc_fetch_idx_reg <= 3'd0;
                                state_reg <= ST_DESC_AR;
                            end
                        end
                    end

                    ST_DESC_AR: begin
                        if (m_axi_arvalid && m_axi_arready) begin
                            state_reg <= ST_DESC_R;
                        end
                    end

                    ST_DESC_R: begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            if ((m_axi_rresp != 2'b00) || !m_axi_rlast) begin
                                status_busy_reg <= 1'b0;
                                status_error_reg <= 1'b1;
                                state_reg <= ST_IDLE;
                            end else begin
                                case (desc_fetch_idx_reg)
                                    3'd0: desc_net_id_reg_r <= m_axi_rdata;
                                    3'd1: desc_input_addr_reg_r <= m_axi_rdata;
                                    3'd2: desc_output_addr_reg_r <= m_axi_rdata;
                                    3'd3: desc_param_addr_reg_r <= m_axi_rdata;
                                    3'd4: desc_scratch_addr_reg_r <= m_axi_rdata;
                                    3'd5: desc_input_words_reg_r <= m_axi_rdata;
                                    3'd6: desc_output_words_reg_r <= m_axi_rdata;
                                    default: desc_flags_reg_r <= m_axi_rdata;
                                endcase

                                if (desc_fetch_idx_reg == 3'd7) begin
                                    signal_idx_reg <= {SIGNAL_WORD_AW{1'b0}};
                                    state_reg <= ST_VALIDATE;
                                end else begin
                                    desc_fetch_idx_reg <= desc_fetch_idx_reg + 3'd1;
                                    state_reg <= ST_DESC_AR;
                                end
                            end
                        end
                    end

                    ST_VALIDATE: begin
                        if (desc_invalid) begin
                            status_busy_reg <= 1'b0;
                            status_error_reg <= 1'b1;
                            state_reg <= ST_IDLE;
                        end else begin
                            signal_idx_reg <= {SIGNAL_WORD_AW{1'b0}};
                            state_reg <= ST_SIGNAL_AR;
                        end
                    end

                    ST_SIGNAL_AR: begin
                        if (m_axi_arvalid && m_axi_arready) begin
                            state_reg <= ST_SIGNAL_R;
                        end
                    end

                    ST_SIGNAL_R: begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            if ((m_axi_rresp != 2'b00) || !m_axi_rlast) begin
                                status_busy_reg <= 1'b0;
                                status_error_reg <= 1'b1;
                                state_reg <= ST_IDLE;
                            end else begin
                                input_fetch_word_count_reg_r <= input_fetch_word_count_reg_r + 32'd1;
                                input_checksum_reg_r <= input_checksum_reg_r + m_axi_rdata;
                                input_last_word_reg_r <= m_axi_rdata;

                                if (signal_idx_reg == (SIGNAL_WORDS - 1)) begin
                                    weight_idx_reg <= {WEIGHT_WORD_AW{1'b0}};
                                    state_reg <= ST_WEIGHT_AR;
                                end else begin
                                    signal_idx_reg <= signal_idx_reg + {{(SIGNAL_WORD_AW-1){1'b0}}, 1'b1};
                                    state_reg <= ST_SIGNAL_AR;
                                end
                            end
                        end
                    end

                    ST_WEIGHT_AR: begin
                        if (m_axi_arvalid && m_axi_arready) begin
                            state_reg <= ST_WEIGHT_R;
                        end
                    end

                    ST_WEIGHT_R: begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            if ((m_axi_rresp != 2'b00) || !m_axi_rlast) begin
                                status_busy_reg <= 1'b0;
                                status_error_reg <= 1'b1;
                                state_reg <= ST_IDLE;
                            end else begin
                                param_fetch_word_count_reg_r <= param_fetch_word_count_reg_r + 32'd1;
                                param_checksum_reg_r <= param_checksum_reg_r + m_axi_rdata;
                                param_last_word_reg_r <= m_axi_rdata;

                                if (weight_idx_reg == (WEIGHT_WORDS - 1)) begin
                                    bias_idx_reg <= {BIAS_WORD_AW{1'b0}};
                                    state_reg <= ST_BIAS_AR;
                                end else begin
                                    weight_idx_reg <= weight_idx_reg + {{(WEIGHT_WORD_AW-1){1'b0}}, 1'b1};
                                    state_reg <= ST_WEIGHT_AR;
                                end
                            end
                        end
                    end

                    ST_BIAS_AR: begin
                        if (m_axi_arvalid && m_axi_arready) begin
                            state_reg <= ST_BIAS_R;
                        end
                    end

                    ST_BIAS_R: begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            if ((m_axi_rresp != 2'b00) || !m_axi_rlast) begin
                                status_busy_reg <= 1'b0;
                                status_error_reg <= 1'b1;
                                state_reg <= ST_IDLE;
                            end else begin
                                param_fetch_word_count_reg_r <= param_fetch_word_count_reg_r + 32'd1;
                                param_checksum_reg_r <= param_checksum_reg_r + m_axi_rdata;
                                param_last_word_reg_r <= m_axi_rdata;

                                if (bias_idx_reg == (BIAS_WORDS - 1)) begin
                                    state_reg <= ST_ENGINE_START;
                                end else begin
                                    bias_idx_reg <= bias_idx_reg + {{(BIAS_WORD_AW-1){1'b0}}, 1'b1};
                                    state_reg <= ST_BIAS_AR;
                                end
                            end
                        end
                    end

                    ST_ENGINE_START: begin
                        if (engine_start_valid && engine_start_ready) begin
                            state_reg <= ST_ENGINE_WAIT;
                        end
                    end

                    ST_ENGINE_WAIT: begin
                        if (engine_error_pulse) begin
                            status_busy_reg <= 1'b0;
                            status_error_reg <= 1'b1;
                            state_reg <= ST_IDLE;
                        end else if (engine_done_pulse) begin
                            write_idx_reg <= {SCRATCH_WORD_AW{1'b0}};
                            state_reg <= ST_WB_AW;
                        end
                    end

                    ST_WB_AW: begin
                        if (m_axi_awvalid && m_axi_awready) begin
                            state_reg <= ST_WB_W;
                        end
                    end

                    ST_WB_W: begin
                        if (m_axi_wvalid && m_axi_wready) begin
                            state_reg <= ST_WB_B;
                        end
                    end

                    ST_WB_B: begin
                        if (m_axi_bvalid && m_axi_bready) begin
                            if (m_axi_bresp != 2'b00) begin
                                status_busy_reg <= 1'b0;
                                status_error_reg <= 1'b1;
                                state_reg <= ST_IDLE;
                            end else if (write_idx_reg == (PHASE1_SCRATCH_WORDS - 1)) begin
                                status_busy_reg <= 1'b0;
                                status_done_reg <= 1'b1;
                                state_reg <= ST_IDLE;
                            end else begin
                                write_idx_reg <= write_idx_reg + {{(SCRATCH_WORD_AW-1){1'b0}}, 1'b1};
                                state_reg <= ST_WB_AW;
                            end
                        end
                    end

                    default: begin
                        state_reg <= ST_IDLE;
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
