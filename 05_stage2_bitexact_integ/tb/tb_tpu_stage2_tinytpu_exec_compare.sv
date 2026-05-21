`timescale 1ns / 1ps
`default_nettype none

module tb_tpu_stage2_tinytpu_exec_compare;
    localparam integer TPU_DESC_F_RELU_BIT          = 0;
    localparam integer TPU_DESC_F_TILE2X2_Q8_8_BIT = 16;

    reg clk;
    reg rst_n;
    reg clear_pulse;
    reg exec_start_pulse;
    reg [31:0] net_id;
    reg [31:0] flags;
    reg [31:0] input_words;
    reg [31:0] output_words;
    reg input_word_valid;
    reg [31:0] input_word;
    reg param_word_valid;
    reg [31:0] param_word;
    reg [31:0] output_word_index;

    wire exec_busy;
    wire exec_done;
    wire exec_error;
    wire [31:0] exec_output_word;
    wire [31:0] ref_output_word;
    wire [31:0] exec_input_count;
    wire [31:0] exec_param_count;
    wire [31:0] ref_input_count;
    wire [31:0] ref_param_count;

    reg [31:0] case_input_mem [0:15];
    reg [31:0] case_param_mem [0:127];
    integer case_input_count;
    integer case_output_count;
    integer case_param_count;
    integer err_count;
    integer timeout_count;
    integer i;

    tpu_stage2_tinytpu_exec dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear_pulse(clear_pulse),
        .exec_start_pulse(exec_start_pulse),
        .net_id(net_id),
        .flags(flags),
        .input_words(input_words),
        .output_words(output_words),
        .input_word_valid(input_word_valid),
        .input_word(input_word),
        .param_word_valid(param_word_valid),
        .param_word(param_word),
        .output_word_index(output_word_index),
        .exec_busy(exec_busy),
        .exec_done(exec_done),
        .exec_error(exec_error),
        .input_word_count(exec_input_count),
        .input_checksum(),
        .input_last_word(),
        .param_word_count(exec_param_count),
        .param_checksum(),
        .param_last_word(),
        .output_word(exec_output_word)
    );

    tpu_mlp_compute_stub ref_u (
        .clk(clk),
        .rst_n(rst_n),
        .clear_pulse(clear_pulse),
        .net_id(net_id),
        .flags(flags),
        .input_words(input_words),
        .input_word_valid(input_word_valid),
        .input_word(input_word),
        .param_word_valid(param_word_valid),
        .param_word(param_word),
        .output_word_index(output_word_index),
        .input_word_count(ref_input_count),
        .input_checksum(),
        .input_last_word(),
        .param_word_count(ref_param_count),
        .param_checksum(),
        .param_last_word(),
        .output_word(ref_output_word)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (dut.ub_rd_input_valid_out_0 || dut.ub_rd_input_valid_out_1 ||
            dut.ub_rd_weight_valid_out_0 || dut.ub_rd_weight_valid_out_1 ||
            dut.sys_valid_out_21 || dut.sys_valid_out_22 ||
            dut.vpu_valid_out_1 || dut.vpu_valid_out_2) begin
            $display("[DBG] t=%0t st=%0d in_v=%0b%0b in_d=%h/%h w_v=%0b%0b w_d=%h/%h sys_v=%0b%0b sys=%h/%h vpu_v=%0b%0b vpu=%h/%h act=%h,%h,%h,%h",
                $time,
                dut.exec_state_reg,
                dut.ub_rd_input_valid_out_1,
                dut.ub_rd_input_valid_out_0,
                dut.ub_rd_input_data_out_1,
                dut.ub_rd_input_data_out_0,
                dut.ub_rd_weight_valid_out_1,
                dut.ub_rd_weight_valid_out_0,
                dut.ub_rd_weight_data_out_1,
                dut.ub_rd_weight_data_out_0,
                dut.sys_valid_out_22,
                dut.sys_valid_out_21,
                dut.sys_data_out_22,
                dut.sys_data_out_21,
                dut.vpu_valid_out_2,
                dut.vpu_valid_out_1,
                dut.vpu_data_out_2,
                dut.vpu_data_out_1,
                dut.real_tpu_u.systolic_inst.pe11.weight_reg_active,
                dut.real_tpu_u.systolic_inst.pe12.weight_reg_active,
                dut.real_tpu_u.systolic_inst.pe21.weight_reg_active,
                dut.real_tpu_u.systolic_inst.pe22.weight_reg_active);
        end
    end

    task automatic drive_idle;
        begin
            @(negedge clk);
            input_word_valid = 1'b0;
            param_word_valid = 1'b0;
            input_word = 32'd0;
            param_word = 32'd0;
            exec_start_pulse = 1'b0;
            clear_pulse = 1'b0;
        end
    endtask

    task automatic pulse_clear;
        begin
            @(negedge clk);
            clear_pulse = 1'b1;
            input_word_valid = 1'b0;
            param_word_valid = 1'b0;
            exec_start_pulse = 1'b0;
            @(negedge clk);
            clear_pulse = 1'b0;
        end
    endtask

    task automatic send_input_word(input [31:0] word);
        begin
            @(negedge clk);
            input_word = word;
            input_word_valid = 1'b1;
            param_word = 32'd0;
            param_word_valid = 1'b0;
            exec_start_pulse = 1'b0;
        end
    endtask

    task automatic send_param_word(input [31:0] word);
        begin
            @(negedge clk);
            input_word = 32'd0;
            input_word_valid = 1'b0;
            param_word = word;
            param_word_valid = 1'b1;
            exec_start_pulse = 1'b0;
        end
    endtask

    task automatic pulse_start;
        begin
            @(negedge clk);
            input_word_valid = 1'b0;
            param_word_valid = 1'b0;
            exec_start_pulse = 1'b1;
            @(negedge clk);
            exec_start_pulse = 1'b0;
        end
    endtask

    task automatic feed_case_streams;
        begin
            for(i = 0; i < case_input_count; i = i + 1) begin
                send_input_word(case_input_mem[i]);
            end
            for(i = 0; i < case_param_count; i = i + 1) begin
                send_param_word(case_param_mem[i]);
            end
            drive_idle();
        end
    endtask

    task automatic compare_outputs(input string case_name);
        begin
            for(i = 0; i < case_output_count; i = i + 1) begin
                output_word_index = i[31:0];
                @(posedge clk);
                if(exec_output_word !== ref_output_word) begin
                    $display("[FAIL] %s out[%0d] exp=%08h got=%08h", case_name, i, ref_output_word, exec_output_word);
                    err_count = err_count + 1;
                end else begin
                    $display("[PASS] %s out[%0d] = %08h", case_name, i, exec_output_word);
                end
            end
        end
    endtask

    task automatic wait_done_or_timeout(input string case_name);
        begin
            timeout_count = 0;
            while((!exec_done) && (!exec_error) && (timeout_count < 400)) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            if(exec_error) begin
                $display("[FAIL] %s exec_error asserted", case_name);
                err_count = err_count + 1;
            end else if(!exec_done) begin
                $display("[FAIL] %s timeout waiting for exec_done", case_name);
                err_count = err_count + 1;
            end
        end
    endtask

    task automatic run_case(input string case_name);
        begin
            $display("\n[CASE] %s", case_name);
            pulse_clear();
            feed_case_streams();
            @(posedge clk);
            if((exec_input_count != case_input_count[31:0]) || (ref_input_count != case_input_count[31:0])) begin
                $display("[FAIL] %s input_count exec=%0d ref=%0d exp=%0d", case_name, exec_input_count, ref_input_count, case_input_count);
                err_count = err_count + 1;
            end
            if((exec_param_count != case_param_count[31:0]) || (ref_param_count != case_param_count[31:0])) begin
                $display("[FAIL] %s param_count exec=%0d ref=%0d exp=%0d", case_name, exec_param_count, ref_param_count, case_param_count);
                err_count = err_count + 1;
            end
            pulse_start();
            wait_done_or_timeout(case_name);
            compare_outputs(case_name);
            drive_idle();
        end
    endtask

    task automatic load_case_single_tile_no_relu;
        begin
            net_id = 32'd0;
            flags = (32'd1 << TPU_DESC_F_TILE2X2_Q8_8_BIT);
            input_words = 32'd1;
            output_words = 32'd2;
            case_input_count = 1;
            case_output_count = 2;
            case_param_count = case_output_count * ((case_input_count << 1) + 1);

            case_input_mem[0] = 32'h0200_0100;

            case_param_mem[0] = 32'h0080_0100;
            case_param_mem[1] = 32'h0040_ff00;
            case_param_mem[2] = 32'hff80_0040;

            case_param_mem[3] = 32'h0100_0000;
            case_param_mem[4] = 32'hff00_0080;
            case_param_mem[5] = 32'h0000_0000;
        end
    endtask

    task automatic load_case_multi_tile_no_relu;
        begin
            net_id = 32'd1;
            flags = (32'd1 << TPU_DESC_F_TILE2X2_Q8_8_BIT);
            input_words = 32'd3;
            output_words = 32'd2;
            case_input_count = 3;
            case_output_count = 2;
            case_param_count = case_output_count * ((case_input_count << 1) + 1);

            case_input_mem[0] = 32'h0100_0200;
            case_input_mem[1] = 32'hfe00_0300;
            case_input_mem[2] = 32'h0080_ff00;

            case_param_mem[0]  = 32'h0000_0100;
            case_param_mem[1]  = 32'h0100_0000;
            case_param_mem[2]  = 32'h0000_0100;
            case_param_mem[3]  = 32'h0100_0000;
            case_param_mem[4]  = 32'h0000_0100;
            case_param_mem[5]  = 32'h0100_0000;
            case_param_mem[6]  = 32'h0000_0000;

            case_param_mem[7]  = 32'hff00_0080;
            case_param_mem[8]  = 32'h0040_0000;
            case_param_mem[9]  = 32'h0080_ff00;
            case_param_mem[10] = 32'h0000_0040;
            case_param_mem[11] = 32'h0100_0080;
            case_param_mem[12] = 32'hff80_0000;
            case_param_mem[13] = 32'h0040_ff00;
        end
    endtask

    task automatic load_case_multi_tile_relu;
        begin
            net_id = 32'd2;
            flags = (32'd1 << TPU_DESC_F_TILE2X2_Q8_8_BIT) | (32'd1 << TPU_DESC_F_RELU_BIT);
            input_words = 32'd2;
            output_words = 2;
            case_input_count = 2;
            case_output_count = 2;
            case_param_count = case_output_count * ((case_input_count << 1) + 1);

            case_input_mem[0] = 32'hff00_0100;
            case_input_mem[1] = 32'h0100_ff00;

            case_param_mem[0] = 32'hff00_0100;
            case_param_mem[1] = 32'h0100_ff00;
            case_param_mem[2] = 32'h0080_ff80;
            case_param_mem[3] = 32'hff00_0100;
            case_param_mem[4] = 32'h0100_ff00;
            case_param_mem[5] = 32'hff80_0080;
            case_param_mem[6] = 32'h0000_0000;

            case_param_mem[7]  = 32'h0100_ff00;
            case_param_mem[8]  = 32'hff00_0100;
            case_param_mem[9]  = 32'hff00_0100;
            case_param_mem[10] = 32'h0100_ff00;
            case_param_mem[11] = 32'h0000_0000;
            case_param_mem[12] = 32'h0000_0000;
            case_param_mem[13] = 32'h0000_0000;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        clear_pulse = 1'b0;
        exec_start_pulse = 1'b0;
        net_id = 32'd0;
        flags = 32'd0;
        input_words = 32'd0;
        output_words = 32'd0;
        input_word_valid = 1'b0;
        input_word = 32'd0;
        param_word_valid = 1'b0;
        param_word = 32'd0;
        output_word_index = 32'd0;
        err_count = 0;

        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        load_case_single_tile_no_relu();
        run_case("single_tile_no_relu");

        load_case_multi_tile_no_relu();
        run_case("multi_tile_no_relu");

        load_case_multi_tile_relu();
        run_case("multi_tile_relu");

        if(err_count == 0) begin
            $display("\n[PASS] tb_tpu_stage2_tinytpu_exec_compare complete");
        end else begin
            $display("\n[FAIL] tb_tpu_stage2_tinytpu_exec_compare err_count=%0d", err_count);
        end
        $finish;
    end
endmodule

`default_nettype wire
