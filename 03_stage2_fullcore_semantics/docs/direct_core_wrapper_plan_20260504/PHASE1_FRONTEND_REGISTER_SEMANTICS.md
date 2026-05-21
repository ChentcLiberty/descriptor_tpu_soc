## Phase 1 - Frontend Register Semantics Extract

### 目的

这份文档把当前 `tpu_stage2_fullcore_bridge` 实际使用到的 frontend 寄存器语义抽出来，作为后续 direct-core wrapper 去掉 AXI-Lite frontend 的替换依据。

### 当前 bridge 实际使用到的 frontend 寄存器

#### `TPU_FE_REG_LEAK` (`0x050`)

用途：写入 `vpu_leak_factor`。

当前来源：

- 默认写 `0`
- 当 `flags[24]=1` 且 `desc_scratch_addr != 0` 时，从 shared SRAM 额外读取 1 个 word，其低 16 bit 作为 Q8.8 leak factor

后续 direct-core 替代：

- 直接驱动 `tpu.v` 的 `vpu_leak_factor_in`

#### `TPU_FE_REG_INV_BATCH` (`0x054`)

用途：写入 `inv_batch_size_times_two`。

当前来源：

- bridge 固定写 `0`

后续 direct-core 替代：

- 直接驱动 `tpu.v` 的 `inv_batch_size_times_two_in`
- 当前前向子集可以继续固定为 `0`

#### `TPU_FE_REG_LR` (`0x058`)

用途：写入 `learning_rate`。

当前来源：

- bridge 固定写 `0`

后续 direct-core 替代：

- 直接驱动 `tpu.v` 的 `learning_rate_in`
- 当前前向子集可以继续固定为 `0`

#### `TPU_FE_REG_UB_DATA0` (`0x020`)
#### `TPU_FE_REG_UB_DATA1` (`0x028`)
#### `TPU_FE_REG_UB_PUSH` (`0x024`)

用途：向 unified buffer 的 host-write 入口装载数据。

当前写入顺序：

1. 写 `X0` 到 `UB_DATA0`，再 `UB_PUSH=1`
2. 写 `X1` 到 `UB_DATA0`，再 `UB_PUSH=1`
3. 写 `W00` 到 `UB_DATA0`，写 `W01` 到 `UB_DATA1`，再 `UB_PUSH=3`
4. 写 `W10` 到 `UB_DATA0`，写 `W11` 到 `UB_DATA1`，再 `UB_PUSH=3`
5. 写 `B0` 到 `UB_DATA0`，写 `B1` 到 `UB_DATA1`，再 `UB_PUSH=3`

语义上对应：

- `X` 的 2 个 lane 通过 host-write 顺序写到 UB input 区
- `W` 的 4 个 scalar 以两次双-lane push 写到 UB weight 区
- `B` 的 2 个 scalar 以一次双-lane push 写到 UB bias 区

后续 direct-core 替代：

- 本地直接驱动 `ub_wr_host_data_in[*]`
- 本地直接驱动 `ub_wr_host_valid_in[*]`
- 在每个 output-word / tile 起始处显式脉冲 `ub_wr_ptr_restore_in`，替代当前 `start_pulse` 带来的指针恢复语义

#### `TPU_FE_REG_IMEM_ADDR` (`0x030`)
#### `TPU_FE_REG_IMEM_W0` (`0x034`)
#### `TPU_FE_REG_IMEM_WE` (`0x040`)
#### `TPU_FE_REG_IMEM_LEN` (`0x044`)

用途：往 reference frontend 内部 IMEM 写 micro-sequence。

当前语义：

- bridge 会依次写入 9 条指令
- `IMEM_LEN=9`
- 然后通过 `CTRL.start` 启动 sequencer

后续 direct-core 替代：

- 不再需要这些寄存器
- 由 wrapper 本地状态机直接按同样顺序驱动 core 控制信号

#### `TPU_FE_REG_CTRL` (`0x000`)

当前仅使用两种值：

- `CTRL.start = 2`：启动 9-step IMEM 序列
- `CTRL.step  = 1`：对最终 `UB Y` readback 指令执行一次单步

后续 direct-core 替代：

- `start` 由 wrapper 本地状态机入口替代
- `step` 由 wrapper 本地 readback 状态替代

#### `TPU_FE_REG_STATUS` (`0x004`)

当前用途：

- bridge 轮询 `STATUS[1:0]`
- 当 `busy=0 && running=0` 时，认为当前 IMEM 序列执行完成

后续 direct-core 替代：

- 由 wrapper 本地状态机直接掌握“当前 tile 执行完成”的时点
- 不再经过 AXI-Lite 读寄存器

### 当前 bridge 没有实际使用的 frontend 能力

当前 bridge 并没有使用：

- `UB_WR_HOST` 32-bit 指令编码路径
- 更一般的 step-by-step 指令序列拼装
- 训练相关寄存器组合
- 更复杂的 IMEM 控制流

### 对 direct-core 改造的结论

当前前向子集真正需要本地化的 frontend 语义只有 5 类：

1. `host write into UB`
2. `set leak / inv_batch / lr`
3. `issue UB read controls`
4. `wait for tile execution completion`
5. `issue final UB Y readback`

也就是说，direct-core 改造并不需要完整复刻 `tpu_frontend_axil`，只需要提取这 5 类最小语义。
