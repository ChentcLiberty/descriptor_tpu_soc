`timescale 1ns / 1ps
`default_nettype none

module tb_tpu_stage2_cnn_frontend_smoke;

    localparam [31:0] DESC0_BASE      = 32'h6001_0000;
    localparam [31:0] DESC1_BASE      = 32'h6001_0100;
    localparam [31:0] SIGNAL_BASE     = 32'h6012_0000;
    localparam [31:0] FEATURE_BASE    = 32'h6012_1000;
    localparam [31:0] OUTPUT_BASE     = 32'h6012_2000;
    localparam [31:0] SCRATCH_BASE    = 32'h6010_0000;
    localparam [31:0] CONV1_W_BASE    = 32'h6007_0000;
    localparam [31:0] CONV1_B_BASE    = 32'h6007_0200;
    localparam [31:0] CONV2_W_BASE    = 32'h6007_0300;
    localparam [31:0] CONV2_B_BASE    = 32'h6007_5300;
    localparam [31:0] FILM_L0_W_BASE  = 32'h600B_1700;
    localparam [31:0] FILM_L0_B_BASE  = 32'h600B_1800;
    localparam [31:0] FILM_L2_W_BASE  = 32'h600B_1900;
    localparam [31:0] FILM_L2_B_BASE  = 32'h600B_5900;

    localparam integer CONV1_IN_LEN = 8;
    localparam integer SIGNAL_WORDS = 4;
    localparam integer FEATURE_WORDS = 1;
    localparam integer CONV1_OUT_CH = 2;
    localparam integer CONV1_KERNEL = 3;
    localparam integer CONV1_PAD = 1;
    localparam integer CONV1_WEIGHT_WORDS = 3;
    localparam integer CONV1_BIAS_WORDS = 1;
    localparam integer PHASE1_SCRATCH_WORDS = (CONV1_OUT_CH * (CONV1_IN_LEN / 2)) / 2;

    localparam integer CONV2_IN_CH = 2;
    localparam integer CONV2_IN_LEN = 4;
    localparam integer CONV2_OUT_CH = 2;
    localparam integer CONV2_KERNEL = 3;
    localparam integer CONV2_PAD = 1;
    localparam integer CONV2_WEIGHT_WORDS = 6;
    localparam integer CONV2_BIAS_WORDS = 1;

    localparam integer FILM_HIDDEN_VALUES = 2;
    localparam integer FILM_OUT_VALUES = 4;
    localparam integer FILM_L0_W_WORDS = 2;
    localparam integer FILM_L0_B_WORDS = 1;
    localparam integer FILM_L2_W_WORDS = 4;
    localparam integer FILM_L2_B_WORDS = 2;

    localparam integer FINAL_OUTPUT_WORDS = 2;
    localparam integer TOTAL_PARAM_WORDS =
        CONV1_WEIGHT_WORDS + CONV1_BIAS_WORDS +
        CONV2_WEIGHT_WORDS + CONV2_BIAS_WORDS +
        FILM_L0_W_WORDS + FILM_L0_B_WORDS +
        FILM_L2_W_WORDS + FILM_L2_B_WORDS;
    localparam integer TOTAL_INPUT_WORDS = SIGNAL_WORDS + FEATURE_WORDS;

    reg         clk;
    reg         rst_n;
    reg         launch_pulse;
    reg         soft_reset_pulse;
    reg  [31:0] desc_base_addr;

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

    reg [31:0] desc_words        [0:15];
    reg [31:0] signal_words      [0:SIGNAL_WORDS-1];
    reg [31:0] feature_words     [0:FEATURE_WORDS-1];
    reg [31:0] conv1_weight_words[0:CONV1_WEIGHT_WORDS-1];
    reg [31:0] conv1_bias_words  [0:CONV1_BIAS_WORDS-1];
    reg [31:0] conv2_weight_words[0:CONV2_WEIGHT_WORDS-1];
    reg [31:0] conv2_bias_words  [0:CONV2_BIAS_WORDS-1];
    reg [31:0] film_l0_weight_words[0:FILM_L0_W_WORDS-1];
    reg [31:0] film_l0_bias_words[0:FILM_L0_B_WORDS-1];
    reg [31:0] film_l2_weight_words[0:FILM_L2_W_WORDS-1];
    reg [31:0] film_l2_bias_words[0:FILM_L2_B_WORDS-1];
    reg [31:0] scratch_words     [0:PHASE1_SCRATCH_WORDS-1];
    reg [31:0] output_words_mem  [0:FINAL_OUTPUT_WORDS-1];
    reg [31:0] write_addr_pending;
    reg        write_addr_seen;
    integer i;

    tpu_stage2_cnn_frontend_wrapper #(
        .EXPECTED_NET_ID(32'd3),
        .EXPECTED_INPUT_WORDS(SIGNAL_WORDS),
        .EXPECTED_OUTPUT_WORDS(FINAL_OUTPUT_WORDS),
        .FEATURE_ADDR_FIXED(FEATURE_BASE),
        .CONV1_W_BASE(CONV1_W_BASE),
        .CONV1_B_BASE(CONV1_B_BASE),
        .CONV2_W_BASE(CONV2_W_BASE),
        .CONV2_B_BASE(CONV2_B_BASE),
        .FILM_L0_W_BASE(FILM_L0_W_BASE),
        .FILM_L0_B_BASE(FILM_L0_B_BASE),
        .FILM_L2_W_BASE(FILM_L2_W_BASE),
        .FILM_L2_B_BASE(FILM_L2_B_BASE),
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
        .FINAL_OUTPUT_WORDS(FINAL_OUTPUT_WORDS),
        .CONV1_IN_CH(1),
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
    ) dut (
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

    function [31:0] pack_q16;
        input integer low_val;
        input integer high_val;
        reg [15:0] low_bits;
        reg [15:0] high_bits;
        begin
            low_bits = low_val[15:0];
            high_bits = high_val[15:0];
            pack_q16 = {high_bits, low_bits};
        end
    endfunction

    function [31:0] bus_read_word;
        input [31:0] addr;
        integer idx;
        begin
            if ((addr >= DESC0_BASE) && (addr < (DESC0_BASE + 8 * 4))) begin
                idx = (addr - DESC0_BASE) >> 2;
                bus_read_word = desc_words[idx];
            end else if ((addr >= DESC1_BASE) && (addr < (DESC1_BASE + 8 * 4))) begin
                idx = 8 + ((addr - DESC1_BASE) >> 2);
                bus_read_word = desc_words[idx];
            end else if ((addr >= SIGNAL_BASE) && (addr < (SIGNAL_BASE + SIGNAL_WORDS * 4))) begin
                idx = (addr - SIGNAL_BASE) >> 2;
                bus_read_word = signal_words[idx];
            end else if ((addr >= FEATURE_BASE) && (addr < (FEATURE_BASE + FEATURE_WORDS * 4))) begin
                idx = (addr - FEATURE_BASE) >> 2;
                bus_read_word = feature_words[idx];
            end else if ((addr >= CONV1_W_BASE) && (addr < (CONV1_W_BASE + CONV1_WEIGHT_WORDS * 4))) begin
                idx = (addr - CONV1_W_BASE) >> 2;
                bus_read_word = conv1_weight_words[idx];
            end else if ((addr >= CONV1_B_BASE) && (addr < (CONV1_B_BASE + CONV1_BIAS_WORDS * 4))) begin
                idx = (addr - CONV1_B_BASE) >> 2;
                bus_read_word = conv1_bias_words[idx];
            end else if ((addr >= CONV2_W_BASE) && (addr < (CONV2_W_BASE + CONV2_WEIGHT_WORDS * 4))) begin
                idx = (addr - CONV2_W_BASE) >> 2;
                bus_read_word = conv2_weight_words[idx];
            end else if ((addr >= CONV2_B_BASE) && (addr < (CONV2_B_BASE + CONV2_BIAS_WORDS * 4))) begin
                idx = (addr - CONV2_B_BASE) >> 2;
                bus_read_word = conv2_bias_words[idx];
            end else if ((addr >= FILM_L0_W_BASE) && (addr < (FILM_L0_W_BASE + FILM_L0_W_WORDS * 4))) begin
                idx = (addr - FILM_L0_W_BASE) >> 2;
                bus_read_word = film_l0_weight_words[idx];
            end else if ((addr >= FILM_L0_B_BASE) && (addr < (FILM_L0_B_BASE + FILM_L0_B_WORDS * 4))) begin
                idx = (addr - FILM_L0_B_BASE) >> 2;
                bus_read_word = film_l0_bias_words[idx];
            end else if ((addr >= FILM_L2_W_BASE) && (addr < (FILM_L2_W_BASE + FILM_L2_W_WORDS * 4))) begin
                idx = (addr - FILM_L2_W_BASE) >> 2;
                bus_read_word = film_l2_weight_words[idx];
            end else if ((addr >= FILM_L2_B_BASE) && (addr < (FILM_L2_B_BASE + FILM_L2_B_WORDS * 4))) begin
                idx = (addr - FILM_L2_B_BASE) >> 2;
                bus_read_word = film_l2_bias_words[idx];
            end else if ((addr >= SCRATCH_BASE) && (addr < (SCRATCH_BASE + PHASE1_SCRATCH_WORDS * 4))) begin
                idx = (addr - SCRATCH_BASE) >> 2;
                bus_read_word = scratch_words[idx];
            end else if ((addr >= OUTPUT_BASE) && (addr < (OUTPUT_BASE + FINAL_OUTPUT_WORDS * 4))) begin
                idx = (addr - OUTPUT_BASE) >> 2;
                bus_read_word = output_words_mem[idx];
            end else begin
                bus_read_word = 32'd0;
            end
        end
    endfunction

    task clear_storage;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                desc_words[i] = 32'd0;
            end
            for (i = 0; i < SIGNAL_WORDS; i = i + 1) begin
                signal_words[i] = 32'd0;
            end
            for (i = 0; i < FEATURE_WORDS; i = i + 1) begin
                feature_words[i] = 32'd0;
            end
            for (i = 0; i < CONV1_WEIGHT_WORDS; i = i + 1) begin
                conv1_weight_words[i] = 32'd0;
            end
            for (i = 0; i < CONV1_BIAS_WORDS; i = i + 1) begin
                conv1_bias_words[i] = 32'd0;
            end
            for (i = 0; i < CONV2_WEIGHT_WORDS; i = i + 1) begin
                conv2_weight_words[i] = 32'd0;
            end
            for (i = 0; i < CONV2_BIAS_WORDS; i = i + 1) begin
                conv2_bias_words[i] = 32'd0;
            end
            for (i = 0; i < FILM_L0_W_WORDS; i = i + 1) begin
                film_l0_weight_words[i] = 32'd0;
            end
            for (i = 0; i < FILM_L0_B_WORDS; i = i + 1) begin
                film_l0_bias_words[i] = 32'd0;
            end
            for (i = 0; i < FILM_L2_W_WORDS; i = i + 1) begin
                film_l2_weight_words[i] = 32'd0;
            end
            for (i = 0; i < FILM_L2_B_WORDS; i = i + 1) begin
                film_l2_bias_words[i] = 32'd0;
            end
            for (i = 0; i < PHASE1_SCRATCH_WORDS; i = i + 1) begin
                scratch_words[i] = 32'd0;
            end
            for (i = 0; i < FINAL_OUTPUT_WORDS; i = i + 1) begin
                output_words_mem[i] = 32'd0;
            end
        end
    endtask

    task program_desc;
        input integer desc_slot;
        input [31:0] net_id;
        input [31:0] input_addr;
        input [31:0] output_addr;
        input [31:0] param_addr;
        input [31:0] scratch_addr;
        input [31:0] input_words;
        input [31:0] output_words;
        input [31:0] flags;
        integer base_idx;
        begin
            base_idx = desc_slot * 8;
            desc_words[base_idx + 0] = net_id;
            desc_words[base_idx + 1] = input_addr;
            desc_words[base_idx + 2] = output_addr;
            desc_words[base_idx + 3] = param_addr;
            desc_words[base_idx + 4] = scratch_addr;
            desc_words[base_idx + 5] = input_words;
            desc_words[base_idx + 6] = output_words;
            desc_words[base_idx + 7] = flags;
        end
    endtask

    task pulse_launch;
        input [31:0] base_addr;
        begin
            @(posedge clk);
            desc_base_addr <= base_addr;
            launch_pulse   <= 1'b1;
            @(posedge clk);
            launch_pulse   <= 1'b0;
        end
    endtask

    task pulse_soft_reset;
        begin
            @(posedge clk);
            soft_reset_pulse <= 1'b1;
            @(posedge clk);
            soft_reset_pulse <= 1'b0;
        end
    endtask

    task wait_done;
        integer cycles;
        reg found;
        begin
            found = 1'b0;
            for (cycles = 0; cycles < 4000; cycles = cycles + 1) begin
                @(posedge clk);
                if (status_done) begin
                    found = 1'b1;
                    cycles = 4000;
                end
            end
            if (!found) begin
                $fatal(1, "timeout waiting for status_done");
            end
        end
    endtask

    task wait_error;
        integer cycles;
        reg found;
        begin
            found = 1'b0;
            for (cycles = 0; cycles < 100; cycles = cycles + 1) begin
                @(posedge clk);
                if (status_error) begin
                    found = 1'b1;
                    cycles = 100;
                end
            end
            if (!found) begin
                $fatal(1, "timeout waiting for status_error");
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_rvalid <= 1'b0;
            m_axi_rdata  <= 32'd0;
            m_axi_rresp  <= 2'b00;
            m_axi_rlast  <= 1'b0;
            m_axi_bvalid <= 1'b0;
            m_axi_bresp  <= 2'b00;
            write_addr_seen <= 1'b0;
            write_addr_pending <= 32'd0;
        end else begin
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                m_axi_rlast  <= 1'b0;
            end

            if (m_axi_arvalid && m_axi_arready) begin
                m_axi_rvalid <= 1'b1;
                m_axi_rdata  <= bus_read_word(m_axi_araddr);
                m_axi_rresp  <= 2'b00;
                m_axi_rlast  <= 1'b1;
            end

            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end

            if (m_axi_awvalid && m_axi_awready) begin
                write_addr_pending <= m_axi_awaddr;
                write_addr_seen <= 1'b1;
            end

            if (m_axi_wvalid && m_axi_wready && write_addr_seen) begin
                if ((write_addr_pending >= SCRATCH_BASE) &&
                    (write_addr_pending < (SCRATCH_BASE + PHASE1_SCRATCH_WORDS * 4))) begin
                    scratch_words[(write_addr_pending - SCRATCH_BASE) >> 2] <= m_axi_wdata;
                end else if ((write_addr_pending >= OUTPUT_BASE) &&
                    (write_addr_pending < (OUTPUT_BASE + FINAL_OUTPUT_WORDS * 4))) begin
                    output_words_mem[(write_addr_pending - OUTPUT_BASE) >> 2] <= m_axi_wdata;
                end else begin
                    $fatal(1, "unexpected write addr %08x", write_addr_pending);
                end
                write_addr_seen <= 1'b0;
                m_axi_bvalid <= 1'b1;
                m_axi_bresp <= 2'b00;
            end
        end
    end

    initial begin
        rst_n            = 1'b0;
        launch_pulse     = 1'b0;
        soft_reset_pulse = 1'b0;
        desc_base_addr   = 32'd0;
        m_axi_arready    = 1'b1;
        m_axi_awready    = 1'b1;
        m_axi_wready     = 1'b1;
        clear_storage();

        signal_words[0] = pack_q16(16'd256, 16'd512);
        signal_words[1] = pack_q16(16'd768, 16'd1024);
        signal_words[2] = pack_q16(16'd1280, 16'd1536);
        signal_words[3] = pack_q16(16'd1792, 16'd2048);
        feature_words[0] = pack_q16(16'd256, 16'd256);

        conv1_weight_words[0] = pack_q16(16'd256, 16'd256);
        conv1_weight_words[1] = pack_q16(16'd256, 16'd256);
        conv1_weight_words[2] = pack_q16(-16'sd256, 16'd256);
        conv1_bias_words[0]   = pack_q16(16'd0, 16'd0);

        conv2_weight_words[0] = pack_q16(16'd256, 16'd256);
        conv2_weight_words[1] = pack_q16(16'd256, 16'd0);
        conv2_weight_words[2] = pack_q16(16'd0, 16'd0);
        conv2_weight_words[3] = pack_q16(16'd0, 16'd0);
        conv2_weight_words[4] = pack_q16(16'd0, 16'd256);
        conv2_weight_words[5] = pack_q16(16'd256, 16'd256);
        conv2_bias_words[0]   = pack_q16(16'd0, 16'd0);

        film_l0_weight_words[0] = pack_q16(16'd256, 16'd0);
        film_l0_weight_words[1] = pack_q16(16'd0, 16'd256);
        film_l0_bias_words[0]   = pack_q16(16'd0, 16'd0);

        film_l2_weight_words[0] = pack_q16(16'd0, 16'd0);
        film_l2_weight_words[1] = pack_q16(-16'sd128, 16'd0);
        film_l2_weight_words[2] = pack_q16(16'd0, 16'd0);
        film_l2_weight_words[3] = pack_q16(16'd0, 16'd0);
        film_l2_bias_words[0]   = pack_q16(16'd0, 16'd0);
        film_l2_bias_words[1]   = pack_q16(16'd0, 16'd256);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        program_desc(
            0,
            32'd3,
            SIGNAL_BASE,
            OUTPUT_BASE,
            32'd0,
            SCRATCH_BASE,
            SIGNAL_WORDS,
            FINAL_OUTPUT_WORDS,
            32'd0
        );

        pulse_launch(DESC0_BASE);
        wait_done();

        if (status_error) begin
            $fatal(1, "valid descriptor raised status_error");
        end
        if (desc_net_id_reg != 32'd3) begin
            $fatal(1, "unexpected desc_net_id_reg=%08x", desc_net_id_reg);
        end
        if (desc_input_words_reg != SIGNAL_WORDS) begin
            $fatal(1, "unexpected desc_input_words_reg=%0d", desc_input_words_reg);
        end
        if (desc_output_words_reg != FINAL_OUTPUT_WORDS) begin
            $fatal(1, "unexpected desc_output_words_reg=%0d", desc_output_words_reg);
        end
        if (input_fetch_word_count_reg != TOTAL_INPUT_WORDS) begin
            $fatal(1, "unexpected input fetch count=%0d", input_fetch_word_count_reg);
        end
        if (param_fetch_word_count_reg != TOTAL_PARAM_WORDS) begin
            $fatal(1, "unexpected param fetch count=%0d", param_fetch_word_count_reg);
        end

        if (scratch_words[0] != 32'h0C00_0600) begin
            $fatal(1, "scratch_words[0] mismatch got=%08x", scratch_words[0]);
        end
        if (scratch_words[1] != 32'h1500_1200) begin
            $fatal(1, "scratch_words[1] mismatch got=%08x", scratch_words[1]);
        end
        if (scratch_words[2] != 32'h0400_0200) begin
            $fatal(1, "scratch_words[2] mismatch got=%08x", scratch_words[2]);
        end
        if (scratch_words[3] != 32'h0700_0600) begin
            $fatal(1, "scratch_words[3] mismatch got=%08x", scratch_words[3]);
        end

        if (output_words_mem[0] != 32'h3300_2400) begin
            $fatal(1, "output_words_mem[0] mismatch got=%08x", output_words_mem[0]);
        end
        if (output_words_mem[1] != 32'h0980_0700) begin
            $fatal(1, "output_words_mem[1] mismatch got=%08x", output_words_mem[1]);
        end

        pulse_soft_reset();
        @(posedge clk);
        if (status_done || status_error || status_busy) begin
            $fatal(1, "soft reset did not clear wrapper status");
        end

        program_desc(
            1,
            32'd1,
            SIGNAL_BASE,
            OUTPUT_BASE,
            32'd0,
            SCRATCH_BASE,
            SIGNAL_WORDS,
            FINAL_OUTPUT_WORDS,
            32'd0
        );

        pulse_launch(DESC1_BASE);
        wait_error();

        if (status_done) begin
            $fatal(1, "invalid descriptor unexpectedly asserted status_done");
        end

        $display("[TB] tpu_stage2_cnn_frontend_smoke passed");
        $finish;
    end

endmodule

`default_nettype wire
