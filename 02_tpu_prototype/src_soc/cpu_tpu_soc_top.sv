`timescale 1ns/1ps
`default_nettype none

module cpu_tpu_soc_top #(
    parameter EN_DCACHE = "false",
    parameter EN_DTCM = "true",
    parameter integer DCACHE_WAY_N = 2,
    parameter integer DCACHE_ENTRY_N = 1024,
    parameter integer DCACHE_LINE_WORD_N = 2,
    parameter integer DCACHE_TAG_WIDTH = 10,
    parameter integer DCACHE_WBUF_ITEM_N = 2,
    parameter integer IMEM_DEPTH = 8192,
    parameter integer DMEM_DEPTH = 8192,
    parameter EN_MEM_BYTE_WRITE = "false",
    parameter IMEM_INIT_FILE = "no_init",
    parameter IMEM_INIT_FILE_B0 = "no_init",
    parameter IMEM_INIT_FILE_B1 = "no_init",
    parameter IMEM_INIT_FILE_B2 = "no_init",
    parameter IMEM_INIT_FILE_B3 = "no_init",
    parameter SGN_PERIOD_MUL = "true",
    parameter [31:0] RST_PC = 32'h0000_0000,
    parameter [31:0] TPU_BASE_ADDR = 32'h4000_4000,
    parameter integer TPU_ADDR_RANGE = 4096
) (
    input  logic        clk,
    input  logic        sys_resetn,
    input  logic        sys_reset_req,

    input  logic [62:0] ext_itr_req_vec,

    output logic [31:0] m_periph_axil_awaddr,
    output logic [2:0]  m_periph_axil_awprot,
    output logic        m_periph_axil_awvalid,
    input  logic        m_periph_axil_awready,
    output logic [31:0] m_periph_axil_wdata,
    output logic [3:0]  m_periph_axil_wstrb,
    output logic        m_periph_axil_wvalid,
    input  logic        m_periph_axil_wready,
    input  logic [1:0]  m_periph_axil_bresp,
    input  logic        m_periph_axil_bvalid,
    output logic        m_periph_axil_bready,
    output logic [31:0] m_periph_axil_araddr,
    output logic [2:0]  m_periph_axil_arprot,
    output logic        m_periph_axil_arvalid,
    input  logic        m_periph_axil_arready,
    input  logic [31:0] m_periph_axil_rdata,
    input  logic [1:0]  m_periph_axil_rresp,
    input  logic        m_periph_axil_rvalid,
    output logic        m_periph_axil_rready,

    output logic [15:0] tpu_vpu_data_out_1,
    output logic [15:0] tpu_vpu_data_out_2,
    output logic        tpu_vpu_valid_out_1,
    output logic        tpu_vpu_valid_out_2,
    output logic [15:0] tpu_sys_data_out_21,
    output logic [15:0] tpu_sys_data_out_22,
    output logic        tpu_sys_valid_out_21,
    output logic        tpu_sys_valid_out_22
);

    logic [31:0] cpu_axil_araddr;
    logic [1:0]  cpu_axil_arburst;
    logic [7:0]  cpu_axil_arlen;
    logic [2:0]  cpu_axil_arsize;
    logic [3:0]  cpu_axil_arcache;
    logic        cpu_axil_arvalid;
    logic        cpu_axil_arready;

    logic [31:0] cpu_axil_awaddr;
    logic [1:0]  cpu_axil_awburst;
    logic [7:0]  cpu_axil_awlen;
    logic [2:0]  cpu_axil_awsize;
    logic [3:0]  cpu_axil_awcache;
    logic        cpu_axil_awvalid;
    logic        cpu_axil_awready;

    logic [1:0]  cpu_axil_bresp;
    logic        cpu_axil_bvalid;
    logic        cpu_axil_bready;

    logic [31:0] cpu_axil_rdata;
    logic [1:0]  cpu_axil_rresp;
    logic        cpu_axil_rlast;
    logic        cpu_axil_rvalid;
    logic        cpu_axil_rready;

    logic [31:0] cpu_axil_wdata;
    logic [3:0]  cpu_axil_wstrb;
    logic        cpu_axil_wlast;
    logic        cpu_axil_wvalid;
    logic        cpu_axil_wready;

    logic [31:0] cpu_mem_axi_rdata;
    logic [1:0]  cpu_mem_axi_rresp;
    logic        cpu_mem_axi_rlast;
    logic        cpu_mem_axi_rvalid;
    logic        cpu_mem_axi_arready;
    logic        cpu_mem_axi_awready;
    logic [1:0]  cpu_mem_axi_bresp;
    logic        cpu_mem_axi_bvalid;
    logic        cpu_mem_axi_wready;

    logic [31:0] tpu_axil_awaddr;
    logic [2:0]  tpu_axil_awprot_unused;
    logic        tpu_axil_awvalid;
    logic        tpu_axil_awready;
    logic [31:0] tpu_axil_wdata;
    logic [3:0]  tpu_axil_wstrb;
    logic        tpu_axil_wvalid;
    logic        tpu_axil_wready;
    logic [1:0]  tpu_axil_bresp;
    logic        tpu_axil_bvalid;
    logic        tpu_axil_bready;
    logic [31:0] tpu_axil_araddr;
    logic [2:0]  tpu_axil_arprot_unused;
    logic        tpu_axil_arvalid;
    logic        tpu_axil_arready;
    logic [31:0] tpu_axil_rdata;
    logic [1:0]  tpu_axil_rresp;
    logic        tpu_axil_rvalid;
    logic        tpu_axil_rready;

    assign cpu_mem_axi_arready = 1'b0;
    assign cpu_mem_axi_awready = 1'b0;
    assign cpu_mem_axi_bresp   = 2'b11;
    assign cpu_mem_axi_bvalid  = 1'b0;
    assign cpu_mem_axi_rdata   = 32'd0;
    assign cpu_mem_axi_rresp   = 2'b11;
    assign cpu_mem_axi_rlast   = 1'b0;
    assign cpu_mem_axi_rvalid  = 1'b0;
    assign cpu_mem_axi_wready  = 1'b0;
    assign cpu_axil_rlast      = 1'b1;

    panda_risc_v_min_proc_sys #(
        .EN_DCACHE(EN_DCACHE),
        .EN_DTCM(EN_DTCM),
        .DCACHE_WAY_N(DCACHE_WAY_N),
        .DCACHE_ENTRY_N(DCACHE_ENTRY_N),
        .DCACHE_LINE_WORD_N(DCACHE_LINE_WORD_N),
        .DCACHE_TAG_WIDTH(DCACHE_TAG_WIDTH),
        .DCACHE_WBUF_ITEM_N(DCACHE_WBUF_ITEM_N),
        .imem_access_timeout_th(16),
        .inst_addr_alignment_width(32),
        .dbus_access_timeout_th(64),
        .icb_zero_latency_supported("false"),
        .en_expt_vec_vectored("false"),
        .en_performance_monitor("true"),
        .init_mtvec_base(30'd0),
        .init_mcause_interrupt(1'b0),
        .init_mcause_exception_code(31'd16),
        .init_misa_mxl(2'b01),
        .init_misa_extensions(26'b00_0000_0000_0001_0001_0000_0000),
        .init_mvendorid_bank(25'h0_00_00_00),
        .init_mvendorid_offset(7'h00),
        .init_marchid(32'h00_00_00_00),
        .init_mimpid(32'h31_2E_30_30),
        .init_mhartid(32'h00_00_00_00),
        .dpc_trace_inst_n(16),
        .inst_id_width(5),
        .en_alu_csr_rw_bypass("true"),
        .imem_baseaddr(32'h0000_0000),
        .imem_addr_range(IMEM_DEPTH * 4),
        .dm_regs_baseaddr(32'hFFFF_F800),
        .dm_regs_addr_range(1024),
        .dmem_baseaddr(32'h1000_0000),
        .dmem_addr_range(DMEM_DEPTH * 4),
        .plic_baseaddr(32'hF000_0000),
        .plic_addr_range(4 * 1024 * 1024),
        .clint_baseaddr(32'hF400_0000),
        .clint_addr_range(64 * 1024 * 1024),
        .ext_peripheral_baseaddr(32'h4000_0000),
        .ext_peripheral_addr_range(16 * 4096),
        .ext_mem_baseaddr(32'h6000_0000),
        .ext_mem_addr_range(8 * 1024 * 1024),
        .en_inst_cmd_fwd("false"),
        .en_inst_rsp_bck("false"),
        .en_data_cmd_fwd("true"),
        .en_data_rsp_bck("true"),
        .en_mem_byte_write(EN_MEM_BYTE_WRITE),
        .imem_init_file(IMEM_INIT_FILE),
        .imem_init_file_b0(IMEM_INIT_FILE_B0),
        .imem_init_file_b1(IMEM_INIT_FILE_B1),
        .imem_init_file_b2(IMEM_INIT_FILE_B2),
        .imem_init_file_b3(IMEM_INIT_FILE_B3),
        .sgn_period_mul(SGN_PERIOD_MUL),
        .rtc_psc_r(50 * 1000),
        .debug_supported("false"),
        .DEBUG_ROM_ADDR(32'h0000_0600),
        .dscratch_n(2),
        .simulation_delay(0)
    ) cpu_subsys (
        .clk(clk),
        .sys_resetn(sys_resetn),
        .sys_reset_req(sys_reset_req),
        .rst_pc(RST_PC),
        .rtc_en(1'b1),
        .m_axi_dbus_araddr(cpu_axil_araddr),
        .m_axi_dbus_arburst(cpu_axil_arburst),
        .m_axi_dbus_arlen(cpu_axil_arlen),
        .m_axi_dbus_arsize(cpu_axil_arsize),
        .m_axi_dbus_arcache(cpu_axil_arcache),
        .m_axi_dbus_arvalid(cpu_axil_arvalid),
        .m_axi_dbus_arready(cpu_axil_arready),
        .m_axi_dbus_awaddr(cpu_axil_awaddr),
        .m_axi_dbus_awburst(cpu_axil_awburst),
        .m_axi_dbus_awlen(cpu_axil_awlen),
        .m_axi_dbus_awsize(cpu_axil_awsize),
        .m_axi_dbus_awcache(cpu_axil_awcache),
        .m_axi_dbus_awvalid(cpu_axil_awvalid),
        .m_axi_dbus_awready(cpu_axil_awready),
        .m_axi_dbus_bresp(cpu_axil_bresp),
        .m_axi_dbus_bvalid(cpu_axil_bvalid),
        .m_axi_dbus_bready(cpu_axil_bready),
        .m_axi_dbus_rdata(cpu_axil_rdata),
        .m_axi_dbus_rresp(cpu_axil_rresp),
        .m_axi_dbus_rlast(cpu_axil_rlast),
        .m_axi_dbus_rvalid(cpu_axil_rvalid),
        .m_axi_dbus_rready(cpu_axil_rready),
        .m_axi_dbus_wdata(cpu_axil_wdata),
        .m_axi_dbus_wstrb(cpu_axil_wstrb),
        .m_axi_dbus_wlast(cpu_axil_wlast),
        .m_axi_dbus_wvalid(cpu_axil_wvalid),
        .m_axi_dbus_wready(cpu_axil_wready),
        .m_axi_dcache_araddr(),
        .m_axi_dcache_arburst(),
        .m_axi_dcache_arlen(),
        .m_axi_dcache_arsize(),
        .m_axi_dcache_arcache(),
        .m_axi_dcache_arvalid(),
        .m_axi_dcache_arready(cpu_mem_axi_arready),
        .m_axi_dcache_awaddr(),
        .m_axi_dcache_awburst(),
        .m_axi_dcache_awlen(),
        .m_axi_dcache_awsize(),
        .m_axi_dcache_awcache(),
        .m_axi_dcache_awvalid(),
        .m_axi_dcache_awready(cpu_mem_axi_awready),
        .m_axi_dcache_bresp(cpu_mem_axi_bresp),
        .m_axi_dcache_bvalid(cpu_mem_axi_bvalid),
        .m_axi_dcache_bready(),
        .m_axi_dcache_rdata(cpu_mem_axi_rdata),
        .m_axi_dcache_rresp(cpu_mem_axi_rresp),
        .m_axi_dcache_rlast(cpu_mem_axi_rlast),
        .m_axi_dcache_rvalid(cpu_mem_axi_rvalid),
        .m_axi_dcache_rready(),
        .m_axi_dcache_wdata(),
        .m_axi_dcache_wstrb(),
        .m_axi_dcache_wlast(),
        .m_axi_dcache_wvalid(),
        .m_axi_dcache_wready(cpu_mem_axi_wready),
        .ibus_timeout(),
        .dbus_timeout(),
        .ext_itr_req_vec(ext_itr_req_vec),
        .hart_access_en(),
        .hart_access_wen(),
        .hart_access_addr(),
        .hart_access_din(),
        .hart_access_dout(32'd0),
        .dbg_halt_req(1'b0),
        .dbg_halt_on_reset_req(1'b0)
    );

    cpu_tpu_axil_splitter #(
        .TPU_BASE_ADDR(TPU_BASE_ADDR),
        .TPU_ADDR_RANGE(TPU_ADDR_RANGE)
    ) axil_splitter (
        .aclk(clk),
        .aresetn(sys_resetn),
        .s_axil_awaddr(cpu_axil_awaddr),
        .s_axil_awprot(3'b000),
        .s_axil_awvalid(cpu_axil_awvalid),
        .s_axil_awready(cpu_axil_awready),
        .s_axil_wdata(cpu_axil_wdata),
        .s_axil_wstrb(cpu_axil_wstrb),
        .s_axil_wvalid(cpu_axil_wvalid),
        .s_axil_wready(cpu_axil_wready),
        .s_axil_bresp(cpu_axil_bresp),
        .s_axil_bvalid(cpu_axil_bvalid),
        .s_axil_bready(cpu_axil_bready),
        .s_axil_araddr(cpu_axil_araddr),
        .s_axil_arprot(3'b000),
        .s_axil_arvalid(cpu_axil_arvalid),
        .s_axil_arready(cpu_axil_arready),
        .s_axil_rdata(cpu_axil_rdata),
        .s_axil_rresp(cpu_axil_rresp),
        .s_axil_rvalid(cpu_axil_rvalid),
        .s_axil_rready(cpu_axil_rready),
        .m0_axil_awaddr(m_periph_axil_awaddr),
        .m0_axil_awprot(m_periph_axil_awprot),
        .m0_axil_awvalid(m_periph_axil_awvalid),
        .m0_axil_awready(m_periph_axil_awready),
        .m0_axil_wdata(m_periph_axil_wdata),
        .m0_axil_wstrb(m_periph_axil_wstrb),
        .m0_axil_wvalid(m_periph_axil_wvalid),
        .m0_axil_wready(m_periph_axil_wready),
        .m0_axil_bresp(m_periph_axil_bresp),
        .m0_axil_bvalid(m_periph_axil_bvalid),
        .m0_axil_bready(m_periph_axil_bready),
        .m0_axil_araddr(m_periph_axil_araddr),
        .m0_axil_arprot(m_periph_axil_arprot),
        .m0_axil_arvalid(m_periph_axil_arvalid),
        .m0_axil_arready(m_periph_axil_arready),
        .m0_axil_rdata(m_periph_axil_rdata),
        .m0_axil_rresp(m_periph_axil_rresp),
        .m0_axil_rvalid(m_periph_axil_rvalid),
        .m0_axil_rready(m_periph_axil_rready),
        .m1_axil_awaddr(tpu_axil_awaddr),
        .m1_axil_awprot(tpu_axil_awprot_unused),
        .m1_axil_awvalid(tpu_axil_awvalid),
        .m1_axil_awready(tpu_axil_awready),
        .m1_axil_wdata(tpu_axil_wdata),
        .m1_axil_wstrb(tpu_axil_wstrb),
        .m1_axil_wvalid(tpu_axil_wvalid),
        .m1_axil_wready(tpu_axil_wready),
        .m1_axil_bresp(tpu_axil_bresp),
        .m1_axil_bvalid(tpu_axil_bvalid),
        .m1_axil_bready(tpu_axil_bready),
        .m1_axil_araddr(tpu_axil_araddr),
        .m1_axil_arprot(tpu_axil_arprot_unused),
        .m1_axil_arvalid(tpu_axil_arvalid),
        .m1_axil_arready(tpu_axil_arready),
        .m1_axil_rdata(tpu_axil_rdata),
        .m1_axil_rresp(tpu_axil_rresp),
        .m1_axil_rvalid(tpu_axil_rvalid),
        .m1_axil_rready(tpu_axil_rready)
    );

    tpu_soc tpu_soc_u (
        .s_axil_aclk(clk),
        .s_axil_aresetn(sys_resetn),
        .s_axil_awaddr(tpu_axil_awaddr[11:0]),
        .s_axil_awvalid(tpu_axil_awvalid),
        .s_axil_awready(tpu_axil_awready),
        .s_axil_wdata(tpu_axil_wdata),
        .s_axil_wstrb(tpu_axil_wstrb),
        .s_axil_wvalid(tpu_axil_wvalid),
        .s_axil_wready(tpu_axil_wready),
        .s_axil_bresp(tpu_axil_bresp),
        .s_axil_bvalid(tpu_axil_bvalid),
        .s_axil_bready(tpu_axil_bready),
        .s_axil_araddr(tpu_axil_araddr[11:0]),
        .s_axil_arvalid(tpu_axil_arvalid),
        .s_axil_arready(tpu_axil_arready),
        .s_axil_rdata(tpu_axil_rdata),
        .s_axil_rresp(tpu_axil_rresp),
        .s_axil_rvalid(tpu_axil_rvalid),
        .s_axil_rready(tpu_axil_rready),
        .vpu_data_out_1(tpu_vpu_data_out_1),
        .vpu_data_out_2(tpu_vpu_data_out_2),
        .vpu_valid_out_1(tpu_vpu_valid_out_1),
        .vpu_valid_out_2(tpu_vpu_valid_out_2),
        .sys_data_out_21(tpu_sys_data_out_21),
        .sys_data_out_22(tpu_sys_data_out_22),
        .sys_valid_out_21(tpu_sys_valid_out_21),
        .sys_valid_out_22(tpu_sys_valid_out_22)
    );

endmodule
