# TPU SoC ECC 实施文档

> 面向当前 `tpu-soc` 工程的 ECC 落地方案
> 目标：为关键存储体引入 1-bit 纠错 / 2-bit 检错（SECDED），优先覆盖 IMEM，再扩展到 Unified Buffer。

---

## 一、实施目标

当前系统中最值得做可靠性保护的对象有两个：

1. `IMEM`：存放 32-bit 指令
2. `Unified Buffer`：存放 16-bit 数据字（X/W/B/Y/H/gradient）

ECC 实施目标分两步：

- 第一步：先让 IMEM 具备 SECDED
- 第二步：再让 UB 具备 SECDED

核心原则：

1. **先做固定宽度实现**，不要一上来追求泛化参数化 ECC 框架。
2. **优先保持 Icarus/VCS 友好**，避免 packed struct array 之类不利于当前项目工具链的写法。
3. **ECC 不只是编码解码，还要有错误状态可观测性**。
4. **双 bit 错误先以“检测并上报”为主，不急着做复杂恢复策略**。

---

## 二、为什么建议先做 IMEM ECC

### 2.1 IMEM 是最适合的第一站

原因：

- 数据宽度固定：32 bit
- 存取路径清晰：AXI 写 -> sequencer 读 -> control unit 用
- 错误后果清晰：指令错误直接影响控制流
- 最容易做 error injection 和系统验证

### 2.2 为什么不先做 UB ECC

UB 也重要，但复杂度更高：

- 读写路径更多
- 数据类型更多
- 和 core 数据通路耦合更深
- 一旦加 ECC，read/writeback/update 路径都要适配

所以最合理顺序是：

1. IMEM ECC
2. UB ECC

---

## 三、编码方案选择

## 3.1 推荐方案：SECDED

即：

- Single Error Correction
- Double Error Detection

### 对 32-bit IMEM word

需要的校验位数量：

- Hamming parity bits：6
- overall parity：1
- 总共：7 bit

所以每条 IMEM 指令的存储形式建议为：

- data：32 bit
- ecc：7 bit

### 对 16-bit UB word

需要的校验位数量：

- Hamming parity bits：5
- overall parity：1
- 总共：6 bit

所以每个 UB word 建议为：

- data：16 bit
- ecc：6 bit

---

## 四、工程实现上的关键选择

## 4.1 不建议直接把存储体扩成单个大 packed word

例如：

- IMEM 不建议直接变成 `logic [38:0] imem [0:N-1]`
- UB 不建议直接变成 `logic [21:0] ub_memory [0:N-1]`

在当前项目中，更推荐：

### IMEM

```systemverilog
logic [31:0] imem_data [0:IMEM_DEPTH-1];
logic [6:0]  imem_ecc  [0:IMEM_DEPTH-1];
```

### UB

```systemverilog
logic [15:0] ub_memory     [0:UB_DEPTH-1];
logic [5:0]  ub_memory_ecc [0:UB_DEPTH-1];
```

### 为什么这么做

1. 更贴合当前工程现有数组风格
2. 更利于 Icarus / VCS 兼容
3. 修改范围更可控
4. 更方便 error injection

---

## 五、推荐模块拆分

## 5.1 第一阶段：固定宽度 ECC 模块

建议先做显式固定宽度模块，而不是一开始就参数化。

### IMEM 用

- `src_axi/ecc_secded_32_enc.sv`
- `src_axi/ecc_secded_32_dec.sv`

### UB 用

- `src_axi/ecc_secded_16_enc.sv`
- `src_axi/ecc_secded_16_dec.sv`

### 这么做的理由

- 当前工程目标是快速落地、快速验证
- 固定宽度逻辑更直观，debug 更容易
- 后续如果稳定，再统一抽象成参数化模块

## 5.2 可选公共工具文件

- `src_axi/ecc_utils.sv`
- `src_axi/ecc_pkg.sv`

第一版不是必须。

---

## 六、IMEM ECC 实施方案

## 6.1 修改范围

主要修改文件：

- `src_axi/tpu_frontend_axil.sv`

### 当前职责

- AXI 写 IMEM
- sequencer 读 IMEM
- 指令送给 `control_unit`

