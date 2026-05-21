`timescale 1ns/1ps
`default_nettype none

import tinytpu_frontend_pkg::*;

module tb_frontend_tpu_core_modes;
    localparam int CLK_PERIOD = 10;
    localparam logic [5:0] INPUT_ADDR  = 6'd0;
    localparam logic [5:0] WEIGHT_ADDR = 6'd2;
    localparam logic [5:0] BIAS_ADDR   = 6'd6;
    localparam logic [5:0] Y_ADDR      = 6'd8;

    typedef enum logic [1:0] {
        PAT_NONE        = 2'd0,
        PAT_FORWARD1100 = 2'd1,
        PAT_TRANS1111   = 2'd2
    } pattern_t;

    logic clk;
    logic rst_n;

    logic        cmd_valid;
    logic        cmd_write;
    logic [11:0] cmd_addr;
    logic [31:0] cmd_wdata;
    logic        cmd_ready;
    logic        rsp_valid;
    logic [31:0] rsp_rdata;
    logic        rsp_ready;

    logic        tile_exec_valid;
    logic [5:0]  tile_exec_input_addr;
    logic [5:0]  tile_exec_weight_addr;
    logic [5:0]  tile_exec_bias_addr;
    logic [5:0]  tile_exec_y_addr;
    logic [3:0]  tile_exec_pathway;
    logic        tile_exec_ready;
    logic        tile_exec_done;

    logic        readback_exec_valid;
    logic [5:0]  readback_exec_addr;
    logic        readback_exec_ready;

    logic        rst_out;
    logic [15:0] ub_wr_host_data_out_0;
    logic        ub_wr_host_valid_out_0;
    logic [15:0] ub_wr_host_data_out_1;
    logic        ub_wr_host_valid_out_1;
    logic        ub_wr_ptr_restore_out;
    logic        sys_switch_out;
    logic        ub_rd_start_out;
    logic        ub_rd_transpose_out;
    logic [1:0]  ub_rd_col_size_out;
    logic [3:0]  ub_rd_row_size_out;
    logic [5:0]  ub_rd_addr_out;
    logic [2:0]  ub_ptr_sel_out;
    logic [3:0]  vpu_data_pathway_out;
    logic [15:0] inv_batch_size_times_two_out;
    logic [15:0] vpu_leak_factor_out;
    logic [15:0] learning_rate_out;

    logic [15:0] ub_wr_host_data_in [0:1];
    logic        ub_wr_host_valid_in[0:1];

    logic signed [15:0] vpu_data_out_1;
    logic signed [15:0] vpu_data_out_2;
    logic               vpu_valid_out_1;
    logic               vpu_valid_out_2;
    logic signed [15:0] sys_data_out_21;
    logic signed [15:0] sys_data_out_22;
    logic               sys_valid_out_21;
    logic               sys_valid_out_22;
    logic signed [15:0] ub_rd_input_data_out_0;
    logic signed [15:0] ub_rd_input_data_out_1;
    logic               ub_rd_input_valid_out_0;
    logic               ub_rd_input_valid_out_1;
    logic signed [15:0] ub_rd_weight_data_out_0;
    logic signed [15:0] ub_rd_weight_data_out_1;
    logic               ub_rd_weight_valid_out_0;
    logic               ub_rd_weight_valid_out_1;
    logic signed [15:0] ub_rd_Y_data_out_0;
    logic signed [15:0] ub_rd_Y_data_out_1;
    logic               ub_rd_Y_valid_out_0;
    logic               ub_rd_Y_valid_out_1;

    integer err_count;
    integer timeout_count;

    pattern_t pattern_mode;
    logic pattern_reset;
    integer seq_idx;
    logic seq_error;
    integer expected_seq_len;

    logic seen_weight_valid;
    logic seen_input_valid;
    logic seen_sys_valid;
    logic seen_bias_valid;
    logic seen_lr_valid;
    logic seen_loss_valid;
    logic seen_lrd_valid;
    logic seen_y_valid;
    logic saw_sys_lane0;
    logic saw_sys_lane1;
    logic saw_vpu_lane0;
    logic saw_vpu_lane1;

    logic signed [15:0] last_sys_lane0;
    logic signed [15:0] last_sys_lane1;
    logic signed [15:0] last_vpu_lane0;
    logic signed [15:0] last_vpu_lane1;

    assign ub_wr_host_data_in[0]  = ub_wr_host_data_out_0;
    assign ub_wr_host_data_in[1]  = ub_wr_host_data_out_1;
    assign ub_wr_host_valid_in[0] = ub_wr_host_valid_out_0;
    assign ub_wr_host_valid_in[1] = ub_wr_host_valid_out_1;

    tpu_frontend_local dut_frontend (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_write(cmd_write),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_ready(cmd_ready),
        .rsp_valid(rsp_valid),
        .rsp_rdata(rsp_rdata),
        .rsp_ready(rsp_ready),
        .tpu_vpu_valid_in(vpu_valid_out_1 | vpu_valid_out_2),
        .tile_exec_valid(tile_exec_valid),
        .tile_exec_input_addr(tile_exec_input_addr),
        .tile_exec_weight_addr(tile_exec_weight_addr),
        .tile_exec_bias_addr(tile_exec_bias_addr),
        .tile_exec_y_addr(tile_exec_y_addr),
        .tile_exec_pathway(tile_exec_pathway),
        .tile_exec_ready(tile_exec_ready),
        .tile_exec_done(tile_exec_done),
        .readback_exec_valid(readback_exec_valid),
        .readback_exec_addr(readback_exec_addr),
        .readback_exec_ready(readback_exec_ready),
        .rst_out(rst_out),
        .ub_wr_host_data_out_0(ub_wr_host_data_out_0),
        .ub_wr_host_valid_out_0(ub_wr_host_valid_out_0),
        .ub_wr_host_data_out_1(ub_wr_host_data_out_1),
        .ub_wr_host_valid_out_1(ub_wr_host_valid_out_1),
        .ub_wr_ptr_restore_out(ub_wr_ptr_restore_out),
        .sys_switch_out(sys_switch_out),
        .ub_rd_start_out(ub_rd_start_out),
        .ub_rd_transpose_out(ub_rd_transpose_out),
        .ub_rd_col_size_out(ub_rd_col_size_out),
        .ub_rd_row_size_out(ub_rd_row_size_out),
        .ub_rd_addr_out(ub_rd_addr_out),
        .ub_ptr_sel_out(ub_ptr_sel_out),
        .vpu_data_pathway_out(vpu_data_pathway_out),
        .inv_batch_size_times_two_out(inv_batch_size_times_two_out),
        .vpu_leak_factor_out(vpu_leak_factor_out),
        .learning_rate_out(learning_rate_out)
    );

    tpu dut_tpu (
        .clk(clk),
        .rst(rst_out),
        .ub_wr_host_data_in(ub_wr_host_data_in),
        .ub_wr_host_valid_in(ub_wr_host_valid_in),
        .ub_wr_ptr_restore_in(ub_wr_ptr_restore_out),
        .ub_rd_start_in(ub_rd_start_out),
        .ub_rd_transpose(ub_rd_transpose_out),
        .ub_ptr_select({6'h0, ub_ptr_sel_out}),
        .ub_rd_addr_in({10'h0, ub_rd_addr_out}),
        .ub_rd_row_size({12'h0, ub_rd_row_size_out}),
        .ub_rd_col_size({14'h0, ub_rd_col_size_out}),
        .learning_rate_in(learning_rate_out),
        .vpu_data_pathway(vpu_data_pathway_out),
        .sys_switch_in(sys_switch_out),
        .vpu_leak_factor_in(vpu_leak_factor_out),
        .inv_batch_size_times_two_in(inv_batch_size_times_two_out),
        .vpu_data_out_1(vpu_data_out_1),
        .vpu_data_out_2(vpu_data_out_2),
        .vpu_valid_out_1(vpu_valid_out_1),
        .vpu_valid_out_2(vpu_valid_out_2),
        .sys_data_out_21(sys_data_out_21),
        .sys_data_out_22(sys_data_out_22),
        .sys_valid_out_21(sys_valid_out_21),
        .sys_valid_out_22(sys_valid_out_22),
        .ub_rd_input_data_out_0(ub_rd_input_data_out_0),
        .ub_rd_input_data_out_1(ub_rd_input_data_out_1),
        .ub_rd_input_valid_out_0(ub_rd_input_valid_out_0),
        .ub_rd_input_valid_out_1(ub_rd_input_valid_out_1),
        .ub_rd_weight_data_out_0(ub_rd_weight_data_out_0),
        .ub_rd_weight_data_out_1(ub_rd_weight_data_out_1),
        .ub_rd_weight_valid_out_0(ub_rd_weight_valid_out_0),
        .ub_rd_weight_valid_out_1(ub_rd_weight_valid_out_1),
        .ub_rd_Y_data_out_0(ub_rd_Y_data_out_0),
        .ub_rd_Y_data_out_1(ub_rd_Y_data_out_1),
        .ub_rd_Y_valid_out_0(ub_rd_Y_valid_out_0),
        .ub_rd_Y_valid_out_1(ub_rd_Y_valid_out_1)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seq_idx           <= 0;
            seq_error         <= 1'b0;
            seen_weight_valid <= 1'b0;
            seen_input_valid  <= 1'b0;
            seen_sys_valid    <= 1'b0;
            seen_bias_valid   <= 1'b0;
            seen_lr_valid     <= 1'b0;
            seen_loss_valid   <= 1'b0;
            seen_lrd_valid    <= 1'b0;
            seen_y_valid      <= 1'b0;
            saw_sys_lane0     <= 1'b0;
            saw_sys_lane1     <= 1'b0;
            saw_vpu_lane0     <= 1'b0;
            saw_vpu_lane1     <= 1'b0;
            last_sys_lane0    <= '0;
            last_sys_lane1    <= '0;
            last_vpu_lane0    <= '0;
            last_vpu_lane1    <= '0;
        end else if (pattern_reset) begin
            seq_idx           <= 0;
            seq_error         <= 1'b0;
            seen_weight_valid <= 1'b0;
            seen_input_valid  <= 1'b0;
            seen_sys_valid    <= 1'b0;
            seen_bias_valid   <= 1'b0;
            seen_lr_valid     <= 1'b0;
            seen_loss_valid   <= 1'b0;
            seen_lrd_valid    <= 1'b0;
            seen_y_valid      <= 1'b0;
            saw_sys_lane0     <= 1'b0;
            saw_sys_lane1     <= 1'b0;
            saw_vpu_lane0     <= 1'b0;
            saw_vpu_lane1     <= 1'b0;
            last_sys_lane0    <= '0;
            last_sys_lane1    <= '0;
            last_vpu_lane0    <= '0;
            last_vpu_lane1    <= '0;
        end else begin
            if (ub_rd_weight_valid_out_0 || ub_rd_weight_valid_out_1)
                seen_weight_valid <= 1'b1;
            if (ub_rd_input_valid_out_0 || ub_rd_input_valid_out_1)
                seen_input_valid <= 1'b1;
            if (sys_valid_out_21) begin
                seen_sys_valid <= 1'b1;
                saw_sys_lane0  <= 1'b1;
                last_sys_lane0 <= sys_data_out_21;
            end
            if (sys_valid_out_22) begin
                seen_sys_valid <= 1'b1;
                saw_sys_lane1  <= 1'b1;
                last_sys_lane1 <= sys_data_out_22;
            end
            if (dut_tpu.vpu_inst.bias_valid_1_out || dut_tpu.vpu_inst.bias_valid_2_out)
                seen_bias_valid <= 1'b1;
            if (dut_tpu.vpu_inst.lr_valid_1_out || dut_tpu.vpu_inst.lr_valid_2_out)
                seen_lr_valid <= 1'b1;
            if (dut_tpu.vpu_inst.loss_valid_1_out || dut_tpu.vpu_inst.loss_valid_2_out)
                seen_loss_valid <= 1'b1;
            if (dut_tpu.vpu_inst.lr_d_valid_1_out || dut_tpu.vpu_inst.lr_d_valid_2_out)
                seen_lrd_valid <= 1'b1;
            if (ub_rd_Y_valid_out_0 || ub_rd_Y_valid_out_1)
                seen_y_valid <= 1'b1;
            if (vpu_valid_out_1) begin
                saw_vpu_lane0  <= 1'b1;
                last_vpu_lane0 <= vpu_data_out_1;
            end
            if (vpu_valid_out_2) begin
                saw_vpu_lane1  <= 1'b1;
                last_vpu_lane1 <= vpu_data_out_2;
            end

            if (sys_switch_out || ub_rd_start_out) begin
                case (pattern_mode)
                    PAT_FORWARD1100: begin
                        case (seq_idx)
                            0: if (!(ub_rd_start_out && ub_ptr_sel_out == TPU_FE_PTR_WEIGHT && dut_frontend.tile_step_idx == 4'd0)) seq_error <= 1'b1;
                            1: if (!(sys_switch_out && dut_frontend.tile_step_idx == 4'd4)) seq_error <= 1'b1;
                            2: if (!(ub_rd_start_out && ub_ptr_sel_out == TPU_FE_PTR_BIAS && dut_frontend.tile_step_idx == 4'd7)) seq_error <= 1'b1;
                            3: if (!(ub_rd_start_out && ub_ptr_sel_out == TPU_FE_PTR_INPUT && dut_frontend.tile_step_idx == 4'd8)) seq_error <= 1'b1;
                            default: seq_error <= 1'b1;
                        endcase
                    end
                    PAT_TRANS1111: begin
                        case (seq_idx)
                            0: if (!(ub_rd_start_out && ub_ptr_sel_out == TPU_FE_PTR_WEIGHT && dut_frontend.tile_step_idx == 4'd0)) seq_error <= 1'b1;
                            1: if (!(sys_switch_out && dut_frontend.tile_step_idx == 4'd4)) seq_error <= 1'b1;
                            2: if (!(ub_rd_start_out && ub_ptr_sel_out == TPU_FE_PTR_Y && dut_frontend.tile_step_idx == 4'd7)) seq_error <= 1'b1;
                            3: if (!(ub_rd_start_out && ub_ptr_sel_out == TPU_FE_PTR_BIAS && dut_frontend.tile_step_idx == 4'd8)) seq_error <= 1'b1;
                            4: if (!(ub_rd_start_out && ub_ptr_sel_out == TPU_FE_PTR_INPUT && dut_frontend.tile_step_idx == 4'd9)) seq_error <= 1'b1;
                            default: seq_error <= 1'b1;
                        endcase
                    end
                    default: seq_error <= 1'b1;
                endcase
                seq_idx <= seq_idx + 1;
            end
        end
    end

    task automatic check_eq16;
        input string label;
        input logic signed [15:0] got;
        input logic signed [15:0] exp;
        begin
            if (got !== exp) begin
                $display("ERROR: %s got=%h exp=%h", label, got, exp);
                err_count = err_count + 1;
            end
        end
    endtask

    task automatic check_true;
        input string label;
        input logic cond;
        begin
            if (!cond) begin
                $display("ERROR: %s", label);
                err_count = err_count + 1;
            end
        end
    endtask

    task automatic pulse_cmd_write;
        input logic [11:0] addr;
        input logic [31:0] data;
        begin
            @(posedge clk);
            while (!cmd_ready) @(posedge clk);
            cmd_valid <= 1'b1;
            cmd_write <= 1'b1;
            cmd_addr  <= addr;
            cmd_wdata <= data;
            @(posedge clk);
            cmd_valid <= 1'b0;
            cmd_write <= 1'b0;
            cmd_addr  <= '0;
            cmd_wdata <= '0;
        end
    endtask

    task automatic preload_pair;
        input logic signed [15:0] lane0;
        input logic signed [15:0] lane1;
        begin
            pulse_cmd_write(TPU_FE_REG_UB_DATA0, {16'h0, lane0});
            pulse_cmd_write(TPU_FE_REG_UB_DATA1, {16'h0, lane1});
            pulse_cmd_write(TPU_FE_REG_UB_PUSH, 32'h0000_0003);
        end
    endtask

    task automatic launch_tile;
        input logic [5:0] input_addr;
        input logic [5:0] weight_addr;
        input logic [5:0] bias_addr;
        input logic [5:0] y_addr;
        input logic [3:0] pathway;
        begin
            @(posedge clk);
            while (!tile_exec_ready) @(posedge clk);
            tile_exec_valid       <= 1'b1;
            tile_exec_input_addr  <= input_addr;
            tile_exec_weight_addr <= weight_addr;
            tile_exec_bias_addr   <= bias_addr;
            tile_exec_y_addr      <= y_addr;
            tile_exec_pathway     <= pathway;
            @(posedge clk);
            tile_exec_valid       <= 1'b0;
            tile_exec_input_addr  <= '0;
            tile_exec_weight_addr <= '0;
            tile_exec_bias_addr   <= '0;
            tile_exec_y_addr      <= '0;
            tile_exec_pathway     <= '0;
        end
    endtask

    task automatic wait_tile_done;
        begin
            timeout_count = 0;
            while (!tile_exec_done) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 400) begin
                    $display("ERROR: tile_exec_done timeout");
                    err_count = err_count + 1;
                    disable wait_tile_done;
                end
            end
            @(posedge clk);
        end
    endtask

    task automatic do_reset;
        begin
            rst_n                <= 1'b0;
            cmd_valid            <= 1'b0;
            cmd_write            <= 1'b0;
            cmd_addr             <= '0;
            cmd_wdata            <= '0;
            rsp_ready            <= 1'b1;
            tile_exec_valid      <= 1'b0;
            tile_exec_input_addr <= '0;
            tile_exec_weight_addr<= '0;
            tile_exec_bias_addr  <= '0;
            tile_exec_y_addr     <= '0;
            tile_exec_pathway    <= '0;
            readback_exec_valid  <= 1'b0;
            readback_exec_addr   <= '0;
            pattern_mode         <= PAT_NONE;
            pattern_reset        <= 1'b1;
            repeat (5) @(posedge clk);
            rst_n                <= 1'b1;
            @(posedge clk);
            pattern_reset        <= 1'b0;
        end
    endtask

    task automatic begin_pattern;
        input pattern_t mode;
        input integer exp_len;
        begin
            pattern_mode     <= mode;
            expected_seq_len <= exp_len;
            pattern_reset    <= 1'b1;
            @(posedge clk);
            pattern_reset    <= 1'b0;
        end
    endtask

    task automatic run_forward_case;
        begin
            $display("[INFO] run_forward_case");
            do_reset();
            pulse_cmd_write(TPU_FE_REG_LEAK,      32'h0000_0000);
            pulse_cmd_write(TPU_FE_REG_INV_BATCH, 32'h0000_0100);
            pulse_cmd_write(TPU_FE_REG_LR,        32'h0000_0080);

            preload_pair(16'sh0100, 16'sh0100); // input [1.0, 1.0]
            preload_pair(16'sh0100, 16'sh0000); // weight pair0
            preload_pair(16'sh0000, 16'shFF00); // weight pair1
            preload_pair(16'sh0000, 16'sh0000); // bias zero

            begin_pattern(PAT_FORWARD1100, 4);
            launch_tile(INPUT_ADDR, WEIGHT_ADDR, BIAS_ADDR, Y_ADDR, 4'b1100);
            wait_tile_done();
            repeat (4) @(posedge clk);

            check_true("forward frontend sequence complete", seq_idx == expected_seq_len);
            check_true("forward frontend sequence no error", !seq_error);
            check_true("forward saw weight valid", seen_weight_valid);
            check_true("forward saw input valid", seen_input_valid);
            check_true("forward saw systolic valid", seen_sys_valid);
            check_true("forward saw bias stage valid", seen_bias_valid);
            check_true("forward saw lr stage valid", seen_lr_valid);
            check_true("forward no loss stage", !seen_loss_valid);
            check_true("forward saw sys lane0", saw_sys_lane0);
            check_true("forward saw sys lane1", saw_sys_lane1);
            check_true("forward saw vpu lane0", saw_vpu_lane0);
            check_true("forward saw vpu lane1", saw_vpu_lane1);
            check_eq16("forward sys lane0", last_sys_lane0, 16'sh0100);
            check_eq16("forward sys lane1", last_sys_lane1, 16'shFF00);
            check_eq16("forward vpu lane0", last_vpu_lane0, 16'sh0100);
            check_eq16("forward vpu lane1", last_vpu_lane1, 16'sh0000);
        end
    endtask

    task automatic run_transition_case;
        begin
            $display("[INFO] run_transition_case");
            do_reset();
            pulse_cmd_write(TPU_FE_REG_LEAK,      32'h0000_0040);
            pulse_cmd_write(TPU_FE_REG_INV_BATCH, 32'h0000_0100);
            pulse_cmd_write(TPU_FE_REG_LR,        32'h0000_0080);

            preload_pair(16'sh0100, 16'sh0100); // input [1.0,1.0]
            preload_pair(16'sh0100, 16'sh0000); // weight pair0
            preload_pair(16'sh0000, 16'sh0200); // weight pair1
            preload_pair(16'sh0000, 16'sh0000); // bias zero
            preload_pair(16'sh0180, 16'sh0040); // Y stored reversed so consumed lanes are [0.25,1.5]

            begin_pattern(PAT_TRANS1111, 5);
            launch_tile(INPUT_ADDR, WEIGHT_ADDR, BIAS_ADDR, Y_ADDR, 4'b1111);
            wait_tile_done();
            repeat (6) @(posedge clk);

            check_true("transition frontend sequence complete", seq_idx == expected_seq_len);
            check_true("transition frontend sequence no error", !seq_error);
            check_true("transition saw weight valid", seen_weight_valid);
            check_true("transition saw input valid", seen_input_valid);
            check_true("transition saw Y valid", seen_y_valid);
            check_true("transition saw systolic valid", seen_sys_valid);
            check_true("transition saw bias stage valid", seen_bias_valid);
            check_true("transition saw lr stage valid", seen_lr_valid);
            check_true("transition saw loss stage valid", seen_loss_valid);
            check_true("transition saw lr_d stage valid", seen_lrd_valid);
            check_true("transition saw sys lane0", saw_sys_lane0);
            check_true("transition saw sys lane1", saw_sys_lane1);
            check_true("transition saw vpu lane0", saw_vpu_lane0);
            check_true("transition saw vpu lane1", saw_vpu_lane1);
            check_eq16("transition sys lane0", last_sys_lane0, 16'sh0100);
            check_eq16("transition sys lane1", last_sys_lane1, 16'sh0200);
            check_eq16("transition vpu lane0", last_vpu_lane0, 16'sh00C0);
            check_eq16("transition vpu lane1", last_vpu_lane1, 16'sh0080);
        end
    endtask

`ifdef ENABLE_FSDB
    initial begin
        $fsdbDumpfile("tb_frontend_tpu_core_modes.fsdb");
        $fsdbDumpvars(0, tb_frontend_tpu_core_modes);
    end
`endif

    initial begin
        clk = 1'b0;
        err_count = 0;
        run_forward_case();
        run_transition_case();
        if (err_count != 0) begin
            $display("TB FAILED err_count=%0d", err_count);
            $fatal(1);
        end
        $display("TB PASSED tb_frontend_tpu_core_modes");
        $finish;
    end
endmodule

`default_nettype wire
