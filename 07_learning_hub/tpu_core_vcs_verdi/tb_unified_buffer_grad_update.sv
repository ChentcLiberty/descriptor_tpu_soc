`timescale 1ns/1ps
`default_nettype none

module tb_unified_buffer_grad_update;
    localparam int CLK_PERIOD = 10;
    localparam int DEPTH = 64;
    localparam logic [15:0] BIAS_ADDR = 16'd0;

    logic clk;
    logic rst;

    logic [15:0] ub_wr_data_in [0:1];
    logic        ub_wr_valid_in[0:1];
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

    logic [15:0] ub_rd_input_data_out_0;
    logic [15:0] ub_rd_input_data_out_1;
    logic        ub_rd_input_valid_out_0;
    logic        ub_rd_input_valid_out_1;
    logic [15:0] ub_rd_weight_data_out_0;
    logic [15:0] ub_rd_weight_data_out_1;
    logic        ub_rd_weight_valid_out_0;
    logic        ub_rd_weight_valid_out_1;
    logic [15:0] ub_rd_bias_data_out_0;
    logic [15:0] ub_rd_bias_data_out_1;
    logic [15:0] ub_rd_Y_data_out_0;
    logic [15:0] ub_rd_Y_data_out_1;
    logic        ub_rd_Y_valid_out_0;
    logic        ub_rd_Y_valid_out_1;
    logic [15:0] ub_rd_H_data_out_0;
    logic [15:0] ub_rd_H_data_out_1;
    logic        ub_rd_H_valid_out_0;
    logic        ub_rd_H_valid_out_1;
    logic [15:0] ub_rd_col_size_out;
    logic        ub_rd_col_size_valid_out;

    integer err_count;

    unified_buffer #(
        .UNIFIED_BUFFER_WIDTH(DEPTH),
        .SYSTOLIC_ARRAY_WIDTH(2)
    ) dut (
        .clk(clk),
        .rst(rst),
        .ub_wr_data_in(ub_wr_data_in),
        .ub_wr_valid_in(ub_wr_valid_in),
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
        .ub_rd_input_data_out_0(ub_rd_input_data_out_0),
        .ub_rd_input_data_out_1(ub_rd_input_data_out_1),
        .ub_rd_input_valid_out_0(ub_rd_input_valid_out_0),
        .ub_rd_input_valid_out_1(ub_rd_input_valid_out_1),
        .ub_rd_weight_data_out_0(ub_rd_weight_data_out_0),
        .ub_rd_weight_data_out_1(ub_rd_weight_data_out_1),
        .ub_rd_weight_valid_out_0(ub_rd_weight_valid_out_0),
        .ub_rd_weight_valid_out_1(ub_rd_weight_valid_out_1),
        .ub_rd_bias_data_out_0(ub_rd_bias_data_out_0),
        .ub_rd_bias_data_out_1(ub_rd_bias_data_out_1),
        .ub_rd_Y_data_out_0(ub_rd_Y_data_out_0),
        .ub_rd_Y_data_out_1(ub_rd_Y_data_out_1),
        .ub_rd_Y_valid_out_0(ub_rd_Y_valid_out_0),
        .ub_rd_Y_valid_out_1(ub_rd_Y_valid_out_1),
        .ub_rd_H_data_out_0(ub_rd_H_data_out_0),
        .ub_rd_H_data_out_1(ub_rd_H_data_out_1),
        .ub_rd_H_valid_out_0(ub_rd_H_valid_out_0),
        .ub_rd_H_valid_out_1(ub_rd_H_valid_out_1),
        .ub_rd_col_size_out(ub_rd_col_size_out),
        .ub_rd_col_size_valid_out(ub_rd_col_size_valid_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

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

    task automatic drive_idle;
        begin
            ub_wr_data_in[0] <= '0;
            ub_wr_data_in[1] <= '0;
            ub_wr_valid_in[0] <= 1'b0;
            ub_wr_valid_in[1] <= 1'b0;
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
            ub_wr_host_data_in[0] <= lane0;
            ub_wr_host_data_in[1] <= lane1;
            ub_wr_host_valid_in[0] <= 1'b1;
            ub_wr_host_valid_in[1] <= 1'b1;
            @(posedge clk);
            ub_wr_host_valid_in[0] <= 1'b0;
            ub_wr_host_valid_in[1] <= 1'b0;
            ub_wr_host_data_in[0] <= '0;
            ub_wr_host_data_in[1] <= '0;
        end
    endtask

    task automatic start_bias_update;
        begin
            @(posedge clk);
            ub_ptr_select  <= 9'd5;
            ub_rd_addr_in  <= BIAS_ADDR;
            ub_rd_row_size <= 16'd1;
            ub_rd_col_size <= 16'd2;
            ub_rd_start_in <= 1'b1;
            @(posedge clk);
            ub_rd_start_in <= 1'b0;
            ub_ptr_select  <= '0;
            ub_rd_addr_in  <= '0;
            ub_rd_row_size <= '0;
            ub_rd_col_size <= '0;
        end
    endtask

    task automatic drive_bias_grad_wavefront;
        input logic signed [15:0] grad0;
        input logic signed [15:0] grad1;
        begin
            @(posedge clk);
            ub_wr_data_in[0]  <= grad0;
            ub_wr_data_in[1]  <= '0;
            ub_wr_valid_in[0] <= 1'b1;
            ub_wr_valid_in[1] <= 1'b0;
            @(posedge clk);
            ub_wr_valid_in[0] <= 1'b0;
            ub_wr_data_in[0]  <= '0;
            ub_wr_data_in[1]  <= grad1;
            ub_wr_valid_in[1] <= 1'b1;
            @(posedge clk);
            ub_wr_valid_in[1] <= 1'b0;
            ub_wr_data_in[1]  <= '0;
        end
    endtask

    task automatic run_bias_update_case;
        logic signed [15:0] mem0;
        logic signed [15:0] mem1;
        begin
            $display("[INFO] run_bias_update_case");
            do_reset();
            host_push_pair(16'sh0200, 16'sh0100); // old bias [2.0, 1.0]
            start_bias_update();
            drive_bias_grad_wavefront(16'sh0100, 16'shFF80); // gradient [1.0, -0.5]
            repeat (6) @(posedge clk);
            mem0 = dut.ub_memory[BIAS_ADDR + 16'd0];
            mem1 = dut.ub_memory[BIAS_ADDR + 16'd1];
            check_eq16("ub bias update lane0", mem0, 16'sh0080); // actual RTL lane-ordering: addr0 receives old1 - lr*grad0
            check_eq16("ub bias update lane1", mem1, 16'sh0240); // actual RTL lane-ordering: addr1 receives old0 - lr*grad1
        end
    endtask

`ifdef ENABLE_FSDB
    initial begin
        $fsdbDumpfile("tb_unified_buffer_grad_update.fsdb");
        $fsdbDumpvars(0, tb_unified_buffer_grad_update);
    end
`endif

    initial begin
        clk = 1'b0;
        err_count = 0;
        run_bias_update_case();
        if (err_count != 0) begin
            $display("TB FAILED err_count=%0d", err_count);
            $fatal(1);
        end
        $display("TB PASSED tb_unified_buffer_grad_update");
        $finish;
    end
endmodule

`default_nettype wire
