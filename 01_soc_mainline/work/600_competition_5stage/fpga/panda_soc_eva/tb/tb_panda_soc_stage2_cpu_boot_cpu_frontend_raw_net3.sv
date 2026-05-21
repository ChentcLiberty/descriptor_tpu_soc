`timescale 1ns / 1ps
`default_nettype none

`include "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/software/generated/breath_cpu_frontend_q8_8_expected.svh"
`include "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/software/generated/breath_cpu_frontend_q8_8_rtl_expected.svh"

module tb_panda_soc_stage2_cpu_boot_cpu_frontend_raw_net3;

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
    localparam [31:0] TPU_CNN_SIGNAL_BASE        = 32'h6012_0000;
    localparam [31:0] TPU_CNN_OUT_BASE           = 32'h6012_2000;

    localparam [31:0] EXPECT_PARAM_KEY0          = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_PARAM_KEY0;
    localparam [31:0] EXPECT_PARAM_KEY1          = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_PARAM_KEY1;
    localparam [31:0] EXPECT_MLP_KEY_OUT0        = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_MLP_KEY_OUT0;
    localparam [31:0] EXPECT_MLP_KEY_OUT15       = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_MLP_KEY_OUT15;
    localparam [31:0] EXPECT_MLP_OTHER_OUT0      = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_MLP_OTHER_OUT0;
    localparam [31:0] EXPECT_MLP_OTHER_OUT15     = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_MLP_OTHER_OUT15;
    localparam [31:0] EXPECT_CNN_OUT0            = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_CNN_OUT0;
    localparam [31:0] EXPECT_CNN_OUT7            = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_CNN_OUT7;
    localparam [31:0] EXPECT_CNN_OUT31           = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_CNN_OUT31;
    localparam [31:0] EXPECT_CNN_OUT63           = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_CNN_OUT63;
    localparam [31:0] EXPECT_CNN_OUT95           = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_CNN_OUT95;
    localparam [31:0] EXPECT_CNN_OUT127          = `BREATH_CPU_FRONTEND_Q8_8_EXPECT_CNN_OUT127;
    localparam [31:0] EXPECT_RAW_NET3_MLP_KEY_OUT0 = `BREATH_CPU_FRONTEND_Q8_8_RTL_EXPECT_MLP_KEY_OUT0;
    localparam [31:0] EXPECT_RAW_NET3_MLP_KEY_OUT15 = `BREATH_CPU_FRONTEND_Q8_8_RTL_EXPECT_MLP_KEY_OUT15;
    localparam [31:0] EXPECT_RAW_NET3_MLP_OTHER_OUT0 = `BREATH_CPU_FRONTEND_Q8_8_RTL_EXPECT_MLP_OTHER_OUT0;
    localparam [31:0] EXPECT_RAW_NET3_MLP_OTHER_OUT15 = `BREATH_CPU_FRONTEND_Q8_8_RTL_EXPECT_MLP_OTHER_OUT15;
    localparam [31:0] EXPECT_RAW_NET3_CLASSIFIER_L2_OUT0 = `BREATH_CPU_FRONTEND_Q8_8_RTL_EXPECT_CLASSIFIER_L2_OUT0;
    localparam [31:0] EXPECT_RAW_NET3_CLASSIFIER_L2_OUT31 = `BREATH_CPU_FRONTEND_Q8_8_RTL_EXPECT_CLASSIFIER_L2_OUT31;
    localparam [31:0] EXPECT_RAW_NET3_CLASSIFIER_OUT0 = `BREATH_CPU_FRONTEND_Q8_8_RTL_EXPECT_CLASSIFIER_OUT0;
    localparam [31:0] EXPECT_RAW_NET3_CLASSIFIER_OUT1 = `BREATH_CPU_FRONTEND_Q8_8_RTL_EXPECT_CLASSIFIER_OUT1;

    localparam integer OUT0_WORD_INDEX = (TPU_OUT_BUF0_BASE - 32'h6000_0000) >> 2;
    localparam integer OUT1_WORD_INDEX = (TPU_OUT_BUF1_BASE - 32'h6000_0000) >> 2;
    localparam integer SCRATCH0_WORD_INDEX = (TPU_SCRATCH0_BASE - 32'h6000_0000) >> 2;
    localparam integer SCRATCH1_WORD_INDEX = (TPU_SCRATCH1_BASE - 32'h6000_0000) >> 2;
    localparam integer CLASS_L0_WORD_INDEX = (TPU_CLASSIFIER_L0_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer CLASS_L1_WORD_INDEX = (TPU_CLASSIFIER_L1_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer CLASS_L2_WORD_INDEX = (TPU_CLASSIFIER_L2_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer CLASS_OUT_WORD_INDEX = (TPU_CLASSIFIER_OUT_BASE - 32'h6000_0000) >> 2;
    localparam integer CNN_OUT_WORD_INDEX = (TPU_CNN_OUT_BASE - 32'h6000_0000) >> 2;
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
    localparam [31:0] DTCM_BASE_ADDR = 32'h1000_0000;
    localparam [31:0] FRONTEND_CNN_READY_ADDR = 32'hFFFF_FFF0;
    localparam [31:0] FRONTEND_PREPROCESS_READY_ADDR = 32'hFFFF_FFF4;
    localparam [31:0] FRONTEND_FEATURE_BASE_ADDR = 32'h6012_1000;
    localparam [31:0] FRONTEND_SIGNAL_BASE_ADDR = 32'h6012_0000;
    localparam integer FRONTEND_FEATURE_WORDS = 4;
    localparam integer FRONTEND_SIGNAL_WORDS = 500;

    localparam IMEM_INIT_FILE    = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_raw_net3/breath_tpu_soc_demo_cpu_frontend_raw_net3_imem.txt";
    localparam IMEM_INIT_FILE_B0 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_raw_net3/breath_tpu_soc_demo_cpu_frontend_raw_net3_imem_b0.txt";
    localparam IMEM_INIT_FILE_B1 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_raw_net3/breath_tpu_soc_demo_cpu_frontend_raw_net3_imem_b1.txt";
    localparam IMEM_INIT_FILE_B2 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_raw_net3/breath_tpu_soc_demo_cpu_frontend_raw_net3_imem_b2.txt";
    localparam IMEM_INIT_FILE_B3 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_raw_net3/breath_tpu_soc_demo_cpu_frontend_raw_net3_imem_b3.txt";
    localparam PARAM_POOL_INIT_FILE = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_cpu_frontend_q8_8/breath_cpu_frontend_q8_8.mem";

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
    reg [31:0] frontend_cnn_ready_shadow;
    reg [31:0] frontend_preprocess_ready_shadow;
    reg [31:0] frontend_cnn_ready_last;
    reg [31:0] frontend_preprocess_ready_last;
    reg frontend_feature_write_seen;
    reg frontend_signal_write_seen;
    reg stop_on_frontend_feature_store;
    reg stop_on_frontend_signal_store;
    reg stop_on_frontend_preprocess_ready;
    reg stop_on_frontend_cnn_ready;

    function [31:0] apply_wmask32;
        input [31:0] old_word;
        input [31:0] new_word;
        input [3:0] wmask;
        begin
            apply_wmask32 = old_word;
            if(wmask[0])
                apply_wmask32[7:0] = new_word[7:0];
            if(wmask[1])
                apply_wmask32[15:8] = new_word[15:8];
            if(wmask[2])
                apply_wmask32[23:16] = new_word[23:16];
            if(wmask[3])
                apply_wmask32[31:24] = new_word[31:24];
        end
    endfunction

    task tb_fail;
        input [255:0] msg;
        begin
            $display("[TB][FAIL] %0s", msg);
            repeat(10) @(posedge clk);
            $finish;
        end
    endtask

    task tb_diag_stop;
        input [255:0] msg;
        begin
            $display("[TB][STOP] %0s", msg);
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
        begin
            actual_word = dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[word_index];
            if(actual_word !== expected_word) begin
                $display("[TB][DBG] word_index=0x%0x actual=0x%08x expected=0x%08x", word_index, actual_word, expected_word);
                tb_fail(tag);
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

    always @(posedge clk) begin
        reg [31:0] frontend_preprocess_ready_now;
        reg [31:0] frontend_cnn_ready_now;
        reg dtcm_write_hs;
        reg [31:0] dtcm_write_addr;
        reg [31:0] dtcm_write_data;
        reg [3:0] dtcm_write_wmask;
        reg data_write_hs;
        reg [31:0] data_write_addr;
        if(ext_resetn) begin
            dtcm_write_hs = dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_valid &&
                dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_ready &&
                (!dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_read);
            dtcm_write_addr = dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_addr;
            dtcm_write_data = dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_wdata;
            dtcm_write_wmask = dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_wmask;
            data_write_hs = dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_valid &&
                dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_ready &&
                (!dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_read);
            data_write_addr = dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_addr;

            frontend_preprocess_ready_now = frontend_preprocess_ready_shadow;
            frontend_cnn_ready_now = frontend_cnn_ready_shadow;

            if(dtcm_write_hs && (dtcm_write_addr == FRONTEND_PREPROCESS_READY_ADDR))
                frontend_preprocess_ready_now = apply_wmask32(frontend_preprocess_ready_shadow, dtcm_write_data, dtcm_write_wmask);
            if(dtcm_write_hs && (dtcm_write_addr == FRONTEND_CNN_READY_ADDR))
                frontend_cnn_ready_now = apply_wmask32(frontend_cnn_ready_shadow, dtcm_write_data, dtcm_write_wmask);

            if((!frontend_feature_write_seen) && data_write_hs &&
               (data_write_addr >= FRONTEND_FEATURE_BASE_ADDR) &&
               (data_write_addr < (FRONTEND_FEATURE_BASE_ADDR + FRONTEND_FEATURE_WORDS * 4))) begin
                frontend_feature_write_seen <= 1'b1;
                $display("[TB][MILESTONE] t=%0t frontend first feature store addr=0x%08x pc=0x%08x inst_rsp_hs=%0d data_rsp_hs=%0d launch_count=%0d",
                    $time,
                    data_write_addr,
                    dut.panda_risc_v_min_proc_sys_u.panda_risc_v_u.panda_risc_v_ifu_u.now_pc,
                    inst_rsp_hs,
                    data_rsp_hs,
                    launch_count);
                if(stop_on_frontend_feature_store)
                    tb_diag_stop("stopped on frontend first feature store");
            end

            if((!frontend_signal_write_seen) && data_write_hs &&
               (data_write_addr >= FRONTEND_SIGNAL_BASE_ADDR) &&
               (data_write_addr < (FRONTEND_SIGNAL_BASE_ADDR + FRONTEND_SIGNAL_WORDS * 4))) begin
                frontend_signal_write_seen <= 1'b1;
                $display("[TB][MILESTONE] t=%0t frontend first signal store addr=0x%08x pc=0x%08x inst_rsp_hs=%0d data_rsp_hs=%0d launch_count=%0d",
                    $time,
                    data_write_addr,
                    dut.panda_risc_v_min_proc_sys_u.panda_risc_v_u.panda_risc_v_ifu_u.now_pc,
                    inst_rsp_hs,
                    data_rsp_hs,
                    launch_count);
                if(stop_on_frontend_signal_store)
                    tb_diag_stop("stopped on frontend first signal store");
            end

            if((frontend_preprocess_ready_last == 32'd0) && (frontend_preprocess_ready_now != 32'd0)) begin
                $display("[TB][MILESTONE] t=%0t frontend preprocess ready=0x%08x pc=0x%08x inst_rsp_hs=%0d data_rsp_hs=%0d dtcm_rsp_hs=%0d launch_count=%0d",
                    $time,
                    frontend_preprocess_ready_now,
                    dut.panda_risc_v_min_proc_sys_u.panda_risc_v_u.panda_risc_v_ifu_u.now_pc,
                    inst_rsp_hs,
                    data_rsp_hs,
                    dtcm_rsp_hs,
                    launch_count);
                if(stop_on_frontend_preprocess_ready)
                    tb_diag_stop("stopped on frontend preprocess ready");
            end

            if((frontend_cnn_ready_last == 32'd0) && (frontend_cnn_ready_now != 32'd0)) begin
                $display("[TB][MILESTONE] t=%0t frontend cnn ready=0x%08x pc=0x%08x inst_rsp_hs=%0d data_rsp_hs=%0d dtcm_rsp_hs=%0d launch_count=%0d",
                    $time,
                    frontend_cnn_ready_now,
                    dut.panda_risc_v_min_proc_sys_u.panda_risc_v_u.panda_risc_v_ifu_u.now_pc,
                    inst_rsp_hs,
                    data_rsp_hs,
                    dtcm_rsp_hs,
                    launch_count);
                if(stop_on_frontend_cnn_ready)
                    tb_diag_stop("stopped on frontend cnn ready");
            end

            frontend_preprocess_ready_shadow <= frontend_preprocess_ready_now;
            frontend_cnn_ready_shadow <= frontend_cnn_ready_now;
            frontend_preprocess_ready_last <= frontend_preprocess_ready_now;
            frontend_cnn_ready_last <= frontend_cnn_ready_now;
        end else begin
            frontend_preprocess_ready_shadow <= 32'd0;
            frontend_cnn_ready_shadow <= 32'd0;
            frontend_preprocess_ready_last <= 32'd0;
            frontend_cnn_ready_last <= 32'd0;
            frontend_feature_write_seen <= 1'b0;
            frontend_signal_write_seen <= 1'b0;
        end
    end

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        #(5_000_000_000);
        $display("[TB][DBG] timeout launch_count=%0d pc=0x%08x inst_cmd_hs=%0d inst_rsp_hs=%0d data_cmd_hs=%0d data_rsp_hs=%0d dtcm_cmd_hs=%0d dtcm_rsp_hs=%0d dbus_aw_hs=%0d dbus_ar_hs=%0d dcache_aw_hs=%0d dcache_ar_hs=%0d inst_addr=0x%08x data_addr=0x%08x dtcm_addr=0x%08x dmem_en=%0b dmem_wen=0x%x dmem_addr=0x%08x preprocess_ready=0x%08x cnn_ready=0x%08x ibus_timeout=%0b dbus_timeout=%0b tpu_busy=%0b tpu_done=%0b tpu_error=%0b tpu_mode=0x%08x tpu_net=0x%08x tpu_desc=0x%08x out0[0]=0x%08x out1[0]=0x%08x",
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
            frontend_preprocess_ready_shadow,
            frontend_cnn_ready_shadow,
            dut.ibus_timeout, dut.dbus_timeout,
            dut.tpu_ctrl_status_busy, dut.tpu_ctrl_status_done, dut.tpu_ctrl_status_error,
            tpu_mode_reg, tpu_net_id_reg, tpu_desc_lo_reg,
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT1_WORD_INDEX + 0]);
        tb_fail("global timeout waiting for raw NET_ID=3 cpu boot completion");
    end

    initial begin
        wait(ext_resetn === 1'b1);
        forever begin
            repeat(1_000_000) @(posedge clk);
            $display("[TB][PROG] t=%0t launch_count=%0d pc=0x%08x inst_rsp_hs=%0d data_rsp_hs=%0d dtcm_rsp_hs=%0d dbus_aw_hs=%0d dbus_ar_hs=%0d dcache_aw_hs=%0d dcache_ar_hs=%0d preprocess_ready=0x%08x cnn_ready=0x%08x tpu_mode=0x%08x tpu_net=0x%08x tpu_desc=0x%08x",
                $time,
                launch_count,
                dut.panda_risc_v_min_proc_sys_u.panda_risc_v_u.panda_risc_v_ifu_u.now_pc,
                inst_rsp_hs,
                data_rsp_hs,
                dtcm_rsp_hs,
                dbus_aw_hs,
                dbus_ar_hs,
                dcache_aw_hs,
                dcache_ar_hs,
                frontend_preprocess_ready_shadow,
                frontend_cnn_ready_shadow,
                tpu_mode_reg,
                tpu_net_id_reg,
                tpu_desc_lo_reg);
        end
    end

    initial begin
        stop_on_frontend_feature_store = $test$plusargs("tb_stop_on_frontend_feature_store");
        stop_on_frontend_signal_store = $test$plusargs("tb_stop_on_frontend_signal_store");
        stop_on_frontend_preprocess_ready = $test$plusargs("tb_stop_on_frontend_preprocess_ready");
        stop_on_frontend_cnn_ready = $test$plusargs("tb_stop_on_frontend_cnn_ready");
        if(stop_on_frontend_feature_store || stop_on_frontend_signal_store ||
           stop_on_frontend_preprocess_ready || stop_on_frontend_cnn_ready)
            $display("[TB] diagnostic stop modes: feature=%0d signal=%0d preprocess=%0d cnn=%0d",
                stop_on_frontend_feature_store,
                stop_on_frontend_signal_store,
                stop_on_frontend_preprocess_ready,
                stop_on_frontend_cnn_ready);

        ext_resetn = 1'b0;
        uart0_rx = 1'b1;
        launch_count = 0;
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
        frontend_cnn_ready_shadow = 32'd0;
        frontend_preprocess_ready_shadow = 32'd0;
        frontend_cnn_ready_last = 32'd0;
        frontend_preprocess_ready_last = 32'd0;
        frontend_feature_write_seen = 1'b0;
        frontend_signal_write_seen = 1'b0;

        repeat(20) @(posedge clk);
        $display("[TB] raw CPU-front-end + NET_ID=3 shared SRAM supplied through shared_sram_init_file: %0s", PARAM_POOL_INIT_FILE);
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
        if(!frontend_feature_write_seen)
            tb_fail("raw feature store was not observed before NET_ID=3 launch");
        if(!frontend_signal_write_seen)
            tb_fail("raw signal store was not observed before NET_ID=3 launch");
        expect_word(DESC0_WORD_INDEX + 0, 32'd3, "raw net3 desc net_id mismatch");
        expect_word(DESC0_WORD_INDEX + 1, TPU_CNN_SIGNAL_BASE, "raw net3 desc input_addr mismatch");
        expect_word(DESC0_WORD_INDEX + 2, TPU_CNN_OUT_BASE, "raw net3 desc output_addr mismatch");
        expect_word(DESC0_WORD_INDEX + 5, 32'd500, "raw net3 desc input_words mismatch");
        expect_word(DESC0_WORD_INDEX + 6, 32'd128, "raw net3 desc output_words mismatch");
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
            tb_fail("final done was not observed after twenty-second launch");
        end

        expect_word(PARAM_KEY_INDEX + 0, EXPECT_PARAM_KEY0, "param_pool key[0] mismatch after CPU boot");
        expect_word(PARAM_KEY_INDEX + 1, EXPECT_PARAM_KEY1, "param_pool key[1] mismatch after CPU boot");
        expect_word(CNN_OUT_WORD_INDEX + 0, EXPECT_CNN_OUT0, "raw net3 cnn output[0] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 7, EXPECT_CNN_OUT7, "raw net3 cnn output[7] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 31, EXPECT_CNN_OUT31, "raw net3 cnn output[31] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 63, EXPECT_CNN_OUT63, "raw net3 cnn output[63] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 95, EXPECT_CNN_OUT95, "raw net3 cnn output[95] mismatch");
        expect_word(CNN_OUT_WORD_INDEX + 127, EXPECT_CNN_OUT127, "raw net3 cnn output[127] mismatch");
        expect_word(OUT0_WORD_INDEX + 0, EXPECT_RAW_NET3_MLP_KEY_OUT0, "raw net3 mlp_key output[0] mismatch");
        expect_word(OUT0_WORD_INDEX + 15, EXPECT_RAW_NET3_MLP_KEY_OUT15, "raw net3 mlp_key output[15] mismatch");
        expect_word(SCRATCH1_WORD_INDEX + 0, EXPECT_RAW_NET3_MLP_OTHER_OUT0, "raw net3 mlp_other output[0] mismatch");
        expect_word(SCRATCH1_WORD_INDEX + 15, EXPECT_RAW_NET3_MLP_OTHER_OUT15, "raw net3 mlp_other output[15] mismatch");
        expect_word(CLASS_L2_WORD_INDEX + 0, EXPECT_RAW_NET3_CLASSIFIER_L2_OUT0, "raw net3 classifier l2 output[0] mismatch");
        expect_word(CLASS_L2_WORD_INDEX + 31, EXPECT_RAW_NET3_CLASSIFIER_L2_OUT31, "raw net3 classifier l2 output[31] mismatch");
        expect_word(CLASS_OUT_WORD_INDEX + 0, EXPECT_RAW_NET3_CLASSIFIER_OUT0, "raw net3 classifier final output[0] mismatch");
        expect_word(CLASS_OUT_WORD_INDEX + 1, EXPECT_RAW_NET3_CLASSIFIER_OUT1, "raw net3 classifier final output[1] mismatch");
        $display("[TB][INFO] raw net3 watchpoints mlp_key=%08x %08x mlp_other=%08x %08x class_l2=%08x %08x",
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 15],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[SCRATCH1_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[SCRATCH1_WORD_INDEX + 15],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_L2_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_L2_WORD_INDEX + 31]);
        $display("[TB][INFO] raw net3 classifier final output = %08x %08x",
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_OUT_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[CLASS_OUT_WORD_INDEX + 1]);

        $display("[TB] cpu boot launched twenty-two stages with raw preprocess + NET_ID=3 CNN path");
        $display("[TB] CPU top-level stage2 raw preprocess + NET_ID=3 boot test passed");
        repeat(20) @(posedge clk);
        $finish;
    end

endmodule
`default_nettype wire
