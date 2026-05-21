# TPU SoC 后续计划：CDC 与 ECC 增强路线图

> 面向当前 `tpu-soc` 原型的下一阶段工程化演进规划
> 目标方向：
> 1. 引入主从异频的跨时钟域设计（CDC）
> 2. 引入 ECC 保护，支持 1-bit 纠错 / 2-bit 检错（SECDED）

---

## 一、为什么现在要做这两件事

当前 `tpu-soc` 已经完成了以下基础闭环：

- 核心 TPU 数据通路打通：`src/`
- AXI-Lite SoC 封装打通：`src_axi/`
- 指令调度与 IMEM 编码打通：`compiler/`
- AXI e2e 验证完成：`41/41 PASS`
- directed bug 收敛完成：H1 `8/8 PASS`

这说明项目已经从“单时钟原型能跑通”进入到“可以做工程化增强”的阶段。

下一步最有价值的增强不是继续堆功能，而是补两个更接近真实芯片场景的能力：

1. **CDC**：把 Host/AXI 控制域和 TPU 计算域从单时钟改成异频双时钟
2. **ECC**：给关键存储体增加容错能力，降低软错误和存储位翻转风险

这两项增强会让当前原型从“能工作”进一步提升到“更像真实 SoC 子系统”。

---

## 二、CDC 规划：主从不同频率跨时钟域设计

### 2.1 当前现状

当前 `tpu-soc` 基本是**单时钟语义**：

- AXI-Lite frontend
- IMEM/sequencer
- TPU core
- UB/VPU/systolic

这些路径默认都在同一个时钟节奏下工作。

对应核心文件：

- `src_axi/tpu_frontend_axil.sv`
- `src_axi/tpu_soc.sv`
- `src_axi/tpu.sv`
- `src_axi/unified_buffer_v3.sv`

### 2.2 目标形态

引入两个时钟域：

- `s_axil_aclk`：主控/寄存器/AXI 域
- `tpu_core_clk`：TPU 核计算域

建议的频率关系：

- AXI 域偏低、稳定，例如 `50~100MHz`
- TPU core 域独立扫频，例如 `150~200MHz`

这样能更贴近真实 SoC 里“控制平面”和“计算平面”异频运行的情况。

### 2.3 最适合切 CDC 的位置

#### 方案 A：AXI frontend 和 TPU core 之间切域

最推荐。

也就是：

- `tpu_frontend_axil.sv` 继续留在 AXI 域
- `tpu.sv`、`systolic.sv`、`vpu.sv`、`unified_buffer_v3.sv` 全部放到 core 域

原因：

1. 当前项目里 AXI frontend 天然属于控制平面
2. TPU core 内部数据流耦合很强，不适合拆成多个小时钟域
3. 在 frontend/core 之间切分，边界最清晰，最利于验证和维护

#### 不推荐的切法

- 在 `UB <-> systolic` 内部切域
- 在 `VPU <-> UB` 内部切域
- 在 `sequencer <-> control_unit` 内部切域

原因：

- 这些位置控制和数据耦合都太强
- 会显著扩大 CDC 复杂度
- 容易引入比当前项目规模更重的时序/一致性问题

### 2.4 需要跨域的信号分类

如果按 `AXI frontend` / `TPU core` 切域，主要跨域对象有 4 类。

#### 1. 控制类单 bit 信号

例如：

- `start`
- `soft_reset`
- `busy/done/status`

处理方式：

- 单 bit 慢控制信号：两级同步器
- 脉冲型信号：pulse sync / toggle sync

#### 2. 配置类多 bit 信号

例如：

- 寄存器配置项
- `learning_rate`（后续如开放）
- 模式控制字段

处理方式：

- 配置寄存器 shadow + enable 握手
- 或基于 request/ack 的跨域寄存器提交机制

#### 3. 指令流 / 命令流

例如：

