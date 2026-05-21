module dump();
integer i;
initial begin
  $dumpfile("waveforms/tpu_pipeline.vcd");
  $dumpvars(0, tpu_pipeline);

  // iverilog 不自动 dump 数组，需要显式逐元素 dump
  for (i = 0; i < 32; i = i + 1) begin
    $dumpvars(0, tpu_pipeline.ub_inst.ub_memory[i]);
  end

  // 显式观察新增的一拍 writeback stage
  $dumpvars(0, tpu_pipeline.vpu_ub_pipe_stage_inst.data_out[0]);
  $dumpvars(0, tpu_pipeline.vpu_ub_pipe_stage_inst.data_out[1]);
  $dumpvars(0, tpu_pipeline.vpu_ub_pipe_stage_inst.valid_out[0]);
  $dumpvars(0, tpu_pipeline.vpu_ub_pipe_stage_inst.valid_out[1]);
end
endmodule
