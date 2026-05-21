`timescale 1ns / 1ps
`default_nettype none

module tb_panda_soc_stage2_cpu_boot_real_params_diag;

    localparam integer CLK_PERIOD = 10;
    localparam [31:0] TPU_DESC0_BASE    = 32'h6001_0000;
    localparam [31:0] TPU_DESC1_BASE    = 32'h6001_1000;
    localparam [31:0] TPU_OUT_BUF0_BASE = 32'h6001_0400;
    localparam [31:0] TPU_OUT_BUF1_BASE = 32'h6001_1400;
    localparam [31:0] TPU_SCRATCH0_BASE = 32'h6001_0800;
    localparam [31:0] TPU_SCRATCH1_BASE = 32'h6001_1800;
    localparam [31:0] TPU_CLASSIFIER_L0_OUT_BASE = 32'h6001_2400;
    localparam [31:0] TPU_CLASSIFIER_L1_OUT_BASE = 32'h6001_2800;
    localparam [31:0] TPU_CLASSIFIER_L2_OUT_BASE = 32'h6001_2C00;
    localparam [31:0] TPU_CLASSIFIER_OUT_BASE    = 32'h6001_3000;

    localparam [31:0] EXPECT_PARAM_KEY0          = 32'hFEDE_FEFA;
    localparam [31:0] EXPECT_PARAM_KEY1          = 32'h000B_FF15;
    localparam [31:0] EXPECT_MLP_KEY_OUT0        = 32'h0000_0000;
    localparam [31:0] EXPECT_MLP_KEY_OUT15       = 32'h01DB_018E;
    localparam [31:0] EXPECT_MLP_OTHER_OUT0      = 32'h0040_0020;
    localparam [31:0] EXPECT_MLP_OTHER_OUT15     = 32'h0000_00CD;
    localparam [31:0] EXPECT_CLASSIFIER_L2_OUT0  = 32'h00A6_0020;
    localparam [31:0] EXPECT_CLASSIFIER_L2_OUT31 = 32'h0216_00D1;
    localparam [31:0] EXPECT_CLASSIFIER_OUT0     = 32'h015E_FB3D;
    localparam [31:0] EXPECT_CLASSIFIER_OUT1     = 32'hFDC5_061D;

    localparam integer OUT0_WORD_INDEX = (TPU_OUT_BUF0_BASE - 32'h6000_0000) >> 2;
    localparam integer OUT1_WORD_INDEX = (TPU_OUT_BUF1_BASE - 32'h6000_0000) >> 2;
    localparam integer SCRATCH0_WORD_INDEX = (TPU_SCRATCH0_BASE - 32'h6000_0000) >> 2;
    localparam integer SCRATCH1_WORD_INDEX = (TPU_SCRATCH1_BASE - 32'h6000_0000) >> 2;
    localparam integer CLASS_L0_WORD_INDEX = (TPU_CLASSIFIER_L0_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer CLASS_L1_WORD_INDEX = (TPU_CLASSIFIER_L1_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer CLASS_L2_WORD_INDEX = (TPU_CLASSIFIER_L2_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer CLASS_OUT_WORD_INDEX = (TPU_CLASSIFIER_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer PARAM_KEY_INDEX = (32'h6000_0000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_KEY_L1_INDEX = (32'h6000_0400 - 32'h6000_0000) >> 2;
    localparam integer PARAM_KEY_L2_INDEX = (32'h6000_2000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_KEY_L3_INDEX = (32'h6000_7000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_KEY_L4_INDEX = (32'h6000_C000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_OTHER_INDEX = (32'h6000_E000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_OTHER_L1_INDEX = (32'h6000_E400 - 32'h6000_0000) >> 2;
    localparam integer PARAM_CLASSIFIER_INDEX = (32'h6002_0000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_CLASSIFIER_L1_INDEX = (32'h6005_0000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_CLASSIFIER_L2_INDEX = (32'h6006_4000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_CLASSIFIER_L3_INDEX = (32'h6006_9000 - 32'h6000_0000) >> 2;
    localparam integer DESC0_WORD_INDEX = (TPU_DESC0_BASE - 32'h6000_0000) >> 2;
    localparam integer DESC1_WORD_INDEX = (TPU_DESC1_BASE - 32'h6000_0000) >> 2;

    localparam IMEM_INIT_FILE    = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_preload_params/breath_tpu_soc_demo_preload_params_imem.txt";
    localparam IMEM_INIT_FILE_B0 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_preload_params/breath_tpu_soc_demo_preload_params_imem_b0.txt";
    localparam IMEM_INIT_FILE_B1 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_preload_params/breath_tpu_soc_demo_preload_params_imem_b1.txt";
    localparam IMEM_INIT_FILE_B2 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_preload_params/breath_tpu_soc_demo_preload_params_imem_b2.txt";
    localparam IMEM_INIT_FILE_B3 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_preload_params/breath_tpu_soc_demo_preload_params_imem_b3.txt";
    localparam PARAM_POOL_INIT_FILE = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_params_q8_8/breath_tpu_param_pool_q8_8.mem";

    reg clk;
    reg ext_resetn;
    reg uart0_rx;
    wire uart0_tx;

    wire        tpu_launch_pulse;
    wire        tpu_soft_reset_pulse;
    wire [31:0] tpu_mode_reg;
    wire [31:0] tpu_net_id_reg;
    wire [31:0] tpu_desc_lo_reg;
    wire [31:0] tpu_desc_hi_reg;
    wire        tpu_irq_en_reg;
    wire [31:0] tpu_perf_cycle_reg;

    integer launch_count;
    integer wait_cycles;
    integer dbus_aw_hs;
    integer dbus_ar_hs;
    integer dcache_aw_hs;
    integer dcache_ar_hs;
    integer inst_cmd_hs;
    integer inst_rsp_hs;
    integer data_cmd_hs;
    integer data_rsp_hs;
    integer dtcm_cmd_hs;
    integer dtcm_rsp_hs;
    integer mismatch_count;

    task tb_fail;
        input [255:0] msg;
        begin
            $display("[TB][FAIL] %0s", msg);
            repeat(10) @(posedge clk);
            $finish;
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

            dump_desc_words(expected_desc_addr);

            @(posedge clk);
        end
    endtask

    task expect_word;
        input integer word_index;
        input [31:0] expected_word;
        input [255:0] tag;
        reg [31:0] actual_word;
        integer signed delta_hi;
        integer signed delta_lo;
        begin
            actual_word = dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[word_index];
            if(actual_word !== expected_word) begin
                mismatch_count = mismatch_count + 1;
                delta_hi = $signed({actual_word[31], actual_word[31:16]}) - $signed({expected_word[31], expected_word[31:16]});
                delta_lo = $signed({actual_word[15], actual_word[15:0]}) - $signed({expected_word[15], expected_word[15:0]});
                $display("[TB][MISMATCH][%0d] %0s word_index=0x%0x actual=0x%08x expected=0x%08x delta_hi=%0d delta_lo=%0d",
                    mismatch_count, tag, word_index, actual_word, expected_word, delta_hi, delta_lo);
            end
        end
    endtask

    task dump_desc_words;
        input [31:0] desc_addr;
        integer desc_word_index;
        integer input_word_index;
        integer param_word_index;
        reg [31:0] input_addr;
        reg [31:0] param_addr;
        begin
            desc_word_index = (desc_addr - 32'h6000_0000) >> 2;
            input_addr = dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 1];
            param_addr = dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 3];
            input_word_index = (input_addr - 32'h6000_0000) >> 2;
            param_word_index = (param_addr - 32'h6000_0000) >> 2;

            $display("[TB][DBG] desc_memx%08x = %08x %08x %08x %08x %08x %08x %08x %08x",
                desc_addr,
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 0],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 1],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 2],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 3],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 4],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 5],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 6],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 7]);

            if((input_addr >= 32'h6000_0000) && (input_addr < 32'h6080_0000)) begin
                $display("[TB][DBG] input_memx%08x = %08x %08x",
                    input_addr,
                    dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[input_word_index + 0],
                    dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[input_word_index + 1]);
            end

            if((param_addr >= 32'h6000_0000) && (param_addr < 32'h6080_0000)) begin
                $display("[TB][DBG] param_memx%08x = %08x %08x",
                    param_addr,
                    dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[param_word_index + 0],
                    dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[param_word_index + 1]);
            end
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
        .tpu_soft_reset_pulse(tpu_soft_reset_pulse),
        .tpu_mode_reg(tpu_mode_reg),
        .tpu_net_id_reg(tpu_net_id_reg),
        .tpu_desc_lo_reg(tpu_desc_lo_reg),
        .tpu_desc_hi_reg(tpu_desc_hi_reg),
        .tpu_irq_en_reg(tpu_irq_en_reg),
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
        if(ext_resetn) begin
            if(dut.m_axi_dbus_awvalid && dut.m_axi_dbus_awready)
                dbus_aw_hs <= dbus_aw_hs + 1;
            if(dut.m_axi_dbus_arvalid && dut.m_axi_dbus_arready)
                dbus_ar_hs <= dbus_ar_hs + 1;
            if(dut.m_axi_dcache_awvalid && dut.m_axi_dcache_awready)
                dcache_aw_hs <= dcache_aw_hs + 1;
            if(dut.m_axi_dcache_arvalid && dut.m_axi_dcache_arready)
                dcache_ar_hs <= dcache_ar_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_inst_valid && dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_inst_ready)
                inst_cmd_hs <= inst_cmd_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m_icb_rsp_inst_valid && dut.panda_risc_v_min_proc_sys_u.m_icb_rsp_inst_ready)
                inst_rsp_hs <= inst_rsp_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_valid && dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_ready)
                data_cmd_hs <= data_cmd_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m_icb_rsp_data_valid && dut.panda_risc_v_min_proc_sys_u.m_icb_rsp_data_ready)
                data_rsp_hs <= data_rsp_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_valid && dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_ready)
                dtcm_cmd_hs <= dtcm_cmd_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_rsp_valid && dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_rsp_ready)
                dtcm_rsp_hs <= dtcm_rsp_hs + 1;
        end
    end

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        #(200_000_000);
        $display("[TB][DBG] timeout launch_count=%0d pc=0x%08x inst_cmd_hs=%0d inst_rsp_hs=%0d data_cmd_hs=%0d data_rsp_hs=%0d dtcm_cmd_hs=%0d dtcm_rsp_hs=%0d dbus_aw_hs=%0d dbus_ar_hs=%0d dcache_aw_hs=%0d dcache_ar_hs=%0d inst_addr=0x%08x data_addr=0x%08x dtcm_addr=0x%08x dmem_en=%0b dmem_wen=0x%x dmem_addr=0x%08x ibus_timeout=%0b dbus_timeout=%0b tpu_busy=%0b tpu_done=%0b tpu_error=%0b tpu_mode=0x%08x tpu_net=0x%08x tpu_desc=0x%08x out0[0]=0x%08x out1[0]=0x%08x",
            launch_count,
            dut.panda_risc_v_min_proc_sys_u.panda_risc_v_u.panda_risc_v_ifu_u.now_pc,
            inst_cmd_hs, inst_rsp_hs, data_cmd_hs, data_rsp_hs, dtcm_cmd_hs, dtcm_rsp_hs,
            dbus_aw_hs, dbus_ar_hs, dcache_aw_hs, dcache_ar_hs,
            dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_inst_addr,
            dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_addr,
            dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_addr,
            dut.panda_risc_v_min_proc_sys_u.dmem_en,
            dut.panda_risc_v_min_proc_sys_u.dmem_wen,
            {dut.panda_risc_v_min_proc_sys_u.dmem_addr, 2'b00},
            dut.ibus_timeout, dut.dbus_timeout,
            dut.tpu_ctrl_status_busy, dut.tpu_ctrl_status_done, dut.tpu_ctrl_status_error,
            tpu_mode_reg, tpu_net_id_reg, tpu_desc_lo_reg,
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT1_WORD_INDEX + 0]);
        tb_fail("global timeout waiting for cpu boot stage2 completion");
    end

    initial begin
        ext_resetn = 1'b0;
        uart0_rx = 1'b1;
        launch_count = 0;
        mismatch_count = 0;
        dbus_aw_hs = 0;
        dbus_ar_hs = 0;
        dcache_aw_hs = 0;
        dcache_ar_hs = 0;
        inst_cmd_hs = 0;
        inst_rsp_hs = 0;
        data_cmd_hs = 0;
        data_rsp_hs = 0;
        dtcm_cmd_hs = 0;
        dtcm_rsp_hs = 0;

        repeat(20) @(posedge clk);
        $display("[TB] real q8.8 param_pool supplied through shared_sram_init_file: %0s", PARAM_POOL_INIT_FILE);
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
        expect_launch(8, 32'd2, TPU_DESC0_BASE);
        expect_launch(9, 32'd2, TPU_DESC1_BASE);
        expect_launch(10, 32'd2, TPU_DESC0_BASE);
        expect_launch(11, 32'd2, TPU_DESC1_BASE);
        expect_launch(12, 32'd2, TPU_DESC0_BASE);
        expect_launch(13, 32'd2, TPU_DESC1_BASE);
        expect_launch(14, 32'd2, TPU_DESC0_BASE);
        expect_launch(15, 32'd2, TPU_DESC1_BASE);
        expect_launch(16, 32'd2, TPU_DESC0_BASE);
        expect_launch(17, 32'd2, TPU_DESC1_BASE);
        expect_launch(18, 32'd2, TPU_DESC0_BASE);
        expect_launch(19, 32'd2, TPU_DESC1_BASE);
        expect_launch(20, 32'd2, TPU_DESC0_BASE);
        expect_launch(21, 32'd2, TPU_DESC1_BASE);

        for(wait_cycles = 0; wait_cycles < 200000; wait_cycles = wait_cycles + 1) begin
            @(posedge clk);
            if(dut.tpu_ctrl_status_done) begin
                wait_cycles = 200000;
            end
        end
        if(!dut.tpu_ctrl_status_done) begin
            $display("[TB][DBG] final launch wait expired busy=%0b done=%0b error=%0b perf=0x%08x desc_net=0x%08x input_words=%0d output_words=%0d input_wc=%0d param_wc=%0d out0[0]=0x%08x out0[1]=0x%08x out1[0]=0x%08x out1[1]=0x%08x",
                dut.tpu_ctrl_status_busy, dut.tpu_ctrl_status_done, dut.tpu_ctrl_status_error, tpu_perf_cycle_reg,
                dut.tpu_dma_stub_desc_net_id, dut.tpu_dma_stub_desc_input_words, dut.tpu_dma_stub_desc_output_words,
                dut.tpu_dma_stub_input_fetch_word_count, dut.tpu_dma_stub_param_fetch_word_count,
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 0],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 1],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT1_WORD_INDEX + 0],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT1_WORD_INDEX + 1]);
            tb_fail("final done was not observed after twenty-first launch");
        end

        expect_word(PARAM_KEY_INDEX + 0, EXPECT_PARAM_KEY0, "param_pool key[0] mismatch after CPU boot");
        expect_word(PARAM_KEY_INDEX + 1, EXPECT_PARAM_KEY1, "param_pool key[1] mismatch after CPU boot");
        expect_word(OUT0_WORD_INDEX + 0, EXPECT_MLP_KEY_OUT0, "real mlp_key final output[0] mismatch");
        expect_word(OUT0_WORD_INDEX + 15, EXPECT_MLP_KEY_OUT15, "real mlp_key final output[15] mismatch");
        expect_word(SCRATCH1_WORD_INDEX + 0, EXPECT_MLP_OTHER_OUT0, "real mlp_other final output[0] mismatch");
        expect_word(SCRATCH1_WORD_INDEX + 15, EXPECT_MLP_OTHER_OUT15, "real mlp_other final output[15] mismatch");
        expect_word(CLASS_L2_WORD_INDEX + 0, EXPECT_CLASSIFIER_L2_OUT0, "real classifier l2 output[0] mismatch");
        expect_word(CLASS_L2_WORD_INDEX + 31, EXPECT_CLASSIFIER_L2_OUT31, "real classifier l2 output[31] mismatch");
        expect_word(CLASS_OUT_WORD_INDEX + 0, EXPECT_CLASSIFIER_OUT0, "real classifier final output[0] mismatch");
        expect_word(CLASS_OUT_WORD_INDEX + 1, EXPECT_CLASSIFIER_OUT1, "real classifier final output[1] mismatch");

        $display("[TB][SUMMARY] out0[0]=0x%08x out0[15]=0x%08x scratch1[0]=0x%08x scratch1[15]=0x%08x class_l2[0]=0x%08x class_l2[31]=0x%08x class_out[0]=0x%08x class_out[1]=0x%08x",
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 15],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[SCRATCH1_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[SCRATCH1_WORD_INDEX + 15],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_L2_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_L2_WORD_INDEX + 31],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_OUT_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_OUT_WORD_INDEX + 1]);

        if(mismatch_count != 0) begin
            $display("[TB][SUMMARY] mismatch_count=%0d", mismatch_count);
            tb_fail("diagnostic run completed with mismatches");
        end

        $display("[TB] cpu boot launched all twenty-one stages with real pretrained q8.8 params");
        $display("[TB] CPU top-level stage2 real-param boot test passed");
        repeat(20) @(posedge clk);
        $finish;
    end

endmodule
`default_nettype wire
