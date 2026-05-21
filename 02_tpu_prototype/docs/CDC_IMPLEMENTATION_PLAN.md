# TPU SoC CDC 实施文档

> 面向当前 `tpu-soc` 工程的 CDC 落地方案
> 目标：把当前单时钟 AXI SoC 原型升级为“AXI 控制域 + TPU 计算域”异频架构，同时尽量不破坏现有 `41/41 PASS` 的功能闭环。

---

## 一、实施目标

当前系统默认单时钟工作：

- `src_axi/tpu_frontend_axil.sv`
- `src_axi/tpu_soc.sv`
- `src_axi/tpu.sv`
- `src_axi/unified_buffer_v3.sv`
- `src_axi/vpu.sv`
- `src_axi/systolic.sv`

都处在同一时钟语义下。

CDC 实施后的目标是：

- `s_axil_aclk`：AXI / 寄存器 / IMEM / 控制域
- `tpu_core_clk`：TPU core / UB / systolic / VPU / gradient_descent 域

核心原则：

1. **只切一刀**：先在 `frontend <-> core` 之间切时钟域，不在 core 内部再切。
2. **控制和数据分开处理**：单 bit 信号用同步器，命令/数据流用 FIFO。
3. **先保证可验证，再谈抽象优雅**：优先使用 plain SV、显式 FIFO、显式状态位，避免引入当前工程不熟悉的复杂封装。
4. **保留现有验证入口**：尽量复用 `test/test_tpu_soc_axil_e2e.py` 的主流程，而不是重写验证体系。

---

## 二、最重要的架构决策

### 2.1 只在 `tpu_frontend_axil` 和 `tpu` 核之间切域

建议架构：

```text
AXI-Lite Domain (s_axil_aclk)
  ├─ register bank
  ├─ IMEM write/read port
  ├─ sequencer / command producer
  └─ command/status bridge
                || CDC boundary ||
Core Domain (tpu_core_clk)
  ├─ control_unit
  ├─ tpu core
  │   ├─ unified_buffer_v3
  │   ├─ systolic
  │   ├─ vpu
  │   └─ gradient_descent
  └─ status/error producer
```

### 2.2 为什么不在 core 内部切域

不建议切的位置：

- `UB <-> systolic`
- `VPU <-> UB`
- `control_unit <-> tpu`

原因：

- 这些位置数据通路和时序关系耦合太重
- 当前项目刚完成功能闭环，继续在 core 内部分时钟会把验证复杂度放大数倍
- 先把“控制平面”和“计算平面”分开，收益最高、风险最低

### 2.3 为什么不用裸同步器跨多 bit 指令和数据

因为：

- 多 bit 总线各位可能不同拍稳定
- `seq_instr_pulse` 这种一拍脉冲跨域非常容易丢
- Host 写 UB 的 data + valid 直接跨域，容易引入不可重复的系统问题

因此本项目 CDC 的核心规则是：

- 单 bit 状态/慢配置：同步器
- 脉冲：pulse/toggle sync
- 命令：async FIFO
- 数据：async FIFO

---

## 三、推荐的模块拆分

### 3.1 新增模块

建议新增以下 CDC 基础模块：

#### 1. `src_axi/cdc_sync_bit.sv`

用途：

- 同步单 bit 慢变化状态信号
- 例如 `busy_core -> busy_axil`

建议接口：

```systemverilog
module cdc_sync_bit (
    input  logic clk_dst,
    input  logic rst_dst,
    input  logic din_async,
    output logic dout_sync
);
```

#### 2. `src_axi/cdc_pulse_sync.sv`

用途：

- 把 AXI 域的 `start` 之类单拍脉冲安全送到 core 域

建议实现：

- toggle-based pulse sync
- AXI 域发 toggle
- core 域同步后做异或产生 pulse

#### 3. `src_axi/async_fifo.sv`

用途：

- 跨域命令流
- 跨域 UB host write 数据流

建议特性：

- 参数化 `DATA_WIDTH`
- Gray code 读写指针
- `full / empty / almost_full / almost_empty` 可选
- 先实现最小功能版，不一开始追求花哨接口

#### 4. `src_axi/tpu_cmd_bridge.sv`

用途：

- 统一管理 AXI 域到 core 域的 command FIFO
- 把 `seq_instr` 和可能的 `soft_reset/start/metadata` 一并打包

建议打包内容：

- `instr[31:0]`
- `is_instr_valid`
- 预留 `cmd_type`

为降低第一版复杂度，也可以先只跨 32-bit instruction 本体，start 走单独 pulse sync。

### 3.2 修改模块

#### 1. `src_axi/tpu_soc.sv`

需要改成双时钟顶层：

建议新增端口：

```systemverilog
input logic s_axil_aclk,
input logic s_axil_aresetn,
input logic tpu_core_clk,
input logic tpu_core_rst
```

当前如果 `tpu_soc.sv` 里默认把 frontend 和 core 都绑在一个 clock 上，需要拆开。

#### 2. `src_axi/tpu_frontend_axil.sv`

这是 CDC 改造的核心文件。

