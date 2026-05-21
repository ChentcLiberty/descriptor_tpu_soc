# 综合相关代码修改总结

> 记录所有为综合优化而做的 RTL 修改，说明原始代码位置、修改后位置、修改内容和原因。

---

## 目录结构说明

```
TitanTPU/
├── _vendor/tiny-tpu/               ← 当前工作目录（已修改的基线）
│   ├── src/                        ← 原始 RTL，含 Bug 修复后的版本
│   │   ├── unified_buffer.sv       ← Bug 修复版（.bak 是修复前原始）
│   │   ├── unified_buffer.sv.bak   ← 修复前原始代码
│   │   ├── gradient_descent.sv     ← Bug 修复版（.bak 是修复前原始）
│   │   ├── gradient_descent.sv.bak ← 修复前原始代码
│   │   ├── pe.sv                   ← Bug 修复版（多驱动修复）
│   │   └── pipeline_exp/           ← 流水线实验新增代码（不修改原文件）
│   │       ├── vpu_ub_pipe_stage.sv ← 新增：VPU→UB 之间的流水线寄存器模块
│   │       ├── tpu_pipeline.sv      ← 新增：插入流水线的顶层变体
│   │       └── README.md
│   └── syn/                        ← 综合脚本和报告
│       ├── dc_script.tcl           ← 主综合脚本（100MHz）
│       ├── dc_freq_search.tcl      ← 扫频脚本（二分查找极限频率）
│       ├── constraints.sdc         ← SDC 时序约束
│       └── reports/                ← 综合报告
└── _vendor/tiny-tpu_timing_opt_20260328/  ← Pipeline 优化备份快照
    └── src/
        ├── vpu_ub_pipe_stage.sv    ← 同 pipeline_exp 版本
        └── tpu_pipeline.sv         ← 同 pipeline_exp 版本
```

**关键原则**：
- 原始 `src/tpu.sv`、`src/vpu.sv` 等基线文件**不修改**
- Bug 修复直接在原文件上做（有 `.bak` 备份）
- 流水线优化以**新增文件**的方式实现（`pipeline_exp/`），不破坏基线
- `tiny-tpu_timing_opt_20260328/` 是 pipeline 版本综合完成时的完整快照

## 时序优化阶段说明

当前仓库里的本地证据链显示，时序优化不是“一步从 164MHz 直接跳到 183.91MHz”，而是至少经历了两个已落盘的阶段：

1. **基线版本**：`6.09ns / 164.10MHz / 49 logic levels`
   - 来源：`/home/jjt/TitanTPU/syn/reports/freq_search/qor_final.rpt`
   - 摘要：`experiments/syn/out/baseline/summary_reference.txt`
2. **第一轮插入寄存器后的已证明频点**：`6.00ns / 166.67MHz / 30 logic levels`
   - 来源：`_vendor/tiny-tpu/experiments/syn/out/pipeline/reports/freq_search/qor_iter2_6.0ns.rpt`
   - 说明：这是 2026-03-25 当时已经确认可过的保守结论，不是最终极限频点。
3. **继续细扫后的最终收敛点**：`5.44ns / 183.91MHz`
   - 来源：`_vendor/tiny-tpu_timing_opt_20260328/experiments/syn/out/pipeline/summary.txt`
   - 关键迭代：`6.00ns PASS -> 5.62ns PASS -> 5.44ns PASS -> 5.34ns FAIL`

> 注：如果还要把更早一轮“160→164MHz”的前置优化写进文档，需要补上对应报告或日志；当前仓库中我只找到了上面这三组可直接引用的数字。

---

## 修改一：unified_buffer.sv — 读取命令初始化竞争条件修复

### 问题描述
原始代码在 `always_comb` 块中初始化读取命令寄存器（`rd_input_ptr`、`rd_weight_ptr` 等），但这些变量同时也在 `always_ff` 块中被赋值，造成**多驱动（multi-driver）竞争条件**，仿真中出现 NBA（Non-Blocking Assignment）竞争，导致读取指针值不确定。

