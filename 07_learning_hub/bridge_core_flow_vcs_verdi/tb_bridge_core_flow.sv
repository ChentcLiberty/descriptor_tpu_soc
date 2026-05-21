`timescale 1ns / 1ps
`default_nettype none

module tb_bridge_core_flow;
    localparam integer CLK_PERIOD = 10;

    localparam [31:0] DESC_BASE   = 32'h6002_0000;
    localparam [31:0] INPUT_BASE  = 32'h6002_0100;
    localparam [31:0] OUTPUT_BASE = 32'h6002_0200;
    localparam [31:0] PARAM_BASE  = 32'h6002_0300;

    localparam [31:0] TPU_DESC_F_RELU         = 32'h0000_0001;
    localparam [31:0] TPU_DESC_F_TILE2X2_Q8_8 = 32'h0001_0000;

    localparam [31:0] EXPECT_OUT0 = 32'h0400_1E00;
    localparam [31:0] EXPECT_OUT1 = 32'h0100_0280;

    localparam integer BR_ST_FE_LOAD_B0 = 23;
    localparam integer BR_ST_FE_LOAD_B1 = 24;
    localparam integer BR_ST_FE_PUSH_B  = 25;

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
    integer tile_launch_count;
    integer tile_done_count;
    integer launch_idx;
    reg [3:0] expected_pathway [0:3];
    reg [15:0] prev_cap0;
    reg [15:0] prev_cap1;
    reg [31:0] tile1_rebias_word;
    reg        saw_tile1_rebias;
    reg        tile_active;
    reg        saw_weight_evt;
    reg        saw_switch_evt;
    reg        saw_bias_evt;
    reg        saw_input_evt;

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

`ifdef ENABLE_FSDB
    initial begin
        $fsdbDumpfile("tb_bridge_core_flow.fsdb");
        $fsdbDumpvars(0, tb_bridge_core_flow);
    end
`else
    initial begin
        $dumpfile("tb_bridge_core_flow.vcd");
        $dumpvars(0, tb_bridge_core_flow);
    end
