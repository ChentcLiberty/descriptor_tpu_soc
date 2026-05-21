`timescale 1ns/1ps
`default_nettype none

module tb_tpu_core_backward_bias_update;
    localparam int CLK_PERIOD = 10;
    localparam logic [15:0] INPUT_ADDR  = 16'd0;
    localparam logic [15:0] WEIGHT_ADDR = 16'd2;
    localparam logic [15:0] H_ADDR      = 16'd6;

    logic clk;
    logic rst;

    logic [15:0] ub_wr_host_data_in [0:1];
    logic        ub_wr_host_valid_in[0:1];
    logic        ub_wr_ptr_restore_in;

    logic        ub_rd_start_in;
    logic        ub_rd_transpose;
    logic [8:0]  ub_ptr_select;
    logic [15:0] ub_rd_addr_in;
    logic [15:0] ub_rd_row_size;
    logic [15:0] ub_rd_col_size;

    logic [15:0] learning_rate_in;
    logic [3:0]  vpu_data_pathway;
    logic        sys_switch_in;
    logic [15:0] vpu_leak_factor_in;
    logic [15:0] inv_batch_size_times_two_in;

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
    logic seen_weight_valid;
    logic seen_input_valid;
    logic seen_h_valid;
    logic seen_sys_valid;
    logic seen_lrd_valid;
    logic saw_vpu_lane0;
    logic saw_vpu_lane1;
    logic signed [15:0] last_vpu_lane0;
    logic signed [15:0] last_vpu_lane1;

    tpu dut (
        .clk(clk),
        .rst(rst),
        .ub_wr_host_data_in(ub_wr_host_data_in),
        .ub_wr_host_valid_in(ub_wr_host_valid_in),
        .ub_wr_ptr_restore_in(ub_wr_ptr_restore_in),
        .ub_rd_start_in(ub_rd_start_in),
        .ub_rd_transpose(ub_rd_transpose),
        .ub_ptr_select(ub_ptr_select),
        .ub_rd_addr_in(ub_rd_addr_in),
        .ub_rd_row_size(ub_rd_row_size),
        .ub_rd_col_size(ub_rd_col_size),
        .learning_rate_in(learning_rate_in),
        .vpu_data_pathway(vpu_data_pathway),
        .sys_switch_in(sys_switch_in),
        .vpu_leak_factor_in(vpu_leak_factor_in),
        .inv_batch_size_times_two_in(inv_batch_size_times_two_in),
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

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            seen_weight_valid <= 1'b0;
            seen_input_valid  <= 1'b0;
            seen_h_valid      <= 1'b0;
            seen_sys_valid    <= 1'b0;
            seen_lrd_valid    <= 1'b0;
            saw_vpu_lane0     <= 1'b0;
            saw_vpu_lane1     <= 1'b0;
            last_vpu_lane0    <= '0;
            last_vpu_lane1    <= '0;
        end else begin
            if (ub_rd_weight_valid_out_0 || ub_rd_weight_valid_out_1)
                seen_weight_valid <= 1'b1;
            if (ub_rd_input_valid_out_0 || ub_rd_input_valid_out_1)
                seen_input_valid <= 1'b1;
            if (dut.ub_inst.ub_rd_H_valid_out_0 || dut.ub_inst.ub_rd_H_valid_out_1)
                seen_h_valid <= 1'b1;
            if (sys_valid_out_21 || sys_valid_out_22)
                seen_sys_valid <= 1'b1;
            if (dut.vpu_inst.lr_d_valid_1_out || dut.vpu_inst.lr_d_valid_2_out)
                seen_lrd_valid <= 1'b1;
            if (vpu_valid_out_1) begin
                saw_vpu_lane0  <= 1'b1;
                last_vpu_lane0 <= vpu_data_out_1;
            end
            if (vpu_valid_out_2) begin
                saw_vpu_lane1  <= 1'b1;
                last_vpu_lane1 <= vpu_data_out_2;
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

    task automatic drive_idle;
        begin
            ub_wr_host_data_in[0] <= '0;
            ub_wr_host_data_in[1] <= '0;
            ub_wr_host_valid_in[0] <= 1'b0;
            ub_wr_host_valid_in[1] <= 1'b0;
            ub_wr_ptr_restore_in <= 1'b0;
            ub_rd_start_in <= 1'b0;
            ub_rd_transpose <= 1'b0;
            ub_ptr_select <= '0;
            ub_rd_addr_in <= '0;
            ub_rd_row_size <= '0;
            ub_rd_col_size <= '0;
            sys_switch_in <= 1'b0;
            vpu_data_pathway <= 4'b0000;
            vpu_leak_factor_in <= 16'h0040;
            inv_batch_size_times_two_in <= 16'h0100;
            learning_rate_in <= 16'h0080;
        end
    endtask

    task automatic do_reset;
        begin
            rst <= 1'b1;
            drive_idle();
            repeat (5) @(posedge clk);
            rst <= 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic host_push_pair;
        input logic signed [15:0] lane0;
        input logic signed [15:0] lane1;
        begin
            @(posedge clk);
            ub_wr_host_data_in[0]   <= lane0;
            ub_wr_host_data_in[1]   <= lane1;
            ub_wr_host_valid_in[0]  <= 1'b1;
            ub_wr_host_valid_in[1]  <= 1'b1;
            @(posedge clk);
            ub_wr_host_valid_in[0]  <= 1'b0;
            ub_wr_host_valid_in[1]  <= 1'b0;
            ub_wr_host_data_in[0]   <= '0;
            ub_wr_host_data_in[1]   <= '0;
        end
    endtask

    task automatic start_read;
        input logic [8:0]  ptr_sel;
        input logic [15:0] addr;
        input logic [15:0] row_sz;
        input logic [15:0] col_sz;
        input logic        transpose;
        begin
            @(posedge clk);
            ub_ptr_select   <= ptr_sel;
            ub_rd_addr_in   <= addr;
            ub_rd_row_size  <= row_sz;
            ub_rd_col_size  <= col_sz;
            ub_rd_transpose <= transpose;
            ub_rd_start_in  <= 1'b1;
            @(posedge clk);
            ub_rd_start_in  <= 1'b0;
            ub_ptr_select   <= '0;
            ub_rd_addr_in   <= '0;
            ub_rd_row_size  <= '0;
            ub_rd_col_size  <= '0;
            ub_rd_transpose <= 1'b0;
        end
    endtask

    task automatic pulse_sys_switch;
        begin
            @(posedge clk);
            sys_switch_in <= 1'b1;
            @(posedge clk);
            sys_switch_in <= 1'b0;
        end
    endtask

    task automatic wait_for_outputs;
        begin
            timeout_count = 0;
            while (!(saw_vpu_lane0 && saw_vpu_lane1)) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 200) begin
                    $display("ERROR: backward output timeout");
                    err_count = err_count + 1;
                    disable wait_for_outputs;
                end
            end
        end
    endtask

    task automatic run_backward_only_case;
        begin
            $display("[INFO] run_backward_only_case");
            do_reset();
            host_push_pair(16'sh0100, 16'sh0100); // input [1.0,1.0]
            host_push_pair(16'sh0100, 16'sh0000); // weight pair0
            host_push_pair(16'sh0000, 16'sh0100); // weight pair1
            host_push_pair(16'sh0200, 16'shFF00); // H [positive, negative]
            start_read(9'd1, WEIGHT_ADDR, 16'd2, 16'd2, 1'b1);
            repeat (4) @(posedge clk);
            pulse_sys_switch();
            start_read(9'd4, H_ADDR, 16'd1, 16'd2, 1'b0);
            vpu_data_pathway <= 4'b0001;
            start_read(9'd0, INPUT_ADDR, 16'd1, 16'd2, 1'b0);
            wait_for_outputs();
            repeat (4) @(posedge clk);

            check_true("backward saw weight valid", seen_weight_valid);
            check_true("backward saw input valid", seen_input_valid);
            check_true("backward saw H valid", seen_h_valid);
            check_true("backward saw systolic valid", seen_sys_valid);
            check_true("backward saw lr_d valid", seen_lrd_valid);
            check_true("backward saw lane0", saw_vpu_lane0);
            check_true("backward saw lane1", saw_vpu_lane1);
            check_eq16("backward vpu lane0", last_vpu_lane0, 16'sh0040);
            check_eq16("backward vpu lane1", last_vpu_lane1, 16'sh0100);
        end
    endtask

`ifdef ENABLE_FSDB
    initial begin
        $fsdbDumpfile("tb_tpu_core_backward_bias_update.fsdb");
        $fsdbDumpvars(0, tb_tpu_core_backward_bias_update);
    end
`endif

    initial begin
        clk = 1'b0;
        err_count = 0;
        run_backward_only_case();
        if (err_count != 0) begin
            $display("TB FAILED err_count=%0d", err_count);
            $fatal(1);
        end
        $display("TB PASSED tb_tpu_core_backward_bias_update");
        $finish;
    end
endmodule

`default_nettype wire
