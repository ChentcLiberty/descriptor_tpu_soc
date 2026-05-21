`timescale 1ns/1ps
`default_nettype none

// TinyTPU SoC Top
// Wraps tpu_frontend_axil + tpu into a single AXI-Lite controlled accelerator.
//
// CPU controls TPU via AXI-Lite:
//   - Load data into UB via UB_DATA / UB_PUSH registers
//   - Stage an 88-bit instruction via INSTR_W0/W1/W2
//   - Dispatch it with CTRL.step=1
//   - Wait enough cycles, then dispatch next instruction

module tpu_soc #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2
)(
    // AXI-Lite slave interface (from PS / host)
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

    // TPU output ports (observable by host or downstream logic)
    output logic [15:0] vpu_data_out_1,
    output logic [15:0] vpu_data_out_2,
    output logic        vpu_valid_out_1,
    output logic        vpu_valid_out_2,

    output logic [15:0] sys_data_out_21,
    output logic [15:0] sys_data_out_22,
    output logic        sys_valid_out_21,
    output logic        sys_valid_out_22
);

    // Internal wires between frontend and TPU core
    logic        clk, rst;

    logic [15:0] ub_wr_host_data_0, ub_wr_host_data_1;
    logic        ub_wr_host_valid_0, ub_wr_host_valid_1;
    // Bridge scalars to unpacked arrays for tpu.sv ports
    logic [15:0] ub_wr_host_data [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic        ub_wr_host_valid [0:SYSTOLIC_ARRAY_WIDTH-1];
    assign ub_wr_host_data[0]  = ub_wr_host_data_0;
    assign ub_wr_host_data[1]  = ub_wr_host_data_1;
    assign ub_wr_host_valid[0] = ub_wr_host_valid_0;
    assign ub_wr_host_valid[1] = ub_wr_host_valid_1;

    logic        sys_switch;
    logic        ub_rd_start;
    logic        ub_rd_transpose;
    logic [1:0]  ub_rd_col_size;
    logic [3:0]  ub_rd_row_size;
    logic [5:0]  ub_rd_addr;
    logic [2:0]  ub_ptr_sel;
    logic [3:0]  vpu_data_pathway;
    logic [15:0] inv_batch_size_times_two;
    logic [15:0] vpu_leak_factor;
    logic [15:0] learning_rate;

    // UB read outputs (not exposed at SoC top in this version)
    logic [15:0] ub_rd_input_data_out_0, ub_rd_input_data_out_1;
    logic        ub_rd_input_valid_out_0, ub_rd_input_valid_out_1;
    logic [15:0] ub_rd_weight_data_out_0, ub_rd_weight_data_out_1;
    logic        ub_rd_weight_valid_out_0, ub_rd_weight_valid_out_1;

    // -------------------------------------------------------------------------
    // Frontend
    // -------------------------------------------------------------------------
    tpu_frontend_axil #(
        .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
    ) frontend (
        .s_axil_aclk    (s_axil_aclk),
        .s_axil_aresetn (s_axil_aresetn),

        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),

        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),

        .s_axil_bresp   (s_axil_bresp),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),

        .s_axil_araddr  (s_axil_araddr),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),

        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),

        .tpu_vpu_valid_in           (vpu_valid_out_1 | vpu_valid_out_2),

        .clk_out                    (clk),
        .rst_out                    (rst),

        .ub_wr_host_data_out_0       (ub_wr_host_data_0),
        .ub_wr_host_valid_out_0      (ub_wr_host_valid_0),
        .ub_wr_host_data_out_1       (ub_wr_host_data_1),
        .ub_wr_host_valid_out_1      (ub_wr_host_valid_1),

        .sys_switch_out              (sys_switch),
        .ub_rd_start_out             (ub_rd_start),
        .ub_rd_transpose_out         (ub_rd_transpose),
        .ub_rd_col_size_out          (ub_rd_col_size),
        .ub_rd_row_size_out          (ub_rd_row_size),
        .ub_rd_addr_out              (ub_rd_addr),
        .ub_ptr_sel_out              (ub_ptr_sel),
        .vpu_data_pathway_out        (vpu_data_pathway),
        .inv_batch_size_times_two_out(inv_batch_size_times_two),
        .vpu_leak_factor_out         (vpu_leak_factor),
        .learning_rate_out           (learning_rate)
    );

    // -------------------------------------------------------------------------
    // TPU core
    // Note: tpu.sv ports use wider widths for ub_rd_* than control_unit output.
    // We zero-extend the narrower frontend signals to match.
    // -------------------------------------------------------------------------
    tpu #(
        .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
    ) tpu_inst (
        .clk                        (clk),
        .rst                        (rst),

        .ub_wr_host_data_in         (ub_wr_host_data),
        .ub_wr_host_valid_in        (ub_wr_host_valid),

        .ub_rd_start_in             (ub_rd_start),
        .ub_rd_transpose            (ub_rd_transpose),
        .ub_ptr_select              ({6'h0, ub_ptr_sel}),       // 9-bit, extend from 3-bit
        .ub_rd_addr_in              ({10'h0, ub_rd_addr}),      // 16-bit, extend from 6-bit
        .ub_rd_row_size             ({12'h0, ub_rd_row_size}),  // 16-bit, extend from 4-bit
        .ub_rd_col_size             ({14'h0, ub_rd_col_size}),  // 16-bit, extend from 2-bit

        .learning_rate_in           (learning_rate),

        .vpu_data_pathway           (vpu_data_pathway),
        .sys_switch_in              (sys_switch),
        .vpu_leak_factor_in         (vpu_leak_factor),
        .inv_batch_size_times_two_in(inv_batch_size_times_two),

        .vpu_data_out_1             (vpu_data_out_1),
        .vpu_data_out_2             (vpu_data_out_2),
        .vpu_valid_out_1            (vpu_valid_out_1),
        .vpu_valid_out_2            (vpu_valid_out_2),

        .sys_data_out_21            (sys_data_out_21),
        .sys_data_out_22            (sys_data_out_22),
        .sys_valid_out_21           (sys_valid_out_21),
        .sys_valid_out_22           (sys_valid_out_22),

        .ub_rd_input_data_out_0     (ub_rd_input_data_out_0),
        .ub_rd_input_data_out_1     (ub_rd_input_data_out_1),
        .ub_rd_input_valid_out_0    (ub_rd_input_valid_out_0),
        .ub_rd_input_valid_out_1    (ub_rd_input_valid_out_1),
        .ub_rd_weight_data_out_0    (ub_rd_weight_data_out_0),
        .ub_rd_weight_data_out_1    (ub_rd_weight_data_out_1),
        .ub_rd_weight_valid_out_0   (ub_rd_weight_valid_out_0),
        .ub_rd_weight_valid_out_1   (ub_rd_weight_valid_out_1)
    );

endmodule