主要变化：

- 保留 AXI register bank
- 保留 IMEM 写入
- sequencer 不再直接把 `seq_instr_pulse + seq_instr` 裸送 core
- 改为通过 command FIFO 跨域
- `busy/done/error` 从 core 域同步回来

#### 3. `src_axi/control_unit.sv`

尽量少改。

建议改法：

- control unit 继续在 core 域使用
- 输入改为来自 command FIFO 的 `cmd_instr`
- 不要把 control unit 也留在 AXI 域，否则 core 内部会出现更多跨域控制线

#### 4. `src_axi/unified_buffer_v3.sv`

第一阶段尽量不碰。

第二阶段如果要做 host write FIFO 化，再改：

- core 域只接收 FIFO 弹出的写请求
- AXI 域不直接 drive UB host valid/data

---

## 四、分阶段实施方案

## Phase 0：准备阶段

目标：在不改变行为的前提下，把现有单时钟设计整理成适合 CDC 改造的结构。

### 任务

1. 梳理 `tpu_frontend_axil.sv` 当前直接送到 core 的信号
2. 分类：
   - 单 bit 控制
   - 单 bit 状态
   - 多 bit 指令
   - 多 bit 数据
3. 明确哪些必须跨域，哪些可以留在 AXI 域
4. 补一份 signal map 文档

### 输出物

- `CDC_SIGNAL_MAP.md`（可选）
- 修改前信号表

### 验证要求

- 不改功能 RTL
- 当前 `test_tpu_soc_axil_e2e.py` 仍保持 PASS

---

## Phase 1：先做 `start/status` 类 CDC

目标：先建立最小跨域骨架，让 AXI 域可以安全启动 core，并安全读回 busy/status。

### 任务

1. 在 `tpu_soc.sv` 增加双时钟端口
2. 新增 `cdc_pulse_sync.sv`，实现 `start` 从 AXI 域到 core 域
3. 新增 `cdc_sync_bit.sv`，实现 `busy` 等状态回传
4. core 域先不启用 command FIFO，只验证最基础的控制跨域

### 为什么先做这个

因为：

- 这是最小改动
- 最容易快速看出 CDC 基础设施是否工作
- 有利于先把 reset、pulse、status 路径吃透

### 风险点

- `start` 不能重复触发或丢失
- reset 不能在两个域语义不一致

### 验证计划

新增测试：

- `test/test_cdc_basic.py`

检查：

1. `start` 脉冲在 AXI 慢/core 快时不丢
2. `start` 脉冲在 AXI 快/core 慢时不丢
3. `busy` 置位与清零都能跨域观察到
4. reset 后状态一致

---

## Phase 2：命令流 CDC 化

目标：把 sequencer 发出的命令安全送到 core 域，替换当前的 `seq_instr_pulse` 裸控制方式。

### 任务

1. 新增 `async_fifo.sv`
2. 新增 `tpu_cmd_bridge.sv`
3. `tpu_frontend_axil.sv` 中：
   - `seq_instr_pulse` 只作用于 AXI 域本地 push 逻辑
   - `seq_instr` 写入 command FIFO
4. core 域：
   - 从 FIFO pop 指令
   - 生成 core-local 的 `cmd_valid`
   - 驱动 `control_unit`

### 推荐 command 格式

最保守版本：

```systemverilog
logic [31:0] cmd_instr;
logic        cmd_valid;
```

也可以为后续预留：

```systemverilog
logic [1:0]  cmd_type;
logic [31:0] cmd_payload;
```

但第一版不建议过度抽象。

### 为什么这一步很关键

因为当前项目里最脆弱的控制之一就是：

- 一拍 `seq_instr_pulse`
- 指令和数据真实到达存在多拍偏移

把命令流 FIFO 化之后，跨域行为会稳定很多，也更容易和后续 scheduler/IMEM 扩展兼容。

### 风险点

- FIFO push/pop 时机和 `pc` 推进关系要理清
- 不要因为 FIFO 引入“发了命令但状态机以为没发”这种语义偏差

### 验证计划

检查：

1. 命令不丢失
2. 命令不乱序
3. `wait_after` 语义在跨域后仍保持正确
4. `vpu_pathway_reg` 相关行为在 core 域仍正确

建议复用：

- `test/test_tpu_soc_axil_e2e.py`
- 外加不同频率比回归

---

## Phase 3：Host 写 UB 数据 CDC 化

目标：把 AXI 域 host write UB 的数据路径也跨域安全化。

### 当前问题

当前 host write 语义本质上还是“AXI 侧直接 drive 到 UB 接口”。

一旦 AXI 与 core 分频，这种直连方式就不再安全。

### 任务

1. 在 AXI 域新增 host write request packing
2. 使用 `async_fifo.sv` 作为写请求 FIFO
3. FIFO payload 建议包含：

```systemverilog
logic [15:0] wr_data_0;
logic [15:0] wr_data_1;
logic        wr_valid_0;
logic        wr_valid_1;
logic        wr_push;
```

4. core 域从 FIFO 弹出后，转成 `unified_buffer_v3.sv` 期望的 host write 接口

