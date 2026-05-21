`timescale 1ns/1ps
`default_nettype none

module tpu_soc_top (
    input  logic        s_axil_aclk,
    input  logic        s_axil_aresetn,
    input  logic [11:0] s_axil_awaddr,
    input  logic        s_axil_awvalid,
    output logic        s_axil_awready,
    input  logic [31:0] s_axil_wdata,
    input  logic [3:0]  s_axil_wstrb,
    input  logic        s_axil_wvalid,
    output logic        s_axil_wready,
    output logic [1:0]  s_axil_bresp,
    output logic        s_axil_bvalid,
    input  logic        s_axil_bready,
    input  logic [11:0] s_axil_araddr,
    input  logic        s_axil_arvalid,
    output logic        s_axil_arready,
    output logic [31:0] s_axil_rdata,
    output logic [1:0]  s_axil_rresp,
    output logic        s_axil_rvalid,
    input  logic        s_axil_rready,
    output logic [15:0] vpu_data_out_1,
    output logic [15:0] vpu_data_out_2,
    output logic        vpu_valid_out_1,
    output logic        vpu_valid_out_2,
    output logic [15:0] sys_data_out_21,
    output logic [15:0] sys_data_out_22,
    output logic        sys_valid_out_21,
    output logic        sys_valid_out_22
);
    tpu_soc #(.SYSTOLIC_ARRAY_WIDTH(2)) dut (.*);
endmodule

module dump;
    initial begin
        $dumpfile("tpu_soc.vcd");
        $dumpvars(0, tpu_soc_top);
    end
endmodule