### 改造后职责

- 写 IMEM 时同时生成 ECC
- 读 IMEM 时先 decode/correct
- 单 bit 错误自动纠正
- 双 bit 错误置位状态并阻止错误指令继续执行

## 6.2 推荐写路径

### 写 IMEM

AXI 写入 32-bit 指令时：

```text
s_axil_wdata -> ecc_secded_32_enc -> imem_data[] + imem_ecc[]
```

### 读 IMEM

sequencer 取指时：

```text
imem_data[] + imem_ecc[] -> ecc_secded_32_dec -> corrected_instr -> seq_instr
```

## 6.3 双 bit 错误策略建议

对于 IMEM，推荐保守策略：

- single-bit error：自动纠正 + 计数
- double-bit error：置错误状态 + 停止 sequencer / 不发该指令

### 为什么不能双 bit 错误还继续执行

因为控制指令一旦被错误执行，后续系统行为会不可信，debug 成本极高。

---

## 七、UB ECC 实施方案

## 7.1 修改范围

主要修改文件：

- `src_axi/unified_buffer_v3.sv`
- 若想保持 non-AXI 对照路径一致，也建议同步修改：
  - `src/unified_buffer_v3.sv`

## 7.2 写路径

对于所有进入 UB 的写操作：

- host write
- VPU / update writeback

都应统一成：

```text
write_data -> ecc_secded_16_enc -> ub_memory[] + ub_memory_ecc[]
```

## 7.3 读路径

对于所有从 UB 读出的数据：

- input stream
- weight stream
- bias/Y/H/grad read

统一变成：

```text
ub_memory[] + ub_memory_ecc[] -> ecc_secded_16_dec -> corrected_data
```

## 7.4 单 bit / 双 bit 策略建议

### 单 bit 错误

- 自动纠正
- 置 `single_err` 标志
- 计数器加一
- 数据继续向下游流动

### 双 bit 错误

建议按数据类别分级处理：

#### 第一版最保守方案

无论哪类 UB 数据：

- 置 `double_err` 标志
- 记录地址
- 停止当前执行或置 fatal error

#### 后续可优化方案

按数据类别分级：

- 权重/指令相关：fatal
- 某些中间值：可仅上报

但第一版不建议一开始就做复杂策略。

---

## 八、错误状态与寄存器上报

ECC 成功与否不能只看波形，必须从 AXI 侧可观测。

建议在 `tpu_frontend_axil.sv` 中增加状态寄存器：

- `imem_ecc_single_err_count`
- `imem_ecc_double_err_flag`
- `imem_ecc_error_addr`
- `ub_ecc_single_err_count`
- `ub_ecc_double_err_flag`
- `ub_ecc_error_addr`
- `ecc_error_source`

### 建议语义

- count：累加计数
- flag：sticky，软件写 1 清除
- addr：记录最近一次错误地址
- source：IMEM / UB

---

## 九、error injection 设计建议

ECC 若没有 error injection，很难做成真正可信的验证闭环。

## 9.1 IMEM error injection

建议增加 debug-only 机制：

- 指定地址
- 指定位翻转 mask

例如通过 testbench 层直接改：

- `imem_data[idx] ^= mask`
- 或 `imem_ecc[idx] ^= mask`

### 第一版建议

优先 testbench 层直接注入，不急着做 AXI 可编程 fault injection 寄存器。

## 9.2 UB error injection

同样建议在 testbench 层直接做：

- 指定 UB 地址
- 翻转 data bit / ecc bit

### 为什么先在 TB 注入

- 改动小
- 最适合快速验证 encoder/decoder 正确性
- 不污染正式 RTL 控制面

---

## 十、分阶段实施方案

## Phase 1：IMEM ECC 基础版

### 目标

先让 IMEM 支持 SECDED，并对 AXI e2e 主流程影响最小。

### 任务

1. 新增 `ecc_secded_32_enc.sv`
2. 新增 `ecc_secded_32_dec.sv`
3. `tpu_frontend_axil.sv` 增加 `imem_data[]` 和 `imem_ecc[]`
4. 写 IMEM 时生成 ECC
5. 取指时先 decode/correct
6. 增加 IMEM ECC 状态寄存器

