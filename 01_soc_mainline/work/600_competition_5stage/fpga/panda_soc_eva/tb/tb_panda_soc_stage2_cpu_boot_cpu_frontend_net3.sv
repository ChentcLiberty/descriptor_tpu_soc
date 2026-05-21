`timescale 1ns / 1ps
`default_nettype none
`include "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/software/generated/breath_cpu_frontend_fixture_expected.svh"

module tb_panda_soc_stage2_cpu_boot_cpu_frontend_net3;

    localparam integer CLK_PERIOD = 10;
    localparam [31:0] TPU_DESC0_BASE    = 32'h6001_0000;
    localparam [31:0] TPU_DESC1_BASE    = 32'h6001_1000;
    localparam [31:0] TPU_OUT_BUF0_BASE = 32'h6001_0400;
    localparam [31:0] TPU_SCRATCH1_BASE = 32'h6001_1800;
    localparam [31:0] TPU_CLASSIFIER_OUT_BASE = 32'h6001_3000;
    localparam [31:0] TPU_CNN_SIGNAL_BASE = 32'h6012_0000;
    localparam [31:0] TPU_CNN_OUT_BASE    = 32'h6012_2000;

    localparam [31:0] EXPECT_PARAM_KEY0          = 32'hFEDE_FEFA;
    localparam [31:0] EXPECT_PARAM_KEY1          = 32'h000B_FF15;
    localparam [31:0] EXPECT_MLP_KEY_OUT0        = `BREATH_CPU_FRONTEND_FIXTURE_EXPECT_MLP_KEY_OUT0;
    localparam [31:0] EXPECT_MLP_KEY_OUT15       = `BREATH_CPU_FRONTEND_FIXTURE_EXPECT_MLP_KEY_OUT15;
    localparam [31:0] EXPECT_MLP_OTHER_OUT0      = `BREATH_CPU_FRONTEND_FIXTURE_EXPECT_MLP_OTHER_OUT0;
    localparam [31:0] EXPECT_MLP_OTHER_OUT15     = `BREATH_CPU_FRONTEND_FIXTURE_EXPECT_MLP_OTHER_OUT15;
    localparam [31:0] EXPECT_CNN_OUT0            = 32'h0022_000E;
    localparam [31:0] EXPECT_CNN_OUT7            = 32'h000B_006C;
    localparam [31:0] EXPECT_CNN_OUT31           = 32'h00CE_0029;
    localparam [31:0] EXPECT_CNN_OUT63           = 32'h0076_0087;
    localparam [31:0] EXPECT_CNN_OUT95           = 32'h008F_001B;
    localparam [31:0] EXPECT_CNN_OUT127          = 32'h002F_0026;
    localparam [31:0] EXPECT_CLASSIFIER_OUT0     = 32'hFE2D_01CA;
    localparam [31:0] EXPECT_CLASSIFIER_OUT1     = 32'hFEAF_01EB;

    localparam integer OUT0_WORD_INDEX = (TPU_OUT_BUF0_BASE - 32'h6000_0000) >> 2;
    localparam integer SCRATCH1_WORD_INDEX = (TPU_SCRATCH1_BASE - 32'h6000_0000) >> 2;
    localparam integer CLASS_OUT_WORD_INDEX = (TPU_CLASSIFIER_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer CNN_OUT_WORD_INDEX = (TPU_CNN_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer PARAM_KEY_INDEX = (32'h6000_0000 - 32'h6000_0000) >> 2;
    localparam integer DESC0_WORD_INDEX = (TPU_DESC0_BASE - 32'h6000_0000) >> 2;

    localparam IMEM_INIT_FILE    = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_net3_fixture/breath_tpu_soc_demo_cpu_frontend_net3_fixture_imem.txt";
    localparam IMEM_INIT_FILE_B0 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_net3_fixture/breath_tpu_soc_demo_cpu_frontend_net3_fixture_imem_b0.txt";
    localparam IMEM_INIT_FILE_B1 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_net3_fixture/breath_tpu_soc_demo_cpu_frontend_net3_fixture_imem_b1.txt";
    localparam IMEM_INIT_FILE_B2 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_net3_fixture/breath_tpu_soc_demo_cpu_frontend_net3_fixture_imem_b2.txt";
    localparam IMEM_INIT_FILE_B3 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_net3_fixture/breath_tpu_soc_demo_cpu_frontend_net3_fixture_imem_b3.txt";
    localparam PARAM_POOL_INIT_FILE = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_cpu_frontend_q8_8/breath_cpu_frontend_q8_8.mem";

    reg clk;
    reg ext_resetn;
    reg uart0_rx;
    wire uart0_tx;

    wire        tpu_launch_pulse;
    wire [31:0] tpu_net_id_reg;
    wire [31:0] tpu_desc_lo_reg;
    wire [31:0] tpu_perf_cycle_reg;

    integer launch_count;
    integer wait_cycles;

    task tb_fail;
        input [255:0] msg;
        begin
            $display("[TB][FAIL] %0s", msg);
            repeat(10) @(posedge clk);
            $finish;
        end
    endtask

    task expect_word;
        input integer word_index;
        input [31:0] expected_word;
        input [255:0] tag;
        reg [31:0] actual_word;
        begin
            actual_word = dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[word_index];
            if(actual_word !== expected_word) begin
                $display("[TB][DBG] word_index=0x%0x actual=0x%08x expected=0x%08x", word_index, actual_word, expected_word);
                tb_fail(tag);
            end
        end
    endtask

    task expect_launch;
        input integer expected_idx;
        input [31:0] expected_net_id;
        input [31:0] expected_desc_addr;
        begin
            while(tpu_launch_pulse !== 1'b1)
                @(posedge clk);

            launch_count = launch_count + 1;
            $display("[TB] observed launch #%0d net_id=0x%08x desc=0x%08x", launch_count, tpu_net_id_reg, tpu_desc_lo_reg);

            if(launch_count != expected_idx)
                tb_fail("unexpected launch count order");
            if(tpu_net_id_reg != expected_net_id)
                tb_fail("unexpected net_id on launch");
            if(tpu_desc_lo_reg != expected_desc_addr)
                tb_fail("unexpected desc address on launch");

            @(posedge clk);
        end
    endtask

    panda_soc_stage2_base_top #(
        .EN_DCACHE("true"),
        .EN_DTCM("true"),
        .USE_TPU_STATUS_STUB(1),
        .USE_TPU_DESC_DMA_STUB(1),
        .USE_TPU_REAL_WRAPPER(1),
        .SIM_TPU_CTRL_AXIL_BYPASS(0),
        .imem_init_file(IMEM_INIT_FILE),
        .imem_init_file_b0(IMEM_INIT_FILE_B0),
        .imem_init_file_b1(IMEM_INIT_FILE_B1),
        .imem_init_file_b2(IMEM_INIT_FILE_B2),
        .imem_init_file_b3(IMEM_INIT_FILE_B3),
        .shared_sram_init_file(PARAM_POOL_INIT_FILE)
    ) dut (
        .clk(clk),
        .ext_resetn(ext_resetn),
        .uart0_rx(uart0_rx),
        .uart0_tx(uart0_tx),
        .tpu_status_busy(1'b0),
        .tpu_status_done(1'b0),
        .tpu_status_error(1'b0),
        .tpu_launch_pulse(tpu_launch_pulse),
        .tpu_soft_reset_pulse(),
        .tpu_mode_reg(),
        .tpu_net_id_reg(tpu_net_id_reg),
        .tpu_desc_lo_reg(tpu_desc_lo_reg),
        .tpu_desc_hi_reg(),
        .tpu_irq_en_reg(),
        .tpu_perf_cycle_reg(tpu_perf_cycle_reg),
        .sim_tpu_ctrl_axil_awaddr(32'd0),
        .sim_tpu_ctrl_axil_awprot(3'd0),
        .sim_tpu_ctrl_axil_awvalid(1'b0),
        .sim_tpu_ctrl_axil_awready(),
        .sim_tpu_ctrl_axil_wdata(32'd0),
        .sim_tpu_ctrl_axil_wstrb(4'd0),
        .sim_tpu_ctrl_axil_wvalid(1'b0),
        .sim_tpu_ctrl_axil_wready(),
        .sim_tpu_ctrl_axil_bresp(),
        .sim_tpu_ctrl_axil_bvalid(),
        .sim_tpu_ctrl_axil_bready(1'b0),
        .sim_tpu_ctrl_axil_araddr(32'd0),
        .sim_tpu_ctrl_axil_arprot(3'd0),
        .sim_tpu_ctrl_axil_arvalid(1'b0),
        .sim_tpu_ctrl_axil_arready(),
        .sim_tpu_ctrl_axil_rdata(),
        .sim_tpu_ctrl_axil_rresp(),
        .sim_tpu_ctrl_axil_rvalid(),
        .sim_tpu_ctrl_axil_rready(1'b0),
        .tpu_axi_araddr(32'd0),
        .tpu_axi_arburst(2'd0),
        .tpu_axi_arlen(8'd0),
        .tpu_axi_arsize(3'd0),
        .tpu_axi_arcache(4'd0),
        .tpu_axi_arvalid(1'b0),
        .tpu_axi_arready(),
        .tpu_axi_awaddr(32'd0),
        .tpu_axi_awburst(2'd0),
        .tpu_axi_awlen(8'd0),
        .tpu_axi_awsize(3'd0),
        .tpu_axi_awcache(4'd0),
        .tpu_axi_awvalid(1'b0),
        .tpu_axi_awready(),
        .tpu_axi_bresp(),
        .tpu_axi_bvalid(),
        .tpu_axi_bready(1'b0),
        .tpu_axi_rdata(),
        .tpu_axi_rresp(),
        .tpu_axi_rlast(),
        .tpu_axi_rvalid(),
        .tpu_axi_rready(1'b0),
        .tpu_axi_wdata(32'd0),
        .tpu_axi_wstrb(4'd0),
        .tpu_axi_wlast(1'b0),
        .tpu_axi_wvalid(1'b0),
        .tpu_axi_wready()
    );

    always @(posedge clk) begin
        if(ext_resetn && dut.tpu_ctrl_status_error)
            tb_fail("tpu ctrl reported error");
    end

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        #(1_000_000_000);
        $display("[TB][DBG] timeout launch_count=%0d perf=0x%08x class_out=%08x %08x",
            launch_count,
            tpu_perf_cycle_reg,
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_OUT_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_OUT_WORD_INDEX + 1]);
        tb_fail("global timeout waiting for cpu boot net3 completion");
    end

    initial begin
        ext_resetn = 1'b0;
        uart0_rx = 1'b1;
        launch_count = 0;

        repeat(20) @(posedge clk);
        expect_word(PARAM_KEY_INDEX + 0, EXPECT_PARAM_KEY0, "preloaded param_pool key[0] mismatch");
        expect_word(PARAM_KEY_INDEX + 1, EXPECT_PARAM_KEY1, "preloaded param_pool key[1] mismatch");
        ext_resetn = 1'b1;

        expect_launch(1, 32'd0, TPU_DESC0_BASE);
        expect_launch(2, 32'd0, TPU_DESC1_BASE);
        expect_launch(3, 32'd0, TPU_DESC0_BASE);
        expect_launch(4, 32'd0, TPU_DESC1_BASE);
        expect_launch(5, 32'd0, TPU_DESC0_BASE);
        expect_launch(6, 32'd1, TPU_DESC1_BASE);
        expect_launch(7, 32'd1, TPU_DESC0_BASE);
        expect_launch(8, 32'd3, TPU_DESC0_BASE);
        expect_word(DESC0_WORD_INDEX + 0, 32'd3, "net3 desc net_id mismatch");
        expect_word(DESC0_WORD_INDEX + 1, TPU_CNN_SIGNAL_BASE, "net3 desc input_addr mismatch");
        expect_word(DESC0_WORD_INDEX + 2, TPU_CNN_OUT_BASE, "net3 desc output_addr mismatch");
        expect_word(DESC0_WORD_INDEX + 5, 32'd500, "net3 desc input_words mismatch");
        expect_word(DESC0_WORD_INDEX + 6, 32'd128, "net3 desc output_words mismatch");
        expect_launch(9, 32'd2, TPU_DESC0_BASE);
        expect_launch(10, 32'd2, TPU_DESC1_BASE);
        expect_launch(11, 32'd2, TPU_DESC0_BASE);
        expect_launch(12, 32'd2, TPU_DESC1_BASE);
        expect_launch(13, 32'd2, TPU_DESC0_BASE);
        expect_launch(14, 32'd2, TPU_DESC1_BASE);
        expect_launch(15, 32'd2, TPU_DESC0_BASE);
        expect_launch(16, 32'd2, TPU_DESC1_BASE);
        expect_launch(17, 32'd2, TPU_DESC0_BASE);
        expect_launch(18, 32'd2, TPU_DESC1_BASE);
        expect_launch(19, 32'd2, TPU_DESC0_BASE);
        expect_launch(20, 32'd2, TPU_DESC1_BASE);
        expect_launch(21, 32'd2, TPU_DESC0_BASE);
        expect_launch(22, 32'd2, TPU_DESC1_BASE);

        for(wait_cycles = 0; wait_cycles < 200000; wait_cycles = wait_cycles + 1) begin
            @(posedge clk);
            if(dut.tpu_ctrl_status_done)
                wait_cycles = 200000;
        end

        if(!dut.tpu_ctrl_status_done)
            tb_fail("final done was not observed after twenty-second launch");

        expect_word(OUT0_WORD_INDEX + 0, EXPECT_MLP_KEY_OUT0, "cpu-front-end mlp_key final output[0] mismatch");
        expect_word(OUT0_WORD_INDEX + 15, EXPECT_MLP_KEY_OUT15, "cpu-front-end mlp_key final output[15] mismatch");
        expect_word(SCRATCH1_WORD_INDEX + 0, EXPECT_MLP_OTHER_OUT0, "cpu-front-end mlp_other final output[0] mismatch");
        expect_word(SCRATCH1_WORD_INDEX + 15, EXPECT_MLP_OTHER_OUT15, "cpu-front-end mlp_other final output[15] mismatch");

        expect_word(CNN_OUT_WORD_INDEX + 0, EXPECT_CNN_OUT0, "net3 cnn output[0] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 7, EXPECT_CNN_OUT7, "net3 cnn output[7] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 31, EXPECT_CNN_OUT31, "net3 cnn output[31] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 63, EXPECT_CNN_OUT63, "net3 cnn output[63] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 95, EXPECT_CNN_OUT95, "net3 cnn output[95] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 127, EXPECT_CNN_OUT127, "net3 cnn output[127] mismatch");
        expect_word(CLASS_OUT_WORD_INDEX + 0, EXPECT_CLASSIFIER_OUT0, "net3 classifier output[0] mismatch");
        expect_word(CLASS_OUT_WORD_INDEX + 1, EXPECT_CLASSIFIER_OUT1, "net3 classifier output[1] mismatch");

        $display("[TB][INFO] classifier final output = %08x %08x",
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_OUT_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_OUT_WORD_INDEX + 1]);
        $display("[TB] cpu boot launched twenty-two stages with NET_ID=3 CNN front-end path");
        $display("[TB] CPU top-level stage2 CPU-front-end NET_ID=3 boot test passed");
        repeat(20) @(posedge clk);
        $finish;
    end

endmodule
`default_nettype wire
