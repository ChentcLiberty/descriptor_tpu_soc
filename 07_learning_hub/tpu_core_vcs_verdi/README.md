# TPU Core VCS/Verdi Verification

这套目录专门做 `frontend_local -> tpu core` 和 `tpu core / unified_buffer` 的直接验证，目标是把下面三类问题分开看清：

1. `frontend_local` 状态机怎样驱动 `UB/systolic/PE/VPU`
2. 推理和训练在 VPU 路径、数据流、控制流上的区别
3. 训练里的 backward / gradient-update 在核心内部是怎么走的

## 目录内容

- `tb_frontend_tpu_core_modes.sv`
  - 例化 `tpu_frontend_local + tpu`
  - 顺序跑两种 tile：
    - `1100` forward/inference
    - `1111` transition/training-output-layer
  - 验证 frontend step 顺序、UB 读口、systolic 输出、VPU 各级 valid/data
- `tb_tpu_core_backward_bias_update.sv`
  - 直连 `tpu`
  - 验证 `0001` backward 路径
  - 重点看 `H` 对 leaky-relu-derivative 的门控
- `tb_unified_buffer_grad_update.sv`
  - 直连 `unified_buffer`
  - 验证训练里的 `ptr_sel=5` bias-update 写回链
- `tb_tpu_training_timing_flow.sv`
  - 只例化 `tpu`
  - 顺序跑 4 个阶段：
    - `1100` forward
    - `1111` transition / output-layer training
    - `0001` backward
    - `ptr_sel=5` bias-update
  - 重点验证训练时序、控制流和核心模块交互，不经过 `frontend_local`

## 运行方法

```bash
cd /home/jjt/soc/my_soc/tpu_soc_learning_hub_20260505/tpu_core_vcs_verdi
./run_vcs_tpu_core_suite.sh
```

或分开跑：

```bash
./run_vcs_frontend_tpu_core_modes.sh
./run_vcs_tpu_core_backward_bias_update.sh
./run_vcs_unified_buffer_grad_update.sh
./run_vcs_tpu_training_timing_flow.sh
```

对应 Verdi：

```bash
./run_verdi_frontend_tpu_core_modes.sh
./run_verdi_tpu_core_backward_bias_update.sh
./run_verdi_unified_buffer_grad_update.sh
./run_verdi_tpu_training_timing_flow.sh
```

## 已验证结果

### 1. `tb_frontend_tpu_core_modes.sv`

输出目录：
- `sim_build_vcs_frontend_tpu_core_modes`

波形：
- `sim_build_vcs_frontend_tpu_core_modes/tb_frontend_tpu_core_modes.fsdb`

验证点：
- `1100` forward
  - frontend 顺序：`WEIGHT -> SWITCH -> BIAS -> INPUT -> WAIT`
  - systolic 最终两 lane 输出：`0x0100`, `0xFF00`
  - VPU 最终输出：`0x0100`, `0x0000`
  - 说明：第二 lane 经 ReLU 被截到 `0`
- `1111` transition
  - frontend 顺序：`WEIGHT -> SWITCH -> Y -> BIAS -> INPUT -> WAIT`
  - systolic 最终两 lane 输出：`0x0100`, `0x0200`
  - VPU 最终输出：`0x00C0`, `0x0080`
  - 对应 `(H-Y)` 路径输出
  - 注意：`Y` 在当前 UB `ptr_sel=3` 读法下有 lane 反序，所以 testbench 按实际 RTL 的 Y-lane 顺序 preload

### 2. `tb_tpu_core_backward_bias_update.sv`

输出目录：
- `sim_build_vcs_tpu_core_backward_bias_update`

波形：
- `sim_build_vcs_tpu_core_backward_bias_update/tb_tpu_core_backward_bias_update.fsdb`

验证点：
- `0001` backward 路径
- `H` 的符号控制 leaky-relu-derivative 是否透传 / 乘 leak
- 当前 RTL 观测到的最终 VPU 输出：
  - lane0 = `0x0040`
  - lane1 = `0x0100`
