`timescale 1ns / 1ps
`default_nettype none

module tb_tpu_stage2_fullcore_leaky_compare;
    localparam integer CLK_PERIOD = 10;
    localparam [31:0] DESC_BASE   = 32'h6003_0000;
    localparam [31:0] INPUT_BASE  = 32'h6003_0100;
    localparam [31:0] OUTPUT_BASE = 32'h6003_0200;
    localparam [31:0] PARAM_BASE  = 32'h6003_0300;
    localparam [31:0] SCRATCH_BASE = 32'h6003_0400;
    localparam [31:0] TPU_DESC_F_RELU          = 32'h0000_0001;
    localparam [31:0] TPU_DESC_F_TILE2X2_Q8_8   = 32'h0001_0000;
    localparam [31:0] TPU_DESC_F_SCRATCH_LEAK   = 32'h0100_0000;
    localparam integer MAX_INPUT_WORDS = 7;
    localparam integer MAX_PARAM_WORDS = 32;
    localparam integer MAX_OUTPUT_WORDS = 4;

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

    reg [31:0] case_net_id;
    reg [31:0] case_flags;
    reg [31:0] case_input_words;
    reg [31:0] case_output_words;
    reg [31:0] case_scratch_addr;
    reg [15:0] case_leak_factor;
    integer case_param_count;
    reg [31:0] case_input_mem [0:MAX_INPUT_WORDS-1];
    reg [31:0] case_param_mem [0:MAX_PARAM_WORDS-1];
    reg [31:0] case_expected_mem [0:MAX_OUTPUT_WORDS-1];
    integer err_count;
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

    task automatic clear_case_storage;
        begin
            case_net_id = 32'd0;
            case_flags = 32'd0;
            case_input_words = 32'd0;
            case_output_words = 32'd0;
            case_scratch_addr = 32'd0;
            case_leak_factor = 16'd0;
            case_param_count = 0;
            for(i = 0; i < MAX_INPUT_WORDS; i = i + 1) begin
                case_input_mem[i] = 32'd0;
            end
            for(i = 0; i < MAX_PARAM_WORDS; i = i + 1) begin
                case_param_mem[i] = 32'd0;
            end
            for(i = 0; i < MAX_OUTPUT_WORDS; i = i + 1) begin
                case_expected_mem[i] = 32'd0;
            end
        end
    endtask

    task automatic load_case_single_tile_leaky_half;
        begin
            clear_case_storage();
            case_net_id = 32'd10;
            case_flags = TPU_DESC_F_TILE2X2_Q8_8 | TPU_DESC_F_RELU | TPU_DESC_F_SCRATCH_LEAK;
            case_input_words = 32'd1;
            case_output_words = 32'd2;
            case_scratch_addr = SCRATCH_BASE;
            case_leak_factor = 16'h0080;
            case_param_count = 6;

            case_input_mem[0] = 32'h0200_0100;

            case_param_mem[0] = 32'h0080_0100;
            case_param_mem[1] = 32'h0040_ff00;
            case_param_mem[2] = 32'hff80_0040;
            case_param_mem[3] = 32'h0100_0000;
            case_param_mem[4] = 32'hff00_0080;
            case_param_mem[5] = 32'h0000_0000;

            case_expected_mem[0] = 32'hff80_0240;
            case_expected_mem[1] = 32'hff40_0200;
        end
    endtask

    task automatic load_case_multi_tile_leaky_quarter;
        begin
            clear_case_storage();
            case_net_id = 32'd11;
            case_flags = TPU_DESC_F_TILE2X2_Q8_8 | TPU_DESC_F_RELU | TPU_DESC_F_SCRATCH_LEAK;
            case_input_words = 32'd3;
            case_output_words = 32'd2;
            case_scratch_addr = SCRATCH_BASE;
            case_leak_factor = 16'h0040;
            case_param_count = 14;

            case_input_mem[0] = 32'h0100_0200;
            case_input_mem[1] = 32'hfe00_0300;
            case_input_mem[2] = 32'h0080_ff00;

            case_param_mem[0]  = 32'h0000_0100;
            case_param_mem[1]  = 32'h0100_0000;
            case_param_mem[2]  = 32'h0000_0100;
            case_param_mem[3]  = 32'h0100_0000;
            case_param_mem[4]  = 32'h0000_0100;
            case_param_mem[5]  = 32'h0100_0000;
            case_param_mem[6]  = 32'h0000_0000;
            case_param_mem[7]  = 32'hff00_0080;
            case_param_mem[8]  = 32'h0040_0000;
            case_param_mem[9]  = 32'h0080_ff00;
            case_param_mem[10] = 32'h0000_0040;
            case_param_mem[11] = 32'h0100_0080;
            case_param_mem[12] = 32'hff80_0000;
            case_param_mem[13] = 32'h0040_ff00;

            case_expected_mem[0] = 32'hffe0_0400;
            case_expected_mem[1] = 32'h0100_fec0;
        end
    endtask

    task automatic clear_backing_memory;
        begin
            for(i = 0; i < 1024; i = i + 1) begin
                mem[i] = 32'd0;
            end
        end
    endtask

    task automatic program_case_to_memory;
        integer idx;
        begin
            clear_backing_memory();
            mem[(DESC_BASE >> 2) & 32'h3ff] = case_net_id;
            mem[((DESC_BASE + 32'd4) >> 2) & 32'h3ff] = INPUT_BASE;
            mem[((DESC_BASE + 32'd8) >> 2) & 32'h3ff] = OUTPUT_BASE;
            mem[((DESC_BASE + 32'd12) >> 2) & 32'h3ff] = PARAM_BASE;
            mem[((DESC_BASE + 32'd16) >> 2) & 32'h3ff] = case_scratch_addr;
            mem[((DESC_BASE + 32'd20) >> 2) & 32'h3ff] = case_input_words;
            mem[((DESC_BASE + 32'd24) >> 2) & 32'h3ff] = case_output_words;
            mem[((DESC_BASE + 32'd28) >> 2) & 32'h3ff] = case_flags;

            if(case_scratch_addr != 32'd0) begin
                mem[(case_scratch_addr >> 2) & 32'h3ff] = {16'd0, case_leak_factor};
            end
            for(idx = 0; idx < case_input_words; idx = idx + 1) begin
                mem[((INPUT_BASE + (idx << 2)) >> 2) & 32'h3ff] = case_input_mem[idx];
            end
            for(idx = 0; idx < case_param_count; idx = idx + 1) begin
                mem[((PARAM_BASE + (idx << 2)) >> 2) & 32'h3ff] = case_param_mem[idx];
            end
        end
    endtask

    task automatic pulse_soft_reset;
        begin
            @(posedge clk);
            soft_reset_pulse <= 1'b1;
            @(posedge clk);
            soft_reset_pulse <= 1'b0;
        end
    endtask

    task automatic pulse_launch;
        begin
            @(posedge clk);
            desc_base_addr <= DESC_BASE;
            launch_pulse <= 1'b1;
            @(posedge clk);
            launch_pulse <= 1'b0;
        end
    endtask

    task automatic wait_done_or_timeout(input string case_name);
        begin
            timeout_count = 0;
            while((!status_done) && (!status_error) && (timeout_count < 12000)) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            $display("[TB] %s done=%0b error=%0b timeout=%0d out0=%08h out1=%08h in_cnt=%0d param_cnt=%0d",
                     case_name, status_done, status_error, timeout_count,
                     mem[(OUTPUT_BASE >> 2) & 32'h3ff],
                     mem[((OUTPUT_BASE + 32'd4) >> 2) & 32'h3ff],
                     input_fetch_word_count_reg, param_fetch_word_count_reg);
            if(status_error) begin
                $display("[FAIL] %s status_error asserted", case_name);
                err_count = err_count + 1;
            end
            if(!status_done) begin
                $display("[FAIL] %s timeout waiting for done", case_name);
                err_count = err_count + 1;
            end
        end
    endtask

    task automatic compare_case_outputs(input string case_name);
        integer idx;
        reg [31:0] actual_word;
        begin
            if(desc_scratch_addr_reg != case_scratch_addr) begin
                $display("[FAIL] %s scratch addr mismatch: got %08h expected %08h",
                         case_name, desc_scratch_addr_reg, case_scratch_addr);
                err_count = err_count + 1;
            end
            if(input_fetch_word_count_reg != case_input_words) begin
                $display("[FAIL] %s input fetch count mismatch: got %0d expected %0d",
                         case_name, input_fetch_word_count_reg, case_input_words);
                err_count = err_count + 1;
            end
            if(param_fetch_word_count_reg != case_param_count[31:0]) begin
                $display("[FAIL] %s param fetch count mismatch: got %0d expected %0d",
                         case_name, param_fetch_word_count_reg, case_param_count);
                err_count = err_count + 1;
            end
            for(idx = 0; idx < case_output_words; idx = idx + 1) begin
                actual_word = mem[((OUTPUT_BASE + (idx << 2)) >> 2) & 32'h3ff];
                if(actual_word != case_expected_mem[idx]) begin
                    $display("[FAIL] %s out%0d mismatch: got %08h expected %08h",
                             case_name, idx, actual_word, case_expected_mem[idx]);
                    err_count = err_count + 1;
                end
            end
        end
    endtask

    task automatic run_case(input string case_name);
        begin
            pulse_soft_reset();
            program_case_to_memory();
            pulse_launch();
            wait_done_or_timeout(case_name);
            compare_case_outputs(case_name);
        end
    endtask

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
        err_count = 0;
        clear_case_storage();
        clear_backing_memory();

        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        load_case_single_tile_leaky_half();
        run_case("single_tile_leaky_half");

        load_case_multi_tile_leaky_quarter();
        run_case("multi_tile_leaky_quarter");

        if(err_count == 0) begin
            $display("[PASS] tb_tpu_stage2_fullcore_leaky_compare complete");
        end else begin
            $display("[FAIL] tb_tpu_stage2_fullcore_leaky_compare err_count=%0d", err_count);
        end
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
