`timescale 1ns/1ps
`default_nettype none

module tb_tpu_h1_bias_fix;
    localparam int SYSTOLIC_ARRAY_WIDTH = 2;

    localparam logic [15:0] FXP_ZERO = 16'h0000;
    localparam logic [15:0] FXP_ONE  = 16'h0100;

    localparam logic [15:0] W1_00 = 16'h004c;
    localparam logic [15:0] W1_01 = 16'hff6c;
    localparam logic [15:0] W1_10 = 16'h0017;
    localparam logic [15:0] W1_11 = 16'h006c;
    localparam logic [15:0] W2_0  = 16'h0087;
    localparam logic [15:0] W2_1  = 16'h004c;
    localparam logic [15:0] B1_0  = 16'hff82;
    localparam logic [15:0] B1_1  = 16'h0030;
    localparam logic [15:0] B2_0  = 16'h00a3;

    localparam logic [15:0] LEAK   = 16'h0080;
    localparam logic [15:0] INV_N2 = 16'h0080;
    localparam logic [15:0] LR     = 16'h00c0;

    localparam logic [15:0] EXP_H1_COL1 [0:3] = '{16'hffc1, 16'hff77, 16'hffe7, 16'hff9d};
    localparam logic [15:0] EXP_H1_COL2 [0:3] = '{16'h0030, 16'h009c, 16'h0047, 16'h00b3};

    logic clk;
    logic rst;
    logic [15:0] ub_wr_host_data_in [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic ub_wr_host_valid_in [0:SYSTOLIC_ARRAY_WIDTH-1];
    logic ub_rd_start_in;
    logic ub_rd_transpose;
    logic [8:0] ub_ptr_select;
    logic [15:0] ub_rd_addr_in;
    logic [15:0] ub_rd_row_size;
    logic [15:0] ub_rd_col_size;
    logic [15:0] learning_rate_in;
    logic [3:0] vpu_data_pathway;
    logic sys_switch_in;
    logic [15:0] vpu_leak_factor_in;
    logic [15:0] inv_batch_size_times_two_in;

    logic [15:0] vpu_data_out_1;
    logic [15:0] vpu_data_out_2;
    logic vpu_valid_out_1;
    logic vpu_valid_out_2;
    logic [15:0] sys_data_out_21;
    logic [15:0] sys_data_out_22;
    logic sys_valid_out_21;
    logic sys_valid_out_22;
    logic [15:0] ub_rd_input_data_out_0;
    logic [15:0] ub_rd_input_data_out_1;
    logic ub_rd_input_valid_out_0;
    logic ub_rd_input_valid_out_1;
    logic [15:0] ub_rd_weight_data_out_0;
    logic [15:0] ub_rd_weight_data_out_1;
    logic ub_rd_weight_valid_out_0;
    logic ub_rd_weight_valid_out_1;

    logic [15:0] got_col1 [0:3];
    logic [15:0] got_col2 [0:3];
    int got_col1_n;
    int got_col2_n;
    int fail_count;
    bit seen_any_valid;

    tpu #(.SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)) dut (
        .clk(clk),
        .rst(rst),
        .ub_wr_host_data_in(ub_wr_host_data_in),
        .ub_wr_host_valid_in(ub_wr_host_valid_in),
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
        .ub_rd_weight_valid_out_1(ub_rd_weight_valid_out_1)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("tb_tpu_h1_bias_fix.vcd");
        $dumpvars(0, tb_tpu_h1_bias_fix);
    end

    task automatic clear_controls();
        begin
            ub_wr_host_data_in[0] = '0;
            ub_wr_host_data_in[1] = '0;
            ub_wr_host_valid_in[0] = 1'b0;
            ub_wr_host_valid_in[1] = 1'b0;
            ub_rd_start_in = 1'b0;
            ub_rd_transpose = 1'b0;
            ub_ptr_select = '0;
            ub_rd_addr_in = '0;
            ub_rd_row_size = '0;
            ub_rd_col_size = '0;
            vpu_data_pathway = 4'b0000;
            sys_switch_in = 1'b0;
        end
    endtask

    task automatic host_write_cycle(
        input logic [15:0] data0,
        input logic        valid0,
        input logic [15:0] data1,
        input logic        valid1
    );
        begin
            @(negedge clk);
            ub_wr_host_data_in[0] = data0;
            ub_wr_host_valid_in[0] = valid0;
            ub_wr_host_data_in[1] = data1;
            ub_wr_host_valid_in[1] = valid1;
            @(posedge clk);
        end
    endtask

    task automatic load_all_data();
        begin
            host_write_cycle(FXP_ZERO, 1'b1, FXP_ZERO, 1'b0);
            host_write_cycle(FXP_ZERO, 1'b1, FXP_ZERO, 1'b1);
            host_write_cycle(FXP_ONE,  1'b1, FXP_ONE,  1'b1);
            host_write_cycle(FXP_ONE,  1'b1, FXP_ZERO, 1'b1);
            host_write_cycle(FXP_ZERO, 1'b1, FXP_ONE,  1'b1);
            host_write_cycle(FXP_ONE,  1'b1, FXP_ZERO, 1'b0);
            host_write_cycle(FXP_ONE,  1'b1, FXP_ZERO, 1'b0);
            host_write_cycle(FXP_ZERO, 1'b1, FXP_ZERO, 1'b0);
            host_write_cycle(W1_00,    1'b1, FXP_ZERO, 1'b0);
            host_write_cycle(W1_10,    1'b1, W1_01,    1'b1);
            host_write_cycle(B1_0,     1'b1, W1_11,    1'b1);
            host_write_cycle(W2_0,     1'b1, B1_1,     1'b1);
            host_write_cycle(B2_0,     1'b1, W2_1,     1'b1);
            host_write_cycle(FXP_ZERO, 1'b0, FXP_ZERO, 1'b0);
        end
    endtask

    task automatic start_read(
        input logic [8:0] ptr_sel,
        input logic [15:0] addr,
        input logic [15:0] rows,
        input logic [15:0] cols,
        input logic transpose
    );
        begin
            @(negedge clk);
            ub_rd_start_in = 1'b1;
            ub_rd_transpose = transpose;
            ub_ptr_select = ptr_sel;
            ub_rd_addr_in = addr;
            ub_rd_row_size = rows;
            ub_rd_col_size = cols;
            @(posedge clk);
        end
    endtask

    task automatic stop_read();
        begin
            @(negedge clk);
            ub_rd_start_in = 1'b0;
            ub_rd_transpose = 1'b0;
            ub_ptr_select = '0;
            ub_rd_addr_in = '0;
            ub_rd_row_size = '0;
            ub_rd_col_size = '0;
        end
    endtask

    task automatic check_word(
        input string tag,
        input logic [15:0] exp,
        input logic [15:0] got
    );
        begin
            if (got !== exp) begin
                $display("[FAIL] %s exp=%h got=%h", tag, exp, got);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] %s exp=%h got=%h", tag, exp, got);
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst) begin
            if (vpu_valid_out_1 && got_col1_n < 4) begin
                got_col1[got_col1_n] <= vpu_data_out_1;
                $display("[%0t] col1[%0d]=%h bias0=%h sys21=%h valid21=%0b",
                         $time, got_col1_n, vpu_data_out_1,
                         dut.ub_inst.ub_rd_bias_data_out_0,
                         sys_data_out_21, sys_valid_out_21);
                got_col1_n <= got_col1_n + 1;
                seen_any_valid <= 1'b1;
            end
            if (vpu_valid_out_2 && got_col2_n < 4) begin
                got_col2[got_col2_n] <= vpu_data_out_2;
                $display("[%0t] col2[%0d]=%h bias1=%h sys22=%h valid22=%0b bias_ctr=%0d",
                         $time, got_col2_n, vpu_data_out_2,
                         dut.ub_inst.ub_rd_bias_data_out_1,
                         sys_data_out_22, sys_valid_out_22,
                         dut.ub_inst.rd_bias_time_counter);
                got_col2_n <= got_col2_n + 1;
                seen_any_valid <= 1'b1;
            end
        end
    end

    initial begin
        fail_count = 0;
        got_col1_n = 0;
        got_col2_n = 0;
        seen_any_valid = 1'b0;

        rst = 1'b1;
        learning_rate_in = LR;
        vpu_leak_factor_in = LEAK;
        inv_batch_size_times_two_in = INV_N2;
        clear_controls();

        repeat (5) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        load_all_data();

        for (int dbg_i = 0; dbg_i <= 20; dbg_i++) begin
            $display("[DBG] UB[%0d]=%h", dbg_i, dut.ub_inst.ub_memory[dbg_i]);
        end

        start_read(9'd1, 16'd12, 16'd2, 16'd2, 1'b1);
        stop_read();
        repeat (4) begin
            @(posedge clk);
            $display("[DBG] W stream v0=%0b d0=%h v1=%0b d1=%h pe12_out=%h",
                     ub_rd_weight_valid_out_0, ub_rd_weight_data_out_0,
                     ub_rd_weight_valid_out_1, ub_rd_weight_data_out_1,
                     dut.systolic_inst.pe_weight_out_12);
        end

        @(negedge clk);
        sys_switch_in = 1'b1;
        @(posedge clk);
        @(negedge clk);
        sys_switch_in = 1'b0;

        $display("[DBG] pre-wait inactive PE11=%h PE12=%h PE21=%h PE22=%h",
                 dut.systolic_inst.pe11.weight_reg_inactive,
                 dut.systolic_inst.pe12.weight_reg_inactive,
                 dut.systolic_inst.pe21.weight_reg_inactive,
                 dut.systolic_inst.pe22.weight_reg_inactive);
        $display("[DBG] pre-wait active   PE11=%h PE12=%h PE21=%h PE22=%h",
                 dut.systolic_inst.pe11.weight_reg_active,
                 dut.systolic_inst.pe12.weight_reg_active,
                 dut.systolic_inst.pe21.weight_reg_active,
                 dut.systolic_inst.pe22.weight_reg_active);

        // The switch pulse reaches PE22 two cycles later. Wait until the
        // active weights are guaranteed to be visible across the full array.
        repeat (2) @(posedge clk);

        $display("[DBG] post-wait active  PE11=%h PE12=%h PE21=%h PE22=%h",
                 dut.systolic_inst.pe11.weight_reg_active,
                 dut.systolic_inst.pe12.weight_reg_active,
                 dut.systolic_inst.pe21.weight_reg_active,
                 dut.systolic_inst.pe22.weight_reg_active);

        vpu_data_pathway = 4'b1100;
        start_read(9'd0, 16'd0, 16'd4, 16'd2, 1'b0);
        stop_read();
        start_read(9'd2, 16'd16, 16'd4, 16'd2, 1'b0);
        stop_read();

        repeat (40) @(posedge clk);

        if (!seen_any_valid) begin
            $display("[FAIL] no VPU output observed");
            fail_count = fail_count + 1;
        end

        if (got_col1_n != 4) begin
            $display("[FAIL] col1 count exp=4 got=%0d", got_col1_n);
            fail_count = fail_count + 1;
        end
        if (got_col2_n != 4) begin
            $display("[FAIL] col2 count exp=4 got=%0d", got_col2_n);
            fail_count = fail_count + 1;
        end

        if (got_col1_n == 4) begin
            check_word("H1 col1[0]", EXP_H1_COL1[0], got_col1[0]);
            check_word("H1 col1[1]", EXP_H1_COL1[1], got_col1[1]);
            check_word("H1 col1[2]", EXP_H1_COL1[2], got_col1[2]);
            check_word("H1 col1[3]", EXP_H1_COL1[3], got_col1[3]);
        end

        if (got_col2_n == 4) begin
            check_word("H1 col2[0]", EXP_H1_COL2[0], got_col2[0]);
            check_word("H1 col2[1]", EXP_H1_COL2[1], got_col2[1]);
            check_word("H1 col2[2]", EXP_H1_COL2[2], got_col2[2]);
            check_word("H1 col2[3]", EXP_H1_COL2[3], got_col2[3]);
        end

        if (fail_count == 0) begin
            $display("[PASS] tb_tpu_h1_bias_fix complete");
        end else begin
            $display("[FAIL] tb_tpu_h1_bias_fix fail_count=%0d", fail_count);
        end
        $finish;
    end

    initial begin
        #5000;
        $display("[FAIL] tb_tpu_h1_bias_fix timeout");
        $finish;
    end
endmodule