- 说明：这表明当前 `H` 的 lane 使用顺序在这条路径上是反过来的
  - 一个 lane 被 leak 因子 `0x0040` 缩放
  - 另一个 lane 直接透传

### 3. `tb_unified_buffer_grad_update.sv`

输出目录：
- `sim_build_vcs_unified_buffer_grad_update`

波形：
- `sim_build_vcs_unified_buffer_grad_update/tb_unified_buffer_grad_update.fsdb`

验证点：
- `ptr_sel=5` bias-update
- 使用两拍 gradient wavefront，而不是两 lane 同拍
- 最终验证 UB 内存更新：
  - `addr0 = 0x0080`
  - `addr1 = 0x0240`
- 说明：这是当前 RTL 的实际 bias-update lane/addr 对应关系
  - 第一拍 gradient 会更新 `addr0`，但对应的 old-value 来源是反 lane 的
  - 第二拍 gradient 会更新 `addr1`

### 4. `tb_tpu_training_timing_flow.sv`

输出目录：
- `sim_build_vcs_tpu_training_timing_flow`

波形：
- `sim_build_vcs_tpu_training_timing_flow/tb_tpu_training_timing_flow.fsdb`

验证点：
- `1100` forward
  - `weight_valid -> input_valid -> sys_valid -> bias_valid -> lr_valid -> vpu_valid`
- `1111` transition
  - `weight_valid -> Y_valid -> input_valid -> sys_valid -> bias_valid -> lr_valid -> loss_valid -> lr_d_valid -> vpu_valid`
- `0001` backward
  - `weight_valid -> H_valid -> input_valid -> sys_valid -> lr_d_valid -> vpu_valid`
- `ptr_sel=5` bias-update
  - 在 `0001` 产生梯度的同时，UB 内部 `gradient_descent` 吃到 `vpu_valid/data`
  - 观测 `grad_descent_valid_in`、`grad_descent_done_out` 和最终 `ub_memory`

这个 testbench 是 TPU-only 的训练时序入口：
- 不经过 `frontend_local`
- 直接驱动 `ub_rd_start_in / ub_ptr_select / sys_switch_in / vpu_data_pathway`
- 更适合看训练里的时序和控制流

## 算法和硬件路径对应

### 推理 forward

算法：

```text
Z = W * X + b
H = ReLU(Z) 或 LeakyReLU(Z)
```

当前硬件：
- `frontend_local`
  - `step0` 读 weight
  - `step4` `sys_switch`
  - `step7` 读 bias
  - `step8` 读 input
- `tpu`
  - `UB` 把 weight 送到 systolic 顶部
  - `UB` 把 input 送到 systolic 左侧
  - `PE` 做 Q8.8 MAC
  - `VPU 1100` 做 `sys -> bias -> lr/relu`

关键控制信号：
- `tile_step_idx`
- `ub_rd_start_out`
- `ub_ptr_sel_out`
- `sys_switch_out`
- `vpu_data_pathway_out=1100`

### 训练输出层 transition

算法：

```text
H = act(WX + b)
dL/dH = (2/N) * (H - Y)
dL/dZ = dL/dH * act'(H)
```

当前硬件：
- `frontend_local`
  - `step7` 先读 `Y`
  - `step8` 再读 `bias`
  - `step9` 再读 `input`
- `VPU 1111`
  - `bias`
  - `leaky_relu`
  - `loss_parent` 计算 `(2/N)*(H-Y)`
  - `leaky_relu_derivative_parent` 计算 `dL/dZ`

关键控制信号：
- `ub_ptr_sel_out = TPU_FE_PTR_Y`
- `vpu_data_pathway_out=1111`
- `dut_tpu.vpu_inst.loss_valid_1_out/2_out`
- `dut_tpu.vpu_inst.lr_d_valid_1_out/2_out`

