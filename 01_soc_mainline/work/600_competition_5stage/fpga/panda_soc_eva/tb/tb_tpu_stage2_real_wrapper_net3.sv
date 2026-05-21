`timescale 1ns / 1ps
`default_nettype none

module tb_tpu_stage2_real_wrapper_net3;

    localparam integer CLK_PERIOD = 10;
    localparam [31:0] DESC_BASE_ADDR   = 32'h6015_0000;
    localparam [31:0] SIGNAL_BASE_ADDR = 32'h6012_0000;
    localparam [31:0] FEATURE_BASE_ADDR= 32'h6012_1000;
    localparam [31:0] OUTPUT_BASE_ADDR = 32'h6012_2000;
    localparam [31:0] SCRATCH_BASE_ADDR= 32'h6010_0000;
    localparam [31:0] PARAM_BASE_ADDR  = 32'h6007_0000;
    localparam integer SIGNAL_WORDS    = 500;
    localparam integer FEATURE_WORDS   = 4;
    localparam integer OUTPUT_WORDS    = 128;
    localparam integer PARAM_WORDS     = 71168;
    localparam integer INPUT_FETCH_WORDS = SIGNAL_WORDS + FEATURE_WORDS;
    localparam integer PARAM_FETCH_WORDS = PARAM_WORDS;

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

    integer wait_cycles;
    integer idx;
    integer word_idx;

    function automatic integer mem_index;
        input [31:0] byte_addr;
        begin
            mem_index = ((byte_addr & 32'h007f_ffff) >> 2);
        end
    endfunction

    task tb_fail;
        input [255:0] msg;
        begin
            $display("[TB][FAIL] %0s", msg);
            repeat(5) @(posedge clk);
            $finish;
        end
    endtask

    task pulse_launch;
        begin
            @(posedge clk);
            launch_pulse <= 1'b1;
            @(posedge clk);
            launch_pulse <= 1'b0;
        end
    endtask

    task check_output_word;
        input integer out_idx;
        input [31:0] expected_word;
        reg [31:0] actual_word;
        begin
            actual_word =
                panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(OUTPUT_BASE_ADDR) + out_idx];
            if(actual_word !== expected_word) begin
                $display(
                    "[TB][FAIL] output[%0d] expected=%08x actual=%08x",
                    out_idx,
                    expected_word,
                    actual_word
                );
                tb_fail("NET_ID=3 output word mismatch");
            end
        end
    endtask

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
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        #(500_000_000);
        tb_fail("global timeout waiting for NET_ID=3 real-wrapper regression");
    end

    initial begin
        rst_n = 1'b0;
        launch_pulse = 1'b0;
        soft_reset_pulse = 1'b0;
        desc_base_addr = DESC_BASE_ADDR;

        repeat(8) @(posedge clk);
        rst_n = 1'b1;
        repeat(4) @(posedge clk);

        $display("[TB] preload shared SRAM from breath_cpu_frontend_q8_8.mem");
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

        for(wait_cycles = 0; wait_cycles < 64; wait_cycles = wait_cycles + 1) begin
            @(posedge clk);
            if(status_busy) begin
                wait_cycles = 64;
            end
        end
        if(!status_busy) begin
            tb_fail("busy not asserted after NET_ID=3 launch");
        end

        wait_cycles = 0;
        while((!status_done) && (!status_error) && (wait_cycles < 40_000_000)) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if(status_error) begin
            tb_fail("NET_ID=3 real-wrapper regression hit error");
        end
        if(!status_done) begin
            tb_fail("timeout waiting for NET_ID=3 done");
        end
        if(status_busy) begin
            tb_fail("busy still asserted when done");
        end

        if(desc_net_id_reg !== 32'd3) begin
            tb_fail("desc_net_id_reg mismatch for NET_ID=3 dispatch");
        end
        if(desc_input_addr_reg !== SIGNAL_BASE_ADDR) begin
            tb_fail("desc_input_addr_reg mismatch");
        end
        if(desc_output_addr_reg !== OUTPUT_BASE_ADDR) begin
            tb_fail("desc_output_addr_reg mismatch");
        end
        if(desc_scratch_addr_reg !== SCRATCH_BASE_ADDR) begin
            tb_fail("desc_scratch_addr_reg mismatch");
        end
        if(desc_input_words_reg !== SIGNAL_WORDS) begin
            tb_fail("desc_input_words_reg mismatch");
        end
        if(desc_output_words_reg !== OUTPUT_WORDS) begin
            tb_fail("desc_output_words_reg mismatch");
        end
        if(input_fetch_word_count_reg !== INPUT_FETCH_WORDS) begin
            $display(
                "[TB] input_fetch expected=%0d actual=%0d",
                INPUT_FETCH_WORDS,
                input_fetch_word_count_reg
            );
            tb_fail("input_fetch_word_count_reg mismatch");
        end
        if(param_fetch_word_count_reg !== PARAM_FETCH_WORDS) begin
            $display(
                "[TB] param_fetch expected=%0d actual=%0d",
                PARAM_FETCH_WORDS,
                param_fetch_word_count_reg
            );
            tb_fail("param_fetch_word_count_reg mismatch");
        end

        if(panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(FEATURE_BASE_ADDR) + 0] !== 32'h008E_FF18) begin
            tb_fail("feature preload word0 mismatch");
        end
        if(panda_soc_shared_mem_subsys_u.axi_ram_u.mem[mem_index(SIGNAL_BASE_ADDR) + 0] !== 32'hFF65_FF66) begin
            tb_fail("signal preload word0 mismatch");
        end

        check_output_word(0,   32'h0022_000E);
        check_output_word(7,   32'h000B_006C);
        check_output_word(31,  32'h00CE_0029);
        check_output_word(63,  32'h0076_0087);
        check_output_word(95,  32'h008F_001B);
        check_output_word(127, 32'h002F_0026);

        $display(
            "[TB][PASS] NET_ID=3 real-wrapper regression passed in %0d cycles, checksum in=%08x param=%08x",
            wait_cycles,
            input_checksum_reg,
            param_checksum_reg
        );
        repeat(5) @(posedge clk);
        $finish;
    end

endmodule

`default_nettype wire
