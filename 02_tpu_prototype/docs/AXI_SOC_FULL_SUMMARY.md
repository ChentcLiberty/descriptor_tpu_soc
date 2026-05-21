# TinyTPU AXI-Lite SoC 端到端验证 — 完整工作总结

> 最近更新：2026-04-02
> 说明：下文保留了 2026-03-31 的 debug 过程记录，并在文首补充当前仓库的最新状态

---

## 0. 2026-04-02 当前状态更新

2026-04-02 对当前仓库重新执行了关键验证：

### 已复跑结果

1. `make test_tpu_soc_axil_e2e`
   - 结果：`PASS`
   - 关键结论：`41/41 PASS`
   - 覆盖范围：`H1 + dZ2 + dZ1 + UB 中更新后的 W1/B1/W2/B2`
2. `make test_tpu_soc_axil_train_convergence`
   - 结果：`PASS`
   - 关键结论：12 个 epoch 后，`loss 0.2529 -> 0.1777`
   - 最终预测：`(0, 1, 1, 0)`，即 XOR 全部分类正确

### 当前仓库可对外表述的项目状态

- AXI-Lite SoC 前端、寄存器写入、IMEM 装载和 sequencer 启动链路已经跑通
- 当前 `59` 条 IMEM 指令可以驱动 2x2 tiny-tpu 原型完成单次训练闭环
- 单次 e2e 闭环验证已经从早期的 `H1 6/8 PASS` 收敛到当前的 `41/41 PASS`
- 多 epoch 训练闭环在当前 XOR / Q8.8 / 2-layer MLP 配置下已验证可收敛

### 关于下文历史记录

下文第六到第八部分保留了 2026-03-31 的阶段性记录，其中提到的 `H1 col2 bias 对齐 bug` 在当前仓库中已经不再是现状。阅读时请以本节的 2026-04-02 更新为准，把后文当作 debug 历史而不是当前结论。

---

## 一、工作目标

在原始 `tiny-tpu`（testbench 直接驱动 RTL 端口）的基础上，实现一套完整的 **AXI-Lite SoC 接口层**，并通过 cocotb e2e 测试验证整个 MLP forward pass（H1 输出）与原始 testbench 一致。

整体架构：
```
cocotb (Python)
  └─ AXI-Lite Master
       └─ tpu_soc_top
            ├─ tpu_frontend_axil   ← AXI 解码 + sequencer
            └─ tpu_soc
                 ├─ tpu_frontend_axil (实例)
                 └─ tpu (原始 RTL 核)
                      ├─ systolic
                      ├─ vpu
                      └─ unified_buffer_v3
```

---

## 二、新增文件

| 文件 | 说明 |
|------|------|
| `src_axi/tpu_frontend_axil.sv` | AXI-Lite 解码、寄存器堆、sequencer、IMEM |
| `src_axi/tpu_soc.sv` | SoC 顶层，连接 frontend 和 TPU 核 |
| `src_axi/control_unit.sv` | 指令解码，输出 TPU 控制信号 |
| `compiler/scheduler.py` | 从 model_spec 生成 schedule（指令序列） |
| `compiler/encode_instrs.py` | 将 schedule 编码为 32-bit IMEM hex |
| `compiler/out/imem.hex` | 当前 MLP 2×2 的 IMEM（59 条指令） |
| `test/test_tpu_soc_axil_e2e.py` | cocotb e2e 测试：AXI 加载数据、启动 sequencer、比对 H1/dZ2/dZ1/UB update |

---

## 三、32-bit 指令格式

```
[31:24]  reserved (bit23=wait_after)
[22:19]  vpu_data_pathway (4-bit)
[18:16]  ptr_sel (3-bit)
[15]     ub_rd_transpose
[14:13]  ub_rd_col_size
[12:9]   ub_rd_row_size
[8:3]    ub_rd_addr
[2:0]    opcode: 000=NOP, 001=CONTROL, 010=UB_RD
```

