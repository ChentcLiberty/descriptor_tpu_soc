`timescale 1ns/1ps
`default_nettype none

import tinytpu_frontend_pkg::*;

module tpu_frontend_local #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        cmd_valid,
    input  logic        cmd_write,
    input  logic [11:0] cmd_addr,
    input  logic [31:0] cmd_wdata,
    output logic        cmd_ready,
    output logic        rsp_valid,
    output logic [31:0] rsp_rdata,
    input  logic        rsp_ready,

    input  logic        tpu_vpu_valid_in,

    input  logic        tile_exec_valid,
    input  logic [5:0]  tile_exec_input_addr,
    input  logic [5:0]  tile_exec_weight_addr,
    input  logic [5:0]  tile_exec_bias_addr,
    input  logic [5:0]  tile_exec_y_addr,
    input  logic [3:0]  tile_exec_pathway,
    output logic        tile_exec_ready,
    output logic        tile_exec_done,

    input  logic        readback_exec_valid,
    input  logic [5:0]  readback_exec_addr,
    output logic        readback_exec_ready,

    output logic        rst_out,
    output logic [15:0] ub_wr_host_data_out_0,
    output logic        ub_wr_host_valid_out_0,
    output logic [15:0] ub_wr_host_data_out_1,
    output logic        ub_wr_host_valid_out_1,
    output logic        ub_wr_ptr_restore_out,
    output logic        sys_switch_out,
    output logic        ub_rd_start_out,
    output logic        ub_rd_transpose_out,
    output logic [1:0]  ub_rd_col_size_out,
    output logic [3:0]  ub_rd_row_size_out,
    output logic [5:0]  ub_rd_addr_out,
    output logic [2:0]  ub_ptr_sel_out,
    output logic [3:0]  vpu_data_pathway_out,
    output logic [15:0] inv_batch_size_times_two_out,
    output logic [15:0] vpu_leak_factor_out,
    output logic [15:0] learning_rate_out
);

    localparam logic [3:0] TILE_LAST_STEP = 4'd9;

    typedef enum logic [1:0] {
        EXEC_IDLE          = 2'b00,
        EXEC_TILE_DISPATCH = 2'b01,
        EXEC_TILE_ADVANCE  = 2'b10,
        EXEC_TILE_WAIT     = 2'b11
    } exec_state_t;

    exec_state_t exec_state;

    logic [15:0] ub_data0_reg;
    logic [15:0] ub_data1_reg;
    logic [15:0] leak_factor_reg;
    logic [15:0] inv_batch_n2_reg;
    logic [15:0] learning_rate_reg;
    logic [3:0]  vpu_pathway_reg;

    logic        ub_push0_pulse;
    logic        ub_push1_pulse;
    logic        ub_wr_ptr_restore_pulse;

    logic [5:0]  tile_input_addr_reg;
    logic [5:0]  tile_weight_addr_reg;
    logic [5:0]  tile_bias_addr_reg;
    logic [5:0]  tile_y_addr_reg;
    logic [3:0]  tile_pathway_reg;
    logic [3:0]  tile_step_idx;

    logic        vpu_valid_prev;
    wire         vpu_drain;
    logic        exec_busy;

    assign rst_out = ~rst_n;
    assign vpu_drain = vpu_valid_prev && !tpu_vpu_valid_in;
    assign exec_busy = (exec_state != EXEC_IDLE);
    assign cmd_ready = (!rsp_valid) && (exec_state == EXEC_IDLE);
    assign tile_exec_ready = (!rsp_valid) && (exec_state == EXEC_IDLE);
    assign readback_exec_ready = (!rsp_valid) && (exec_state == EXEC_IDLE) && !tile_exec_valid && !cmd_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exec_state               <= EXEC_IDLE;
            ub_data0_reg             <= '0;
            ub_data1_reg             <= '0;
            leak_factor_reg          <= '0;
            inv_batch_n2_reg         <= '0;
            learning_rate_reg        <= '0;
            vpu_pathway_reg          <= '0;
            ub_push0_pulse           <= 1'b0;
            ub_push1_pulse           <= 1'b0;
            ub_wr_ptr_restore_pulse  <= 1'b0;
            tile_input_addr_reg      <= '0;
            tile_weight_addr_reg     <= '0;
            tile_bias_addr_reg       <= '0;
            tile_y_addr_reg          <= '0;
            tile_pathway_reg         <= '0;
            tile_step_idx            <= '0;
            tile_exec_done           <= 1'b0;
            vpu_valid_prev           <= 1'b0;
            rsp_valid                <= 1'b0;
            rsp_rdata                <= '0;
            sys_switch_out           <= 1'b0;
            ub_rd_start_out          <= 1'b0;
            ub_rd_transpose_out      <= 1'b0;
            ub_rd_col_size_out       <= '0;
            ub_rd_row_size_out       <= '0;
            ub_rd_addr_out           <= '0;
            ub_ptr_sel_out           <= '0;
        end else begin
            vpu_valid_prev          <= tpu_vpu_valid_in;
            ub_push0_pulse          <= 1'b0;
            ub_push1_pulse          <= 1'b0;
            ub_wr_ptr_restore_pulse <= 1'b0;
            tile_exec_done          <= 1'b0;
            sys_switch_out          <= 1'b0;
            ub_rd_start_out         <= 1'b0;
            ub_rd_transpose_out     <= 1'b0;
            ub_rd_col_size_out      <= '0;
            ub_rd_row_size_out      <= '0;
            ub_rd_addr_out          <= '0;
            ub_ptr_sel_out          <= '0;

            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            if (cmd_valid && cmd_ready) begin
                if (cmd_write) begin
                    case (cmd_addr)
                        TPU_FE_REG_UB_DATA0:  ub_data0_reg      <= cmd_wdata[15:0];
                        TPU_FE_REG_UB_PUSH: begin
                            if (cmd_wdata[0]) ub_push0_pulse <= 1'b1;
                            if (cmd_wdata[1]) ub_push1_pulse <= 1'b1;
                        end
                        TPU_FE_REG_UB_DATA1:  ub_data1_reg      <= cmd_wdata[15:0];
                        TPU_FE_REG_LEAK:      leak_factor_reg   <= cmd_wdata[15:0];
                        TPU_FE_REG_INV_BATCH: inv_batch_n2_reg  <= cmd_wdata[15:0];
                        TPU_FE_REG_LR:        learning_rate_reg <= cmd_wdata[15:0];
                        default: ;
                    endcase
                end else begin
                    rsp_valid <= 1'b1;
                    case (cmd_addr)
                        TPU_FE_REG_CTRL:      rsp_rdata <= 32'h0;
                        TPU_FE_REG_STATUS:    rsp_rdata <= {30'h0, exec_busy, exec_busy};
                        TPU_FE_REG_UB_DATA0:  rsp_rdata <= {16'h0, ub_data0_reg};
                        TPU_FE_REG_UB_DATA1:  rsp_rdata <= {16'h0, ub_data1_reg};
                        TPU_FE_REG_LEAK:      rsp_rdata <= {16'h0, leak_factor_reg};
                        TPU_FE_REG_INV_BATCH: rsp_rdata <= {16'h0, inv_batch_n2_reg};
                        TPU_FE_REG_LR:        rsp_rdata <= {16'h0, learning_rate_reg};
                        default:              rsp_rdata <= 32'hDEAD_BEEF;
                    endcase
                end
            end

            case (exec_state)
                EXEC_IDLE: begin
                    if (tile_exec_valid && tile_exec_ready) begin
                        tile_input_addr_reg     <= tile_exec_input_addr;
                        tile_weight_addr_reg    <= tile_exec_weight_addr;
                        tile_bias_addr_reg      <= tile_exec_bias_addr;
                        tile_y_addr_reg         <= tile_exec_y_addr;
                        tile_pathway_reg        <= tile_exec_pathway;
                        tile_step_idx           <= 4'd0;
                        ub_wr_ptr_restore_pulse <= 1'b1;
                        exec_state              <= EXEC_TILE_DISPATCH;
                    end else if (readback_exec_valid && readback_exec_ready) begin
                        ub_rd_start_out     <= 1'b1;
                        ub_rd_addr_out      <= readback_exec_addr;
                        ub_rd_row_size_out  <= 4'd1;
                        ub_rd_col_size_out  <= 2'd2;
                        ub_rd_transpose_out <= 1'b0;
                        ub_ptr_sel_out      <= TPU_FE_PTR_Y;
                        vpu_pathway_reg     <= 4'b0000;
                    end
                end

                EXEC_TILE_DISPATCH: begin
                    case (tile_step_idx)
                        4'd0: begin
                            ub_rd_start_out     <= 1'b1;
                            ub_rd_addr_out      <= tile_weight_addr_reg;
                            ub_rd_row_size_out  <= 4'd2;
                            ub_rd_col_size_out  <= 2'd2;
                            ub_rd_transpose_out <= 1'b1;
                            ub_ptr_sel_out      <= TPU_FE_PTR_WEIGHT;
                            vpu_pathway_reg     <= 4'b0000;
                            exec_state          <= EXEC_TILE_ADVANCE;
                        end
                        4'd1,
                        4'd2,
                        4'd3,
                        4'd5,
                        4'd6: begin
                            exec_state <= EXEC_TILE_ADVANCE;
                        end
                        4'd4: begin
                            sys_switch_out <= 1'b1;
                            exec_state     <= EXEC_TILE_ADVANCE;
                        end
                        4'd7: begin
                            if (tile_pathway_reg[1]) begin
                                ub_rd_start_out     <= 1'b1;
                                ub_rd_addr_out      <= tile_y_addr_reg;
                                ub_rd_row_size_out  <= 4'd1;
                                ub_rd_col_size_out  <= 2'd2;
                                ub_rd_transpose_out <= 1'b0;
                                ub_ptr_sel_out      <= TPU_FE_PTR_Y;
                                vpu_pathway_reg     <= 4'b0000;
                                exec_state          <= EXEC_TILE_ADVANCE;
                            end else begin
                                ub_rd_start_out     <= 1'b1;
                                ub_rd_addr_out      <= tile_bias_addr_reg;
                                ub_rd_row_size_out  <= 4'd1;
                                ub_rd_col_size_out  <= 2'd2;
                                ub_rd_transpose_out <= 1'b0;
                                ub_ptr_sel_out      <= TPU_FE_PTR_BIAS;
                                vpu_pathway_reg     <= tile_pathway_reg;
                                exec_state          <= EXEC_TILE_ADVANCE;
                            end
                        end
                        4'd8: begin
                            if (tile_pathway_reg[1]) begin
                                ub_rd_start_out     <= 1'b1;
                                ub_rd_addr_out      <= tile_bias_addr_reg;
                                ub_rd_row_size_out  <= 4'd1;
                                ub_rd_col_size_out  <= 2'd2;
                                ub_rd_transpose_out <= 1'b0;
                                ub_ptr_sel_out      <= TPU_FE_PTR_BIAS;
                                vpu_pathway_reg     <= tile_pathway_reg;
                                exec_state          <= EXEC_TILE_ADVANCE;
                            end else begin
                                ub_rd_start_out     <= 1'b1;
                                ub_rd_addr_out      <= tile_input_addr_reg;
                                ub_rd_row_size_out  <= 4'd1;
                                ub_rd_col_size_out  <= 2'd2;
                                ub_rd_transpose_out <= 1'b0;
                                ub_ptr_sel_out      <= TPU_FE_PTR_INPUT;
                                vpu_pathway_reg     <= tile_pathway_reg;
                                exec_state          <= EXEC_TILE_WAIT;
                            end
                        end
                        4'd9: begin
                            ub_rd_start_out     <= 1'b1;
                            ub_rd_addr_out      <= tile_input_addr_reg;
                            ub_rd_row_size_out  <= 4'd1;
                            ub_rd_col_size_out  <= 2'd2;
                            ub_rd_transpose_out <= 1'b0;
                            ub_ptr_sel_out      <= TPU_FE_PTR_INPUT;
                            vpu_pathway_reg     <= tile_pathway_reg;
                            exec_state          <= EXEC_TILE_WAIT;
                        end
                        default: begin
                            tile_exec_done <= 1'b1;
                            exec_state     <= EXEC_IDLE;
                        end
                    endcase
                end

                EXEC_TILE_ADVANCE: begin
                    if (tile_step_idx >= TILE_LAST_STEP) begin
                        tile_exec_done <= 1'b1;
                        exec_state     <= EXEC_IDLE;
                    end else begin
                        tile_step_idx <= tile_step_idx + 4'd1;
                        exec_state    <= EXEC_TILE_DISPATCH;
                    end
                end

                EXEC_TILE_WAIT: begin
                    if (vpu_drain) begin
                        tile_exec_done <= 1'b1;
                        exec_state     <= EXEC_IDLE;
                    end
                end

                default: exec_state <= EXEC_IDLE;
            endcase
        end
    end

    assign inv_batch_size_times_two_out = inv_batch_n2_reg;
    assign vpu_leak_factor_out          = leak_factor_reg;
    assign learning_rate_out            = learning_rate_reg;
    assign vpu_data_pathway_out         = vpu_pathway_reg;
    assign ub_wr_ptr_restore_out        = ub_wr_ptr_restore_pulse;
    assign ub_wr_host_valid_out_0       = ub_push0_pulse;
    assign ub_wr_host_valid_out_1       = ub_push1_pulse;
    assign ub_wr_host_data_out_0        = ub_data0_reg;
    assign ub_wr_host_data_out_1        = ub_data1_reg;

endmodule

`default_nettype wire