### 为什么建议做成 FIFO，而不是多 bit 同步器

因为：

- 这里是数据通路，不是单 bit 配置
- 有成组信号和时序关系
- FIFO 天然更适合做节拍解耦和 backpressure 处理

### 风险点

- FIFO nearly full 时 AXI 侧如何 backpressure
- 连续写入是否会打乱 lane0/lane1 的配对关系

### 验证计划

新增测试场景：

1. 连续写入 X/W/B
2. AXI 快、core 慢
3. core 快、AXI 慢
4. FIFO 满边界
5. reset during write

---

## Phase 4：状态 / 错误 / 中断增强

目标：让 CDC 后的 SoC 更像一个完整外设，而不是只靠轮询 `busy`。

### 建议新增状态

- `cmd_done`
- `core_busy`
- `cmd_error`
- `fifo_overflow`
- `fifo_underflow`
- 预留 `ecc_error`

### 状态上报方式

建议：

- sticky status register
- clear-on-write AXI status reg
- 如后续需要可加 interrupt line

### 风险点

- sticky 位和 pulse 位不要混
- AXI 域读状态时要保证一致性

---

## 五、reset 设计建议

CDC 项目里 reset 很容易被忽视，但实际上很关键。

### 推荐策略

- AXI 域 reset：`s_axil_aresetn`
- core 域 reset：`tpu_core_rst`
- FIFO 两端各自使用本域 reset

### 第一版建议

- 先让两个 reset 同源但分域同步
- 不要第一版就做复杂独立 reset sequence

### 必须验证的问题

1. AXI 域 reset 时 core 是否误启动
2. core 域 reset 时 AXI 状态是否卡死
3. FIFO reset 后是否出现假 full/假 empty

---

## 六、文件级改造清单

## 6.1 建议新增文件

- `src_axi/cdc_sync_bit.sv`
- `src_axi/cdc_pulse_sync.sv`
- `src_axi/async_fifo.sv`
- `src_axi/tpu_cmd_bridge.sv`
- `test/test_cdc_basic.py`
- `test/test_tpu_soc_axil_cdc_e2e.py`

## 6.2 建议修改文件

- `src_axi/tpu_soc.sv`
- `src_axi/tpu_frontend_axil.sv`
- `src_axi/control_unit.sv`
- `src_axi/unified_buffer_v3.sv`（Phase 3）
- `test/tb_tpu_soc_axil.sv`
- `test/test_tpu_soc_axil_e2e.py`

## 6.3 尽量保持不动的文件

- `src_axi/pe.sv`
- `src_axi/systolic.sv`
- `src_axi/vpu.sv`
- `src_axi/gradient_descent.sv`

理由：

- 它们都应该继续留在同一个 core 时钟域内部
- 第一轮 CDC 不要把问题扩展到核心计算链路

---

## 七、验证与回归计划

## 7.1 回归分层

### 层 1：CDC primitive 单元测试

测试对象：

- `cdc_sync_bit.sv`
- `cdc_pulse_sync.sv`
- `async_fifo.sv`

### 层 2：bridge 集成测试

测试对象：

- `tpu_cmd_bridge.sv`

### 层 3：SoC CDC e2e 测试

测试对象：

- `tpu_soc.sv`
- `test_tpu_soc_axil_cdc_e2e.py`

## 7.2 频率组合建议

至少覆盖：

- `1:1`
- `1:2`
- `2:1`
- `3:5`
- `5:3`

## 7.3 压力测试清单

1. 连续 start
2. 连续命令 dispatch
3. 连续 UB 写入
4. reset during command in flight
5. FIFO full/empty 边界
6. AXI 快 / core 慢极端比值

---

## 八、阶段性交付建议

推荐按以下提交节奏推进：

### Commit 1

- 双时钟顶层骨架
- `cdc_sync_bit.sv`
- `cdc_pulse_sync.sv`
- basic CDC test

### Commit 2

- `async_fifo.sv`
- `tpu_cmd_bridge.sv`
- 命令流跨域
- e2e 初步回归

### Commit 3

- host write FIFO 化
- `unified_buffer_v3.sv` 适配
- CDC e2e 压测

### Commit 4

- 状态 / 错误 / sticky reg
- 文档和回归脚本完善

---

## 九、最容易踩的坑

1. 直接双触发器同步多 bit `seq_instr`
2. 让 `seq_instr_pulse` 裸跨域
3. FIFO reset 策略不一致
4. AXI 域认为 push 成功，但 core 域实际上没消费
5. 状态位用 pulse 表示，软件侧读不到
6. 一开始就在 core 内部切多个时钟域

---

## 十、实施优先级结论

最合理的 CDC 实施顺序是：

1. **双时钟骨架 + start/status CDC**
2. **命令流 async FIFO 化**
3. **UB host write FIFO 化**
4. **错误/状态增强**

这样推进的好处：

- 每一步都能单独验证
- 不会一次性破坏现有 `41/41 PASS` 闭环
- 面试时也更容易讲成“我有明确的 CDC 工程实施方法”