**wait_after（bit23）**：该位置 1 时，sequencer 在 dispatch 本条指令后进入 SEQ_WAIT，等待 `vpu_drain`（vpu_valid 下降沿）才推进到下一条指令。

---

## 四、Sequencer 设计

```
SEQ_IDLE → (start_pulse) → SEQ_DISPATCH → SEQ_ADVANCE / SEQ_WAIT
                                                ↑          ↓
                                           ← vpu_drain ←─┘
```

- **SEQ_DISPATCH**：把 `imem[pc]` 发给 control_unit（`seq_instr_pulse=1` 持续 1 拍），同时更新 `vpu_pathway_reg`
- **SEQ_ADVANCE**：无需等待，立即推进 pc
- **SEQ_WAIT**：等 `vpu_drain = vpu_valid_prev & !vpu_valid_now`，才推进 pc
- **`needs_wait`**：由 IMEM 指令 bit[23]（`wait_after`）控制，而非隐式 ptr_sel 推断

---

## 五、Debug 过程详细记录

### Bug 1：UB host write 完全无效（wr_ptr 始终为 0）

**现象**：cocotb 写 UB_DATA + push 后，`ub_inst.wr_ptr` 不变，UB memory 全 0。

**根因**：Icarus Verilog 对 **unpacked array 类型的 output port** 的 `assign` 语句有 bug——`ub_wr_host_valid_out[0]` 始终是 X，导致 UB 无法采样到有效的 `wr_en`。

**修复**：
- `tpu_frontend_axil.sv`：把 `output logic ub_wr_host_valid_out [0:N-1]` 改为两个独立 scalar port：`ub_wr_host_valid_out_0`、`ub_wr_host_valid_out_1`
- `tpu_soc.sv`：用 scalar wire 接收，再用 `assign ub_wr_host_valid[0] = ...` 桥接到 `tpu.sv` 的 unpacked array 输入

---

### Bug 2：control_unit always_comb X 传播

**现象**：`cu_ub_valid[0]` 是 X，导致 `ub_wr_host_valid_out` 也是 X。

**根因**：Icarus 对 `always_comb` 内部的 constant part-select（`instruction[18:3]` 等）报 warning 并导致整个块 X。

**修复**：
```sv
// 把 always_comb 里的 part select 提取为顶层 assign
logic [5:0]  f_addr;   assign f_addr  = instruction[8:3];
logic [3:0]  f_row;    assign f_row   = instruction[12:9];
// ...
always @(*) begin  // 改为 always @(*)
```

---

### Bug 3：vpu_data_pathway 不持久

**现象**：systolic 输出 Z 经过 VPU 时，pathway=0（全关），H1 输出全为 0。

**根因**：`vpu_data_pathway` 从每条 IMEM 指令的 bits[22:19] 实时解码。当 `seq_instr_pulse=0`（两条指令间隙），`instr_to_cu=0`，pathway 变为 0，VPU 流水线断路。

而 systolic array 的输出在 dispatch stream_x 之后的**数个 cycle** 才出现，此时 pulse 早已清零。

**修复**：加 `vpu_pathway_reg`，在每次 UB_RD dispatch 时 latch：
```sv
if (seq_instr_pulse && seq_instr[2:0] == 3'b010)
    vpu_pathway_reg <= seq_instr[22:19];
assign vpu_data_pathway_out = vpu_pathway_reg;
```

---

### Bug 4：SWITCH 指令时序错误

**现象**：systolic array 输出全为 0（权重是 0）。

**根因**：scheduler 原来的顺序是 `load_w1 → stream_x → SWITCH → stream_b1`。SWITCH 在 stream_x 之后，但 stream_x（ptr_sel=0）原来有 needs_wait，导致 SWITCH 被阻塞到 vpu_drain 之后才执行——此时 systolic 已经用了全 0 的 active weight 计算完了。

另外即使调整顺序后，`load_w1 → SWITCH` 之间只有 2 个 cycle，权重还没完全 feed 进 shadow 寄存器（需要 row+col=4 个 cycle）。

