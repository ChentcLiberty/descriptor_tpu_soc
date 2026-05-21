module dump();
integer i;
initial begin
  $dumpfile("waveforms/tpu.vcd");
  $dumpvars(0, tpu);
  // iverilog 不自动 dump 数组，需要显式逐元素 dump
  for (i = 0; i < 32; i = i + 1) begin
    $dumpvars(0, tpu.ub_inst.ub_memory[i]);
  end
end
endmodule