### 修改位置
- 原始文件：`src/unified_buffer.sv.bak`（line 168 附近）
- 修改后：`src/unified_buffer.sv`（line 168）

### 修改内容

**修改前**（`unified_buffer.sv.bak`，line 168-244）：
```systemverilog
// 原始：用 always_comb 初始化读取命令，与 always_ff 形成多驱动
always_comb begin
    if (ub_rd_start_in) begin
        case (ub_ptr_select)
            0: begin
                rd_input_transpose = ub_rd_transpose;
                rd_input_ptr = ub_rd_addr_in;
                if(ub_rd_transpose) begin
                    rd_input_row_size = ub_rd_col_size;
                    rd_input_col_size = ub_rd_row_size;
                end else begin
                    rd_input_row_size = ub_rd_row_size;
                    rd_input_col_size = ub_rd_col_size;
                end
                rd_input_time_counter = '0;
            end
            1: begin
                rd_weight_transpose = ub_rd_transpose;
                // ...（省略其余 case 分支）
            end
            // case 2-6: rd_bias, rd_Y, rd_H, rd_grad_bias, rd_grad_weight
        endcase
    end else begin
        ub_rd_col_size_out = 0;
        ub_rd_col_size_valid_out = 1'b0;
    end
end
```

**修改后**（`unified_buffer.sv`，line 168-169）：
```systemverilog
// 修复：移除 always_comb 块，改为在 always_ff 块中统一初始化
// Read command initialization logic moved to always_ff block below
// This fixes the multi-driver issue while maintaining functionality
```
所有读取命令的初始化逻辑迁移到 `always_ff @(posedge clk)` 块内，消除组合/时序逻辑双重驱动。

### 修复原因
- **根本原因**：SystemVerilog 中，被 `always_ff` 驱动的变量不能再被 `always_comb` 赋值，否则是非法多驱动
- **仿真表现**：VCS 仿真中读取指针在 `ub_rd_start_in` 有效时出现竞争，`rd_input_ptr` 值不确定
- **修复效果**：消除竞争条件，仿真结果稳定，综合后 DRC 无违例

---

## 修改二：gradient_descent.sv — sub_in_a 多驱动修复

### 问题描述
`gradient_descent.sv` 中 `sub_in_a` 信号同时在 `always_ff` 块中被初始化赋值（`<= '0`）和在组合逻辑路径中被使用，造成驱动冲突。

### 修改位置
- 原始文件：`src/gradient_descent.sv.bak`（line 66）
- 修改后：`src/gradient_descent.sv`（line 66）

### 修改内容

**修改前**（`gradient_descent.sv.bak`，line 66）：
```systemverilog
// 原始：在 always_ff 中对组合逻辑信号做多余的初始化赋值
sub_in_a <= '0;   // 多余的时序赋值，与组合逻辑驱动冲突
```

**修改后**（`gradient_descent.sv`，line 66）：
```systemverilog
// 修复：移除多余的时序赋值，sub_in_a 纯由组合逻辑驱动
// sub_in_a is purely combinational, will be 0 when value_old_in is 0
```

### 修复原因
- `sub_in_a` 是减法器的输入端，其值完全由 `value_old_in` 决定（纯组合逻辑）
- 在 `always_ff` 中对其赋 `<= '0` 是多余操作，且与组合驱动形成多驱动
- 修复后：`sub_in_a` 的驱动来源唯一（组合逻辑），综合工具不再报多驱动警告

---

## 修改三：pe.sv — weight_reg_active 多驱动修复

### 问题描述
`pe.sv` 中 `weight_reg_active` 同时被 `always_comb` 和 `always_ff` 驱动，是典型的多驱动问题。`always_comb` 试图根据使能条件组合赋值，`always_ff` 在时钟沿做时序赋值，两者冲突。

### 修改位置
- 文件：`src/pe.sv`（已修复，无 .bak 备份，通过 git 历史可查）