**修复**：
1. 调整顺序：`load_w → NOP×4 → SWITCH → stream`
2. ptr_sel=0（input stream）不需要 wait，立即 advance

---

### Bug 5：needs_wait 逻辑消耗错误的 drain

**现象**：sequencer 在 `load_old_b2`（pc=17）永久卡住，`vpu_drain` 不再产生。

**根因**：原来 `needs_wait` 包含 ptr_sel=2（bias）。transition_layer2 的流程：
```
stream_h1(ptr_sel=0) → stream_b2(ptr_sel=2, wait) → 等 dZ2 drain
                                                         ↓
                                              load_old_b2(ptr_sel=5, wait) → 又等 drain
```
dZ2 的 vpu_valid 只产生一次 drain，被 stream_b2 的 wait 消耗掉了，load_old_b2 再等就永远没有 drain 了。

**修复**：改用 IMEM bit[23] 作为显式 `wait_after` 标记，只在真正需要等 drain 的指令上设置：
- `stream_b1`（forward_layer1 → 等 H1 drain）
- `load_old_b2`（transition_layer2 → 等 dZ2 drain）
- `load_old_b1`（backward_layer1 → 等 dZ1 drain）
- `load_old_w1/w2`（weight update → 等 dW drain）

---

### Bug 6：scheduler 缺 vpu_path 字段

**现象**：stream_b1 的 vpu_pathway=0000，H1 经过 VPU 时所有模块关闭（全 bypass），输出全 0。

**根因**：scheduler.py 里 `stream_b1`、`stream_b2`、`stream_y` 等指令没有传入 `vpu_path` 参数，默认编码为 0。原始 testbench 里 `vpu_data_pathway` 是持久寄存器（一次设置后保持），而 IMEM 方案里每条指令独立编码，必须显式指定。

**修复**：在 scheduler.py 里为所有 UB_RD 指令补全 `vpu_path`：

| 指令 | pathway | 含义 |
|------|---------|------|
| stream_x / stream_b1 | 1100 | bias + leaky_relu（forward layer 1）|
| stream_h1 / stream_b2 / stream_y / load_old_b2 | 1111 | bias + relu + loss + relu_d（layer 2 + loss）|
| stream_dz2 / stream_h1_for_derivative / load_old_b1 | 0001 | leaky_relu_derivative only |
| load_dz1 / load_old_w1/w2 | 0000 | 纯 systolic，VPU bypass |

---

## 六、阶段性测试结果与当前结论

### 2026-03-31 阶段性结果

当时 AXI 路径已经与原始 `test_tpu_verify` 的已知行为对齐，H1 结果仍停留在 `6/8 PASS`，对应 bug 见下一节历史问题记录。

### 2026-04-02 当前结果

#### 1. 单次 e2e 闭环

```
make test_tpu_soc_axil_e2e
=== Scoreboard: 41/41 PASS ===
```

检查范围：

- `H1[4x2]`
- `dZ2[4]`
- `dZ1[4x2]`
- `UB dZ2[4]`
- `UB dZ1[8]`
- `UB updated W1[4] / B1[2] / W2[2] / B2[1]`

#### 2. 多 epoch 训练闭环

```
make test_tpu_soc_axil_train_convergence
epoch 0:  ref loss=0.2529 pred=(0, 0, 1, 1)
epoch 12: hw  loss=0.1777 pred=(0, 1, 1, 0)
PASS
```

当前可以确认：

- 训练 loss 随 epoch 下降
- 最终 XOR 任务达到 `4/4` 正确分类
- 当前 AXI 路径不只是 forward 验证，而是训练闭环可运行

---

## 七、历史问题记录：H1 col2 时序偏移 bug（当前仓库已修复）

**位置**：`src_axi/unified_buffer_v3.sv`，`rd_bias_time_counter` 逻辑

**现象**：
- H1[1,1]：exp=0.609，got=0.277（≈exp/2）
- H1[3,1]：exp=0.699，got=0.367（≈exp/2）

**根因分析**：

