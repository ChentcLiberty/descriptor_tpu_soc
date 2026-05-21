+incdir+./core
+incdir+./bridge
+incdir+./reference

./core/fixedpoint.sv
./core/gradient_descent.sv
./core/bias_child.sv
./core/bias_parent.sv
./core/leaky_relu_child.sv
./core/leaky_relu_parent.sv
./core/leaky_relu_derivative_child.sv
./core/leaky_relu_derivative_parent.sv
./core/loss_child.sv
./core/loss_parent.sv
./core/pe.sv
./core/systolic.sv
./core/unified_buffer_v3.sv
./core/vpu.sv
./core/tpu.sv

./reference/control_unit.sv
./reference/tpu_frontend_axil.sv
./reference/tpu_soc.sv

./bridge/tinytpu_frontend_pkg.sv
./bridge/tpu_frontend_local.sv
./bridge/tpu_stage2_fullcore_bridge.sv
./bridge/tpu_stage2_fullcore_wrapper.sv
./bridge/tpu_stage2_real_wrapper.v
