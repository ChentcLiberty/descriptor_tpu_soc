`timescale 1ns / 1ps
`default_nettype none

`include "uvm_macros.svh"

import uvm_pkg::*;

`include "stage2_net3_obs_if.sv"
`include "test_cases.sv"
`include "envs.sv"
`include "scoreboards.sv"
`include "monitors.sv"
`include "transactions.sv"

module tb_tpu_stage2_real_wrapper_net3_uvm;

    localparam integer CLK_PERIOD = 10;
    localparam [31:0] DESC_BASE_ADDR   = 32'h6015_0000;
    localparam [31:0] SIGNAL_BASE_ADDR = 32'h6012_0000;
    localparam [31:0] FEATURE_BASE_ADDR= 32'h6012_1000;
    localparam [31:0] OUTPUT_BASE_ADDR = 32'h6012_2000;
    localparam [31:0] SCRATCH_BASE_ADDR= 32'h6010_0000;
    localparam [31:0] PARAM_BASE_ADDR  = 32'h6007_0000;
    localparam integer SIGNAL_WORDS    = 500;
    localparam integer OUTPUT_WORDS    = 128;

    reg clk;
    reg rst_n;
    reg launch_pulse;
    reg soft_reset_pulse;
    reg [31:0] desc_base_addr;

    wire        status_busy;
    wire        status_done;
    wire        status_error;
    wire [31:0] desc_net_id_reg;
    wire [31:0] desc_input_addr_reg;
    wire [31:0] desc_output_addr_reg;
    wire [31:0] desc_param_addr_reg;
    wire [31:0] desc_scratch_addr_reg;
    wire [31:0] desc_input_words_reg;
    wire [31:0] desc_output_words_reg;
    wire [31:0] desc_flags_reg;
    wire [31:0] input_fetch_word_count_reg;
    wire [31:0] input_checksum_reg;
    wire [31:0] input_last_word_reg;
    wire [31:0] param_fetch_word_count_reg;
    wire [31:0] param_checksum_reg;
    wire [31:0] param_last_word_reg;

    wire [31:0] m_axi_araddr;
    wire [1:0]  m_axi_arburst;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [3:0]  m_axi_arcache;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_awaddr;
    wire [1:0]  m_axi_awburst;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [3:0]  m_axi_awcache;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rlast;
    wire        m_axi_rvalid;
    wire        m_axi_rready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    wire        m_axi_wready;

    integer idx;

    stage2_net3_obs_if obs_if(.clk(clk));

    function automatic integer mem_index;
        input [31:0] byte_addr;
        begin
            mem_index = ((byte_addr & 32'h007f_ffff) >> 2);
        end
    endfunction

    task pulse_launch;
        begin
            @(posedge clk);
            launch_pulse <= 1'b1;
            @(posedge clk);
            launch_pulse <= 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        obs_if.rst_n = 1'b0;
        uvm_config_db #(virtual stage2_net3_obs_if)::set(null, "uvm_test_top.env.mon", "obs_vif", obs_if);
        run_test("Stage2Net3RealWrapperSmokeTest");
    end

    always @(*) begin
        obs_if.rst_n                     = rst_n;
        obs_if.status_busy               = status_busy;
        obs_if.status_done               = status_done;
        obs_if.status_error              = status_error;
        obs_if.desc_net_id_reg           = desc_net_id_reg;
        obs_if.desc_input_addr_reg       = desc_input_addr_reg;
        obs_if.desc_output_addr_reg      = desc_output_addr_reg;
        obs_if.desc_scratch_addr_reg     = desc_scratch_addr_reg;
        obs_if.desc_input_words_reg      = desc_input_words_reg;
        obs_if.desc_output_words_reg     = desc_output_words_reg;
        obs_if.input_fetch_word_count_reg= input_fetch_word_count_reg;
        obs_if.input_checksum_reg        = input_checksum_reg;
        obs_if.param_fetch_word_count_reg= param_fetch_word_count_reg;
        obs_if.param_checksum_reg        = param_checksum_reg;
        obs_if.signal_word0              = panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(SIGNAL_BASE_ADDR) + 0];
        obs_if.feature_word0             = panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(FEATURE_BASE_ADDR) + 0];
        obs_if.output_word0              = panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(OUTPUT_BASE_ADDR) + 0];
        obs_if.output_word7              = panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(OUTPUT_BASE_ADDR) + 7];
        obs_if.output_word31             = panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(OUTPUT_BASE_ADDR) + 31];
        obs_if.output_word63             = panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(OUTPUT_BASE_ADDR) + 63];
        obs_if.output_word95             = panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(OUTPUT_BASE_ADDR) + 95];
        obs_if.output_word127            = panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(OUTPUT_BASE_ADDR) + 127];
    end

    initial begin
        #(500_000_000);
        $fatal(1, "[TB][FAIL] global timeout waiting for NET_ID=3 UVM smoke");
    end

    tpu_stage2_real_wrapper tpu_stage2_real_wrapper_u (
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

    panda_soc_shared_mem_subsys panda_soc_shared_mem_subsys_u (
        .clk(clk),
        .rst(~rst_n),
        .cpu_axi_araddr(32'd0),
        .cpu_axi_arburst(2'd0),
        .cpu_axi_arlen(8'd0),
        .cpu_axi_arsize(3'd0),
        .cpu_axi_arcache(4'd0),
        .cpu_axi_arvalid(1'b0),
        .cpu_axi_arready(),
        .cpu_axi_awaddr(32'd0),
        .cpu_axi_awburst(2'd0),
        .cpu_axi_awlen(8'd0),
        .cpu_axi_awsize(3'd0),
        .cpu_axi_awcache(4'd0),
        .cpu_axi_awvalid(1'b0),
        .cpu_axi_awready(),
        .cpu_axi_bresp(),
        .cpu_axi_bvalid(),
        .cpu_axi_bready(1'b0),
        .cpu_axi_rdata(),
        .cpu_axi_rresp(),
        .cpu_axi_rlast(),
        .cpu_axi_rvalid(),
        .cpu_axi_rready(1'b0),
        .cpu_axi_wdata(32'd0),
        .cpu_axi_wstrb(4'd0),
        .cpu_axi_wlast(1'b0),
        .cpu_axi_wvalid(1'b0),
        .cpu_axi_wready(),
        .tpu_axi_araddr(m_axi_araddr),
        .tpu_axi_arburst(m_axi_arburst),
        .tpu_axi_arlen(m_axi_arlen),
        .tpu_axi_arsize(m_axi_arsize),
        .tpu_axi_arcache(m_axi_arcache),
        .tpu_axi_arvalid(m_axi_arvalid),
        .tpu_axi_arready(m_axi_arready),
        .tpu_axi_awaddr(m_axi_awaddr),
        .tpu_axi_awburst(m_axi_awburst),
        .tpu_axi_awlen(m_axi_awlen),
        .tpu_axi_awsize(m_axi_awsize),
        .tpu_axi_awcache(m_axi_awcache),
        .tpu_axi_awvalid(m_axi_awvalid),
        .tpu_axi_awready(m_axi_awready),
        .tpu_axi_bresp(m_axi_bresp),
        .tpu_axi_bvalid(m_axi_bvalid),
        .tpu_axi_bready(m_axi_bready),
        .tpu_axi_rdata(m_axi_rdata),
        .tpu_axi_rresp(m_axi_rresp),
        .tpu_axi_rlast(m_axi_rlast),
        .tpu_axi_rvalid(m_axi_rvalid),
        .tpu_axi_rready(m_axi_rready),
        .tpu_axi_wdata(m_axi_wdata),
        .tpu_axi_wstrb(m_axi_wstrb),
        .tpu_axi_wlast(m_axi_wlast),
        .tpu_axi_wvalid(m_axi_wvalid),
        .tpu_axi_wready(m_axi_wready)
    );

    initial begin
        rst_n = 1'b0;
        launch_pulse = 1'b0;
        soft_reset_pulse = 1'b0;
        desc_base_addr = DESC_BASE_ADDR;

        repeat(8) @(posedge clk);
        rst_n = 1'b1;
        repeat(4) @(posedge clk);

        $display("[TB][UVM] preload shared SRAM from breath_cpu_frontend_q8_8.mem");
        $readmemh(
            "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_cpu_frontend_q8_8/breath_cpu_frontend_q8_8.mem",
            panda_soc_shared_mem_subsys_u.axi_ram_u.mem
        );

        for(idx = 0; idx < OUTPUT_WORDS; idx = idx + 1) begin
            panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(OUTPUT_BASE_ADDR) + idx] = 32'hDEAD_BEEF;
        end

        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(DESC_BASE_ADDR) + 0] = 32'd3;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(DESC_BASE_ADDR) + 1] = SIGNAL_BASE_ADDR;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(DESC_BASE_ADDR) + 2] = OUTPUT_BASE_ADDR;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(DESC_BASE_ADDR) + 3] = PARAM_BASE_ADDR;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(DESC_BASE_ADDR) + 4] = SCRATCH_BASE_ADDR;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(DESC_BASE_ADDR) + 5] = SIGNAL_WORDS;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(DESC_BASE_ADDR) + 6] = OUTPUT_WORDS;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(DESC_BASE_ADDR) + 7] = 32'd0;

        pulse_launch();
    end

endmodule

`default_nettype wire