### 回归要求

- 原始无错误场景仍与现有 e2e 结果一致
- `41/41 PASS` 不被破坏

---

## Phase 2：IMEM ECC 错误注入验证

### 任务

新增测试：

- `test/test_imem_ecc.py`

覆盖：

1. 无错误
2. 单 bit data error
3. 单 bit ecc error
4. 双 bit error
5. 连续错误注入

### 关键验收点

- 单 bit 指令错误被正确纠正
- 双 bit 指令错误不会被误纠正成另一条合法指令继续执行

---

## Phase 3：UB ECC 基础版

### 任务

1. 新增 `ecc_secded_16_enc.sv`
2. 新增 `ecc_secded_16_dec.sv`
3. `unified_buffer_v3.sv` 增加并行 `ub_memory_ecc[]`
4. 所有写入路径统一做 encode
5. 所有读出路径统一做 decode/correct
6. 增加 UB ECC 状态位

### 风险点

- `unified_buffer_v3.sv` 职责本就很重
- 这里最容易引入功能回归
- 必须在每种 transaction 路径上都验证读写

---

## Phase 4：UB ECC 系统验证

### 任务

新增测试：

- `test/test_ub_ecc.py`
- `test/test_tpu_soc_axil_ecc_e2e.py`

覆盖场景：

1. 权重字 1-bit 错误
2. bias 字 1-bit 错误
3. 中间激活字 1-bit 错误
4. 双 bit 错误上报
5. update/writeback 路径 ECC 保持正确

---

## 十一、文件级改造清单

## 11.1 建议新增文件

- `src_axi/ecc_secded_32_enc.sv`
- `src_axi/ecc_secded_32_dec.sv`
- `src_axi/ecc_secded_16_enc.sv`
- `src_axi/ecc_secded_16_dec.sv`
- `test/test_imem_ecc.py`
- `test/test_ub_ecc.py`
- `test/test_tpu_soc_axil_ecc_e2e.py`

## 11.2 建议修改文件

- `src_axi/tpu_frontend_axil.sv`
- `src_axi/unified_buffer_v3.sv`
- 可选：`src/unified_buffer_v3.sv`
- `test/test_tpu_soc_axil_e2e.py`

## 11.3 第一阶段尽量不改的文件

- `src_axi/control_unit.sv`
- `src_axi/vpu.sv`
- `src_axi/systolic.sv`
- `src_axi/pe.sv`

理由：

- ECC 优先先包在存储边界，不要把修改扩散到 compute core 内部

---

## 十二、验证计划

## 12.1 无错误回归

先证明：

- 加 ECC 但无注错时，行为与原设计一致
- 现有 `41/41 PASS` 不变

## 12.2 单 bit 纠错验证

证明：

- data bit 翻转被纠正
- ecc bit 翻转被纠正
- single error 计数正确

## 12.3 双 bit 检错验证

证明：

- double error flag 被置位
- 不会错误地“纠正成另一个值”
- IMEM 双 bit 错误时 sequencer 停止或报错

## 12.4 压力测试

建议覆盖：

1. 连续错误注入
2. 连续 AXI 写 IMEM + 取指
3. UB 高频读写并发
4. reset 打断后的错误状态清理

---

## 十三、最容易踩的坑

1. 把 data 和 ecc 混成一个 packed array，结果仿真器兼容性变差
2. 只做 encode/decode，不做状态上报
3. 双 bit 错误仍然继续执行指令
4. 只验证 data bit 翻转，不验证 ecc bit 翻转
5. UB 某些写路径补了 encode，另一些写路径漏掉
6. 只在独立小测试里验证 ECC，没回归 e2e 主流程

---

## 十四、实施优先级结论

最合理的 ECC 实施顺序是：

1. **先做 IMEM ECC 基础版**
2. **再做 IMEM error injection 与系统验证**
3. **再做 UB ECC 基础版**
4. **最后做 UB ECC e2e 回归**

这样推进的好处：

- 从最小改动、最易验证的存储体切入
- 不会一次把 `unified_buffer_v3.sv` 变得不可收拾
- 更容易向面试官讲清楚“为什么先做 IMEM，再做 UB”

