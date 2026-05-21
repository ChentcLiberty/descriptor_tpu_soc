`timescale 1ns/1ps
`default_nettype none

module cpu_tpu_axil_splitter #(
    parameter [31:0] TPU_BASE_ADDR = 32'h4000_4000,
    parameter integer TPU_ADDR_RANGE = 4096
) (
    input  logic        aclk,
    input  logic        aresetn,

    input  logic [31:0] s_axil_awaddr,
    input  logic [2:0]  s_axil_awprot,
    input  logic        s_axil_awvalid,
    output logic        s_axil_awready,

    input  logic [31:0] s_axil_wdata,
    input  logic [3:0]  s_axil_wstrb,
    input  logic        s_axil_wvalid,
    output logic        s_axil_wready,

    output logic [1:0]  s_axil_bresp,
    output logic        s_axil_bvalid,
    input  logic        s_axil_bready,

    input  logic [31:0] s_axil_araddr,
    input  logic [2:0]  s_axil_arprot,
    input  logic        s_axil_arvalid,
    output logic        s_axil_arready,

    output logic [31:0] s_axil_rdata,
    output logic [1:0]  s_axil_rresp,
    output logic        s_axil_rvalid,
    input  logic        s_axil_rready,

    output logic [31:0] m0_axil_awaddr,
    output logic [2:0]  m0_axil_awprot,
    output logic        m0_axil_awvalid,
    input  logic        m0_axil_awready,

    output logic [31:0] m0_axil_wdata,
    output logic [3:0]  m0_axil_wstrb,
    output logic        m0_axil_wvalid,
    input  logic        m0_axil_wready,

    input  logic [1:0]  m0_axil_bresp,
    input  logic        m0_axil_bvalid,
    output logic        m0_axil_bready,

    output logic [31:0] m0_axil_araddr,
    output logic [2:0]  m0_axil_arprot,
    output logic        m0_axil_arvalid,
    input  logic        m0_axil_arready,

    input  logic [31:0] m0_axil_rdata,
    input  logic [1:0]  m0_axil_rresp,
    input  logic        m0_axil_rvalid,
    output logic        m0_axil_rready,

    output logic [31:0] m1_axil_awaddr,
    output logic [2:0]  m1_axil_awprot,
    output logic        m1_axil_awvalid,
    input  logic        m1_axil_awready,

    output logic [31:0] m1_axil_wdata,
    output logic [3:0]  m1_axil_wstrb,
    output logic        m1_axil_wvalid,
    input  logic        m1_axil_wready,

    input  logic [1:0]  m1_axil_bresp,
    input  logic        m1_axil_bvalid,
    output logic        m1_axil_bready,

    output logic [31:0] m1_axil_araddr,
    output logic [2:0]  m1_axil_arprot,
    output logic        m1_axil_arvalid,
    input  logic        m1_axil_arready,

    input  logic [31:0] m1_axil_rdata,
    input  logic [1:0]  m1_axil_rresp,
    input  logic        m1_axil_rvalid,
    output logic        m1_axil_rready
);

    logic write_sel_tpu_reg;
    logic read_sel_tpu_reg;
    logic write_busy_reg;
    logic read_busy_reg;

    logic aw_sel_tpu;
    logic ar_sel_tpu;

    assign aw_sel_tpu =
        (s_axil_awaddr >= TPU_BASE_ADDR) &&
        (s_axil_awaddr < (TPU_BASE_ADDR + TPU_ADDR_RANGE));
    assign ar_sel_tpu =
        (s_axil_araddr >= TPU_BASE_ADDR) &&
        (s_axil_araddr < (TPU_BASE_ADDR + TPU_ADDR_RANGE));

    assign m0_axil_awaddr  = s_axil_awaddr;
    assign m0_axil_awprot  = s_axil_awprot;
    assign m0_axil_awvalid = s_axil_awvalid && !aw_sel_tpu && !write_busy_reg;

    assign m1_axil_awaddr  = s_axil_awaddr;
    assign m1_axil_awprot  = s_axil_awprot;
    assign m1_axil_awvalid = s_axil_awvalid && aw_sel_tpu && !write_busy_reg;

    assign s_axil_awready =
        !write_busy_reg &&
        (aw_sel_tpu ? m1_axil_awready : m0_axil_awready);

    assign m0_axil_wdata  = s_axil_wdata;
    assign m0_axil_wstrb  = s_axil_wstrb;
    assign m0_axil_wvalid = s_axil_wvalid && write_busy_reg && !write_sel_tpu_reg;

    assign m1_axil_wdata  = s_axil_wdata;
    assign m1_axil_wstrb  = s_axil_wstrb;
    assign m1_axil_wvalid = s_axil_wvalid && write_busy_reg && write_sel_tpu_reg;

    assign s_axil_wready =
        write_busy_reg &&
        (write_sel_tpu_reg ? m1_axil_wready : m0_axil_wready);

    assign m0_axil_bready = s_axil_bready && !write_sel_tpu_reg;
    assign m1_axil_bready = s_axil_bready && write_sel_tpu_reg;

    assign s_axil_bresp  = write_sel_tpu_reg ? m1_axil_bresp : m0_axil_bresp;
    assign s_axil_bvalid = write_sel_tpu_reg ? m1_axil_bvalid : m0_axil_bvalid;

    assign m0_axil_araddr  = s_axil_araddr;
    assign m0_axil_arprot  = s_axil_arprot;
    assign m0_axil_arvalid = s_axil_arvalid && !ar_sel_tpu && !read_busy_reg;

    assign m1_axil_araddr  = s_axil_araddr;
    assign m1_axil_arprot  = s_axil_arprot;
    assign m1_axil_arvalid = s_axil_arvalid && ar_sel_tpu && !read_busy_reg;

    assign s_axil_arready =
        !read_busy_reg &&
        (ar_sel_tpu ? m1_axil_arready : m0_axil_arready);

    assign m0_axil_rready = s_axil_rready && !read_sel_tpu_reg;
    assign m1_axil_rready = s_axil_rready && read_sel_tpu_reg;

    assign s_axil_rdata  = read_sel_tpu_reg ? m1_axil_rdata : m0_axil_rdata;
    assign s_axil_rresp  = read_sel_tpu_reg ? m1_axil_rresp : m0_axil_rresp;
    assign s_axil_rvalid = read_sel_tpu_reg ? m1_axil_rvalid : m0_axil_rvalid;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            write_sel_tpu_reg <= 1'b0;
            read_sel_tpu_reg  <= 1'b0;
            write_busy_reg    <= 1'b0;
            read_busy_reg     <= 1'b0;
        end else begin
            if (!write_busy_reg && s_axil_awvalid && s_axil_awready) begin
                write_sel_tpu_reg <= aw_sel_tpu;
                write_busy_reg    <= 1'b1;
            end else if (write_busy_reg && s_axil_bvalid && s_axil_bready) begin
                write_busy_reg <= 1'b0;
            end

            if (!read_busy_reg && s_axil_arvalid && s_axil_arready) begin
                read_sel_tpu_reg <= ar_sel_tpu;
                read_busy_reg    <= 1'b1;
            end else if (read_busy_reg && s_axil_rvalid && s_axil_rready) begin
                read_busy_reg <= 1'b0;
            end
        end
    end

endmodule
