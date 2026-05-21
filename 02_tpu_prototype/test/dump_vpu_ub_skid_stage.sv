module dump();
integer i;
initial begin
  $dumpfile("waveforms/vpu_ub_skid_stage.vcd");
  $dumpvars(0, vpu_ub_skid_stage);

  for (i = 0; i < 2; i = i + 1) begin
    $dumpvars(0, vpu_ub_skid_stage.hold_data[i]);
    $dumpvars(0, vpu_ub_skid_stage.hold_valid[i]);
    $dumpvars(0, vpu_ub_skid_stage.data_in[i]);
    $dumpvars(0, vpu_ub_skid_stage.valid_in[i]);
    $dumpvars(0, vpu_ub_skid_stage.data_out[i]);
    $dumpvars(0, vpu_ub_skid_stage.valid_out[i]);
  end
end
endmodule
