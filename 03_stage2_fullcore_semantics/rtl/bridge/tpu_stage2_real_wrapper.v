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

    tpu_stage2_fullcore_wrapper #(
        .AXI_SIZE_WORD(AXI_SIZE_WORD)
    ) fullcore_wrapper_u (
        .clk(clk),
        .rst_n(rst_n),
        .launch_pulse(launch_pulse),
        .soft_reset_pulse(soft_reset_pulse),
        .desc_base_addr(desc_base_addr),
        .status_busy(status_busy),
        .status_done(status_done),
        .status_error(status_error),
        .desc_net_id_reg(desc_net_id_reg),
        .desc_input_addr_reg(desc_input_addr_reg),
        .desc_output_addr_reg(desc_output_addr_reg),
        .desc_param_addr_reg(desc_param_addr_reg),
        .desc_scratch_addr_reg(desc_scratch_addr_reg),
        .desc_input_words_reg(desc_input_words_reg),
        .desc_output_words_reg(desc_output_words_reg),
        .desc_flags_reg(desc_flags_reg),
        .input_fetch_word_count_reg(input_fetch_word_count_reg),
        .input_checksum_reg(input_checksum_reg),
        .input_last_word_reg(input_last_word_reg),
        .param_fetch_word_count_reg(param_fetch_word_count_reg),
        .param_checksum_reg(param_checksum_reg),
        .param_last_word_reg(param_last_word_reg),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready)
    );

endmodule

`default_nettype wire