- `seq_instr`
- `seq_instr_pulse`
- IMEM dispatch 结果

处理方式：

- 不建议直接把 `seq_instr_pulse` 裸跨域
- 建议改为 **command async FIFO**
- AXI 域写入 command，core 域弹出执行

#### 4. 数据流 / 写入流

例如：

- Host 写 UB 的 data/valid/ptr
- 若未来想让 AXI 直接灌更多数据

处理方式：

- 建议改为 **dual-clock write FIFO** 或 async FIFO
- 不建议多 bit data + valid 直接同步器跨域

### 2.5 推荐的 CDC 架构改造

#### 第一阶段：最小可用 CDC 版本

目标：先让控制域和计算域分开，但不大改微架构。

建议改造：

1. `tpu_frontend_axil.sv` 保留 AXI 域
2. 新增 `cmd_async_fifo.sv`
3. sequencer 不再直接打一拍 `seq_instr_pulse` 到 core
4. 改为把 32-bit command 写入 async FIFO
5. TPU core 域从 FIFO 取出命令再送入 `control_unit`
6. `done/busy` 通过同步器或 status FIFO 回传到 AXI 域

优点：

- 改造边界清晰
- 最适合当前原型规模
- 可逐步演进，不必一次重写整个 frontend

#### 第二阶段：UB host write 跨域化

当前 Host 对 UB 的写入和核心执行仍然耦合较紧。

建议：

- 在 AXI 域和 UB 写入口之间增加 data async FIFO
- 把 `ub_wr_host_data/valid` 改成 FIFO 化接口
- core 域负责从 FIFO 出队写入 UB

这样能避免 AXI 数据节拍直接受 core clock 约束。

#### 第三阶段：状态与中断机制增强

建议：

- 新增 `cmd_done` / `error_status` / `ecc_error_status`
- 通过同步后的 sticky status 或 event queue 上报 AXI 域

这会让 SoC 子系统更像真实加速器外设，而不是仅依赖轮询某个 `busy` 位。

### 2.6 CDC 相关新增/修改文件建议

#### 重点新增文件

建议新增：

- `src_axi/cdc_sync_bit.sv`
- `src_axi/cdc_pulse_sync.sv`
- `src_axi/async_fifo.sv`
- `src_axi/tpu_cmd_bridge.sv`

#### 重点修改文件

建议修改：

- `src_axi/tpu_frontend_axil.sv`
- `src_axi/tpu_soc.sv`
- `src_axi/control_unit.sv`
- `src_axi/unified_buffer_v3.sv`（如果做 host write FIFO 化）

#### 建议保持不动的文件

尽量先不改：

- `src_axi/systolic.sv`
- `src_axi/vpu.sv`
- `src_axi/pe.sv`

理由：

- 这些都属于同一个 core domain 内部计算链路
- 先保持 core 内单时钟，降低第一轮 CDC 风险

### 2.7 CDC 验证计划

CDC 不是只改 RTL，还必须有针对性的验证。

#### 功能验证

新增测试目标：

1. AXI 域慢、core 域快
2. AXI 域快、core 域慢
3. start 脉冲跨域不丢失
4. done/status 回传不丢失
5. command FIFO 不丢命令、不乱序
6. UB host write FIFO 在 backpressure 下不丢数据

#### 压力测试

重点建议：

- 随机主从频率比，例如 `1:1`、`1:2`、`2:1`、`3:5`
- reset 分别在 AXI 域/core 域打断
- 连续 start / 连续写命令 / 连续写 UB 数据
- FIFO near-full / near-empty 边界

#### 静态检查

后续如果工具链允许，建议加入：

- CDC lint
- 异步 FIFO 结构检查
- reset domain crossing 检查

---

## 三、ECC 规划：1-bit 纠错 / 2-bit 检错（SECDED）

### 3.1 为什么要在这个项目里做 ECC

当前 `tpu-soc` 里最值得保护的对象不是控制信号，而是**存储体**：

