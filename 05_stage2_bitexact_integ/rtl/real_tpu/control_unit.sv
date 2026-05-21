`timescale 1ns/1ps
`default_nettype none

// TinyTPU Control Unit - 32-bit opcode instruction decoder
//
// Instruction format (32-bit):
//   opcode=3'b000  NOP      no operation
//   opcode=3'b001  SWITCH   sys_switch_in=1
//   opcode=3'b010  UB_RD    ub_rd_start_in=1, fields below
//     [2:0]   opcode
//     [8:3]   ub_rd_addr_in[5:0]
//     [12:9]  ub_rd_row_size[3:0]
//     [14:13] ub_rd_col_size[1:0]
//     [15]    ub_rd_transpose
//     [18:16] ub_ptr_sel[2:0]  (0=input,1=weight,2=bias,3=Y,4=H,5=grad_bias,6=grad_weight)
//     [22:19] vpu_data_pathway[3:0]
//     [31:23] reserved
//   opcode=3'b011  UB_WR_HOST  drive ub_wr_host_valid for one cycle
//     [2:0]   opcode
//     [18:3]  ub_wr_host_data[15:0]
//     [31:19] reserved

module control_unit (
    input  logic [31:0] instruction,

    output logic        sys_switch_in,
    output logic        ub_rd_start_in,
    output logic        ub_rd_transpose,
    output logic        ub_wr_host_valid_in_1,
    output logic        ub_wr_host_valid_in_2,
    output logic [1:0]  ub_rd_col_size,
    output logic [3:0]  ub_rd_row_size,
    output logic [5:0]  ub_rd_addr_in,
    output logic [2:0]  ub_ptr_sel,
    output logic [15:0] ub_wr_host_data_in_1,
    output logic [15:0] ub_wr_host_data_in_2,
    output logic [3:0]  vpu_data_pathway,
    input  logic [15:0] inv_batch_size_times_two_in,
    input  logic [15:0] vpu_leak_factor_in
);

    logic [2:0] opcode;
    assign opcode = instruction[2:0];

    // Break out fields as intermediate assigns to avoid Icarus always_comb part-select limitation
    logic [5:0]  f_addr;    assign f_addr     = instruction[8:3];
    logic [3:0]  f_row;     assign f_row      = instruction[12:9];
    logic [1:0]  f_col;     assign f_col      = instruction[14:13];
    logic        f_trans;   assign f_trans    = instruction[15];
    logic [2:0]  f_ptr;     assign f_ptr      = instruction[18:16];
    logic [3:0]  f_vpu;     assign f_vpu      = instruction[22:19];
    logic [15:0] f_wrdata;  assign f_wrdata   = instruction[18:3];

    always @(*) begin
        // defaults
        sys_switch_in              = 1'b0;
        ub_rd_start_in             = 1'b0;
        ub_rd_transpose            = 1'b0;
        ub_wr_host_valid_in_1      = 1'b0;
        ub_wr_host_valid_in_2      = 1'b0;
        ub_rd_col_size             = 2'b0;
        ub_rd_row_size             = 4'b0;
        ub_rd_addr_in              = 6'b0;
        ub_ptr_sel                 = 3'b0;
        ub_wr_host_data_in_1       = 16'b0;
        ub_wr_host_data_in_2       = 16'b0;
        vpu_data_pathway           = 4'b0;
        case (opcode)
            3'b000: ; // NOP - all defaults

            3'b001: begin // SWITCH
                sys_switch_in = 1'b1;
            end

            3'b010: begin // UB_RD
                ub_rd_start_in   = 1'b1;
                ub_rd_addr_in    = f_addr;
                ub_rd_row_size   = f_row;
                ub_rd_col_size   = f_col;
                ub_rd_transpose  = f_trans;
                ub_ptr_sel       = f_ptr;
                vpu_data_pathway = f_vpu;
            end

            3'b011: begin // UB_WR_HOST
                ub_wr_host_valid_in_1 = 1'b1;
                ub_wr_host_valid_in_2 = 1'b1;
                ub_wr_host_data_in_1  = f_wrdata;
                ub_wr_host_data_in_2  = f_wrdata;
            end

            default: ; // reserved - all defaults
        endcase
    end

endmodule