### 训练 hidden-layer/backward

算法：

```text
dL/dZ = dL/dH * act'(H)
```

当前硬件：
- `tpu` 直连 `0001`
- systolic 输出作为 `dL/dH`
- `H` 从 UB `ptr_sel=4` 读入
- `VPU 0001` 只走 `lr_d` 路径

关键控制信号：
- `ub_ptr_select = 4` 读 `H`
- `vpu_data_pathway = 0001`
- `dut.vpu_inst.lr_d_valid_1_out/2_out`

### 训练参数更新

算法：

```text
value_new = value_old - lr * grad
```

当前硬件：
- 在 `unified_buffer` 内通过 `gradient_descent` 实现
- bias update 用 `ptr_sel=5`
- weight update 预留 `ptr_sel=6`
- 当前这套验证目录只把 `ptr_sel=5` 的 bias-update 路径单独打通了

关键控制信号：
- `ub_ptr_select = 5`
- `ub_wr_data_in[*]`
- `ub_wr_valid_in[*]`
- `dut.grad_descent_valid_in[*]`
- `dut.value_old_in[*]`
- `dut.value_updated_out[*]`

## Verdi 建议先看哪些信号

### `tb_frontend_tpu_core_modes.sv`

`frontend`
- `dut_frontend.exec_state`
- `dut_frontend.tile_step_idx`
- `dut_frontend.ub_rd_start_out`
- `dut_frontend.ub_ptr_sel_out`
- `dut_frontend.ub_rd_addr_out`
- `dut_frontend.sys_switch_out`
- `dut_frontend.vpu_data_pathway_out`

`UB/systolic`
- `dut_tpu.ub_rd_weight_valid_out_0/1`
- `dut_tpu.ub_rd_input_valid_out_0/1`
- `dut_tpu.sys_valid_out_21/22`
- `dut_tpu.sys_data_out_21/22`
- `dut_tpu.systolic_inst.pe11.weight_reg_inactive`
- `dut_tpu.systolic_inst.pe11.weight_reg_active`
- `dut_tpu.systolic_inst.pe21.pe_psum_out`
- `dut_tpu.systolic_inst.pe22.pe_psum_out`

`VPU`
- `dut_tpu.vpu_inst.bias_valid_1_out/2_out`
- `dut_tpu.vpu_inst.lr_valid_1_out/2_out`
- `dut_tpu.vpu_inst.loss_valid_1_out/2_out`
- `dut_tpu.vpu_inst.lr_d_valid_1_out/2_out`
- `dut_tpu.vpu_data_out_1/2`
- `dut_tpu.vpu_valid_out_1/2`

### `tb_tpu_core_backward_bias_update.sv`

- `dut.ub_inst.ub_rd_H_valid_out_0/1`
- `dut.vpu_inst.lr_d_valid_1_out/2_out`
- `dut.vpu_inst.lr_d_H_in_1/2`
- `dut.vpu_data_out_1/2`
- `dut.vpu_valid_out_1/2`

### `tb_unified_buffer_grad_update.sv`

- `dut.rd_grad_bias_time_counter`
- `dut.rd_grad_bias_started`
- `dut.rd_grad_bias_value_phase`
- `dut.grad_descent_valid_in[0/1]`
- `dut.value_old_in[0/1]`
- `dut.value_updated_out[0/1]`
- `dut.grad_descent_ptr`
- `dut.ub_memory[0]`
- `dut.ub_memory[1]`

## 结论

这套验证现在已经把三条关键链分开打通：
- `frontend -> UB -> systolic -> VPU` 的推理/transition
- `tpu` 直连的 `0001 backward`
- `unified_buffer` 的 `ptr_sel=5` bias-update

还没单独补的是：
- `ptr_sel=6` weight-update 的独立回归
- `bridge` 参与的整层训练调度

如果后面要继续，最自然的下一步就是补一个 `ptr_sel=6` 的 weight-update 单元级 testbench。
