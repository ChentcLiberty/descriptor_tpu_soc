`timescale 1ns / 1ps
`default_nettype none

module tb_bridge_core_flow_l1_16x32;
    localparam integer CLK_PERIOD = 10;
    localparam [31:0] MEM_BASE    = 32'h6003_0000;
    localparam [31:0] DESC_BASE   = MEM_BASE + 32'h0000;
    localparam [31:0] INPUT_BASE  = MEM_BASE + 32'h0100;
    localparam [31:0] OUTPUT_BASE = MEM_BASE + 32'h0200;
    localparam [31:0] PARAM_BASE  = MEM_BASE + 32'h1000;
    localparam integer MEM_WORDS  = 4096;

    localparam integer INPUT_WORDS  = 16;
    localparam integer OUTPUT_WORDS = 32;
    localparam integer STRIDE_WORDS = INPUT_WORDS * 2 + 1;
    localparam integer TOTAL_TILES  = INPUT_WORDS * OUTPUT_WORDS;
    localparam integer TOTAL_1000   = OUTPUT_WORDS * (INPUT_WORDS - 1);
    localparam integer TOTAL_1100   = OUTPUT_WORDS;

    localparam [31:0] TPU_DESC_F_RELU         = 32'h0000_0001;
    localparam [31:0] TPU_DESC_F_TILE2X2_Q8_8 = 32'h0001_0000;

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

    reg [31:0] mem [0:MEM_WORDS-1];
    reg [31:0] expected_out [0:OUTPUT_WORDS-1];
    reg [31:0] pending_raddr;
    reg        read_pending;
    reg [31:0] pending_waddr;
    reg        aw_seen;

    integer i;
    integer j;
    integer timeout_count;
    integer tile_launch_count;
    integer tile_done_count;
    integer weight_cmd_count;
    integer switch_count;
    integer bias_cmd_count;
    integer input_cmd_count;
    integer pathway_1000_count;
    integer pathway_1100_count;
    integer launch_idx;
    integer first_failing_out_idx;

    reg [3:0] current_tile_pathway_mon;
    reg       tile_active;
    reg       saw_weight_evt;
    reg       saw_switch_evt;
    reg       saw_bias_evt;
    reg       saw_input_evt;
    reg       saw_ub_weight_valid0;
    reg       saw_ub_weight_valid1;
    reg       saw_ub_input_valid0;
    reg       saw_ub_input_valid1;
    reg       saw_sys_valid21;
    reg       saw_sys_valid22;
    reg       saw_bias_stage_valid1;
    reg       saw_bias_stage_valid2;
    reg       saw_lr_stage_valid1;
    reg       saw_lr_stage_valid2;
    reg       saw_vpu_valid1;
    reg       saw_vpu_valid2;
    reg [15:0] prev_cap0;
    reg [15:0] prev_cap1;
    reg [31:0] first_rebias_word;
    reg        saw_first_rebias;

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
        $fsdbDumpfile("tb_bridge_core_flow_l1_16x32.fsdb");
        $fsdbDumpvars(0, tb_bridge_core_flow_l1_16x32);
    end
