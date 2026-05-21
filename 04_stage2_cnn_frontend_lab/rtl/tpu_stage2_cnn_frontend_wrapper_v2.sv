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
    parameter [31:0] CONV2_W_BASE         =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_WEIGHT_BASE,
    parameter [31:0] CONV2_B_BASE         =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_BIAS_BASE,
    parameter [31:0] FILM_L0_W_BASE       =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L0_W_BASE,
    parameter [31:0] FILM_L0_B_BASE       =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L0_B_BASE,
    parameter [31:0] FILM_L2_W_BASE       =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L2_W_BASE,
    parameter [31:0] FILM_L2_B_BASE       =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L2_B_BASE,
    parameter integer SIGNAL_WORDS        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_SIGNAL_WORDS,
    parameter integer FEATURE_WORDS       =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FEATURE_WORDS,
    parameter integer CONV1_WEIGHT_WORDS  =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_WEIGHT_WORDS,
    parameter integer CONV1_BIAS_WORDS    =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_BIAS_WORDS,
    parameter integer CONV2_WEIGHT_WORDS  =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_WEIGHT_WORDS,
    parameter integer CONV2_BIAS_WORDS    =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_BIAS_WORDS,
    parameter integer FILM_L0_W_WORDS     =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L0_W_WORDS,
    parameter integer FILM_L0_B_WORDS     =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L0_B_WORDS,
    parameter integer FILM_L2_W_WORDS     =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L2_W_WORDS,
    parameter integer FILM_L2_B_WORDS     =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_L2_B_WORDS,
    parameter integer FINAL_OUTPUT_WORDS  =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FINAL_OUTPUT_WORDS,
    parameter integer CONV1_IN_CH         =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_IN_CH,
    parameter integer CONV1_IN_LEN        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_IN_LEN,
    parameter integer CONV1_OUT_CH        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_OUT_CH,
    parameter integer CONV1_KERNEL        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_KERNEL,
    parameter integer CONV1_PAD           =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV1_PAD,
    parameter integer CONV2_IN_CH         =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_IN_CH,
    parameter integer CONV2_IN_LEN        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_IN_LEN,
    parameter integer CONV2_OUT_CH        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_OUT_CH,
    parameter integer CONV2_KERNEL        =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_KERNEL,
    parameter integer CONV2_PAD           =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_CONV2_PAD,
    parameter integer FILM_HIDDEN_VALUES  =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_HIDDEN_VALUES,
    parameter integer FILM_OUT_VALUES     =
        tpu_stage2_cnn_frontend_pkg::STAGE2_CNN_FILM_OUT_VALUES
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

    localparam integer PHASE1_SCRATCH_WORDS = (CONV1_OUT_CH * (CONV1_IN_LEN / 2)) / 2;

    localparam [3:0] ST_IDLE         = 4'd0;
    localparam [3:0] ST_DESC_AR      = 4'd1;
    localparam [3:0] ST_DESC_R       = 4'd2;
    localparam [3:0] ST_VALIDATE     = 4'd3;
    localparam [3:0] ST_FETCH_AR     = 4'd4;
    localparam [3:0] ST_FETCH_R      = 4'd5;
    localparam [3:0] ST_ENGINE_START = 4'd6;
    localparam [3:0] ST_ENGINE_WAIT  = 4'd7;
    localparam [3:0] ST_WB_AW        = 4'd8;
    localparam [3:0] ST_WB_W         = 4'd9;
    localparam [3:0] ST_WB_B         = 4'd10;

    localparam [3:0] FK_SIGNAL   = 4'd0;
    localparam [3:0] FK_FEATURE  = 4'd1;
    localparam [3:0] FK_CONV1_W  = 4'd2;
    localparam [3:0] FK_CONV1_B  = 4'd3;
    localparam [3:0] FK_CONV2_W  = 4'd4;
    localparam [3:0] FK_CONV2_B  = 4'd5;
    localparam [3:0] FK_FILM0_W  = 4'd6;
    localparam [3:0] FK_FILM0_B  = 4'd7;
    localparam [3:0] FK_FILM2_W  = 4'd8;
    localparam [3:0] FK_FILM2_B  = 4'd9;

    localparam [1:0] WB_PHASE1 = 2'd0;
    localparam [1:0] WB_PHASE2 = 2'd1;

    reg [3:0]  state_reg;
    reg [2:0]  desc_fetch_idx_reg;
    reg [3:0]  fetch_kind_reg;
    reg [31:0] fetch_idx_reg;
    reg [1:0]  write_bank_reg;
    reg [31:0] write_idx_reg;
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

    wire        engine_start_valid;
    wire        engine_start_ready;
    wire        engine_busy;
    wire        engine_done_pulse;
    wire        engine_error_pulse;
    wire [2:0]  engine_phase_dbg;
    wire [31:0] engine_cycle_count_dbg;
    wire [31:0] engine_output_rd_data;
    wire        desc_invalid;
    wire        read_resp_fire;
    wire        fetch_is_runtime_input;
    wire [31:0] araddr_desc;
    wire [31:0] araddr_fetch;
    wire [31:0] awaddr_writeback;
    wire [31:0] fetch_base_addr;
    wire [31:0] fetch_word_limit;
    wire [31:0] write_base_addr;
    wire [31:0] write_word_limit;
    wire [3:0]  next_fetch_kind;

    wire signal_wr_valid;
    wire feature_wr_valid;
    wire conv1_weight_wr_valid;
    wire conv1_bias_wr_valid;
    wire conv2_weight_wr_valid;
    wire conv2_bias_wr_valid;
    wire film_l0_weight_wr_valid;
    wire film_l0_bias_wr_valid;
    wire film_l2_weight_wr_valid;
    wire film_l2_bias_wr_valid;

    function automatic [3:0] next_fetch_kind_fn;
        input [3:0] curr_kind;
        begin
            case (curr_kind)
                FK_SIGNAL:  next_fetch_kind_fn = FK_FEATURE;
                FK_FEATURE: next_fetch_kind_fn = FK_CONV1_W;
                FK_CONV1_W: next_fetch_kind_fn = FK_CONV1_B;
                FK_CONV1_B: next_fetch_kind_fn = FK_CONV2_W;
                FK_CONV2_W: next_fetch_kind_fn = FK_CONV2_B;
                FK_CONV2_B: next_fetch_kind_fn = FK_FILM0_W;
                FK_FILM0_W: next_fetch_kind_fn = FK_FILM0_B;
                FK_FILM0_B: next_fetch_kind_fn = FK_FILM2_W;
                FK_FILM2_W: next_fetch_kind_fn = FK_FILM2_B;
                default:    next_fetch_kind_fn = FK_FILM2_B;
            endcase
        end
    endfunction

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
    assign next_fetch_kind = next_fetch_kind_fn(fetch_kind_reg);

    assign fetch_base_addr =
        (fetch_kind_reg == FK_SIGNAL)  ? desc_input_addr_reg_r :
        (fetch_kind_reg == FK_FEATURE) ? FEATURE_ADDR_FIXED   :
        (fetch_kind_reg == FK_CONV1_W) ? CONV1_W_BASE        :
        (fetch_kind_reg == FK_CONV1_B) ? CONV1_B_BASE        :
        (fetch_kind_reg == FK_CONV2_W) ? CONV2_W_BASE        :
        (fetch_kind_reg == FK_CONV2_B) ? CONV2_B_BASE        :
        (fetch_kind_reg == FK_FILM0_W) ? FILM_L0_W_BASE      :
        (fetch_kind_reg == FK_FILM0_B) ? FILM_L0_B_BASE      :
        (fetch_kind_reg == FK_FILM2_W) ? FILM_L2_W_BASE      :
        FILM_L2_B_BASE;

    assign fetch_word_limit =
        (fetch_kind_reg == FK_SIGNAL)  ? SIGNAL_WORDS        :
        (fetch_kind_reg == FK_FEATURE) ? FEATURE_WORDS       :
        (fetch_kind_reg == FK_CONV1_W) ? CONV1_WEIGHT_WORDS  :
        (fetch_kind_reg == FK_CONV1_B) ? CONV1_BIAS_WORDS    :
        (fetch_kind_reg == FK_CONV2_W) ? CONV2_WEIGHT_WORDS  :
        (fetch_kind_reg == FK_CONV2_B) ? CONV2_BIAS_WORDS    :
        (fetch_kind_reg == FK_FILM0_W) ? FILM_L0_W_WORDS     :
        (fetch_kind_reg == FK_FILM0_B) ? FILM_L0_B_WORDS     :
        (fetch_kind_reg == FK_FILM2_W) ? FILM_L2_W_WORDS     :
        FILM_L2_B_WORDS;

    assign araddr_fetch = fetch_base_addr + (fetch_idx_reg << 2);

    assign write_base_addr =
        (write_bank_reg == WB_PHASE1) ? desc_scratch_addr_reg_r :
        desc_output_addr_reg_r;

    assign write_word_limit =
        (write_bank_reg == WB_PHASE1) ? PHASE1_SCRATCH_WORDS :
        FINAL_OUTPUT_WORDS;

    assign awaddr_writeback = write_base_addr + (write_idx_reg << 2);

    assign m_axi_araddr =
        (state_reg == ST_DESC_AR) ? araddr_desc : araddr_fetch;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = AXI_SIZE_WORD;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arvalid =
        (state_reg == ST_DESC_AR) ||
        (state_reg == ST_FETCH_AR);

    assign m_axi_rready =
        (state_reg == ST_DESC_R) ||
        (state_reg == ST_FETCH_R);

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

    assign read_resp_fire = m_axi_rvalid && m_axi_rready && (m_axi_rresp == 2'b00) && m_axi_rlast;
    assign fetch_is_runtime_input =
        (fetch_kind_reg == FK_SIGNAL) ||
        (fetch_kind_reg == FK_FEATURE);

    assign signal_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_SIGNAL);
    assign feature_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_FEATURE);
    assign conv1_weight_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_CONV1_W);
    assign conv1_bias_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_CONV1_B);
    assign conv2_weight_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_CONV2_W);
    assign conv2_bias_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_CONV2_B);
    assign film_l0_weight_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_FILM0_W);
    assign film_l0_bias_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_FILM0_B);
    assign film_l2_weight_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_FILM2_W);
    assign film_l2_bias_wr_valid =
        (state_reg == ST_FETCH_R) && read_resp_fire && (fetch_kind_reg == FK_FILM2_B);

    assign engine_start_valid = (state_reg == ST_ENGINE_START);

    assign desc_invalid =
        (desc_net_id_reg_r != EXPECTED_NET_ID) ||
        (desc_input_addr_reg_r == 32'd0) ||
        (desc_output_addr_reg_r == 32'd0) ||
        (desc_scratch_addr_reg_r == 32'd0) ||
        (desc_input_words_reg_r != EXPECTED_INPUT_WORDS) ||
        (desc_output_words_reg_r != EXPECTED_OUTPUT_WORDS);

    cnn_frontend_engine_v2 #(
        .SIGNAL_WORDS(SIGNAL_WORDS),
        .FEATURE_WORDS(FEATURE_WORDS),
        .CONV1_WEIGHT_WORDS(CONV1_WEIGHT_WORDS),
        .CONV1_BIAS_WORDS(CONV1_BIAS_WORDS),
        .CONV2_WEIGHT_WORDS(CONV2_WEIGHT_WORDS),
        .CONV2_BIAS_WORDS(CONV2_BIAS_WORDS),
        .FILM_L0_W_WORDS(FILM_L0_W_WORDS),
        .FILM_L0_B_WORDS(FILM_L0_B_WORDS),
        .FILM_L2_W_WORDS(FILM_L2_W_WORDS),
        .FILM_L2_B_WORDS(FILM_L2_B_WORDS),
        .CONV1_IN_CH(CONV1_IN_CH),
        .CONV1_IN_LEN(CONV1_IN_LEN),
        .CONV1_OUT_CH(CONV1_OUT_CH),
        .CONV1_KERNEL(CONV1_KERNEL),
        .CONV1_PAD(CONV1_PAD),
        .CONV2_IN_CH(CONV2_IN_CH),
        .CONV2_IN_LEN(CONV2_IN_LEN),
        .CONV2_OUT_CH(CONV2_OUT_CH),
        .CONV2_KERNEL(CONV2_KERNEL),
        .CONV2_PAD(CONV2_PAD),
        .FILM_HIDDEN_VALUES(FILM_HIDDEN_VALUES),
        .FILM_OUT_VALUES(FILM_OUT_VALUES)
    ) engine_u (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset_pulse(soft_reset_pulse),
        .signal_wr_valid(signal_wr_valid),
        .signal_wr_addr(fetch_idx_reg[15:0]),
        .signal_wr_data(m_axi_rdata),
        .feature_wr_valid(feature_wr_valid),
        .feature_wr_addr(fetch_idx_reg[15:0]),
        .feature_wr_data(m_axi_rdata),
        .conv1_weight_wr_valid(conv1_weight_wr_valid),
        .conv1_weight_wr_addr(fetch_idx_reg[15:0]),
        .conv1_weight_wr_data(m_axi_rdata),
        .conv1_bias_wr_valid(conv1_bias_wr_valid),
        .conv1_bias_wr_addr(fetch_idx_reg[15:0]),
        .conv1_bias_wr_data(m_axi_rdata),
        .conv2_weight_wr_valid(conv2_weight_wr_valid),
        .conv2_weight_wr_addr(fetch_idx_reg[15:0]),
        .conv2_weight_wr_data(m_axi_rdata),
        .conv2_bias_wr_valid(conv2_bias_wr_valid),
        .conv2_bias_wr_addr(fetch_idx_reg[15:0]),
        .conv2_bias_wr_data(m_axi_rdata),
        .film_l0_weight_wr_valid(film_l0_weight_wr_valid),
        .film_l0_weight_wr_addr(fetch_idx_reg[15:0]),
        .film_l0_weight_wr_data(m_axi_rdata),
        .film_l0_bias_wr_valid(film_l0_bias_wr_valid),
        .film_l0_bias_wr_addr(fetch_idx_reg[15:0]),
        .film_l0_bias_wr_data(m_axi_rdata),
        .film_l2_weight_wr_valid(film_l2_weight_wr_valid),
        .film_l2_weight_wr_addr(fetch_idx_reg[15:0]),
        .film_l2_weight_wr_data(m_axi_rdata),
        .film_l2_bias_wr_valid(film_l2_bias_wr_valid),
        .film_l2_bias_wr_addr(fetch_idx_reg[15:0]),
        .film_l2_bias_wr_data(m_axi_rdata),
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
        .output_rd_bank(write_bank_reg),
        .output_rd_addr(write_idx_reg[15:0]),
        .output_rd_data(engine_output_rd_data)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg                    <= ST_IDLE;
            desc_fetch_idx_reg           <= 3'd0;
            fetch_kind_reg               <= FK_SIGNAL;
            fetch_idx_reg                <= 32'd0;
            write_bank_reg               <= WB_PHASE1;
            write_idx_reg                <= 32'd0;
            status_busy_reg              <= 1'b0;
            status_done_reg              <= 1'b0;
            status_error_reg             <= 1'b0;
            desc_net_id_reg_r            <= 32'd0;
            desc_input_addr_reg_r        <= 32'd0;
            desc_output_addr_reg_r       <= 32'd0;
            desc_param_addr_reg_r        <= 32'd0;
            desc_scratch_addr_reg_r      <= 32'd0;
            desc_input_words_reg_r       <= 32'd0;
            desc_output_words_reg_r      <= 32'd0;
            desc_flags_reg_r             <= 32'd0;
            input_fetch_word_count_reg_r <= 32'd0;
            input_checksum_reg_r         <= 32'd0;
            input_last_word_reg_r        <= 32'd0;
            param_fetch_word_count_reg_r <= 32'd0;
            param_checksum_reg_r         <= 32'd0;
            param_last_word_reg_r        <= 32'd0;
        end else begin
            if (soft_reset_pulse) begin
                state_reg                    <= ST_IDLE;
                desc_fetch_idx_reg           <= 3'd0;
                fetch_kind_reg               <= FK_SIGNAL;
                fetch_idx_reg                <= 32'd0;
                write_bank_reg               <= WB_PHASE1;
                write_idx_reg                <= 32'd0;
                status_busy_reg              <= 1'b0;
                status_done_reg              <= 1'b0;
                status_error_reg             <= 1'b0;
                desc_net_id_reg_r            <= 32'd0;
                desc_input_addr_reg_r        <= 32'd0;
                desc_output_addr_reg_r       <= 32'd0;
                desc_param_addr_reg_r        <= 32'd0;
                desc_scratch_addr_reg_r      <= 32'd0;
                desc_input_words_reg_r       <= 32'd0;
                desc_output_words_reg_r      <= 32'd0;
                desc_flags_reg_r             <= 32'd0;
                input_fetch_word_count_reg_r <= 32'd0;
                input_checksum_reg_r         <= 32'd0;
                input_last_word_reg_r        <= 32'd0;
                param_fetch_word_count_reg_r <= 32'd0;
                param_checksum_reg_r         <= 32'd0;
                param_last_word_reg_r        <= 32'd0;
            end else begin
                case (state_reg)
                    ST_IDLE: begin
                        status_busy_reg <= 1'b0;
                        if (launch_pulse) begin
                            status_done_reg              <= 1'b0;
                            status_error_reg             <= 1'b0;
                            input_fetch_word_count_reg_r <= 32'd0;
                            input_checksum_reg_r         <= 32'd0;
                            input_last_word_reg_r        <= 32'd0;
                            param_fetch_word_count_reg_r <= 32'd0;
                            param_checksum_reg_r         <= 32'd0;
                            param_last_word_reg_r        <= 32'd0;
                            fetch_kind_reg               <= FK_SIGNAL;
                            fetch_idx_reg                <= 32'd0;
                            write_bank_reg               <= WB_PHASE1;
                            write_idx_reg                <= 32'd0;

                            if (desc_base_addr == 32'd0) begin
                                status_error_reg <= 1'b1;
                            end else begin
                                status_busy_reg    <= 1'b1;
                                desc_fetch_idx_reg <= 3'd0;
                                state_reg          <= ST_DESC_AR;
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
                                status_busy_reg  <= 1'b0;
                                status_error_reg <= 1'b1;
                                state_reg        <= ST_IDLE;
                            end else begin
                                case (desc_fetch_idx_reg)
                                    3'd0: desc_net_id_reg_r       <= m_axi_rdata;
                                    3'd1: desc_input_addr_reg_r   <= m_axi_rdata;
                                    3'd2: desc_output_addr_reg_r  <= m_axi_rdata;
                                    3'd3: desc_param_addr_reg_r   <= m_axi_rdata;
                                    3'd4: desc_scratch_addr_reg_r <= m_axi_rdata;
                                    3'd5: desc_input_words_reg_r  <= m_axi_rdata;
                                    3'd6: desc_output_words_reg_r <= m_axi_rdata;
                                    default: desc_flags_reg_r     <= m_axi_rdata;
                                endcase

                                if (desc_fetch_idx_reg == 3'd7) begin
                                    fetch_kind_reg <= FK_SIGNAL;
                                    fetch_idx_reg  <= 32'd0;
                                    state_reg      <= ST_VALIDATE;
                                end else begin
                                    desc_fetch_idx_reg <= desc_fetch_idx_reg + 3'd1;
                                    state_reg          <= ST_DESC_AR;
                                end
                            end
                        end
                    end

                    ST_VALIDATE: begin
                        if (desc_invalid) begin
                            status_busy_reg  <= 1'b0;
                            status_error_reg <= 1'b1;
                            state_reg        <= ST_IDLE;
                        end else begin
                            fetch_kind_reg <= FK_SIGNAL;
                            fetch_idx_reg  <= 32'd0;
                            state_reg      <= ST_FETCH_AR;
                        end
                    end

                    ST_FETCH_AR: begin
                        if (m_axi_arvalid && m_axi_arready) begin
                            state_reg <= ST_FETCH_R;
                        end
                    end

                    ST_FETCH_R: begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            if ((m_axi_rresp != 2'b00) || !m_axi_rlast) begin
                                status_busy_reg  <= 1'b0;
                                status_error_reg <= 1'b1;
                                state_reg        <= ST_IDLE;
                            end else begin
                                if (fetch_is_runtime_input) begin
                                    input_fetch_word_count_reg_r <= input_fetch_word_count_reg_r + 32'd1;
                                    input_checksum_reg_r         <= input_checksum_reg_r + m_axi_rdata;
                                    input_last_word_reg_r        <= m_axi_rdata;
                                end else begin
                                    param_fetch_word_count_reg_r <= param_fetch_word_count_reg_r + 32'd1;
                                    param_checksum_reg_r         <= param_checksum_reg_r + m_axi_rdata;
                                    param_last_word_reg_r        <= m_axi_rdata;
                                end

                                if (fetch_idx_reg == (fetch_word_limit - 1)) begin
                                    fetch_idx_reg <= 32'd0;
                                    if (fetch_kind_reg == FK_FILM2_B) begin
                                        state_reg <= ST_ENGINE_START;
                                    end else begin
                                        fetch_kind_reg <= next_fetch_kind;
                                        state_reg <= ST_FETCH_AR;
                                    end
                                end else begin
                                    fetch_idx_reg <= fetch_idx_reg + 32'd1;
                                    state_reg <= ST_FETCH_AR;
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
                            status_busy_reg  <= 1'b0;
                            status_error_reg <= 1'b1;
                            state_reg        <= ST_IDLE;
                        end else if (engine_done_pulse) begin
                            write_bank_reg <= WB_PHASE1;
                            write_idx_reg  <= 32'd0;
                            state_reg      <= ST_WB_AW;
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
                                status_busy_reg  <= 1'b0;
                                status_error_reg <= 1'b1;
                                state_reg        <= ST_IDLE;
                            end else if (write_idx_reg == (write_word_limit - 1)) begin
                                if (write_bank_reg == WB_PHASE1) begin
                                    write_bank_reg <= WB_PHASE2;
                                    write_idx_reg  <= 32'd0;
                                    state_reg      <= ST_WB_AW;
                                end else begin
                                    status_busy_reg <= 1'b0;
                                    status_done_reg <= 1'b1;
                                    state_reg       <= ST_IDLE;
                                end
                            end else begin
                                write_idx_reg <= write_idx_reg + 32'd1;
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
