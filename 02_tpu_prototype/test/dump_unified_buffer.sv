module dump();
  initial begin
    $dumpfile("waveforms/unified_buffer.vcd");
    $dumpvars(0, unified_buffer);

    // Icarus VCD 无法 dump 端口级 unpacked array，通过 fixed.sv 中的 dbg_ wire 观察
    // 写入信号: dbg_wr_host_data_0/1, dbg_wr_host_valid_0/1
    //          dbg_wr_data_0/1, dbg_wr_valid_0/1
    // 这些由 $dumpvars(0, unified_buffer) 自动包含

    // 内部 unpacked array 需要手动展开
    $dumpvars(0, unified_buffer.ub_rd_input_data_out[0]);
    $dumpvars(0, unified_buffer.ub_rd_input_data_out[1]);
    $dumpvars(0, unified_buffer.ub_rd_input_valid_out[0]);
    $dumpvars(0, unified_buffer.ub_rd_input_valid_out[1]);
    $dumpvars(0, unified_buffer.ub_rd_weight_data_out[0]);
    $dumpvars(0, unified_buffer.ub_rd_weight_data_out[1]);
    $dumpvars(0, unified_buffer.ub_rd_weight_valid_out[0]);
    $dumpvars(0, unified_buffer.ub_rd_weight_valid_out[1]);
    $dumpvars(0, unified_buffer.ub_rd_bias_data_out[0]);
    $dumpvars(0, unified_buffer.ub_rd_bias_data_out[1]);
    $dumpvars(0, unified_buffer.ub_rd_Y_data_out[0]);
    $dumpvars(0, unified_buffer.ub_rd_Y_data_out[1]);
    $dumpvars(0, unified_buffer.ub_rd_H_data_out[0]);
    $dumpvars(0, unified_buffer.ub_rd_H_data_out[1]);

    // 梯度下降
    $dumpvars(0, unified_buffer.value_old_in[0]);
    $dumpvars(0, unified_buffer.value_old_in[1]);
    $dumpvars(0, unified_buffer.value_updated_out[0]);
    $dumpvars(0, unified_buffer.value_updated_out[1]);
    $dumpvars(0, unified_buffer.grad_descent_valid_in[0]);
    $dumpvars(0, unified_buffer.grad_descent_valid_in[1]);
    $dumpvars(0, unified_buffer.grad_descent_done_out[0]);
    $dumpvars(0, unified_buffer.grad_descent_done_out[1]);

    // memory 前 8 个地址
    $dumpvars(0, unified_buffer.ub_memory[0]);
    $dumpvars(0, unified_buffer.ub_memory[1]);
    $dumpvars(0, unified_buffer.ub_memory[2]);
    $dumpvars(0, unified_buffer.ub_memory[3]);
    $dumpvars(0, unified_buffer.ub_memory[4]);
    $dumpvars(0, unified_buffer.ub_memory[5]);
    $dumpvars(0, unified_buffer.ub_memory[6]);
    $dumpvars(0, unified_buffer.ub_memory[7]);
  end
endmodule