`else
    initial begin
        $dumpfile("tb_bridge_core_flow_l1_16x32.vcd");
        $dumpvars(0, tb_bridge_core_flow_l1_16x32);
    end
`endif

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    function automatic integer word_index(input [31:0] addr);
        begin
            word_index = (addr - MEM_BASE) >> 2;
        end
    endfunction

    function automatic integer s16(input [15:0] value);
        begin
            s16 = $signed(value);
        end
    endfunction

    function automatic [15:0] u16(input integer value);
        begin
            u16 = value[15:0];
        end
    endfunction

    function automatic [31:0] pack16(input integer low_lane, input integer high_lane);
        begin
            pack16 = {u16(high_lane), u16(low_lane)};
        end
    endfunction

    function automatic integer coeff_sel(input integer seed);
        begin
            case (seed % 7)
                0: coeff_sel = 16'sh0000;
                1: coeff_sel = 16'sh0020;
                2: coeff_sel = 16'sh0040;
                3: coeff_sel = 16'sh0060;
                4: coeff_sel = -16'sh0040;
                5: coeff_sel = -16'sh0020;
                default: coeff_sel = 16'sh0080;
            endcase
        end
    endfunction

    function automatic integer input_lane0(input integer idx);
        begin
            input_lane0 = ((idx % 8) - 4) * 16'sh0020;
        end
    endfunction

    function automatic integer input_lane1(input integer idx);
        begin
            input_lane1 = (((idx + 3) % 8) - 4) * 16'sh0010;
        end
    endfunction

    function automatic integer bias_lane0(input integer out_idx);
        begin
            bias_lane0 = ((out_idx % 5) - 2) * 16'sh0010;
        end
    endfunction

    function automatic integer bias_lane1(input integer out_idx);
        begin
            bias_lane1 = (((out_idx + 2) % 5) - 2) * 16'sh0010;
        end
    endfunction

    function automatic longint signed round_shift_signed(input longint signed value, input integer shift);
        longint signed add;
        begin
            if (shift <= 0) begin
                round_shift_signed = value <<< (-shift);
            end else begin
                add = 64'sd1 <<< (shift - 1);
                if (value >= 0)
                    round_shift_signed = (value + add) >>> shift;
                else
                    round_shift_signed = -(((-value) + add) >>> shift);
            end
        end
    endfunction

    function automatic [15:0] sat16(input longint signed value);
        begin
            if (value > 32767)
                sat16 = 16'h7FFF;
            else if (value < -32768)
                sat16 = 16'h8000;
            else
                sat16 = value[15:0];
        end
    endfunction

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

    task init_descriptor_inputs_params;
        integer in_idx;
        integer out_idx;
        integer base_idx;
        integer w00;
        integer w01;
        integer w10;
        integer w11;
        begin
            mem[word_index(DESC_BASE + 32'd0)]  = 32'd0;
            mem[word_index(DESC_BASE + 32'd4)]  = INPUT_BASE;
            mem[word_index(DESC_BASE + 32'd8)]  = OUTPUT_BASE;
            mem[word_index(DESC_BASE + 32'd12)] = PARAM_BASE;
            mem[word_index(DESC_BASE + 32'd16)] = 32'd0;
            mem[word_index(DESC_BASE + 32'd20)] = INPUT_WORDS;
            mem[word_index(DESC_BASE + 32'd24)] = OUTPUT_WORDS;
            mem[word_index(DESC_BASE + 32'd28)] = TPU_DESC_F_RELU | TPU_DESC_F_TILE2X2_Q8_8;

            for (in_idx = 0; in_idx < INPUT_WORDS; in_idx = in_idx + 1) begin
                mem[word_index(INPUT_BASE + in_idx * 4)] = pack16(input_lane0(in_idx), input_lane1(in_idx));
            end

            for (out_idx = 0; out_idx < OUTPUT_WORDS; out_idx = out_idx + 1) begin
                base_idx = word_index(PARAM_BASE + out_idx * STRIDE_WORDS * 4);
                for (in_idx = 0; in_idx < INPUT_WORDS; in_idx = in_idx + 1) begin
                    w00 = coeff_sel(out_idx * 11 + in_idx * 3 + 0);
                    w01 = coeff_sel(out_idx * 11 + in_idx * 3 + 1);
                    w10 = coeff_sel(out_idx *  7 + in_idx * 5 + 2);
                    w11 = coeff_sel(out_idx *  7 + in_idx * 5 + 3);
                    mem[base_idx + in_idx * 2 + 0] = pack16(w00, w01);
                    mem[base_idx + in_idx * 2 + 1] = pack16(w10, w11);
                end
                mem[base_idx + INPUT_WORDS * 2] = pack16(bias_lane0(out_idx), bias_lane1(out_idx));
            end
        end
    endtask

    task compute_expected_outputs;
        integer out_idx;
        integer in_idx;
        integer in_word;
        integer p0;
        integer p1;
        integer bias;
        integer x0;
        integer x1;
        longint signed acc0;
        longint signed acc1;
        longint signed shifted0;
        longint signed shifted1;
        integer y0;
        integer y1;
        begin
            for (out_idx = 0; out_idx < OUTPUT_WORDS; out_idx = out_idx + 1) begin
                acc0 = 0;
                acc1 = 0;
                for (in_idx = 0; in_idx < INPUT_WORDS; in_idx = in_idx + 1) begin
                    in_word = mem[word_index(INPUT_BASE + in_idx * 4)];
                    p0 = mem[word_index(PARAM_BASE + (out_idx * STRIDE_WORDS + in_idx * 2 + 0) * 4)];
                    p1 = mem[word_index(PARAM_BASE + (out_idx * STRIDE_WORDS + in_idx * 2 + 1) * 4)];
                    x0 = s16(in_word[15:0]);
                    x1 = s16(in_word[31:16]);
                    acc0 = acc0 + x0 * s16(p0[15:0]);
                    acc0 = acc0 + x1 * s16(p0[31:16]);
                    acc1 = acc1 + x0 * s16(p1[15:0]);
                    acc1 = acc1 + x1 * s16(p1[31:16]);
                end
                bias = mem[word_index(PARAM_BASE + (out_idx * STRIDE_WORDS + INPUT_WORDS * 2) * 4)];
                acc0 = acc0 + (longint'(s16(bias[15:0])) <<< 8);
                acc1 = acc1 + (longint'(s16(bias[31:16])) <<< 8);
                shifted0 = round_shift_signed(acc0, 8);
                shifted1 = round_shift_signed(acc1, 8);
                if (shifted0 < 0)
                    y0 = 0;
                else
                    y0 = sat16(shifted0);
                if (shifted1 < 0)
                    y1 = 0;
                else
                    y1 = sat16(shifted1);
                expected_out[out_idx] = {u16(y1), u16(y0)};
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
        weight_cmd_count = 0;
        switch_count = 0;
        bias_cmd_count = 0;
        input_cmd_count = 0;
        pathway_1000_count = 0;
        pathway_1100_count = 0;
        launch_idx = 0;
        first_failing_out_idx = -1;
        current_tile_pathway_mon = 4'd0;
        tile_active = 1'b0;
        saw_weight_evt = 1'b0;
        saw_switch_evt = 1'b0;
        saw_bias_evt = 1'b0;
        saw_input_evt = 1'b0;
        saw_ub_weight_valid0 = 1'b0;
        saw_ub_weight_valid1 = 1'b0;
        saw_ub_input_valid0 = 1'b0;
        saw_ub_input_valid1 = 1'b0;
        saw_sys_valid21 = 1'b0;
        saw_sys_valid22 = 1'b0;
        saw_bias_stage_valid1 = 1'b0;
        saw_bias_stage_valid2 = 1'b0;
        saw_lr_stage_valid1 = 1'b0;
        saw_lr_stage_valid2 = 1'b0;
        saw_vpu_valid1 = 1'b0;
        saw_vpu_valid2 = 1'b0;
        prev_cap0 = 16'd0;
        prev_cap1 = 16'd0;
        first_rebias_word = 32'd0;
        saw_first_rebias = 1'b0;

        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = 32'd0;
        for (i = 0; i < OUTPUT_WORDS; i = i + 1)
            expected_out[i] = 32'd0;

        init_descriptor_inputs_params();
        compute_expected_outputs();

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        @(posedge clk);
        desc_base_addr <= DESC_BASE;
        launch_pulse <= 1'b1;
        @(posedge clk);
        launch_pulse <= 1'b0;

        timeout_count = 0;
        while ((!status_done) && (!status_error) && (timeout_count < 500000)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        if (status_error)
            fail("status_error asserted");
        if (!status_done)
            fail("timeout waiting for status_done");

        check_eq32("desc_input_words_reg", desc_input_words_reg, INPUT_WORDS);
        check_eq32("desc_output_words_reg", desc_output_words_reg, OUTPUT_WORDS);
        check_eq32("input_fetch_word_count_reg", input_fetch_word_count_reg, INPUT_WORDS);
        check_eq32("param_fetch_word_count_reg", param_fetch_word_count_reg, OUTPUT_WORDS * STRIDE_WORDS);
        check_eqi("tile_launch_count", tile_launch_count, TOTAL_TILES);
        check_eqi("tile_done_count", tile_done_count, TOTAL_TILES);
        check_eqi("weight_cmd_count", weight_cmd_count, TOTAL_TILES);
        check_eqi("switch_count", switch_count, TOTAL_TILES);
        check_eqi("bias_cmd_count", bias_cmd_count, TOTAL_TILES);
        check_eqi("input_cmd_count", input_cmd_count, TOTAL_TILES);
        check_eqi("pathway_1000_count", pathway_1000_count, TOTAL_1000);
        check_eqi("pathway_1100_count", pathway_1100_count, TOTAL_1100);

        if (!saw_first_rebias)
            fail("did not observe first rebias event");

        for (i = 0; i < OUTPUT_WORDS; i = i + 1) begin
            if (mem[word_index(OUTPUT_BASE + i * 4)] !== expected_out[i]) begin
                $display("[TB][FAIL] output_word[%0d] got=%08h exp=%08h",
                         i, mem[word_index(OUTPUT_BASE + i * 4)], expected_out[i]);
                $finish;
            end
        end

        $display("[TB] outputs verified: %0d words", OUTPUT_WORDS);
        $display("[TB] tile_launch=%0d tile_done=%0d 1000=%0d 1100=%0d", tile_launch_count, tile_done_count, pathway_1000_count, pathway_1100_count);
        $display("[TB] frontend events weight=%0d switch=%0d bias=%0d input=%0d", weight_cmd_count, switch_count, bias_cmd_count, input_cmd_count);
        $display("[TB] first_rebias=%08h input_fetch=%0d param_fetch=%0d timeout=%0d", first_rebias_word, input_fetch_word_count_reg, param_fetch_word_count_reg, timeout_count);
        $display("[TB][PASS] full 16x32-word bridge/frontend/core validation completed");
        $finish;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            tile_launch_count <= 0;
            tile_done_count <= 0;
            weight_cmd_count <= 0;
            switch_count <= 0;
            bias_cmd_count <= 0;
            input_cmd_count <= 0;
            pathway_1000_count <= 0;
            pathway_1100_count <= 0;
            launch_idx <= 0;
            current_tile_pathway_mon <= 4'd0;
            tile_active <= 1'b0;
            saw_weight_evt <= 1'b0;
            saw_switch_evt <= 1'b0;
            saw_bias_evt <= 1'b0;
            saw_input_evt <= 1'b0;
            saw_ub_weight_valid0 <= 1'b0;
            saw_ub_weight_valid1 <= 1'b0;
            saw_ub_input_valid0 <= 1'b0;
            saw_ub_input_valid1 <= 1'b0;
            saw_sys_valid21 <= 1'b0;
            saw_sys_valid22 <= 1'b0;
            saw_bias_stage_valid1 <= 1'b0;
            saw_bias_stage_valid2 <= 1'b0;
            saw_lr_stage_valid1 <= 1'b0;
            saw_lr_stage_valid2 <= 1'b0;
            saw_vpu_valid1 <= 1'b0;
            saw_vpu_valid2 <= 1'b0;
            prev_cap0 <= 16'd0;
            prev_cap1 <= 16'd0;
            first_rebias_word <= 32'd0;
            saw_first_rebias <= 1'b0;
        end else begin
            if (!saw_first_rebias &&
                (dut.bridge_u.output_word_idx_reg == 32'd0) &&
                (dut.bridge_u.tile_word_idx_reg == 32'd1) &&
                ((dut.bridge_u.state_reg == BR_ST_FE_LOAD_B0) ||
                 (dut.bridge_u.state_reg == BR_ST_FE_LOAD_B1) ||
                 (dut.bridge_u.state_reg == BR_ST_FE_PUSH_B))) begin
                first_rebias_word <= dut.bridge_u.current_bias_word;
                saw_first_rebias <= 1'b1;
                if (dut.bridge_u.current_bias_word !== {prev_cap1, prev_cap0}) begin
                    $display("[TB][FAIL] first rebias mismatch got=%08h exp=%04h_%04h",
                             dut.bridge_u.current_bias_word, prev_cap1, prev_cap0);
                    $finish;
                end
            end

            if (dut.tile_exec_valid && dut.tile_exec_ready) begin
                tile_launch_count <= tile_launch_count + 1;
                current_tile_pathway_mon <= dut.tile_exec_pathway;
                if (dut.tile_exec_pathway == 4'b1000)
                    pathway_1000_count <= pathway_1000_count + 1;
                else if (dut.tile_exec_pathway == 4'b1100)
                    pathway_1100_count <= pathway_1100_count + 1;
                else begin
                    $display("[TB][FAIL] unexpected tile pathway %04b at launch_idx=%0d", dut.tile_exec_pathway, launch_idx);
                    $finish;
                end
                if ((launch_idx < 4) || (launch_idx >= TOTAL_TILES - 4)) begin
                    $display("[TRACE] tile_launch idx=%0d out_idx=%0d tile_idx=%0d pathway=%04b bias=%08h",
                             launch_idx, dut.bridge_u.output_word_idx_reg, dut.bridge_u.tile_word_idx_reg,
                             dut.tile_exec_pathway, dut.bridge_u.current_bias_word);
                end
                launch_idx <= launch_idx + 1;
                tile_active <= 1'b1;
                saw_weight_evt <= 1'b0;
                saw_switch_evt <= 1'b0;
                saw_bias_evt <= 1'b0;
                saw_input_evt <= 1'b0;
                saw_ub_weight_valid0 <= 1'b0;
                saw_ub_weight_valid1 <= 1'b0;
                saw_ub_input_valid0 <= 1'b0;
                saw_ub_input_valid1 <= 1'b0;
                saw_sys_valid21 <= 1'b0;
                saw_sys_valid22 <= 1'b0;
                saw_bias_stage_valid1 <= 1'b0;
                saw_bias_stage_valid2 <= 1'b0;
                saw_lr_stage_valid1 <= 1'b0;
                saw_lr_stage_valid2 <= 1'b0;
                saw_vpu_valid1 <= 1'b0;
                saw_vpu_valid2 <= 1'b0;
            end

            if (tile_active && dut.frontend_u.ub_rd_start_out && (dut.frontend_u.ub_ptr_sel_out == 3'd1)) begin
                if (saw_weight_evt)
                    fail("duplicate weight-read command inside one tile");
                saw_weight_evt <= 1'b1;
                weight_cmd_count <= weight_cmd_count + 1;
            end
            if (tile_active && dut.frontend_u.sys_switch_out) begin
                if (!saw_weight_evt)
                    fail("sys_switch before weight-read command");
                saw_switch_evt <= 1'b1;
                switch_count <= switch_count + 1;
            end
            if (tile_active && dut.frontend_u.ub_rd_start_out && (dut.frontend_u.ub_ptr_sel_out == 3'd2)) begin
                if (!saw_switch_evt)
                    fail("bias-read command before sys_switch");
                saw_bias_evt <= 1'b1;
                bias_cmd_count <= bias_cmd_count + 1;
            end
            if (tile_active && dut.frontend_u.ub_rd_start_out && (dut.frontend_u.ub_ptr_sel_out == 3'd0)) begin
                if (!saw_bias_evt)
                    fail("input-read command before bias-read command");
                saw_input_evt <= 1'b1;
                input_cmd_count <= input_cmd_count + 1;
            end

            if (tile_active && dut.ub_rd_weight_valid_out_0) saw_ub_weight_valid0 <= 1'b1;
            if (tile_active && dut.ub_rd_weight_valid_out_1) saw_ub_weight_valid1 <= 1'b1;
            if (tile_active && dut.ub_rd_input_valid_out_0)  saw_ub_input_valid0 <= 1'b1;
            if (tile_active && dut.ub_rd_input_valid_out_1)  saw_ub_input_valid1 <= 1'b1;
            if (tile_active && dut.sys_valid_out_21)         saw_sys_valid21 <= 1'b1;
            if (tile_active && dut.sys_valid_out_22)         saw_sys_valid22 <= 1'b1;
            if (tile_active && dut.tpu_inst.vpu_inst.bias_valid_1_out) saw_bias_stage_valid1 <= 1'b1;
            if (tile_active && dut.tpu_inst.vpu_inst.bias_valid_2_out) saw_bias_stage_valid2 <= 1'b1;
            if (tile_active && dut.tpu_inst.vpu_inst.lr_valid_1_out)   saw_lr_stage_valid1 <= 1'b1;
            if (tile_active && dut.tpu_inst.vpu_inst.lr_valid_2_out)   saw_lr_stage_valid2 <= 1'b1;
            if (tile_active && dut.vpu_valid_out_1)         saw_vpu_valid1 <= 1'b1;
            if (tile_active && dut.vpu_valid_out_2)         saw_vpu_valid2 <= 1'b1;

            if (dut.tile_exec_done) begin
                tile_done_count <= tile_done_count + 1;
                if (!saw_weight_evt || !saw_switch_evt || !saw_bias_evt || !saw_input_evt)
                    fail("tile_exec_done before frontend command sequence completed");
                if (!saw_ub_weight_valid0 || !saw_ub_weight_valid1)
                    fail("tile_exec_done before UB weight-valid interaction completed");
                if (!saw_ub_input_valid0 || !saw_ub_input_valid1)
                    fail("tile_exec_done before UB input-valid interaction completed");
                if (!saw_sys_valid21 || !saw_sys_valid22)
                    fail("tile_exec_done before systolic valid outputs completed");
                if (!saw_bias_stage_valid1 || !saw_bias_stage_valid2)
                    fail("tile_exec_done before VPU bias-stage valid completed");
                if (!saw_vpu_valid1 || !saw_vpu_valid2)
                    fail("tile_exec_done before VPU output valid completed");
                if ((current_tile_pathway_mon == 4'b1100) && (!saw_lr_stage_valid1 || !saw_lr_stage_valid2))
                    fail("terminal tile missing leaky-relu stage valid outputs");
                if ((current_tile_pathway_mon == 4'b1000) && (saw_lr_stage_valid1 || saw_lr_stage_valid2))
                    fail("non-terminal tile unexpectedly exercised leaky-relu stage");
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
                m_axi_rdata <= mem[word_index(pending_raddr)];
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
                mem[word_index(pending_waddr)] <= m_axi_wdata;
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
