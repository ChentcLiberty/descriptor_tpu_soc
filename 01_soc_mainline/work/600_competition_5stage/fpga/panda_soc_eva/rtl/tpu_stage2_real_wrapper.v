`timescale 1ns / 1ps
`default_nettype none

module tpu_stage2_real_wrapper #(
    parameter [2:0] AXI_SIZE_WORD = 3'b010,
    parameter [31:0] NET0_PARAM_WORDS = 32'd4,
    parameter [31:0] NET1_PARAM_WORDS = 32'd6,
    parameter [31:0] NET2_PARAM_WORDS = 32'd8,
    parameter [31:0] NET3_PARAM_WORDS = 32'd0
)(
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

    wire unused_ok;
    assign unused_ok = &{
        1'b0,
        NET0_PARAM_WORDS[0],
        NET1_PARAM_WORDS[0],
        NET2_PARAM_WORDS[0],
        NET3_PARAM_WORDS[0]
    };

    localparam [31:0] CNN_NET_ID = tpu_stage2_cnn_frontend_pkg::STAGE2_NET_ID_CNN1D;
    localparam [2:0]
        DST_IDLE    = 3'd0,
        DST_PEEK_AR = 3'd1,
        DST_PEEK_R  = 3'd2,
        DST_CHILD   = 3'd3,
        DST_DONE    = 3'd4,
        DST_FAIL    = 3'd5;

    reg [2:0]  dispatch_state_reg;
    reg        dispatch_cnn_reg;
    reg [31:0] peek_net_id_reg;
    reg [31:0] peek_araddr_reg;
    reg        peek_arvalid_reg;
    reg        peek_rready_reg;
    reg        fullcore_launch_pulse_reg;
    reg        cnn_launch_pulse_reg;
    reg        status_busy_reg;
    reg        status_done_reg;
    reg        status_error_reg;

    wire using_peek;
    assign using_peek = (dispatch_state_reg == DST_PEEK_AR) || (dispatch_state_reg == DST_PEEK_R);

    wire        full_status_busy;
    wire        full_status_done;
    wire        full_status_error;
    wire [31:0] full_desc_net_id_reg;
    wire [31:0] full_desc_input_addr_reg;
    wire [31:0] full_desc_output_addr_reg;
    wire [31:0] full_desc_param_addr_reg;
    wire [31:0] full_desc_scratch_addr_reg;
    wire [31:0] full_desc_input_words_reg;
    wire [31:0] full_desc_output_words_reg;
    wire [31:0] full_desc_flags_reg;
    wire [31:0] full_input_fetch_word_count_reg;
    wire [31:0] full_input_checksum_reg;
    wire [31:0] full_input_last_word_reg;
    wire [31:0] full_param_fetch_word_count_reg;
    wire [31:0] full_param_checksum_reg;
    wire [31:0] full_param_last_word_reg;
    wire [31:0] full_m_axi_araddr;
    wire [1:0]  full_m_axi_arburst;
    wire [7:0]  full_m_axi_arlen;
    wire [2:0]  full_m_axi_arsize;
    wire [3:0]  full_m_axi_arcache;
    wire        full_m_axi_arvalid;
    wire        full_m_axi_arready;
    wire [31:0] full_m_axi_awaddr;
    wire [1:0]  full_m_axi_awburst;
    wire [7:0]  full_m_axi_awlen;
    wire [2:0]  full_m_axi_awsize;
    wire [3:0]  full_m_axi_awcache;
    wire        full_m_axi_awvalid;
    wire        full_m_axi_awready;
    wire [1:0]  full_m_axi_bresp;
    wire        full_m_axi_bvalid;
    wire        full_m_axi_bready;
    wire [31:0] full_m_axi_rdata;
    wire [1:0]  full_m_axi_rresp;
    wire        full_m_axi_rlast;
    wire        full_m_axi_rvalid;
    wire        full_m_axi_rready;
    wire [31:0] full_m_axi_wdata;
    wire [3:0]  full_m_axi_wstrb;
    wire        full_m_axi_wlast;
    wire        full_m_axi_wvalid;
    wire        full_m_axi_wready;

    wire        cnn_status_busy;
    wire        cnn_status_done;
    wire        cnn_status_error;
    wire [31:0] cnn_desc_net_id_reg;
    wire [31:0] cnn_desc_input_addr_reg;
    wire [31:0] cnn_desc_output_addr_reg;
    wire [31:0] cnn_desc_param_addr_reg;
    wire [31:0] cnn_desc_scratch_addr_reg;
    wire [31:0] cnn_desc_input_words_reg;
    wire [31:0] cnn_desc_output_words_reg;
    wire [31:0] cnn_desc_flags_reg;
    wire [31:0] cnn_input_fetch_word_count_reg;
    wire [31:0] cnn_input_checksum_reg;
    wire [31:0] cnn_input_last_word_reg;
    wire [31:0] cnn_param_fetch_word_count_reg;
    wire [31:0] cnn_param_checksum_reg;
    wire [31:0] cnn_param_last_word_reg;
    wire [31:0] cnn_m_axi_araddr;
    wire [1:0]  cnn_m_axi_arburst;
    wire [7:0]  cnn_m_axi_arlen;
    wire [2:0]  cnn_m_axi_arsize;
    wire [3:0]  cnn_m_axi_arcache;
    wire        cnn_m_axi_arvalid;
    wire        cnn_m_axi_arready;
    wire [31:0] cnn_m_axi_awaddr;
    wire [1:0]  cnn_m_axi_awburst;
    wire [7:0]  cnn_m_axi_awlen;
    wire [2:0]  cnn_m_axi_awsize;
    wire [3:0]  cnn_m_axi_awcache;
    wire        cnn_m_axi_awvalid;
    wire        cnn_m_axi_awready;
    wire [1:0]  cnn_m_axi_bresp;
    wire        cnn_m_axi_bvalid;
    wire        cnn_m_axi_bready;
    wire [31:0] cnn_m_axi_rdata;
    wire [1:0]  cnn_m_axi_rresp;
    wire        cnn_m_axi_rlast;
    wire        cnn_m_axi_rvalid;
    wire        cnn_m_axi_rready;
    wire [31:0] cnn_m_axi_wdata;
    wire [3:0]  cnn_m_axi_wstrb;
    wire        cnn_m_axi_wlast;
    wire        cnn_m_axi_wvalid;
    wire        cnn_m_axi_wready;

    assign status_busy  = status_busy_reg;
    assign status_done  = status_done_reg;
    assign status_error = status_error_reg;

    assign desc_net_id_reg       = dispatch_cnn_reg ? cnn_desc_net_id_reg       : full_desc_net_id_reg;
    assign desc_input_addr_reg   = dispatch_cnn_reg ? cnn_desc_input_addr_reg   : full_desc_input_addr_reg;
    assign desc_output_addr_reg  = dispatch_cnn_reg ? cnn_desc_output_addr_reg  : full_desc_output_addr_reg;
    assign desc_param_addr_reg   = dispatch_cnn_reg ? cnn_desc_param_addr_reg   : full_desc_param_addr_reg;
    assign desc_scratch_addr_reg = dispatch_cnn_reg ? cnn_desc_scratch_addr_reg : full_desc_scratch_addr_reg;
    assign desc_input_words_reg  = dispatch_cnn_reg ? cnn_desc_input_words_reg  : full_desc_input_words_reg;
    assign desc_output_words_reg = dispatch_cnn_reg ? cnn_desc_output_words_reg : full_desc_output_words_reg;
    assign desc_flags_reg        = dispatch_cnn_reg ? cnn_desc_flags_reg        : full_desc_flags_reg;

    assign input_fetch_word_count_reg = dispatch_cnn_reg ? cnn_input_fetch_word_count_reg : full_input_fetch_word_count_reg;
    assign input_checksum_reg         = dispatch_cnn_reg ? cnn_input_checksum_reg         : full_input_checksum_reg;
    assign input_last_word_reg        = dispatch_cnn_reg ? cnn_input_last_word_reg        : full_input_last_word_reg;
    assign param_fetch_word_count_reg = dispatch_cnn_reg ? cnn_param_fetch_word_count_reg : full_param_fetch_word_count_reg;
    assign param_checksum_reg         = dispatch_cnn_reg ? cnn_param_checksum_reg         : full_param_checksum_reg;
    assign param_last_word_reg        = dispatch_cnn_reg ? cnn_param_last_word_reg        : full_param_last_word_reg;

    assign m_axi_araddr  = using_peek ? peek_araddr_reg  : (dispatch_cnn_reg ? cnn_m_axi_araddr  : full_m_axi_araddr);
    assign m_axi_arburst = using_peek ? 2'b01           : (dispatch_cnn_reg ? cnn_m_axi_arburst : full_m_axi_arburst);
    assign m_axi_arlen   = using_peek ? 8'd0            : (dispatch_cnn_reg ? cnn_m_axi_arlen   : full_m_axi_arlen);
    assign m_axi_arsize  = using_peek ? AXI_SIZE_WORD   : (dispatch_cnn_reg ? cnn_m_axi_arsize  : full_m_axi_arsize);
    assign m_axi_arcache = using_peek ? 4'b0011         : (dispatch_cnn_reg ? cnn_m_axi_arcache : full_m_axi_arcache);
    assign m_axi_arvalid = using_peek ? peek_arvalid_reg: (dispatch_cnn_reg ? cnn_m_axi_arvalid : full_m_axi_arvalid);
    assign m_axi_rready  = using_peek ? peek_rready_reg : (dispatch_cnn_reg ? cnn_m_axi_rready  : full_m_axi_rready);

    assign m_axi_awaddr  = using_peek ? 32'd0                 : (dispatch_cnn_reg ? cnn_m_axi_awaddr  : full_m_axi_awaddr);
    assign m_axi_awburst = using_peek ? 2'd0                  : (dispatch_cnn_reg ? cnn_m_axi_awburst : full_m_axi_awburst);
    assign m_axi_awlen   = using_peek ? 8'd0                  : (dispatch_cnn_reg ? cnn_m_axi_awlen   : full_m_axi_awlen);
    assign m_axi_awsize  = using_peek ? 3'd0                  : (dispatch_cnn_reg ? cnn_m_axi_awsize  : full_m_axi_awsize);
    assign m_axi_awcache = using_peek ? 4'd0                  : (dispatch_cnn_reg ? cnn_m_axi_awcache : full_m_axi_awcache);
    assign m_axi_awvalid = using_peek ? 1'b0                  : (dispatch_cnn_reg ? cnn_m_axi_awvalid : full_m_axi_awvalid);
    assign m_axi_bready  = using_peek ? 1'b0                  : (dispatch_cnn_reg ? cnn_m_axi_bready  : full_m_axi_bready);
    assign m_axi_wdata   = using_peek ? 32'd0                 : (dispatch_cnn_reg ? cnn_m_axi_wdata   : full_m_axi_wdata);
    assign m_axi_wstrb   = using_peek ? 4'd0                  : (dispatch_cnn_reg ? cnn_m_axi_wstrb   : full_m_axi_wstrb);
    assign m_axi_wlast   = using_peek ? 1'b0                  : (dispatch_cnn_reg ? cnn_m_axi_wlast   : full_m_axi_wlast);
    assign m_axi_wvalid  = using_peek ? 1'b0                  : (dispatch_cnn_reg ? cnn_m_axi_wvalid  : full_m_axi_wvalid);

    assign full_m_axi_arready = (!using_peek && !dispatch_cnn_reg) ? m_axi_arready : 1'b0;
    assign full_m_axi_awready = (!using_peek && !dispatch_cnn_reg) ? m_axi_awready : 1'b0;
    assign full_m_axi_bresp   = m_axi_bresp;
    assign full_m_axi_bvalid  = (!using_peek && !dispatch_cnn_reg) ? m_axi_bvalid : 1'b0;
    assign full_m_axi_rdata   = m_axi_rdata;
    assign full_m_axi_rresp   = m_axi_rresp;
    assign full_m_axi_rlast   = m_axi_rlast;
    assign full_m_axi_rvalid  = (!using_peek && !dispatch_cnn_reg) ? m_axi_rvalid : 1'b0;
    assign full_m_axi_wready  = (!using_peek && !dispatch_cnn_reg) ? m_axi_wready : 1'b0;

    assign cnn_m_axi_arready = (!using_peek && dispatch_cnn_reg) ? m_axi_arready : 1'b0;
    assign cnn_m_axi_awready = (!using_peek && dispatch_cnn_reg) ? m_axi_awready : 1'b0;
    assign cnn_m_axi_bresp   = m_axi_bresp;
    assign cnn_m_axi_bvalid  = (!using_peek && dispatch_cnn_reg) ? m_axi_bvalid : 1'b0;
    assign cnn_m_axi_rdata   = m_axi_rdata;
    assign cnn_m_axi_rresp   = m_axi_rresp;
    assign cnn_m_axi_rlast   = m_axi_rlast;
    assign cnn_m_axi_rvalid  = (!using_peek && dispatch_cnn_reg) ? m_axi_rvalid : 1'b0;
    assign cnn_m_axi_wready  = (!using_peek && dispatch_cnn_reg) ? m_axi_wready : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dispatch_state_reg       <= DST_IDLE;
            dispatch_cnn_reg         <= 1'b0;
            peek_net_id_reg          <= 32'd0;
            peek_araddr_reg          <= 32'd0;
            peek_arvalid_reg         <= 1'b0;
            peek_rready_reg          <= 1'b0;
            fullcore_launch_pulse_reg<= 1'b0;
            cnn_launch_pulse_reg     <= 1'b0;
            status_busy_reg          <= 1'b0;
            status_done_reg          <= 1'b0;
            status_error_reg         <= 1'b0;
        end else begin
            fullcore_launch_pulse_reg <= 1'b0;
            cnn_launch_pulse_reg      <= 1'b0;

            if(soft_reset_pulse) begin
                dispatch_state_reg       <= DST_IDLE;
                dispatch_cnn_reg         <= 1'b0;
                peek_net_id_reg          <= 32'd0;
                peek_araddr_reg          <= 32'd0;
                peek_arvalid_reg         <= 1'b0;
                peek_rready_reg          <= 1'b0;
                status_busy_reg          <= 1'b0;
                status_done_reg          <= 1'b0;
                status_error_reg         <= 1'b0;
            end else begin
                case(dispatch_state_reg)
                    DST_IDLE: begin
                        if(launch_pulse) begin
                            status_done_reg  <= 1'b0;
                            status_error_reg <= 1'b0;
                            if(desc_base_addr == 32'd0) begin
                                status_busy_reg    <= 1'b0;
                                status_error_reg   <= 1'b1;
                                dispatch_state_reg <= DST_FAIL;
                            end else begin
                                status_busy_reg    <= 1'b1;
                                dispatch_cnn_reg   <= 1'b0;
                                peek_net_id_reg    <= 32'd0;
                                peek_araddr_reg    <= desc_base_addr;
                                peek_arvalid_reg   <= 1'b1;
                                peek_rready_reg    <= 1'b0;
                                dispatch_state_reg <= DST_PEEK_AR;
                            end
                        end
                    end

                    DST_PEEK_AR: begin
                        if(m_axi_arready) begin
                            peek_arvalid_reg   <= 1'b0;
                            peek_rready_reg    <= 1'b1;
                            dispatch_state_reg <= DST_PEEK_R;
                        end
                    end

                    DST_PEEK_R: begin
                        if(m_axi_rvalid) begin
                            peek_rready_reg <= 1'b0;
                            if(m_axi_rresp != 2'b00) begin
                                status_busy_reg    <= 1'b0;
                                status_error_reg   <= 1'b1;
                                dispatch_state_reg <= DST_FAIL;
                            end else begin
                                peek_net_id_reg  <= m_axi_rdata;
                                dispatch_cnn_reg <= (m_axi_rdata == CNN_NET_ID);
                                if(m_axi_rdata == CNN_NET_ID) begin
                                    cnn_launch_pulse_reg <= 1'b1;
                                end else begin
                                    fullcore_launch_pulse_reg <= 1'b1;
                                end
                                dispatch_state_reg <= DST_CHILD;
                            end
                        end
                    end

                    DST_CHILD: begin
                        if(dispatch_cnn_reg ? cnn_status_done : full_status_done) begin
                            status_busy_reg    <= 1'b0;
                            status_done_reg    <= 1'b1;
                            dispatch_state_reg <= DST_DONE;
                        end else if(dispatch_cnn_reg ? cnn_status_error : full_status_error) begin
                            status_busy_reg    <= 1'b0;
                            status_error_reg   <= 1'b1;
                            dispatch_state_reg <= DST_FAIL;
                        end
                    end

                    DST_DONE: begin
                    end

                    DST_FAIL: begin
                    end

                    default: begin
                        dispatch_state_reg <= DST_IDLE;
                        status_busy_reg    <= 1'b0;
                        status_done_reg    <= 1'b0;
                        status_error_reg   <= 1'b0;
                    end
                endcase
            end
        end
    end

    tpu_stage2_fullcore_wrapper #(
        .AXI_SIZE_WORD(AXI_SIZE_WORD)
    ) fullcore_wrapper_u (
        .clk(clk),
        .rst_n(rst_n),
        .launch_pulse(fullcore_launch_pulse_reg),
        .soft_reset_pulse(soft_reset_pulse),
        .desc_base_addr(desc_base_addr),
        .status_busy(full_status_busy),
        .status_done(full_status_done),
        .status_error(full_status_error),
        .desc_net_id_reg(full_desc_net_id_reg),
        .desc_input_addr_reg(full_desc_input_addr_reg),
        .desc_output_addr_reg(full_desc_output_addr_reg),
        .desc_param_addr_reg(full_desc_param_addr_reg),
        .desc_scratch_addr_reg(full_desc_scratch_addr_reg),
        .desc_input_words_reg(full_desc_input_words_reg),
        .desc_output_words_reg(full_desc_output_words_reg),
        .desc_flags_reg(full_desc_flags_reg),
        .input_fetch_word_count_reg(full_input_fetch_word_count_reg),
        .input_checksum_reg(full_input_checksum_reg),
        .input_last_word_reg(full_input_last_word_reg),
        .param_fetch_word_count_reg(full_param_fetch_word_count_reg),
        .param_checksum_reg(full_param_checksum_reg),
        .param_last_word_reg(full_param_last_word_reg),
        .m_axi_araddr(full_m_axi_araddr),
        .m_axi_arburst(full_m_axi_arburst),
        .m_axi_arlen(full_m_axi_arlen),
        .m_axi_arsize(full_m_axi_arsize),
        .m_axi_arcache(full_m_axi_arcache),
        .m_axi_arvalid(full_m_axi_arvalid),
        .m_axi_arready(full_m_axi_arready),
        .m_axi_awaddr(full_m_axi_awaddr),
        .m_axi_awburst(full_m_axi_awburst),
        .m_axi_awlen(full_m_axi_awlen),
        .m_axi_awsize(full_m_axi_awsize),
        .m_axi_awcache(full_m_axi_awcache),
        .m_axi_awvalid(full_m_axi_awvalid),
        .m_axi_awready(full_m_axi_awready),
        .m_axi_bresp(full_m_axi_bresp),
        .m_axi_bvalid(full_m_axi_bvalid),
        .m_axi_bready(full_m_axi_bready),
        .m_axi_rdata(full_m_axi_rdata),
        .m_axi_rresp(full_m_axi_rresp),
        .m_axi_rlast(full_m_axi_rlast),
        .m_axi_rvalid(full_m_axi_rvalid),
        .m_axi_rready(full_m_axi_rready),
        .m_axi_wdata(full_m_axi_wdata),
        .m_axi_wstrb(full_m_axi_wstrb),
        .m_axi_wlast(full_m_axi_wlast),
        .m_axi_wvalid(full_m_axi_wvalid),
        .m_axi_wready(full_m_axi_wready)
    );

    tpu_stage2_cnn_frontend_wrapper #(
        .AXI_SIZE_WORD(AXI_SIZE_WORD)
    ) cnn_frontend_wrapper_u (
        .clk(clk),
        .rst_n(rst_n),
        .launch_pulse(cnn_launch_pulse_reg),
        .soft_reset_pulse(soft_reset_pulse),
        .desc_base_addr(desc_base_addr),
        .status_busy(cnn_status_busy),
        .status_done(cnn_status_done),
        .status_error(cnn_status_error),
        .desc_net_id_reg(cnn_desc_net_id_reg),
        .desc_input_addr_reg(cnn_desc_input_addr_reg),
        .desc_output_addr_reg(cnn_desc_output_addr_reg),
        .desc_param_addr_reg(cnn_desc_param_addr_reg),
        .desc_scratch_addr_reg(cnn_desc_scratch_addr_reg),
        .desc_input_words_reg(cnn_desc_input_words_reg),
        .desc_output_words_reg(cnn_desc_output_words_reg),
        .desc_flags_reg(cnn_desc_flags_reg),
        .input_fetch_word_count_reg(cnn_input_fetch_word_count_reg),
        .input_checksum_reg(cnn_input_checksum_reg),
        .input_last_word_reg(cnn_input_last_word_reg),
        .param_fetch_word_count_reg(cnn_param_fetch_word_count_reg),
        .param_checksum_reg(cnn_param_checksum_reg),
        .param_last_word_reg(cnn_param_last_word_reg),
        .m_axi_araddr(cnn_m_axi_araddr),
        .m_axi_arburst(cnn_m_axi_arburst),
        .m_axi_arlen(cnn_m_axi_arlen),
        .m_axi_arsize(cnn_m_axi_arsize),
        .m_axi_arcache(cnn_m_axi_arcache),
        .m_axi_arvalid(cnn_m_axi_arvalid),
        .m_axi_arready(cnn_m_axi_arready),
        .m_axi_awaddr(cnn_m_axi_awaddr),
        .m_axi_awburst(cnn_m_axi_awburst),
        .m_axi_awlen(cnn_m_axi_awlen),
        .m_axi_awsize(cnn_m_axi_awsize),
        .m_axi_awcache(cnn_m_axi_awcache),
        .m_axi_awvalid(cnn_m_axi_awvalid),
        .m_axi_awready(cnn_m_axi_awready),
        .m_axi_bresp(cnn_m_axi_bresp),
        .m_axi_bvalid(cnn_m_axi_bvalid),
        .m_axi_bready(cnn_m_axi_bready),
        .m_axi_rdata(cnn_m_axi_rdata),
        .m_axi_rresp(cnn_m_axi_rresp),
        .m_axi_rlast(cnn_m_axi_rlast),
        .m_axi_rvalid(cnn_m_axi_rvalid),
        .m_axi_rready(cnn_m_axi_rready),
        .m_axi_wdata(cnn_m_axi_wdata),
        .m_axi_wstrb(cnn_m_axi_wstrb),
        .m_axi_wlast(cnn_m_axi_wlast),
        .m_axi_wvalid(cnn_m_axi_wvalid),
        .m_axi_wready(cnn_m_axi_wready)
    );

endmodule

`default_nettype wire
