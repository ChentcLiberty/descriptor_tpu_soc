module dump();
integer i;
initial begin
  $dumpfile("waveforms/tpu_handshake.vcd");
  $dumpvars(0, tpu_handshake);

  for (i = 0; i < 32; i = i + 1) begin
    $dumpvars(0, tpu_handshake.ub_inst.ub_memory[i]);
  end

  for (i = 0; i < 2; i = i + 1) begin
    $dumpvars(0, tpu_handshake.vpu_ub_skid_stage_inst.hold_data[i]);
    $dumpvars(0, tpu_handshake.vpu_ub_skid_stage_inst.hold_valid[i]);
  end
end
endmodule
