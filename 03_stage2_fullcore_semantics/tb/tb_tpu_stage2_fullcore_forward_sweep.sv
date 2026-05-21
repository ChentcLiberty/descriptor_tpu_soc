`timescale 1ns / 1ps
`default_nettype none

module tb_tpu_stage2_fullcore_forward_sweep;
    localparam integer CLK_PERIOD = 10;
    localparam [31:0] DESC_BASE   = 32'h6004_0000;
    localparam [31:0] INPUT_BASE  = 32'h6004_0100;
    localparam [31:0] OUTPUT_BASE = 32'h6004_0200;
    localparam [31:0] PARAM_BASE  = 32'h6004_0300;
    localparam [31:0] SCRATCH_BASE = 32'h6004_0400;
    localparam [31:0] TPU_DESC_F_RELU          = 32'h0000_0001;
    localparam [31:0] TPU_DESC_F_TILE2X2_Q8_8   = 32'h0001_0000;
    localparam [31:0] TPU_DESC_F_SCRATCH_LEAK   = 32'h0100_0000;
    localparam integer MAX_INPUT_WORDS  = 7;
    localparam integer MAX_OUTPUT_WORDS = 4;
    localparam integer MAX_PARAM_WORDS  = MAX_OUTPUT_WORDS * ((MAX_INPUT_WORDS << 1) + 1);

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
    integer case_count;
    integer timeout_count;
    integer i;

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

    function automatic signed [15:0] pattern_q88;
        input integer seed;
        begin
            case(seed % 12)
                0:  pattern_q88 = 16'shfe80; // -1.5
                1:  pattern_q88 = 16'shff00; // -1.0
                2:  pattern_q88 = 16'shff40; // -0.75
                3:  pattern_q88 = 16'shff80; // -0.5
                4:  pattern_q88 = 16'shffc0; // -0.25
                5:  pattern_q88 = 16'sh0000; //  0.0
                6:  pattern_q88 = 16'sh0040; //  0.25
                7:  pattern_q88 = 16'sh0080; //  0.5
                8:  pattern_q88 = 16'sh00c0; //  0.75
                9:  pattern_q88 = 16'sh0100; //  1.0
                10: pattern_q88 = 16'sh0140; //  1.25
                default: pattern_q88 = 16'sh0180; // 1.5
            endcase
        end
    endfunction

    function automatic signed [31:0] q8_8_round_shift_32;
        input signed [47:0] value;
        reg signed [47:0] rounded;
        begin
            if(value >= 48'sd0) begin
                rounded = (value + 48'sd128) >>> 8;
            end else begin
                rounded = -(((-value) + 48'sd128) >>> 8);
            end
            if(rounded > 48'sd2147483647) begin
                q8_8_round_shift_32 = 32'sh7fff_ffff;
            end else if(rounded < -48'sd2147483648) begin
                q8_8_round_shift_32 = 32'sh8000_0000;
            end else begin
                q8_8_round_shift_32 = rounded[31:0];
            end
        end
    endfunction

    function automatic signed [15:0] q8_8_saturate;
        input signed [31:0] value;
        begin
            if(value > 32'sd32767) begin
                q8_8_saturate = 16'sh7fff;
            end else if(value < -32'sd32768) begin
                q8_8_saturate = 16'sh8000;
            end else begin
                q8_8_saturate = value[15:0];
            end
        end
    endfunction

    function automatic signed [15:0] q8_8_mul_16;
        input signed [15:0] a;
        input signed [15:0] b;
        reg signed [31:0] shifted;
        reg signed [47:0] product;
        begin
            product = $signed(a) * $signed(b);
            shifted = q8_8_round_shift_32(product);
            q8_8_mul_16 = q8_8_saturate(shifted);
        end
    endfunction

    function automatic signed [15:0] apply_activation;
        input signed [15:0] pre_activation;
        input integer relu_en;
        input signed [15:0] leak_factor;
        begin
            if(!relu_en || (pre_activation >= 16'sd0)) begin
                apply_activation = pre_activation;
            end else begin
                apply_activation = q8_8_mul_16(pre_activation, leak_factor);
            end
        end
    endfunction

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

    task automatic clear_backing_memory;
        begin
            for(i = 0; i < 1024; i = i + 1) begin
                mem[i] = 32'd0;
            end
        end
    endtask

    task automatic build_case;
        input integer seed;
        input integer input_words_i;
        input integer output_words_i;
        input integer relu_en;
        input signed [15:0] leak_factor_i;
        input integer use_scratch_i;
        integer out_idx;
        integer in_idx;
        integer base;
        reg signed [15:0] x0;
        reg signed [15:0] x1;
        reg signed [15:0] w00;
        reg signed [15:0] w01;
        reg signed [15:0] w10;
        reg signed [15:0] w11;
        reg signed [15:0] b0;
        reg signed [15:0] b1;
        reg signed [47:0] acc0;
        reg signed [47:0] acc1;
        reg signed [31:0] shifted0;
        reg signed [31:0] shifted1;
        reg signed [15:0] pre0;
        reg signed [15:0] pre1;
        reg signed [15:0] y0;
        reg signed [15:0] y1;
        begin
            clear_case_storage();
            case_net_id = 32'd100 + seed[31:0];
            case_flags = TPU_DESC_F_TILE2X2_Q8_8
                       | (relu_en ? TPU_DESC_F_RELU : 32'd0)
                       | ((relu_en && use_scratch_i) ? TPU_DESC_F_SCRATCH_LEAK : 32'd0);
            case_input_words = input_words_i[31:0];
            case_output_words = output_words_i[31:0];
            case_scratch_addr = (relu_en && use_scratch_i) ? SCRATCH_BASE : 32'd0;
            case_leak_factor = (relu_en && use_scratch_i) ? leak_factor_i : 16'd0;
            case_param_count = output_words_i * ((input_words_i << 1) + 1);

            for(in_idx = 0; in_idx < input_words_i; in_idx = in_idx + 1) begin
                x0 = pattern_q88(seed + (in_idx * 5) + 0);
                x1 = pattern_q88(seed + (in_idx * 5) + 2);
                case_input_mem[in_idx] = {x1, x0};
            end

            for(out_idx = 0; out_idx < output_words_i; out_idx = out_idx + 1) begin
                base = out_idx * ((input_words_i << 1) + 1);
                acc0 = 48'sd0;
                acc1 = 48'sd0;
                for(in_idx = 0; in_idx < input_words_i; in_idx = in_idx + 1) begin
                    x0 = case_input_mem[in_idx][15:0];
                    x1 = case_input_mem[in_idx][31:16];
                    w00 = pattern_q88(seed + (out_idx * 17) + (in_idx * 7) + 1);
                    w01 = pattern_q88(seed + (out_idx * 17) + (in_idx * 7) + 3);
                    w10 = pattern_q88(seed + (out_idx * 17) + (in_idx * 7) + 5);
                    w11 = pattern_q88(seed + (out_idx * 17) + (in_idx * 7) + 7);
                    case_param_mem[base + (in_idx << 1)] = {w01, w00};
                    case_param_mem[base + (in_idx << 1) + 1] = {w11, w10};
                    acc0 = acc0 + (x0 * w00) + (x1 * w01);
                    acc1 = acc1 + (x0 * w10) + (x1 * w11);
                end

                b0 = pattern_q88(seed + (out_idx * 17) + 91);
                b1 = pattern_q88(seed + (out_idx * 17) + 95);
                case_param_mem[base + (input_words_i << 1)] = {b1, b0};
                acc0 = acc0 + ($signed({{32{b0[15]}}, b0}) <<< 8);
                acc1 = acc1 + ($signed({{32{b1[15]}}, b1}) <<< 8);
                shifted0 = q8_8_round_shift_32(acc0);
                shifted1 = q8_8_round_shift_32(acc1);
                pre0 = q8_8_saturate(shifted0);
                pre1 = q8_8_saturate(shifted1);
                y0 = apply_activation(pre0, relu_en, case_leak_factor);
                y1 = apply_activation(pre1, relu_en, case_leak_factor);
                case_expected_mem[out_idx] = {y1, y0};
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

    task automatic wait_done_or_timeout;
        input integer case_idx;
        begin
            timeout_count = 0;
            while((!status_done) && (!status_error) && (timeout_count < 50000)) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            $display("[TB] case=%0d in=%0d out=%0d relu=%0d leak=%04h scratch=%08h done=%0b error=%0b timeout=%0d out0=%08h out1=%08h in_cnt=%0d param_cnt=%0d",
                     case_idx,
                     case_input_words,
                     case_output_words,
                     case_flags[0],
                     case_leak_factor,
                     case_scratch_addr,
                     status_done,
                     status_error,
                     timeout_count,
                     mem[(OUTPUT_BASE >> 2) & 32'h3ff],
                     mem[((OUTPUT_BASE + 32'd4) >> 2) & 32'h3ff],
                     input_fetch_word_count_reg,
                     param_fetch_word_count_reg);
            if(status_error) begin
                $display("[FAIL] case=%0d status_error asserted", case_idx);
                err_count = err_count + 1;
            end
            if(!status_done) begin
                $display("[FAIL] case=%0d timeout waiting for done", case_idx);
                err_count = err_count + 1;
            end
        end
    endtask

    task automatic compare_outputs;
        input integer case_idx;
        integer idx;
        reg [31:0] actual_word;
        begin
            if(desc_scratch_addr_reg != case_scratch_addr) begin
                $display("[FAIL] case=%0d scratch addr mismatch: got %08h expected %08h",
                         case_idx, desc_scratch_addr_reg, case_scratch_addr);
                err_count = err_count + 1;
            end
            if(input_fetch_word_count_reg != case_input_words) begin
                $display("[FAIL] case=%0d input fetch count mismatch: got %0d expected %0d",
                         case_idx, input_fetch_word_count_reg, case_input_words);
                err_count = err_count + 1;
            end
            if(param_fetch_word_count_reg != case_param_count[31:0]) begin
                $display("[FAIL] case=%0d param fetch count mismatch: got %0d expected %0d",
                         case_idx, param_fetch_word_count_reg, case_param_count);
                err_count = err_count + 1;
            end
            for(idx = 0; idx < case_output_words; idx = idx + 1) begin
                actual_word = mem[((OUTPUT_BASE + (idx << 2)) >> 2) & 32'h3ff];
                if(actual_word != case_expected_mem[idx]) begin
                    $display("[FAIL] case=%0d out%0d mismatch: got %08h expected %08h",
                             case_idx, idx, actual_word, case_expected_mem[idx]);
                    err_count = err_count + 1;
                end
            end
        end
    endtask

    task automatic run_generated_case;
        input integer case_idx;
        input integer seed;
        input integer input_words_i;
        input integer output_words_i;
        input integer relu_en;
        input signed [15:0] leak_factor_i;
        input integer use_scratch_i;
        begin
            build_case(seed, input_words_i, output_words_i, relu_en, leak_factor_i, use_scratch_i);
            pulse_soft_reset();
            program_case_to_memory();
            pulse_launch();
            wait_done_or_timeout(case_idx);
            compare_outputs(case_idx);
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        integer input_words_loop;
        integer output_words_loop;
        integer activation_mode_loop;
        integer relu_loop;
        reg signed [15:0] leak_factor_loop;
        integer use_scratch_loop;
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
        case_count = 0;
        clear_case_storage();
        clear_backing_memory();

        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        for(input_words_loop = 1; input_words_loop <= MAX_INPUT_WORDS; input_words_loop = input_words_loop + 1) begin
            for(output_words_loop = 1; output_words_loop <= MAX_OUTPUT_WORDS; output_words_loop = output_words_loop + 1) begin
                for(activation_mode_loop = 0; activation_mode_loop < 4; activation_mode_loop = activation_mode_loop + 1) begin
                    case(activation_mode_loop)
                        0: begin
                            relu_loop = 0;
                            leak_factor_loop = 16'h0000;
                            use_scratch_loop = 0;
                        end
                        1: begin
                            relu_loop = 1;
                            leak_factor_loop = 16'h0000;
                            use_scratch_loop = 0;
                        end
                        2: begin
                            relu_loop = 1;
                            leak_factor_loop = 16'h0040;
                            use_scratch_loop = 1;
                        end
                        default: begin
                            relu_loop = 1;
                            leak_factor_loop = 16'h0080;
                            use_scratch_loop = 1;
                        end
                    endcase
                    run_generated_case(case_count,
                                       (input_words_loop * 23) + (output_words_loop * 11) + (activation_mode_loop * 3),
                                       input_words_loop,
                                       output_words_loop,
                                       relu_loop,
                                       leak_factor_loop,
                                       use_scratch_loop);
                    case_count = case_count + 1;
                end
            end
        end

        if(err_count == 0) begin
            $display("[PASS] tb_tpu_stage2_fullcore_forward_sweep complete cases=%0d", case_count);
        end else begin
            $display("[FAIL] tb_tpu_stage2_fullcore_forward_sweep err_count=%0d cases=%0d", err_count, case_count);
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
