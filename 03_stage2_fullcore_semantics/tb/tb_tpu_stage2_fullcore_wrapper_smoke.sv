`timescale 1ns / 1ps
`default_nettype none

module tb_tpu_stage2_fullcore_wrapper_smoke;
    localparam integer CLK_PERIOD = 10;
    localparam [31:0] DESC_BASE   = 32'h6001_0000;
    localparam [31:0] INPUT_BASE  = 32'h6001_0100;
    localparam [31:0] OUTPUT_BASE = 32'h6001_0200;
    localparam [31:0] PARAM_BASE  = 32'h6001_0300;
    localparam [31:0] TPU_DESC_F_TILE2X2_Q8_8 = 32'h0001_0000;

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
    reg         m_axi_arready;
    wire [31:0] m_axi_awaddr;
    wire [1:0]  m_axi_awburst;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [3:0]  m_axi_awcache;
    wire        m_axi_awvalid;
    reg         m_axi_awready;
    reg  [1:0]  m_axi_bresp;
    reg         m_axi_bvalid;
    wire        m_axi_bready;
    reg  [31:0] m_axi_rdata;
    reg  [1:0]  m_axi_rresp;
    reg         m_axi_rlast;
    reg         m_axi_rvalid;
    wire        m_axi_rready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;

    reg [31:0] mem [0:1023];
    reg [31:0] pending_raddr;
    reg        read_pending;
    reg [31:0] pending_waddr;
    reg        aw_seen;
    integer i;
    integer timeout_count;

    tpu_stage2_fullcore_wrapper dut (
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

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        launch_pulse = 1'b0;
        soft_reset_pulse = 1'b0;
        desc_base_addr = 32'd0;
        m_axi_arready = 1'b1;
        m_axi_awready = 1'b1;
        m_axi_bresp = 2'b00;
        m_axi_bvalid = 1'b0;
        m_axi_rdata = 32'd0;
        m_axi_rresp = 2'b00;
        m_axi_rlast = 1'b1;
        m_axi_rvalid = 1'b0;
        m_axi_wready = 1'b1;
        pending_raddr = 32'd0;
        read_pending = 1'b0;
        pending_waddr = 32'd0;
        aw_seen = 1'b0;

        for(i = 0; i < 1024; i = i + 1) begin
            mem[i] = 32'd0;
        end

        mem[(DESC_BASE  >> 2) & 32'h3ff] = 32'd0;
        mem[((DESC_BASE + 32'd4)  >> 2) & 32'h3ff] = INPUT_BASE;
        mem[((DESC_BASE + 32'd8)  >> 2) & 32'h3ff] = OUTPUT_BASE;
        mem[((DESC_BASE + 32'd12) >> 2) & 32'h3ff] = PARAM_BASE;
        mem[((DESC_BASE + 32'd16) >> 2) & 32'h3ff] = 32'd0;
        mem[((DESC_BASE + 32'd20) >> 2) & 32'h3ff] = 32'd1;
        mem[((DESC_BASE + 32'd24) >> 2) & 32'h3ff] = 32'd2;
        mem[((DESC_BASE + 32'd28) >> 2) & 32'h3ff] = TPU_DESC_F_TILE2X2_Q8_8;

        mem[(INPUT_BASE >> 2) & 32'h3ff] = 32'h0200_0100;

        mem[(PARAM_BASE >> 2) & 32'h3ff] = 32'h0080_0100;
        mem[((PARAM_BASE + 32'd4) >> 2) & 32'h3ff] = 32'h0040_ff00;
        mem[((PARAM_BASE + 32'd8) >> 2) & 32'h3ff] = 32'hff80_0040;

        mem[((PARAM_BASE + 32'd12) >> 2) & 32'h3ff] = 32'h0100_0000;
        mem[((PARAM_BASE + 32'd16) >> 2) & 32'h3ff] = 32'hff00_0080;
        mem[((PARAM_BASE + 32'd20) >> 2) & 32'h3ff] = 32'h0000_0000;

        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        @(posedge clk);
        desc_base_addr <= DESC_BASE;
        launch_pulse <= 1'b1;
        @(posedge clk);
        launch_pulse <= 1'b0;

        timeout_count = 0;
        while((!status_done) && (!status_error) && (timeout_count < 6000)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        $display("[TB] done=%0b error=%0b timeout=%0d out0=%08h out1=%08h in_cnt=%0d param_cnt=%0d", status_done, status_error, timeout_count, mem[(OUTPUT_BASE >> 2) & 32'h3ff], mem[((OUTPUT_BASE + 32'd4) >> 2) & 32'h3ff], input_fetch_word_count_reg, param_fetch_word_count_reg);

        if(status_error) begin
            $display("[TB][FAIL] status_error asserted");
            $finish;
        end
        if(!status_done) begin
            $display("[TB][FAIL] timeout waiting for done");
            $finish;
        end
        if(input_fetch_word_count_reg != 32'd1) begin
            $display("[TB][FAIL] input fetch count mismatch: %0d", input_fetch_word_count_reg);
            $finish;
        end
        if(param_fetch_word_count_reg != 32'd6) begin
            $display("[TB][FAIL] param fetch count mismatch: %0d", param_fetch_word_count_reg);
            $finish;
        end
        if(mem[(OUTPUT_BASE >> 2) & 32'h3ff] != 32'hff00_0240) begin
            $display("[TB][FAIL] out0 mismatch: got %08h expected ff000240", mem[(OUTPUT_BASE >> 2) & 32'h3ff]);
            $finish;
        end
        if(mem[((OUTPUT_BASE + 32'd4) >> 2) & 32'h3ff] != 32'hfe80_0200) begin
            $display("[TB][FAIL] out1 mismatch: got %08h expected fe800200", mem[((OUTPUT_BASE + 32'd4) >> 2) & 32'h3ff]);
            $finish;
        end

        $display("[TB][PASS] fullcore smoke completed, out0=%08h out1=%08h", mem[(OUTPUT_BASE >> 2) & 32'h3ff], mem[((OUTPUT_BASE + 32'd4) >> 2) & 32'h3ff]);
        $finish;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            read_pending <= 1'b0;
            m_axi_rvalid <= 1'b0;
            m_axi_bvalid <= 1'b0;
            aw_seen <= 1'b0;
        end else begin
            if(m_axi_arvalid && m_axi_arready) begin
                pending_raddr <= m_axi_araddr;
                read_pending <= 1'b1;
            end

            if(read_pending && !m_axi_rvalid) begin
                m_axi_rdata <= mem[(pending_raddr >> 2) & 32'h3ff];
                m_axi_rresp <= 2'b00;
                m_axi_rlast <= 1'b1;
                m_axi_rvalid <= 1'b1;
                read_pending <= 1'b0;
            end else if(m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
            end

            if(m_axi_awvalid && m_axi_awready) begin
                pending_waddr <= m_axi_awaddr;
                aw_seen <= 1'b1;
            end

            if(aw_seen && m_axi_wvalid && m_axi_wready) begin
                mem[(pending_waddr >> 2) & 32'h3ff] <= m_axi_wdata;
                aw_seen <= 1'b0;
                m_axi_bvalid <= 1'b1;
                m_axi_bresp <= 2'b00;
            end else if(m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