- IMEM：存放 32-bit 指令
- Unified Buffer：存放 X/W/B/Y/H/gradient 等关键数据
- 后续若增加参数缓存，也应考虑保护

ECC 的价值：

1. 更符合芯片级存储可靠性设计思路
2. 能自然扩展出 error injection / fault campaign 验证
3. 很适合作为你项目下一阶段的“可靠性增强”亮点

### 3.2 最适合先加 ECC 的位置

#### 第一优先级：IMEM

原因：

- 指令宽度固定 32-bit
- 访问模式清晰
- 出错后影响大，且行为容易观察
- 最适合先做 SECDED 原型

#### 第二优先级：Unified Buffer

原因：

- UB 是关键数据存储体
- 一旦位翻转，可能影响权重、激活、梯度和输出
- 更接近真实 on-chip buffer 保护需求

#### 第三优先级：状态/配置寄存器

优先级低于 IMEM/UB。

原因：

- 数量少
- 更适合 parity 或冗余保护，而不是优先做完整 ECC

### 3.3 推荐的 ECC 方案

目标是 **SECDED**：

- Single Error Correction
- Double Error Detection

对于当前项目最推荐的实现方式：

#### IMEM

- 原始数据：32 bit
- 扩展后：`32 + ECC bits`
- 读出时先 decode/correct，再送给 `control_unit`

#### UB

- 对每个存储 word 单独附加 ECC bits
- 读 UB 时做 decode
- 写 UB 时同步生成 ECC

### 3.4 ECC 插入点建议

#### IMEM ECC

当前链路：

- AXI 写 IMEM
- sequencer 读 IMEM
- 指令送 control unit

建议改成：

- AXI 写入时：`data -> ecc_encode -> imem_array`
- 读出时：`imem_array -> ecc_decode/correct -> seq_instr`

最适合修改的文件：

- `src_axi/tpu_frontend_axil.sv`

#### UB ECC

当前链路：

- Host/AXI 写 UB
- core 读 UB 给 systolic/VPU/update
- 结果回写 UB

建议改成：

- 写入 UB：先 encode 再存
- 读出 UB：先 decode/correct 再使用

最适合修改的文件：

- `src_axi/unified_buffer_v3.sv`
- 若保留 non-AXI 对照，也同步修改 `src/unified_buffer_v3.sv`

### 3.5 推荐新增文件

建议新增：

- `src_axi/ecc_secded_32_enc.sv`
- `src_axi/ecc_secded_32_dec.sv`
- `src_axi/ecc_pkg.sv` 或 `src_axi/ecc_utils.sv`

若后续想统一 core/axi 两边实现，也可以在 `src/` 和 `src_axi/` 同步放置。

### 3.6 ECC 状态与异常上报设计

ECC 不是只纠错，还要有**可观测性**。

建议增加：

- `ecc_single_err_count`
- `ecc_double_err_flag`
- `ecc_error_addr`
- `ecc_error_source`（IMEM / UB）

并通过 AXI-Lite 状态寄存器暴露：

- 单 bit 错误：自动纠正 + 计数
- 双 bit 错误：置位 error flag，可选中断/停止执行

### 3.7 ECC 验证计划

#### 基础功能验证

至少覆盖：

1. 无错误：decode 输出与原值一致
2. 单 bit 翻转：correct 后恢复原值，并置 single error 标志
3. 双 bit 翻转：不纠正，置 double error 标志
4. 连续错误注入：状态计数是否正确

#### 系统级验证

建议新增：

- IMEM 某条指令注入 1-bit error，sequencer 仍能正常执行
- IMEM 注入 2-bit error，状态寄存器报错
- UB 权重字注入 1-bit error，输出结果保持正确
- UB 注入 2-bit error，结果停止或置错误标志

#### 压力面建议

- 随机地址错误注入
- 高并发 AXI 写 + core 读同时进行时的 ECC 路径
- CDC + ECC 叠加场景（后续阶段）

