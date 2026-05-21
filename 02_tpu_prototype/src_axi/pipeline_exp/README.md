# Pipeline Experiment Variant

这个目录放的是独立于原始实现的实验代码，不修改 `src/` 下现有基线 RTL。

当前内容：

- `vpu_ub_pipe_stage.sv`：插在 `VPU -> UB` 之间的一拍寄存器。
- `tpu_pipeline.sv`：基于原始 `tpu.sv` 的顶层变体，保持原有端口风格和实例名，方便复用现有 cocotb testbench。

设计原则：

- 原始 `src/tpu.sv`、`src/vpu.sv`、`src/unified_buffer_v3.sv` 不改。
- 新变体只在 top-level 上插入 writeback pipeline。
- `systolic_inst`、`ub_inst`、`vpu_inst` 这些实例名保持不变，便于复用现有测试里的层级探针。

推荐用法：

- 基线版本：`make test_tpu_verify`
- Pipeline 实验版本：`make -f Makefile.pipeline_exp test_tpu_pipeline_verify`
- 两边都复用 `test/test_tpu_verification.py`，但实验版的 `vpu_valid_out_*` 会整体晚一拍。
- 对比时重点看：
  - `vpu_valid_out_*` 是否整体晚一拍
  - UB writeback 是否因此错位
  - 旧 testbench 是否会因为固定时序假设而报错
  - 综合时是否因一拍寄存器换来更高 Fmax

当前静态校验结果：

- `make -n -f Makefile.pipeline_exp test_tpu_pipeline_verify` 已确认会编译：
  - `src/unified_buffer_v3.sv`
  - `src/pipeline_exp/vpu_ub_pipe_stage.sv`
  - `src/pipeline_exp/tpu_pipeline.sv`
  - `test/dump_tpu_pipeline.sv`
- 本机当前缺 `iverilog` / `cocotb-config`，所以这里只完成了构建链路的静态检查，动态仿真需要在装好工具链后执行。