### 修改内容

**修复方案**：统一为纯时序逻辑（`always_ff`），删除 `always_comb` 中对 `weight_reg_active` 的赋值：

```systemverilog
// 修复后：weight_reg_active 只在 always_ff 中驱动
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        weight_reg_active <= '0;
        weight_reg_inactive <= '0;
    end else begin
        if (pe_accept_weight) begin
            weight_reg_inactive <= pe_weight_in;  // 预加载到 inactive
        end
        if (pe_switch) begin
            weight_reg_active <= weight_reg_inactive;  // 切换生效
        end
    end
end
// always_comb 中不再驱动 weight_reg_active
```

### 修复原因
- PE 的双缓冲权重寄存器（active/inactive）本质是时序逻辑，应完全在 `always_ff` 中控制
- 混用 `always_comb` 导致综合工具报多驱动错误，仿真结果不确定
- 修复后：PE 11/11 测试用例全部通过

---

## 修改四：新增 vpu_ub_pipe_stage.sv — 流水线寄存器模块

### 文件位置
- 新增文件：`src/pipeline_exp/vpu_ub_pipe_stage.sv`
- 不修改任何原有文件

### 完整代码

```systemverilog
`timescale 1ns/1ps
`default_nettype none

module vpu_ub_pipe_stage #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2,
    parameter int DATA_WIDTH = 16
)(
    input logic clk,
    input logic rst,

    input logic [DATA_WIDTH-1:0] data_in [0:SYSTOLIC_ARRAY_WIDTH-1],
    input logic valid_in [0:SYSTOLIC_ARRAY_WIDTH-1],

    output logic [DATA_WIDTH-1:0] data_out [0:SYSTOLIC_ARRAY_WIDTH-1],
    output logic valid_out [0:SYSTOLIC_ARRAY_WIDTH-1]
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                data_out[i] <= '0;
                valid_out[i] <= 1'b0;
            end
        end else begin
            for (int i = 0; i < SYSTOLIC_ARRAY_WIDTH; i++) begin
                data_out[i] <= data_in[i];
                valid_out[i] <= valid_in[i];
            end
        end
    end

endmodule
```

### 设计意图
- 在 VPU 输出和 UB 写入端口之间插入一拍寄存器
- 把关键路径（45 级，6.57ns）切断为两段（各约 22-23 级，~3.5ns）
- 复位风格与 PE 保持一致（高有效 rst，`posedge rst`）
- 参数化设计，`SYSTOLIC_ARRAY_WIDTH` 可配

### 综合效果
| 阶段 | 周期/频率 | 逻辑级数 | 说明 |
|------|-----------|----------|------|
| 基线参考 | `6.09ns / 164.10MHz` | `49` | `/home/jjt/TitanTPU/syn/` 主 flow 的 established baseline |
| 第一轮 pipeline 已证明频点 | `6.00ns / 166.67MHz` | `30` | 2026-03-25 本地实验先证明“打一拍后可稳定提频” |
| 继续细扫后的最终频点 | `5.44ns / 183.91MHz` | 文档其余处按 `38` 级描述 | 2026-03-28 继续二分/细扫后收敛到最终数字 |

补充说明：
- `166.67MHz` 是第一轮寄存器插入后“已证明可过”的保守结果。
- `183.91MHz` 是在同一 pipeline 思路下继续细扫得到的最终收敛点。
- Latency 代价始终是 `+1 cycle`，吞吐量不变。

---

## 修改五：新增 tpu_pipeline.sv — 流水线顶层变体

### 文件位置
- 新增文件：`src/pipeline_exp/tpu_pipeline.sv`
- 不修改 `src/tpu.sv`（原始顶层保留）

### 核心修改逻辑（相对于 tpu.sv）

