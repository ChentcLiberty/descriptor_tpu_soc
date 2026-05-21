`timescale 1ns / 1ps
`default_nettype none

module tpu_stage2_fullcore_wrapper #(
    parameter [2:0] AXI_SIZE_WORD = 3'b010
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

    wire        fe_cmd_valid;
    wire        fe_cmd_write;
    wire [11:0] fe_cmd_addr;
    wire [31:0] fe_cmd_wdata;
    wire        fe_cmd_ready;
    wire        fe_rsp_valid;
    wire [31:0] fe_rsp_rdata;
    wire        fe_rsp_ready;
    wire        tile_exec_valid;
    wire [5:0]  tile_exec_input_addr;
    wire [5:0]  tile_exec_weight_addr;
    wire [5:0]  tile_exec_bias_addr;
    wire [5:0]  tile_exec_y_addr;
    wire [3:0]  tile_exec_pathway;
    wire        tile_exec_ready;
    wire        tile_exec_done;
    wire        readback_exec_valid;
    wire [5:0]  readback_exec_addr;
    wire        readback_exec_ready;
    wire        core_reset_req;

    wire [15:0] ub_wr_host_data_0;
    wire [15:0] ub_wr_host_data_1;
    wire        ub_wr_host_valid_0;
    wire        ub_wr_host_valid_1;
    wire        ub_wr_ptr_restore;
    wire [15:0] ub_wr_host_data [0:1];
    wire        ub_wr_host_valid[0:1];
    assign ub_wr_host_data[0] = ub_wr_host_data_0;
    assign ub_wr_host_data[1] = ub_wr_host_data_1;
    assign ub_wr_host_valid[0] = ub_wr_host_valid_0;
    assign ub_wr_host_valid[1] = ub_wr_host_valid_1;

    wire        sys_switch;
    wire        ub_rd_start;
    wire        ub_rd_transpose;
    wire [1:0]  ub_rd_col_size;
    wire [3:0]  ub_rd_row_size;
    wire [5:0]  ub_rd_addr;
    wire [2:0]  ub_ptr_sel;
    wire [3:0]  vpu_data_pathway;
    wire [15:0] inv_batch_size_times_two;
    wire [15:0] vpu_leak_factor;
    wire [15:0] learning_rate;

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
    wire [15:0] ub_rd_y_data_out_0;
    wire [15:0] ub_rd_y_data_out_1;
    wire        ub_rd_y_valid_out_0;
    wire        ub_rd_y_valid_out_1;

    tpu_stage2_fullcore_bridge #(
        .AXI_SIZE_WORD(AXI_SIZE_WORD)
    ) bridge_u (
        .clk(clk),
        .rst_n(rst_n),
        .launch_pulse(launch_pulse),
        .soft_reset_pulse(soft_reset_pulse),
        .desc_base_addr(desc_base_addr),
        .vpu_data_out_1(vpu_data_out_1),
        .vpu_data_out_2(vpu_data_out_2),
        .vpu_valid_out_1(vpu_valid_out_1),
        .vpu_valid_out_2(vpu_valid_out_2),
        .ub_rd_y_data_out_0(ub_rd_y_data_out_0),
        .ub_rd_y_data_out_1(ub_rd_y_data_out_1),
        .ub_rd_y_valid_out_0(ub_rd_y_valid_out_0),
        .ub_rd_y_valid_out_1(ub_rd_y_valid_out_1),
        .core_reset_req(core_reset_req),
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
        .m_axi_wready(m_axi_wready),
        .fe_cmd_valid(fe_cmd_valid),
        .fe_cmd_write(fe_cmd_write),
        .fe_cmd_addr(fe_cmd_addr),
        .fe_cmd_wdata(fe_cmd_wdata),
        .fe_cmd_ready(fe_cmd_ready),
        .fe_rsp_valid(fe_rsp_valid),
        .fe_rsp_rdata(fe_rsp_rdata),
        .fe_rsp_ready(fe_rsp_ready),
        .tile_exec_valid(tile_exec_valid),
        .tile_exec_input_addr(tile_exec_input_addr),
        .tile_exec_weight_addr(tile_exec_weight_addr),
        .tile_exec_bias_addr(tile_exec_bias_addr),
        .tile_exec_y_addr(tile_exec_y_addr),
        .tile_exec_pathway(tile_exec_pathway),
        .tile_exec_ready(tile_exec_ready),
        .tile_exec_done(tile_exec_done),
        .readback_exec_valid(readback_exec_valid),
        .readback_exec_addr(readback_exec_addr),
        .readback_exec_ready(readback_exec_ready)
    );

    tpu_frontend_local #(
        .SYSTOLIC_ARRAY_WIDTH(2)
    ) frontend_u (
        .clk(clk),
        .rst_n(rst_n & ~core_reset_req),
        .cmd_valid(fe_cmd_valid),
        .cmd_write(fe_cmd_write),
        .cmd_addr(fe_cmd_addr),
        .cmd_wdata(fe_cmd_wdata),
        .cmd_ready(fe_cmd_ready),
        .rsp_valid(fe_rsp_valid),
        .rsp_rdata(fe_rsp_rdata),
        .rsp_ready(fe_rsp_ready),
        .tpu_vpu_valid_in(vpu_valid_out_1 | vpu_valid_out_2),
        .tile_exec_valid(tile_exec_valid),
        .tile_exec_input_addr(tile_exec_input_addr),
        .tile_exec_weight_addr(tile_exec_weight_addr),
        .tile_exec_bias_addr(tile_exec_bias_addr),
        .tile_exec_y_addr(tile_exec_y_addr),
        .tile_exec_pathway(tile_exec_pathway),
        .tile_exec_ready(tile_exec_ready),
        .tile_exec_done(tile_exec_done),
        .readback_exec_valid(readback_exec_valid),
        .readback_exec_addr(readback_exec_addr),
        .readback_exec_ready(readback_exec_ready),
        .rst_out(),
        .ub_wr_host_data_out_0(ub_wr_host_data_0),
        .ub_wr_host_valid_out_0(ub_wr_host_valid_0),
        .ub_wr_host_data_out_1(ub_wr_host_data_1),
        .ub_wr_host_valid_out_1(ub_wr_host_valid_1),
        .ub_wr_ptr_restore_out(ub_wr_ptr_restore),
        .sys_switch_out(sys_switch),
        .ub_rd_start_out(ub_rd_start),
        .ub_rd_transpose_out(ub_rd_transpose),
        .ub_rd_col_size_out(ub_rd_col_size),
        .ub_rd_row_size_out(ub_rd_row_size),
        .ub_rd_addr_out(ub_rd_addr),
        .ub_ptr_sel_out(ub_ptr_sel),
        .vpu_data_pathway_out(vpu_data_pathway),
        .inv_batch_size_times_two_out(inv_batch_size_times_two),
        .vpu_leak_factor_out(vpu_leak_factor),
        .learning_rate_out(learning_rate)
    );

    tpu #(
        .SYSTOLIC_ARRAY_WIDTH(2),
        .UNIFIED_BUFFER_DEPTH(64)
    ) tpu_inst (
        .clk(clk),
        .rst(~(rst_n & ~core_reset_req)),
        .ub_wr_host_data_in(ub_wr_host_data),
        .ub_wr_host_valid_in(ub_wr_host_valid),
        .ub_wr_ptr_restore_in(ub_wr_ptr_restore),
        .ub_rd_start_in(ub_rd_start),
        .ub_rd_transpose(ub_rd_transpose),
        .ub_ptr_select({6'h0, ub_ptr_sel}),
        .ub_rd_addr_in({10'h0, ub_rd_addr}),
        .ub_rd_row_size({12'h0, ub_rd_row_size}),
        .ub_rd_col_size({14'h0, ub_rd_col_size}),
        .learning_rate_in(learning_rate),
        .vpu_data_pathway(vpu_data_pathway),
        .sys_switch_in(sys_switch),
        .vpu_leak_factor_in(vpu_leak_factor),
        .inv_batch_size_times_two_in(inv_batch_size_times_two),
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
        .ub_rd_weight_valid_out_1(ub_rd_weight_valid_out_1),
        .ub_rd_Y_data_out_0(ub_rd_y_data_out_0),
        .ub_rd_Y_data_out_1(ub_rd_y_data_out_1),
        .ub_rd_Y_valid_out_0(ub_rd_y_valid_out_0),
        .ub_rd_Y_valid_out_1(ub_rd_y_valid_out_1)
    );

    wire unused_ok;
    assign unused_ok = &{
        1'b0,
        sys_data_out_21[0],
        sys_data_out_22[0],
        sys_valid_out_21,
        sys_valid_out_22,
        ub_rd_input_data_out_0[0],
        ub_rd_input_data_out_1[0],
        ub_rd_input_valid_out_0,
        ub_rd_input_valid_out_1,
        ub_rd_weight_data_out_0[0],
        ub_rd_weight_data_out_1[0],
        ub_rd_weight_valid_out_0,
        ub_rd_weight_valid_out_1
    };

endmodule

`default_nettype wire
