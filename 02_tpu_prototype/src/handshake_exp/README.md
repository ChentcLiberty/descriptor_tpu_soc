# Handshake Experiment Variant

这个目录放的是独立于主线 RTL 的最小握手实验版本，目标不是一次性把整个 tiny-tpu 都改成可反压架构，而是先把 `VPU -> UB` 写回边界做成可观察、可实验的局部 `ready/valid` 闭环。

当前内容：

- `vpu_ub_skid_stage.sv`：一拍容量的本地 skid stage。
- `tpu_handshake.sv`：基于原始 `tpu.sv` 的实验顶层，新增 `wb_ready_in` 控制写回接收。

设计原则：

- 不修改原始 `src/tpu.sv`、`src/vpu.sv`、`src/unified_buffer_v3.sv`。
- 只在 `VPU -> UB` 边界增加局部保持能力。
- 如果 stall 期间只有一个待发 beat，这一级可以把 `data/valid` 锁住直到 `ready` 恢复。
- 如果 stall 期间连续来了第二个 beat，由于主线 VPU 还没有真正消费 `ready`，这一级会拉高 `overflow_out`，把“局部握手不等于全链路反压”明确暴露出来。

推荐命令：

- 单元级验证 skid stage：`make -f Makefile.handshake_exp test_vpu_ub_skid_stage_verify`
- 集成编译实验顶层：`make -f Makefile.handshake_exp compile_tpu_handshake`

重点观察：

- `wb_ready_in` 拉低后，`vpu_data_out_*` / `vpu_valid_out_*` 是否保持。
- `wb_ready_to_vpu_out` 是否表明这一级已经无法继续安全接收。
- `wb_overflow_out` 是否在连续 stall + 连续输入时拉高。

这套实验更适合面试里讲“我先验证现有接口边界，再逐步把握手机制补进去”，而不是夸大成“全系统已经支持 backpressure”。
