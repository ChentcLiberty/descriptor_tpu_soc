`timescale 1ns/1ps
`default_nettype none

module tb_tpu_training_timing_flow;
    localparam int CLK_PERIOD = 10;

    localparam logic [15:0] INPUT_ADDR  = 16'd0;
    localparam logic [15:0] WEIGHT_ADDR = 16'd2;
    localparam logic [15:0] BIAS_ADDR   = 16'd6;
    localparam logic [15:0] Y_ADDR      = 16'd8;
    localparam logic [15:0] H_ADDR      = 16'd10;
    localparam logic [15:0] UPDATE_ADDR = 16'd12;

    typedef enum logic [2:0] {
        PAT_NONE        = 3'd0,
        PAT_FORWARD1100 = 3'd1,
        PAT_TRANS1111   = 3'd2,
        PAT_BACK0001    = 3'd3,
        PAT_UPD_BIAS    = 3'd4
    } pattern_t;

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

    pattern_t pattern_mode;
    logic pattern_reset;
    integer phase_cycle;

    integer first_weight_valid_cycle;
    integer first_y_valid_cycle;
    integer first_h_valid_cycle;
    integer first_input_valid_cycle;
    integer first_sys21_cycle;
    integer first_sys22_cycle;
    integer first_bias_valid_cycle;
    integer first_lr_valid_cycle;
    integer first_loss_valid_cycle;
    integer first_lrd_valid_cycle;
    integer first_vpu_valid_cycle;
    integer first_grad_valid_cycle;
    integer first_grad_done_cycle;

    logic signed [15:0] last_sys_lane0;
    logic signed [15:0] last_sys_lane1;
    logic signed [15:0] last_vpu_lane0;
    logic signed [15:0] last_vpu_lane1;
    logic saw_vpu_lane0;
    logic saw_vpu_lane1;

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

    task automatic clear_phase_monitors;
        begin
            phase_cycle              = 0;
            first_weight_valid_cycle = -1;
            first_y_valid_cycle      = -1;
            first_h_valid_cycle      = -1;
            first_input_valid_cycle  = -1;
            first_sys21_cycle        = -1;
            first_sys22_cycle        = -1;
            first_bias_valid_cycle   = -1;
            first_lr_valid_cycle     = -1;
            first_loss_valid_cycle   = -1;
            first_lrd_valid_cycle    = -1;
            first_vpu_valid_cycle    = -1;
            first_grad_valid_cycle   = -1;
            first_grad_done_cycle    = -1;
            last_sys_lane0           = '0;
            last_sys_lane1           = '0;
            last_vpu_lane0           = '0;
            last_vpu_lane1           = '0;
            saw_vpu_lane0            = 1'b0;
            saw_vpu_lane1            = 1'b0;
        end
    endtask

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clear_phase_monitors();
        end else if (pattern_reset) begin
            clear_phase_monitors();
        end else begin
            phase_cycle <= phase_cycle + 1;

            if (first_weight_valid_cycle < 0 &&
                (ub_rd_weight_valid_out_0 || ub_rd_weight_valid_out_1))
                first_weight_valid_cycle <= phase_cycle;

            if (first_y_valid_cycle < 0 &&
                (ub_rd_Y_valid_out_0 || ub_rd_Y_valid_out_1))
                first_y_valid_cycle <= phase_cycle;

            if (first_h_valid_cycle < 0 &&
                (dut.ub_inst.ub_rd_H_valid_out_0 || dut.ub_inst.ub_rd_H_valid_out_1))
                first_h_valid_cycle <= phase_cycle;

            if (first_input_valid_cycle < 0 &&
                (ub_rd_input_valid_out_0 || ub_rd_input_valid_out_1))
                first_input_valid_cycle <= phase_cycle;

            if (first_sys21_cycle < 0 && sys_valid_out_21)
                first_sys21_cycle <= phase_cycle;

            if (first_sys22_cycle < 0 && sys_valid_out_22)
                first_sys22_cycle <= phase_cycle;

            if (first_bias_valid_cycle < 0 &&
                (dut.vpu_inst.bias_valid_1_out || dut.vpu_inst.bias_valid_2_out))
                first_bias_valid_cycle <= phase_cycle;

            if (first_lr_valid_cycle < 0 &&
                (dut.vpu_inst.lr_valid_1_out || dut.vpu_inst.lr_valid_2_out))
                first_lr_valid_cycle <= phase_cycle;

            if (first_loss_valid_cycle < 0 &&
                (dut.vpu_inst.loss_valid_1_out || dut.vpu_inst.loss_valid_2_out))
                first_loss_valid_cycle <= phase_cycle;

            if (first_lrd_valid_cycle < 0 &&
                (dut.vpu_inst.lr_d_valid_1_out || dut.vpu_inst.lr_d_valid_2_out))
                first_lrd_valid_cycle <= phase_cycle;

            if (first_vpu_valid_cycle < 0 &&
                (vpu_valid_out_1 || vpu_valid_out_2))
                first_vpu_valid_cycle <= phase_cycle;

            if (first_grad_valid_cycle < 0 &&
                (dut.ub_inst.grad_descent_valid_in[0] || dut.ub_inst.grad_descent_valid_in[1]))
                first_grad_valid_cycle <= phase_cycle;

            if (first_grad_done_cycle < 0 &&
                (dut.ub_inst.grad_descent_done_out[0] || dut.ub_inst.grad_descent_done_out[1]))
                first_grad_done_cycle <= phase_cycle;

            if (sys_valid_out_21)
                last_sys_lane0 <= sys_data_out_21;
            if (sys_valid_out_22)
                last_sys_lane1 <= sys_data_out_22;
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

    task automatic check_order;
        input string label;
        input integer a;
        input integer b;
        begin
            if (a < 0 || b < 0 || !(a < b)) begin
                $display("ERROR: order %s a=%0d b=%0d", label, a, b);
                err_count = err_count + 1;
            end
        end
    endtask

    task automatic check_order_le;
        input string label;
        input integer a;
        input integer b;
        begin
            if (a < 0 || b < 0 || !(a <= b)) begin
                $display("ERROR: order %s a=%0d b=%0d", label, a, b);
                err_count = err_count + 1;
            end
        end
    endtask

    task automatic drive_idle;
        begin
            ub_wr_host_data_in[0]  <= '0;
            ub_wr_host_data_in[1]  <= '0;
            ub_wr_host_valid_in[0] <= 1'b0;
            ub_wr_host_valid_in[1] <= 1'b0;
            ub_wr_ptr_restore_in   <= 1'b0;
            ub_rd_start_in         <= 1'b0;
            ub_rd_transpose        <= 1'b0;
            ub_ptr_select          <= '0;
            ub_rd_addr_in          <= '0;
            ub_rd_row_size         <= '0;
            ub_rd_col_size         <= '0;
            learning_rate_in       <= 16'h0080;
            vpu_data_pathway       <= 4'b0000;
            sys_switch_in          <= 1'b0;
            vpu_leak_factor_in     <= 16'h0040;
            inv_batch_size_times_two_in <= 16'h0100;
            pattern_mode           <= PAT_NONE;
            pattern_reset          <= 1'b0;
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

    task automatic begin_pattern;
        input pattern_t mode;
        begin
            pattern_mode  <= mode;
            pattern_reset <= 1'b1;
            @(posedge clk);
            pattern_reset <= 1'b0;
        end
    endtask

    task automatic host_push_pair;
        input logic signed [15:0] lane0;
        input logic signed [15:0] lane1;
        begin
            @(posedge clk);
            ub_wr_host_data_in[0]  <= lane0;
            ub_wr_host_data_in[1]  <= lane1;
            ub_wr_host_valid_in[0] <= 1'b1;
            ub_wr_host_valid_in[1] <= 1'b1;
            @(posedge clk);
            ub_wr_host_valid_in[0] <= 1'b0;
            ub_wr_host_valid_in[1] <= 1'b0;
            ub_wr_host_data_in[0]  <= '0;
            ub_wr_host_data_in[1]  <= '0;
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

    task automatic wait_for_vpu_lanes;
        begin
            timeout_count = 0;
            while (!(saw_vpu_lane0 && saw_vpu_lane1)) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 200) begin
                    $display("ERROR: VPU output timeout pattern=%0d", pattern_mode);
                    err_count = err_count + 1;
                    disable wait_for_vpu_lanes;
                end
            end
        end
    endtask

    task automatic print_phase_summary;
        input string name;
        begin
            $display("[INFO] %s cycles: weight=%0d y=%0d h=%0d input=%0d sys21=%0d sys22=%0d bias=%0d lr=%0d loss=%0d lrd=%0d vpu=%0d grad=%0d done=%0d",
                name,
                first_weight_valid_cycle,
                first_y_valid_cycle,
                first_h_valid_cycle,
                first_input_valid_cycle,
                first_sys21_cycle,
                first_sys22_cycle,
                first_bias_valid_cycle,
                first_lr_valid_cycle,
                first_loss_valid_cycle,
                first_lrd_valid_cycle,
                first_vpu_valid_cycle,
                first_grad_valid_cycle,
                first_grad_done_cycle
            );
        end
    endtask

    task automatic run_forward_case;
        begin
            $display("[INFO] run_forward_case");
            do_reset();
            vpu_leak_factor_in          <= 16'h0000;
            inv_batch_size_times_two_in <= 16'h0100;
            learning_rate_in            <= 16'h0080;

            host_push_pair(16'sh0100, 16'sh0100); // input [1.0,1.0]
            host_push_pair(16'sh0100, 16'sh0000); // weight pair0
            host_push_pair(16'sh0000, 16'shFF00); // weight pair1
            host_push_pair(16'sh0000, 16'sh0000); // bias

            begin_pattern(PAT_FORWARD1100);
            start_read(9'd1, WEIGHT_ADDR, 16'd2, 16'd2, 1'b1);
            repeat (4) @(posedge clk);
            pulse_sys_switch();
            start_read(9'd2, BIAS_ADDR, 16'd1, 16'd2, 1'b0);
            vpu_data_pathway <= 4'b1100;
            start_read(9'd0, INPUT_ADDR, 16'd1, 16'd2, 1'b0);
            wait_for_vpu_lanes();
            repeat (4) @(posedge clk);

            check_eq16("forward sys lane0", last_sys_lane0, 16'sh0100);
            check_eq16("forward sys lane1", last_sys_lane1, 16'shFF00);
            check_eq16("forward vpu lane0", last_vpu_lane0, 16'sh0100);
            check_eq16("forward vpu lane1", last_vpu_lane1, 16'sh0000);
            check_order("forward weight<input", first_weight_valid_cycle, first_input_valid_cycle);
            check_order("forward input<sys21", first_input_valid_cycle, first_sys21_cycle);
            check_order_le("forward sys21<=sys22", first_sys21_cycle, first_sys22_cycle);
            check_order("forward sys21<bias", first_sys21_cycle, first_bias_valid_cycle);
            check_order_le("forward bias<=lr", first_bias_valid_cycle, first_lr_valid_cycle);
            check_order_le("forward lr<=vpu", first_lr_valid_cycle, first_vpu_valid_cycle);
            check_true("forward no loss", first_loss_valid_cycle < 0);
            check_order("forward lr<lrd_tap", first_lr_valid_cycle, first_lrd_valid_cycle);
            print_phase_summary("forward1100");
        end
    endtask

    task automatic run_transition_case;
        begin
            $display("[INFO] run_transition_case");
            do_reset();
            vpu_leak_factor_in          <= 16'h0040;
            inv_batch_size_times_two_in <= 16'h0100;
            learning_rate_in            <= 16'h0080;

            host_push_pair(16'sh0100, 16'sh0100); // input [1.0,1.0]
            host_push_pair(16'sh0100, 16'sh0000); // weight pair0
            host_push_pair(16'sh0000, 16'sh0200); // weight pair1
            host_push_pair(16'sh0000, 16'sh0000); // bias
            host_push_pair(16'sh0180, 16'sh0040); // Y reversed, consumed as [0.25,1.5]

            begin_pattern(PAT_TRANS1111);
            start_read(9'd1, WEIGHT_ADDR, 16'd2, 16'd2, 1'b1);
            repeat (4) @(posedge clk);
            pulse_sys_switch();
            start_read(9'd3, Y_ADDR, 16'd1, 16'd2, 1'b0);
            start_read(9'd2, BIAS_ADDR, 16'd1, 16'd2, 1'b0);
            vpu_data_pathway <= 4'b1111;
            start_read(9'd0, INPUT_ADDR, 16'd1, 16'd2, 1'b0);
            wait_for_vpu_lanes();
            repeat (6) @(posedge clk);

            check_eq16("transition sys lane0", last_sys_lane0, 16'sh0100);
            check_eq16("transition sys lane1", last_sys_lane1, 16'sh0200);
            check_eq16("transition vpu lane0", last_vpu_lane0, 16'sh00C0);
            check_eq16("transition vpu lane1", last_vpu_lane1, 16'sh0080);
            check_order("transition weight<Y", first_weight_valid_cycle, first_y_valid_cycle);
            check_order("transition Y<input", first_y_valid_cycle, first_input_valid_cycle);
            check_order("transition input<sys21", first_input_valid_cycle, first_sys21_cycle);
            check_order_le("transition sys21<=sys22", first_sys21_cycle, first_sys22_cycle);
            check_order("transition sys21<bias", first_sys21_cycle, first_bias_valid_cycle);
            check_order("transition bias<lr", first_bias_valid_cycle, first_lr_valid_cycle);
            check_order("transition lr<loss", first_lr_valid_cycle, first_loss_valid_cycle);
            check_order("transition loss<lrd", first_loss_valid_cycle, first_lrd_valid_cycle);
            check_order_le("transition lrd<=vpu", first_lrd_valid_cycle, first_vpu_valid_cycle);
            print_phase_summary("transition1111");
        end
    endtask

    task automatic run_backward_case;
        begin
            $display("[INFO] run_backward_case");
            do_reset();
            vpu_leak_factor_in          <= 16'h0040;
            inv_batch_size_times_two_in <= 16'h0100;
            learning_rate_in            <= 16'h0080;

            host_push_pair(16'sh0100, 16'sh0100); // input [1.0,1.0]
            host_push_pair(16'sh0100, 16'sh0000); // weight pair0
            host_push_pair(16'sh0000, 16'sh0100); // weight pair1
            host_push_pair(16'sh0000, 16'sh0000); // dummy bias
            host_push_pair(16'sh0000, 16'sh0000); // dummy Y
            host_push_pair(16'sh0200, 16'shFF00); // H [positive, negative]

            begin_pattern(PAT_BACK0001);
            start_read(9'd1, WEIGHT_ADDR, 16'd2, 16'd2, 1'b1);
            repeat (4) @(posedge clk);
            pulse_sys_switch();
            start_read(9'd4, H_ADDR, 16'd1, 16'd2, 1'b0);
            vpu_data_pathway <= 4'b0001;
            start_read(9'd0, INPUT_ADDR, 16'd1, 16'd2, 1'b0);
            wait_for_vpu_lanes();
            repeat (4) @(posedge clk);

            check_eq16("backward vpu lane0", last_vpu_lane0, 16'sh0040);
            check_eq16("backward vpu lane1", last_vpu_lane1, 16'sh0100);
            check_order("backward weight<H", first_weight_valid_cycle, first_h_valid_cycle);
            check_order("backward H<input", first_h_valid_cycle, first_input_valid_cycle);
            check_order("backward input<sys21", first_input_valid_cycle, first_sys21_cycle);
            check_order("backward sys21<lrd", first_sys21_cycle, first_lrd_valid_cycle);
            check_order_le("backward lrd<=vpu", first_lrd_valid_cycle, first_vpu_valid_cycle);
            check_true("backward no bias", first_bias_valid_cycle < 0);
            check_true("backward no lr", first_lr_valid_cycle < 0);
            check_true("backward no loss", first_loss_valid_cycle < 0);
            print_phase_summary("backward0001");
        end
    endtask

    task automatic run_bias_update_case;
        logic signed [15:0] mem0;
        logic signed [15:0] mem1;
        begin
            $display("[INFO] run_bias_update_case");
            do_reset();
            vpu_leak_factor_in          <= 16'h0040;
            inv_batch_size_times_two_in <= 16'h0100;
            learning_rate_in            <= 16'h0080;

            host_push_pair(16'sh0100, 16'sh0100); // input [1.0,1.0]
            host_push_pair(16'sh0100, 16'sh0000); // weight pair0
            host_push_pair(16'sh0000, 16'sh0100); // weight pair1
            host_push_pair(16'sh0000, 16'sh0000); // dummy bias
            host_push_pair(16'sh0000, 16'sh0000); // dummy Y
            host_push_pair(16'sh0200, 16'shFF00); // H [positive, negative]
            host_push_pair(16'sh0200, 16'sh0100); // old bias values for update

            begin_pattern(PAT_UPD_BIAS);
            start_read(9'd5, UPDATE_ADDR, 16'd1, 16'd2, 1'b0); // arm bias update
            start_read(9'd1, WEIGHT_ADDR, 16'd2, 16'd2, 1'b1);
            repeat (4) @(posedge clk);
            pulse_sys_switch();
            start_read(9'd4, H_ADDR, 16'd1, 16'd2, 1'b0);
            vpu_data_pathway <= 4'b0001;
            start_read(9'd0, INPUT_ADDR, 16'd1, 16'd2, 1'b0);
            wait_for_vpu_lanes();
            repeat (8) @(posedge clk);

            mem0 = dut.ub_inst.ub_memory[UPDATE_ADDR + 16'd0];
            mem1 = dut.ub_inst.ub_memory[UPDATE_ADDR + 16'd1];
            check_eq16("update bias mem0", mem0, 16'sh00E0);
            check_eq16("update bias mem1", mem1, 16'sh0180);
            check_true("update saw grad valid", first_grad_valid_cycle >= 0);
            check_true("update saw grad done", first_grad_done_cycle >= 0);
            check_order_le("update vpu<=grad_valid", first_vpu_valid_cycle, first_grad_valid_cycle);
            check_order("update grad_valid<grad_done", first_grad_valid_cycle, first_grad_done_cycle);
            print_phase_summary("bias_update");
        end
    endtask

`ifdef ENABLE_FSDB
    initial begin
        $fsdbDumpfile("tb_tpu_training_timing_flow.fsdb");
        $fsdbDumpvars(0, tb_tpu_training_timing_flow);
    end
`endif

    initial begin
        clk = 1'b0;
        err_count = 0;
        run_forward_case();
        run_transition_case();
        run_backward_case();
        run_bias_update_case();
        if (err_count != 0) begin
            $display("TB FAILED err_count=%0d", err_count);
            $fatal(1);
        end
        $display("TB PASSED tb_tpu_training_timing_flow");
        $finish;
    end
endmodule

`default_nettype wire