```systemverilog
// -------- 原始 tpu.sv 连接方式（无流水线）--------
// VPU 输出直接连到 UB 写入端（无寄存器，关键路径跨模块）
vpu vpu_inst (
    ...
    .vpu_data_out_1(vpu_data_out_1),   // 直接输出
    .vpu_valid_out_1(vpu_valid_out_1)
);
unified_buffer ub_inst (
    .ub_wr_data_in[0](vpu_data_out_1), // 直接连接，无中间寄存器
    ...
);

// -------- tpu_pipeline.sv 修改后 --------
// Step 1：VPU 输出先进流水线寄存器（vpu_raw_*）
vpu vpu_inst (
    ...
    .vpu_data_out_1(vpu_raw_data_out[0]),  // raw 输出
    .vpu_valid_out_1(vpu_raw_valid_out[0])
);

// Step 2：插入一拍寄存器
vpu_ub_pipe_stage vpu_ub_pipe_stage_inst (
    .clk(clk), .rst(rst),
    .data_in(vpu_raw_data_out),     // 接 VPU 原始输出
    .valid_in(vpu_raw_valid_out),
    .data_out(vpu_pipe_data_out),   // 打一拍后输出
    .valid_out(vpu_pipe_valid_out)
);

// Step 3：UB 接打过拍的信号
assign ub_wr_data_in[0]  = vpu_pipe_data_out[0];
assign ub_wr_valid_in[0] = vpu_pipe_valid_out[0];
unified_buffer ub_inst (
    .ub_wr_data_in(ub_wr_data_in),  // 接寄存器后的信号
    ...
);
```

### 为什么选这个位置切断

从 timing report 可以看到，关键路径的延迟分布：
- `vpu_data_pathway[3]` 输入 → VPU 内部组合逻辑出口：累计 **4.69ns**
- VPU 出口 → gradient_descent/fxp_mul 内部：再累计 **+2.67ns**（乘法器 partial product 树 + fxp_zoom 进位链）
- 总计 **7.36ns**，违反 10ns 约束（扣除 input delay 3ns + uncertainty 0.3ns，只剩 6.7ns 可用）

在 VPU/UB 模块边界插寄存器是最自然的切断点：
1. 不破坏任何模块内部逻辑
2. 两段路径（VPU 内部 ~4.7ns，UB 内部 ~2.7ns）接近均衡
3. 端口信号语义清晰，易于验证

---

## 修改汇总表

| 修改 | 文件 | 类型 | 原因 | 综合影响 |
|------|------|------|------|----------|
| UB 读取命令竞争条件 | `src/unified_buffer.sv` | Bug 修复 | always_comb + always_ff 双驱动 | 消除 DRC 多驱动警告 |
| gradient_descent 多驱动 | `src/gradient_descent.sv` | Bug 修复 | sub_in_a 被 FF 和组合逻辑双驱动 | 消除综合警告 |
| PE weight_reg_active 多驱动 | `src/pe.sv` | Bug 修复 | always_comb + always_ff 冲突 | 消除多驱动，PE 测试 11/11 通过 |
| 新增流水线寄存器模块 | `src/pipeline_exp/vpu_ub_pipe_stage.sv` | 新增文件 | 切断 VPU→UB 关键路径 | 频率提升分阶段体现：`164.10→166.67MHz`（首轮已证明）再到 `183.91MHz`（继续细扫收敛） |
| 新增流水线顶层 | `src/pipeline_exp/tpu_pipeline.sv` | 新增文件 | 连接流水线寄存器，保持基线不变 | 逻辑深度由基线 `49` 级大幅下降；后续文档按最终报告归纳为约 `38` 级，DRC 零违例 |

## 备份策略说明

- **Bug 修复**：直接在原文件修改，用 `.bak` 后缀保留修复前版本
  - `unified_buffer.sv.bak` ← 修复前原始
  - `gradient_descent.sv.bak` ← 修复前原始
- **性能优化**：新建文件，原始文件零改动
  - `src/pipeline_exp/` ← 实验性变体，独立于基线
- **完整快照**：`tiny-tpu_timing_opt_20260328/` ← pipeline 综合完成时的完整目录快照，含综合报告、波形、编译产物