`endif

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    task fail;
        input [1023:0] msg;
        begin
            $display("[TB][FAIL] %0s", msg);
            $finish;
        end
    endtask

    task check_eq32;
        input [1023:0] what;
        input [31:0] got;
        input [31:0] exp;
        begin
            if (got !== exp) begin
                $display("[TB][FAIL] %0s got=%08h exp=%08h", what, got, exp);
                $finish;
            end
        end
    endtask

    task check_eqi;
        input [1023:0] what;
        input integer got;
        input integer exp;
        begin
            if (got !== exp) begin
                $display("[TB][FAIL] %0s got=%0d exp=%0d", what, got, exp);
                $finish;
            end
        end
    endtask

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

        tile_launch_count = 0;
        tile_done_count = 0;
        launch_idx = 0;
        prev_cap0 = 16'd0;
        prev_cap1 = 16'd0;
        tile1_rebias_word = 32'd0;
        saw_tile1_rebias = 1'b0;
        tile_active = 1'b0;
        saw_weight_evt = 1'b0;
        saw_switch_evt = 1'b0;
        saw_bias_evt = 1'b0;
        saw_input_evt = 1'b0;
        expected_pathway[0] = 4'b1000;
        expected_pathway[1] = 4'b1100;
        expected_pathway[2] = 4'b1000;
        expected_pathway[3] = 4'b1100;

        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'd0;

        mem[(DESC_BASE >> 2) & 32'h3ff] = 32'd0;
        mem[((DESC_BASE + 32'd4) >> 2) & 32'h3ff] = INPUT_BASE;
        mem[((DESC_BASE + 32'd8) >> 2) & 32'h3ff] = OUTPUT_BASE;
        mem[((DESC_BASE + 32'd12) >> 2) & 32'h3ff] = PARAM_BASE;
        mem[((DESC_BASE + 32'd16) >> 2) & 32'h3ff] = 32'd0;
        mem[((DESC_BASE + 32'd20) >> 2) & 32'h3ff] = 32'd2;
        mem[((DESC_BASE + 32'd24) >> 2) & 32'h3ff] = 32'd2;
        mem[((DESC_BASE + 32'd28) >> 2) & 32'h3ff] = TPU_DESC_F_RELU | TPU_DESC_F_TILE2X2_Q8_8;

        mem[(INPUT_BASE >> 2) & 32'h3ff] = 32'h0200_0100;
        mem[((INPUT_BASE + 32'd4) >> 2) & 32'h3ff] = 32'h0400_0300;

        mem[(PARAM_BASE >> 2) & 32'h3ff] = 32'h0200_0100;
        mem[((PARAM_BASE + 32'd4) >> 2) & 32'h3ff] = 32'h0080_FF00;
        mem[((PARAM_BASE + 32'd8) >> 2) & 32'h3ff] = 32'h0400_0300;
        mem[((PARAM_BASE + 32'd12) >> 2) & 32'h3ff] = 32'h0100_0000;
        mem[((PARAM_BASE + 32'd16) >> 2) & 32'h3ff] = 32'h0000_0000;

        mem[((PARAM_BASE + 32'd20) >> 2) & 32'h3ff] = 32'h0040_0040;
        mem[((PARAM_BASE + 32'd24) >> 2) & 32'h3ff] = 32'h0000_0200;
        mem[((PARAM_BASE + 32'd28) >> 2) & 32'h3ff] = 32'h0040_0040;
        mem[((PARAM_BASE + 32'd32) >> 2) & 32'h3ff] = 32'h0080_FF00;
        mem[((PARAM_BASE + 32'd36) >> 2) & 32'h3ff] = 32'h0000_0000;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        @(posedge clk);
        desc_base_addr <= DESC_BASE;
        launch_pulse <= 1'b1;
        @(posedge clk);
        launch_pulse <= 1'b0;

        timeout_count = 0;
        while ((!status_done) && (!status_error) && (timeout_count < 10000)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        if (status_error)
            fail("status_error asserted");
        if (!status_done)
            fail("timeout waiting for status_done");

        check_eq32("output_word0", mem[(OUTPUT_BASE >> 2) & 32'h3ff], EXPECT_OUT0);
        check_eq32("output_word1", mem[((OUTPUT_BASE + 32'd4) >> 2) & 32'h3ff], EXPECT_OUT1);
        check_eq32("input_fetch_word_count_reg", input_fetch_word_count_reg, 32'd2);
        check_eq32("param_fetch_word_count_reg", param_fetch_word_count_reg, 32'd10);
        check_eqi("tile_launch_count", tile_launch_count, 4);
        check_eqi("tile_done_count", tile_done_count, 4);

        if (!saw_tile1_rebias)
            fail("did not observe tile1 rebias during bias preload");

        $display("[TB] output0=%08h output1=%08h", mem[(OUTPUT_BASE >> 2) & 32'h3ff], mem[((OUTPUT_BASE + 32'd4) >> 2) & 32'h3ff]);
        $display("[TB] input_fetch=%0d param_fetch=%0d tile_launch=%0d tile_done=%0d tile1_rebias=%08h",
                 input_fetch_word_count_reg, param_fetch_word_count_reg,
                 tile_launch_count, tile_done_count, tile1_rebias_word);
        $display("[TB][PASS] bridge-to-core flow wrapper diagnostic completed");
        $finish;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            tile_launch_count <= 0;
            tile_done_count <= 0;
            launch_idx <= 0;
            prev_cap0 <= 16'd0;
            prev_cap1 <= 16'd0;
            tile1_rebias_word <= 32'd0;
            saw_tile1_rebias <= 1'b0;
            tile_active <= 1'b0;
            saw_weight_evt <= 1'b0;
            saw_switch_evt <= 1'b0;
            saw_bias_evt <= 1'b0;
            saw_input_evt <= 1'b0;
        end else begin
            if (!saw_tile1_rebias &&
                (dut.bridge_u.tile_word_idx_reg == 32'd1) &&
                ((dut.bridge_u.state_reg == BR_ST_FE_LOAD_B0) ||
                 (dut.bridge_u.state_reg == BR_ST_FE_LOAD_B1) ||
                 (dut.bridge_u.state_reg == BR_ST_FE_PUSH_B))) begin
                tile1_rebias_word <= dut.bridge_u.current_bias_word;
                saw_tile1_rebias <= 1'b1;
                if (dut.bridge_u.current_bias_word !== {prev_cap1, prev_cap0}) begin
                    $display("[TB][FAIL] tile1 rebias mismatch got=%08h exp=%04h_%04h",
                             dut.bridge_u.current_bias_word, prev_cap1, prev_cap0);
                    $finish;
                end
            end

            if (dut.tile_exec_valid && dut.tile_exec_ready) begin
                tile_launch_count <= tile_launch_count + 1;
                if (launch_idx > 3)
                    fail("too many tile launches observed");
                if (dut.tile_exec_pathway !== expected_pathway[launch_idx]) begin
                    $display("[TB][FAIL] tile %0d pathway got=%04b exp=%04b",
                             launch_idx, dut.tile_exec_pathway, expected_pathway[launch_idx]);
                    $finish;
                end
                launch_idx <= launch_idx + 1;
                tile_active <= 1'b1;
                saw_weight_evt <= 1'b0;
                saw_switch_evt <= 1'b0;
                saw_bias_evt <= 1'b0;
                saw_input_evt <= 1'b0;
            end

            if (tile_active && dut.frontend_u.ub_rd_start_out && (dut.frontend_u.ub_ptr_sel_out == 3'd1)) begin
                if (saw_weight_evt)
                    fail("duplicate weight read event inside one tile");
                saw_weight_evt <= 1'b1;
            end
            if (tile_active && dut.frontend_u.sys_switch_out) begin
                if (!saw_weight_evt)
                    fail("sys_switch observed before weight read");
                saw_switch_evt <= 1'b1;
            end
            if (tile_active && dut.frontend_u.ub_rd_start_out && (dut.frontend_u.ub_ptr_sel_out == 3'd2)) begin
                if (!saw_switch_evt)
                    fail("bias read observed before sys_switch");
                saw_bias_evt <= 1'b1;
            end
            if (tile_active && dut.frontend_u.ub_rd_start_out && (dut.frontend_u.ub_ptr_sel_out == 3'd0)) begin
                if (!saw_bias_evt)
                    fail("input read observed before bias read");
                saw_input_evt <= 1'b1;
            end

            if (dut.tile_exec_done) begin
                tile_done_count <= tile_done_count + 1;
                if (!saw_weight_evt || !saw_switch_evt || !saw_bias_evt || !saw_input_evt)
                    fail("tile_exec_done before full frontend step sequence");
                prev_cap0 <= dut.bridge_u.captured_out0_reg;
                prev_cap1 <= dut.bridge_u.captured_out1_reg;
                tile_active <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_pending <= 1'b0;
            m_axi_rvalid <= 1'b0;
            m_axi_bvalid <= 1'b0;
            aw_seen <= 1'b0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                pending_raddr <= m_axi_araddr;
                read_pending <= 1'b1;
            end

            if (read_pending && !m_axi_rvalid) begin
                m_axi_rdata <= mem[(pending_raddr >> 2) & 32'h3ff];
                m_axi_rresp <= 2'b00;
                m_axi_rlast <= 1'b1;
                m_axi_rvalid <= 1'b1;
                read_pending <= 1'b0;
            end else if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
            end

            if (m_axi_awvalid && m_axi_awready) begin
                pending_waddr <= m_axi_awaddr;
                aw_seen <= 1'b1;
            end

            if (aw_seen && m_axi_wvalid && m_axi_wready) begin
                mem[(pending_waddr >> 2) & 32'h3ff] <= m_axi_wdata;
                aw_seen <= 1'b0;
                m_axi_bvalid <= 1'b1;
                m_axi_bresp <= 2'b00;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
