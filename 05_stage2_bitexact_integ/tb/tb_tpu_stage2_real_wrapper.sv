`timescale 1ns / 1ps
`default_nettype none

module tb_tpu_stage2_real_wrapper;

    localparam integer CLK_PERIOD = 10;
    localparam [31:0] TILE_DESC_BASE_ADDR   = 32'h6001_3000;
    localparam [31:0] TILE_INPUT_BASE_ADDR  = 32'h6001_3100;
    localparam [31:0] TILE_OUTPUT_BASE_ADDR = 32'h6001_3400;
    localparam [31:0] TILE_PARAM_BASE_ADDR  = 32'h6000_4800;
    localparam [31:0] WIDE_TILE_DESC_BASE_ADDR   = 32'h6001_5000;
    localparam [31:0] WIDE_TILE_INPUT_BASE_ADDR  = 32'h6001_5100;
    localparam [31:0] WIDE_TILE_OUTPUT_BASE_ADDR = 32'h6001_5400;
    localparam [31:0] WIDE_TILE_PARAM_BASE_ADDR  = 32'h6000_5800;
    localparam [31:0] LINEAR_DESC_BASE_ADDR   = 32'h6001_7000;
    localparam [31:0] LINEAR_INPUT_BASE_ADDR  = 32'h6001_7100;
    localparam [31:0] LINEAR_OUTPUT_BASE_ADDR = 32'h6001_7400;
    localparam [31:0] LINEAR_PARAM_BASE_ADDR  = 32'h6000_7000;
    localparam [31:0] CPU_BG_BASE_ADDR = 32'h6001_2000;

    reg clk;
    reg rst_n;
    reg launch_pulse;
    reg soft_reset_pulse;
    reg [31:0] desc_base_addr;

    reg  [31:0] cpu_axi_araddr;
    reg  [1:0]  cpu_axi_arburst;
    reg  [7:0]  cpu_axi_arlen;
    reg  [2:0]  cpu_axi_arsize;
    reg  [3:0]  cpu_axi_arcache;
    reg         cpu_axi_arvalid;
    wire        cpu_axi_arready;
    reg  [31:0] cpu_axi_awaddr;
    reg  [1:0]  cpu_axi_awburst;
    reg  [7:0]  cpu_axi_awlen;
    reg  [2:0]  cpu_axi_awsize;
    reg  [3:0]  cpu_axi_awcache;
    reg         cpu_axi_awvalid;
    wire        cpu_axi_awready;
    wire [1:0]  cpu_axi_bresp;
    wire        cpu_axi_bvalid;
    reg         cpu_axi_bready;
    wire [31:0] cpu_axi_rdata;
    wire [1:0]  cpu_axi_rresp;
    wire        cpu_axi_rlast;
    wire        cpu_axi_rvalid;
    reg         cpu_axi_rready;
    reg  [31:0] cpu_axi_wdata;
    reg  [3:0]  cpu_axi_wstrb;
    reg         cpu_axi_wlast;
    reg         cpu_axi_wvalid;
    wire        cpu_axi_wready;

    wire dma_status_busy;
    wire dma_status_done;
    wire dma_status_error;
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

    wire [31:0] tpu_axi_araddr;
    wire [1:0]  tpu_axi_arburst;
    wire [7:0]  tpu_axi_arlen;
    wire [2:0]  tpu_axi_arsize;
    wire [3:0]  tpu_axi_arcache;
    wire        tpu_axi_arvalid;
    wire        tpu_axi_arready;
    wire [31:0] tpu_axi_awaddr;
    wire [1:0]  tpu_axi_awburst;
    wire [7:0]  tpu_axi_awlen;
    wire [2:0]  tpu_axi_awsize;
    wire [3:0]  tpu_axi_awcache;
    wire        tpu_axi_awvalid;
    wire        tpu_axi_awready;
    wire [1:0]  tpu_axi_bresp;
    wire        tpu_axi_bvalid;
    wire        tpu_axi_bready;
    wire [31:0] tpu_axi_rdata;
    wire [1:0]  tpu_axi_rresp;
    wire        tpu_axi_rlast;
    wire        tpu_axi_rvalid;
    wire        tpu_axi_rready;
    wire [31:0] tpu_axi_wdata;
    wire [3:0]  tpu_axi_wstrb;
    wire        tpu_axi_wlast;
    wire        tpu_axi_wvalid;
    wire        tpu_axi_wready;

    integer output_index;
    reg [15:0] expected_even_q8;
    reg [15:0] expected_odd_q8;
    reg [31:0] expected_output_word;
    reg cpu_bg_write_overlap_seen;
    reg cpu_bg_writer_done;

    task tb_fail;
        input [255:0] msg;
        begin
            $display("[TB][FAIL] %0s", msg);
            repeat(5) @(posedge clk);
            $finish;
        end
    endtask

    panda_soc_shared_mem_subsys dut_mem (
        .clk(clk),
        .rst(~rst_n),
        .cpu_axi_araddr(cpu_axi_araddr),
        .cpu_axi_arburst(cpu_axi_arburst),
        .cpu_axi_arlen(cpu_axi_arlen),
        .cpu_axi_arsize(cpu_axi_arsize),
        .cpu_axi_arcache(cpu_axi_arcache),
        .cpu_axi_arvalid(cpu_axi_arvalid),
        .cpu_axi_arready(cpu_axi_arready),
        .cpu_axi_awaddr(cpu_axi_awaddr),
        .cpu_axi_awburst(cpu_axi_awburst),
        .cpu_axi_awlen(cpu_axi_awlen),
        .cpu_axi_awsize(cpu_axi_awsize),
        .cpu_axi_awcache(cpu_axi_awcache),
        .cpu_axi_awvalid(cpu_axi_awvalid),
        .cpu_axi_awready(cpu_axi_awready),
        .cpu_axi_bresp(cpu_axi_bresp),
        .cpu_axi_bvalid(cpu_axi_bvalid),
        .cpu_axi_bready(cpu_axi_bready),
        .cpu_axi_rdata(cpu_axi_rdata),
        .cpu_axi_rresp(cpu_axi_rresp),
        .cpu_axi_rlast(cpu_axi_rlast),
        .cpu_axi_rvalid(cpu_axi_rvalid),
        .cpu_axi_rready(cpu_axi_rready),
        .cpu_axi_wdata(cpu_axi_wdata),
        .cpu_axi_wstrb(cpu_axi_wstrb),
        .cpu_axi_wlast(cpu_axi_wlast),
        .cpu_axi_wvalid(cpu_axi_wvalid),
        .cpu_axi_wready(cpu_axi_wready),
        .tpu_axi_araddr(tpu_axi_araddr),
        .tpu_axi_arburst(tpu_axi_arburst),
        .tpu_axi_arlen(tpu_axi_arlen),
        .tpu_axi_arsize(tpu_axi_arsize),
        .tpu_axi_arcache(tpu_axi_arcache),
        .tpu_axi_arvalid(tpu_axi_arvalid),
        .tpu_axi_arready(tpu_axi_arready),
        .tpu_axi_awaddr(tpu_axi_awaddr),
        .tpu_axi_awburst(tpu_axi_awburst),
        .tpu_axi_awlen(tpu_axi_awlen),
        .tpu_axi_awsize(tpu_axi_awsize),
        .tpu_axi_awcache(tpu_axi_awcache),
        .tpu_axi_awvalid(tpu_axi_awvalid),
        .tpu_axi_awready(tpu_axi_awready),
        .tpu_axi_bresp(tpu_axi_bresp),
        .tpu_axi_bvalid(tpu_axi_bvalid),
        .tpu_axi_bready(tpu_axi_bready),
        .tpu_axi_rdata(tpu_axi_rdata),
        .tpu_axi_rresp(tpu_axi_rresp),
        .tpu_axi_rlast(tpu_axi_rlast),
        .tpu_axi_rvalid(tpu_axi_rvalid),
        .tpu_axi_rready(tpu_axi_rready),
        .tpu_axi_wdata(tpu_axi_wdata),
        .tpu_axi_wstrb(tpu_axi_wstrb),
        .tpu_axi_wlast(tpu_axi_wlast),
        .tpu_axi_wvalid(tpu_axi_wvalid),
        .tpu_axi_wready(tpu_axi_wready)
    );

    tpu_stage2_real_wrapper #(
        .NET0_PARAM_WORDS(32'd4),
        .NET1_PARAM_WORDS(32'd6),
        .NET2_PARAM_WORDS(32'd8),
        .NET3_PARAM_WORDS(32'd0)
    ) dut_dma (
        .clk(clk),
        .rst_n(rst_n),
        .launch_pulse(launch_pulse),
        .soft_reset_pulse(soft_reset_pulse),
        .desc_base_addr(desc_base_addr),
        .status_busy(dma_status_busy),
        .status_done(dma_status_done),
        .status_error(dma_status_error),
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
        .m_axi_araddr(tpu_axi_araddr),
        .m_axi_arburst(tpu_axi_arburst),
        .m_axi_arlen(tpu_axi_arlen),
        .m_axi_arsize(tpu_axi_arsize),
        .m_axi_arcache(tpu_axi_arcache),
        .m_axi_arvalid(tpu_axi_arvalid),
        .m_axi_arready(tpu_axi_arready),
        .m_axi_awaddr(tpu_axi_awaddr),
        .m_axi_awburst(tpu_axi_awburst),
        .m_axi_awlen(tpu_axi_awlen),
        .m_axi_awsize(tpu_axi_awsize),
        .m_axi_awcache(tpu_axi_awcache),
        .m_axi_awvalid(tpu_axi_awvalid),
        .m_axi_awready(tpu_axi_awready),
        .m_axi_bresp(tpu_axi_bresp),
        .m_axi_bvalid(tpu_axi_bvalid),
        .m_axi_bready(tpu_axi_bready),
        .m_axi_rdata(tpu_axi_rdata),
        .m_axi_rresp(tpu_axi_rresp),
        .m_axi_rlast(tpu_axi_rlast),
        .m_axi_rvalid(tpu_axi_rvalid),
        .m_axi_rready(tpu_axi_rready),
        .m_axi_wdata(tpu_axi_wdata),
        .m_axi_wstrb(tpu_axi_wstrb),
        .m_axi_wlast(tpu_axi_wlast),
        .m_axi_wvalid(tpu_axi_wvalid),
        .m_axi_wready(tpu_axi_wready)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cpu_bg_write_overlap_seen <= 1'b0;
        end else if(dma_status_busy && (cpu_axi_awvalid || cpu_axi_wvalid || cpu_axi_bready)) begin
            cpu_bg_write_overlap_seen <= 1'b1;
        end
    end

    task pulse_launch;
        input [31:0] addr;
        begin
            @(posedge clk);
            desc_base_addr <= addr;
            launch_pulse   <= 1'b1;
            @(posedge clk);
            launch_pulse   <= 1'b0;
        end
    endtask

    task cpu_axi_write_word;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            cpu_axi_awaddr  <= addr;
            cpu_axi_awburst <= 2'b01;
            cpu_axi_awlen   <= 8'd0;
            cpu_axi_awsize  <= 3'b010;
            cpu_axi_awcache <= 4'b0011;
            cpu_axi_awvalid <= 1'b1;

            wait(cpu_axi_awready);
            @(posedge clk);
            cpu_axi_awvalid <= 1'b0;

            cpu_axi_wdata  <= data;
            cpu_axi_wstrb  <= 4'hF;
            cpu_axi_wlast  <= 1'b1;
            cpu_axi_wvalid <= 1'b1;

            wait(cpu_axi_wready);
            @(posedge clk);
            cpu_axi_wvalid <= 1'b0;
            cpu_axi_bready <= 1'b1;

            wait(cpu_axi_bvalid);
            if(cpu_axi_bresp != 2'b00) begin
                tb_fail("cpu background write got error response");
            end
            @(posedge clk);
            cpu_axi_bready <= 1'b0;
        end
    endtask

    task pulse_soft_reset;
        begin
            @(posedge clk);
            soft_reset_pulse <= 1'b1;
            @(posedge clk);
            soft_reset_pulse <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n            = 1'b0;
        launch_pulse     = 1'b0;
        soft_reset_pulse = 1'b0;
        desc_base_addr   = 32'd0;
        expected_output_word = 32'd0;
        cpu_bg_writer_done = 1'b0;

        cpu_axi_araddr   = 32'd0;
        cpu_axi_arburst  = 2'd0;
        cpu_axi_arlen    = 8'd0;
        cpu_axi_arsize   = 3'd0;
        cpu_axi_arcache  = 4'd0;
        cpu_axi_arvalid  = 1'b0;
        cpu_axi_awaddr   = 32'd0;
        cpu_axi_awburst  = 2'd0;
        cpu_axi_awlen    = 8'd0;
        cpu_axi_awsize   = 3'd0;
        cpu_axi_awcache  = 4'd0;
        cpu_axi_awvalid  = 1'b0;
        cpu_axi_bready   = 1'b0;
        cpu_axi_rready   = 1'b0;
        cpu_axi_wdata    = 32'd0;
        cpu_axi_wstrb    = 4'd0;
        cpu_axi_wlast    = 1'b0;
        cpu_axi_wvalid   = 1'b0;

        repeat(8) @(posedge clk);
        rst_n = 1'b1;
        repeat(4) @(posedge clk);

        $display("[TB] preload q8.8 2x2 MAC tile descriptor/input/param directly into shared SRAM model");
        dut_mem.axi_ram_u.mem[((TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 0] = 32'h0000_0000;
        dut_mem.axi_ram_u.mem[((TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 1] = TILE_INPUT_BASE_ADDR;
        dut_mem.axi_ram_u.mem[((TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 2] = TILE_OUTPUT_BASE_ADDR;
        dut_mem.axi_ram_u.mem[((TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 3] = TILE_PARAM_BASE_ADDR;
        dut_mem.axi_ram_u.mem[((TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 4] = 32'h6001_3800;
        dut_mem.axi_ram_u.mem[((TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 5] = 32'd1;
        dut_mem.axi_ram_u.mem[((TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 6] = 32'd2;
        dut_mem.axi_ram_u.mem[((TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 7] = 32'h0001_0000;

        dut_mem.axi_ram_u.mem[((TILE_INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 0] = 32'h0200_0100;
        dut_mem.axi_ram_u.mem[((TILE_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 0] = 32'h0400_0300;
        dut_mem.axi_ram_u.mem[((TILE_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 1] = 32'h0080_FF00;
        dut_mem.axi_ram_u.mem[((TILE_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 2] = 32'hFF80_0040;
        dut_mem.axi_ram_u.mem[((TILE_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 3] = 32'h00C0_0040;
        dut_mem.axi_ram_u.mem[((TILE_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 4] = 32'h0100_FE00;
        dut_mem.axi_ram_u.mem[((TILE_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 5] = 32'h0020_0000;
        dut_mem.axi_ram_u.mem[((TILE_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 0] = 32'hDEAD_BEEF;
        dut_mem.axi_ram_u.mem[((TILE_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 1] = 32'hDEAD_BEEF;

        pulse_launch(TILE_DESC_BASE_ADDR);
        wait(dma_status_busy);

        fork
            begin
                repeat(2) @(posedge clk);
                cpu_axi_write_word(CPU_BG_BASE_ADDR + 32'h0, 32'h1111_2222);
                cpu_axi_write_word(CPU_BG_BASE_ADDR + 32'h4, 32'h3333_4444);
                cpu_axi_write_word(CPU_BG_BASE_ADDR + 32'h8, 32'h5555_6666);
                cpu_bg_writer_done = 1'b1;
            end
        join_none

        wait(dma_status_done);
        wait(cpu_bg_writer_done);
        if(dma_status_error) tb_fail("2x2 MAC tile DMA reported error");
        if(!cpu_bg_write_overlap_seen) tb_fail("cpu background write did not overlap with dma busy window");
        if(desc_net_id_reg !== 32'h0000_0000) tb_fail("tile desc_net_id mismatch");
        if(desc_input_addr_reg !== TILE_INPUT_BASE_ADDR) tb_fail("tile desc_input_addr mismatch");
        if(desc_output_addr_reg !== TILE_OUTPUT_BASE_ADDR) tb_fail("tile desc_output_addr mismatch");
        if(desc_param_addr_reg !== TILE_PARAM_BASE_ADDR) tb_fail("tile desc_param_addr mismatch");
        if(desc_input_words_reg !== 32'd1) tb_fail("tile desc_input_words mismatch");
        if(desc_output_words_reg !== 32'd2) tb_fail("tile desc_output_words mismatch");
        if(desc_flags_reg !== 32'h0001_0000) tb_fail("tile desc_flags mismatch");
        if(input_fetch_word_count_reg !== 32'd1) tb_fail("tile input_fetch_word_count mismatch");
        if(param_fetch_word_count_reg !== 32'd6) tb_fail("tile param_fetch_word_count mismatch");
        if(dut_mem.axi_ram_u.mem[((TILE_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 0] !== 32'hFF80_0B40) begin
            $display("[TB][DBG] tile output0 actual=0x%08x expected=0xFF800B40", dut_mem.axi_ram_u.mem[((TILE_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 0]);
            tb_fail("2x2 MAC tile output word0 mismatch");
        end
        if(dut_mem.axi_ram_u.mem[((TILE_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 1] !== 32'h0020_01C0) begin
            $display("[TB][DBG] tile output1 actual=0x%08x expected=0x002001C0", dut_mem.axi_ram_u.mem[((TILE_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 1]);
            tb_fail("2x2 MAC tile output word1 mismatch");
        end
        if(dut_mem.axi_ram_u.mem[((CPU_BG_BASE_ADDR & 32'h007f_ffff) >> 2) + 0] !== 32'h1111_2222) tb_fail("cpu bg write #0 mismatch");
        if(dut_mem.axi_ram_u.mem[((CPU_BG_BASE_ADDR & 32'h007f_ffff) >> 2) + 1] !== 32'h3333_4444) tb_fail("cpu bg write #1 mismatch");
        if(dut_mem.axi_ram_u.mem[((CPU_BG_BASE_ADDR & 32'h007f_ffff) >> 2) + 2] !== 32'h5555_6666) tb_fail("cpu bg write #2 mismatch");
        $display("[TB] q8.8 multi-tile 2x2 MAC outputs matched expected packed results");

        pulse_soft_reset();
        if(dma_status_busy || dma_status_done || dma_status_error) tb_fail("DMA status did not clear after soft reset");
        if(input_fetch_word_count_reg != 32'd0 || param_fetch_word_count_reg != 32'd0) tb_fail("fetch counters did not clear after soft reset");

        $display("[TB] preload q8.8 2-to-32 tile descriptor/input/param directly into shared SRAM model");
        dut_mem.axi_ram_u.mem[((WIDE_TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 0] = 32'h0000_0000;
        dut_mem.axi_ram_u.mem[((WIDE_TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 1] = WIDE_TILE_INPUT_BASE_ADDR;
        dut_mem.axi_ram_u.mem[((WIDE_TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 2] = WIDE_TILE_OUTPUT_BASE_ADDR;
        dut_mem.axi_ram_u.mem[((WIDE_TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 3] = WIDE_TILE_PARAM_BASE_ADDR;
        dut_mem.axi_ram_u.mem[((WIDE_TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 4] = 32'h6001_5800;
        dut_mem.axi_ram_u.mem[((WIDE_TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 5] = 32'd1;
        dut_mem.axi_ram_u.mem[((WIDE_TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 6] = 32'd16;
        dut_mem.axi_ram_u.mem[((WIDE_TILE_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 7] = 32'h0001_0000;

        dut_mem.axi_ram_u.mem[((WIDE_TILE_INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 0] = 32'h0200_0100;
        for(output_index = 0; output_index < 16; output_index = output_index + 1) begin
            expected_even_q8 = (output_index + 1) << 8;
            dut_mem.axi_ram_u.mem[((WIDE_TILE_PARAM_BASE_ADDR & 32'h007f_ffff) >> 2) + (output_index * 3) + 0] = {16'h0000, expected_even_q8};
            dut_mem.axi_ram_u.mem[((WIDE_TILE_PARAM_BASE_ADDR & 32'h007f_ffff) >> 2) + (output_index * 3) + 1] = {expected_even_q8, 16'h0000};
            dut_mem.axi_ram_u.mem[((WIDE_TILE_PARAM_BASE_ADDR & 32'h007f_ffff) >> 2) + (output_index * 3) + 2] = 32'h0000_0000;
            dut_mem.axi_ram_u.mem[((WIDE_TILE_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + output_index] = 32'hDEAD_BEEF;
        end

        pulse_launch(WIDE_TILE_DESC_BASE_ADDR);
        wait(dma_status_busy);
        wait(dma_status_done);
        if(dma_status_error) tb_fail("2-to-32 MAC tile DMA reported error");
        if(param_fetch_word_count_reg !== 32'd48) tb_fail("2-to-32 tile param_fetch_word_count mismatch");
        for(output_index = 0; output_index < 16; output_index = output_index + 1) begin
            expected_even_q8 = (output_index + 1) << 8;
            expected_odd_q8  = (output_index + 1) << 9;
            expected_output_word = {expected_odd_q8, expected_even_q8};
            if(dut_mem.axi_ram_u.mem[((WIDE_TILE_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + output_index] !== expected_output_word) begin
                $display("[TB][DBG] 2-to-32 output[%0d] actual=0x%08x expected=0x%08x", output_index, dut_mem.axi_ram_u.mem[((WIDE_TILE_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + output_index], expected_output_word);
                tb_fail("2-to-32 MAC tile output mismatch");
            end
        end
        $display("[TB] q8.8 2-to-32 tiled MAC outputs matched expected packed results");

        $display("[TB] preload q8.8 multi-input linear descriptor/input/param directly into shared SRAM model");
        dut_mem.axi_ram_u.mem[((LINEAR_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 0] = 32'h0000_0000;
        dut_mem.axi_ram_u.mem[((LINEAR_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 1] = LINEAR_INPUT_BASE_ADDR;
        dut_mem.axi_ram_u.mem[((LINEAR_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 2] = LINEAR_OUTPUT_BASE_ADDR;
        dut_mem.axi_ram_u.mem[((LINEAR_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 3] = LINEAR_PARAM_BASE_ADDR;
        dut_mem.axi_ram_u.mem[((LINEAR_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 4] = 32'h6001_7800;
        dut_mem.axi_ram_u.mem[((LINEAR_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 5] = 32'd2;
        dut_mem.axi_ram_u.mem[((LINEAR_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 6] = 32'd2;
        dut_mem.axi_ram_u.mem[((LINEAR_DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 7] = 32'h0001_0000;

        dut_mem.axi_ram_u.mem[((LINEAR_INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 0] = 32'h0200_0100;
        dut_mem.axi_ram_u.mem[((LINEAR_INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 1] = 32'h0400_0300;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 0] = 32'h0200_0100;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 1] = 32'h0080_FF00;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 2] = 32'h0400_0300;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 3] = 32'h0100_0000;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 4] = 32'h0000_0000;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 5] = 32'h0040_0040;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 6] = 32'h0000_0200;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 7] = 32'h0040_0040;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 8] = 32'h0080_FF00;
        dut_mem.axi_ram_u.mem[((LINEAR_PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 9] = 32'h0000_0000;
        dut_mem.axi_ram_u.mem[((LINEAR_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 0] = 32'hDEAD_BEEF;
        dut_mem.axi_ram_u.mem[((LINEAR_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 1] = 32'hDEAD_BEEF;

        pulse_launch(LINEAR_DESC_BASE_ADDR);
        wait(dma_status_busy);
        wait(dma_status_done);
        if(dma_status_error) tb_fail("multi-input linear DMA reported error");
        if(input_fetch_word_count_reg !== 32'd2) tb_fail("multi-input linear input_fetch_word_count mismatch");
        if(param_fetch_word_count_reg !== 32'd10) tb_fail("multi-input linear param_fetch_word_count mismatch");
        if(dut_mem.axi_ram_u.mem[((LINEAR_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 0] !== 32'h0400_1E00) begin
            $display("[TB][DBG] linear output0 actual=0x%08x expected=0x04001E00", dut_mem.axi_ram_u.mem[((LINEAR_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 0]);
            tb_fail("multi-input linear output word0 mismatch");
        end
        if(dut_mem.axi_ram_u.mem[((LINEAR_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 1] !== 32'h0100_0280) begin
            $display("[TB][DBG] linear output1 actual=0x%08x expected=0x01000280", dut_mem.axi_ram_u.mem[((LINEAR_OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 1]);
            tb_fail("multi-input linear output word1 mismatch");
        end
        $display("[TB] q8.8 multi-input packed linear outputs matched expected packed results");

        pulse_launch(32'd0);
        repeat(2) @(posedge clk);
        if(!dma_status_error) tb_fail("DMA zero-address launch did not assert error");

        $display("[TB][PASS] stage2 real wrapper DMA/tile integration test passed");
        repeat(5) @(posedge clk);
        $finish;
    end

endmodule
`default_nettype wire