在 2×2 systolic array 里，col1 和 col2 的输出**天然错开 1 cycle**（因为权重沿对角线 feed 进 PE，右列比左列晚 1 拍）。

UB 的 bias read 模块按固定节拍输出 B1：
```
t=0: B1[0] → lane0 bias
t=1: B1[0] + B1[1] → lane0 + lane1 bias（同一 cycle）
t=2: B1[1] → lane1 bias
```

而 systolic 输出时序：
```
t=0: col1[row0] 到达 VPU
t=1: col1[row1], col2[row0] 同时到达
t=2: col1[row2], col2[row1]
...
```

col2[row0] 在 t=1 到达，此时 B1[1] 已经按设计在 t=1 输出了，表面上对齐。但实际仿真中，`rd_bias_time_counter` 的初始化时机比 systolic 输出早 1 cycle，导致 B1[1] 在 col2 数据到来**之前**就已经输出完毕。col2 接收到的 bias 是 0 或者错位的值，而不是正确的 B1[1]。

结果：col2 的每行只叠加了约一半的 bias，输出约为正确值的一半。

**修复方向**：在 `unified_buffer_v3.sv` 里，对 lane1（col2）的 bias 输出增加 1 cycle 延迟，使其与 col2 的 systolic 输出对齐：
```sv
// rd_bias_time_counter 的 lane1 判断改为:
if (rd_bias_time_counter >= j+1 && ...)  // +1 补偿 col2 的天然延迟
```

或者在 bias_child.sv 里对 lane1 的输出加一个 pipeline register。

**历史影响**：此 bug 在当时的原始 `test_tpu.py` / `test_tpu_verify` 路径中同样存在，属于项目原有 RTL 问题，与 AXI 接口本身无关。

**当前说明（2026-04-02）**：当前仓库重新复跑 `make test_tpu_soc_axil_e2e` 时，`H1[4x2]` 已全部通过，因此这一节应视为历史 debug 记录，而不是当前遗留问题。

---

## 八、项目当前状态

| 模块 | 状态 | 备注 |
|------|------|------|
| PE | 验证通过 | `test_pe.py` |
| Systolic Array | 验证通过 | `test_systolic_boundary.py` |
| Unified Buffer | 验证通过 | `test_unified_buffer` / `test_ub_v2_verification` |
| AXI-Lite SoC 接口 | 验证通过 | `make test_tpu_soc_axil_e2e`，2026-04-02 复跑 `41/41 PASS` |
| forward pass | 验证通过 | `H1[4x2]` 在当前 e2e 中全部通过 |
| backward pass | 验证通过 | 当前 e2e 已检查 `dZ2` 和 `dZ1` |
| parameter update | 验证通过 | 当前 e2e 已检查 `UB updated W1/B1/W2/B2` |
| multi-epoch training | 验证通过 | `make test_tpu_soc_axil_train_convergence`，12 epoch 收敛到 XOR 正确分类 |
| 当前边界 | 仍需明确 | 当前结论适用于 `Q8.8 + 2x2 array + 2-layer MLP/XOR` 原型范围 |

---

## 九、后续工作建议

1. **扩大任务规模**：把当前 `2-layer MLP + XOR` 验证链路推广到更一般的 tile 映射和更大一点的样例网络。
2. **扩充训练回归**：在现有 12 epoch 收敛测试之外，补不同初始化、学习率和 corner case 的多组回归。
3. **补齐跨仿真器验证**：继续增加 VCS 回归，确认当前 Icarus 路径通过的训练闭环在另一套仿真器下也稳定可复现。
4. **继续做实现向优化**：沿 `docs/SYN_CODE_CHANGES.md`、`docs/CDC_IMPLEMENTATION_PLAN.md`、`docs/ECC_IMPLEMENTATION_PLAN.md` 推进 timing / CDC / ECC 方向的工程化工作。
5. **扩展指令编码**：利用当前 32-bit 格式中的 reserved 位，为 stride、mask 或更丰富的数据搬运语义留出空间。