---

## 四、CDC 与 ECC 的先后顺序建议

### 推荐顺序

#### Phase 1：IMEM ECC

原因：

- 改动集中
- 最容易验证
- 最容易形成可靠性亮点

#### Phase 2：AXI frontend <-> TPU core CDC

原因：

- 这是系统架构升级
- 复杂度高于 IMEM ECC
- 但收益非常大

#### Phase 3：UB ECC

原因：

- 覆盖面广
- 改动量大
- 和数据通路耦合最深

#### Phase 4：CDC + ECC 联合验证

原因：

- 单独功能做完后再叠加，最稳

### 不推荐顺序

不建议：

- 一上来同时改 CDC + UB ECC + update + learning_rate

原因：

- 变量太多
- 回归难度会大幅增加
- 不利于问题收敛和证据链积累

---

## 五、结合当前项目，最合理的落地版本

### 版本 V1：先做 IMEM ECC

最小改造集：

- `src_axi/tpu_frontend_axil.sv`
- 新增 ECC encoder/decoder
- AXI 状态寄存器增加 ECC 状态位
- cocotb 增加 error injection case

### 版本 V2：再做 AXI/frontend 与 core 异频 CDC

最小改造集：

- `src_axi/tpu_soc.sv` 增加双时钟端口
- `src_axi/tpu_frontend_axil.sv` 保留 AXI 域
- 新增 command async FIFO
- 新增 status 同步器

### 版本 V3：UB ECC + host write FIFO 化

最小改造集：

- `src_axi/unified_buffer_v3.sv`
- 可能同步维护 `src/unified_buffer_v3.sv`
- cocotb 增加权重/激活错误注入

---

## 六、对简历和面试的价值

如果这两项后续计划做成，会显著提升项目的“工程化层次”。

### CDC 能带来的面试亮点

你可以多出这些表达：

- 异频双时钟域设计
- pulse sync / async FIFO / multi-bit CDC
- 控制平面与计算平面分离
- 主从异频 SoC 子系统集成

### ECC 能带来的面试亮点

你可以多出这些表达：

- IMEM/UB 可靠性增强
- SECDED 编码解码链路
- error injection 验证
- 单 bit 自动纠错 / 双 bit 检错上报

### 对华为海思/高要求数字前端岗位的价值

这两项能力很适合回答以下类型问题：

- 如果主控和计算域不同频率，你怎么设计？
- 多 bit 数据跨域你怎么处理？
- 为什么不能直接双触发器同步多 bit bus？
- on-chip buffer/指令存储如何考虑可靠性？
- 单 bit 纠错和双 bit 检错怎么落 RTL？

---

## 七、建议的文档和代码放置位置

### 文档

当前文档已放置：

- `docs/CDC_ECC_FUTURE_PLAN.md`

### 后续新增 RTL 建议路径

建议后续放到：

- `src_axi/cdc_*.sv`
- `src_axi/ecc_*.sv`
- 若需要 core 对照版本，再同步到 `src/`

### 后续新增验证建议路径

建议新增：

- `test/test_cdc_basic.py`
- `test/test_imem_ecc.py`
- `test/test_ub_ecc.py`
- `test/test_tpu_soc_axil_cdc_ecc_e2e.py`

---

## 八、最终建议

结合当前项目现状，**最合理的下一步不是同时大改全部内容**，而是按下面顺序推进：

1. **先做 IMEM ECC**，因为最集中、最易形成新亮点
2. **再做 AXI frontend/core CDC**，把项目从单时钟原型升级成异频 SoC 原型
3. **最后做 UB ECC**，把可靠性真正扩展到数据存储体

这样做的好处是：

- 每一步都能独立回归
- 每一步都能形成简历亮点
- 每一步都容易向面试官讲清楚“为什么这么设计、怎么验证、有什么 trade-off”

