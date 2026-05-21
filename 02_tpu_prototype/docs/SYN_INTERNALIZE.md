# 综合流程内化手册 — Titan-TPU / SMIC 180nm

> 目标：把每一条命令、每一个报告字段、每一个优化决策都变成"我自己做的"，能在技术面上自然地讲出来。

---

## 一、整体流程思路

综合的本质是三件事：**读进来 → 约束好 → 编译优化 → 报告验收**。

```
RTL (SV)  →  analyze/elaborate  →  link  →  source SDC  →  compile_ultra  →  reports
```

每一步都有明确目的，不是黑盒。下面逐步拆解。

---

## 二、库配置：为什么这样写

```tcl
set CORNER "tt_1v8_25c"
set_app_var target_library [list ${CORNER}.db SP018W_V1p8_typ.db]
set_app_var link_library   [concat "*" $target_library]
```

**target_library**：DC 用来做 mapping 的标准单元库。SMIC 180nm 有三个 corner：
- `tt_1v8_25c`：典型角（Typical Temperature），面试说"我用 TT corner 做功能验证和初始综合"
- `ff_1v98_0c`：快角，用于 hold 检查（低温高压，FF 最快，hold 最难过）
- `ss_1v62_125c`：慢角，用于 setup 检查（高温低压，最慢，setup 最难过）

**link_library** 里的 `"*"` 表示"先在已读入的设计里找"，找不到再去 target_library 找。这是 DC 的标准写法，不加 `*` 会报 unresolved reference。

**为什么选 TT corner**：项目目标是 100MHz，TT corner 是最常用的初始综合 corner，结果有代表性。如果要做 sign-off 需要跑 SS corner。

---

## 三、读入设计：analyze vs read_file

```tcl
set_app_var hdlin_enable_vpp true          # 开启 SystemVerilog 支持
set_app_var hdlin_check_no_latch true      # 检查意外 latch（组合逻辑不完整 if/case）
analyze -format sverilog -vcs "-f filelist.f"
elaborate ${DESIGN_NAME} -parameters "SYSTOLIC_ARRAY_WIDTH=${SYSTOLIC_WIDTH}"
current_design ${DESIGN_NAME}
link
```

**analyze**：只做语法检查和中间表示，不展开层次。相当于"编译但不链接"。
**elaborate**：展开参数、生成层次、建立设计数据库。`-parameters` 传入 generate 参数，这里 `SYSTOLIC_ARRAY_WIDTH=2` 决定了脉动阵列是 2×2。
**link**：解析所有模块引用，把子模块和库单元绑定。link 失败说明有 unresolved module。
**uniquify**：把被多次例化的模块复制成独立副本，让 DC 可以对每个实例单独优化。不加 uniquify，DC 对共享模块的优化会互相干扰。

**hdlin_check_no_latch**：这个 flag 很重要。我在调试 PE 模块时发现 always_comb 里 if 分支不完整会推断出 latch，开这个 flag 会在 analyze 阶段就报 warning，比等到仿真发现要早得多。

---

## 四、SDC 约束：每一行的含义

### 4.1 时钟定义

```tcl
set CLK_PERIOD 10.0   # 100MHz
create_clock -name sys_clk -period ${CLK_PERIOD} [get_ports clk]
set_clock_uncertainty -setup 0.3 [get_clocks sys_clk]
set_clock_uncertainty -hold  0.1 [get_clocks sys_clk]
set_clock_transition  0.15  [get_clocks sys_clk]
```

**clock_uncertainty**：模拟时钟树的 jitter + skew。Setup 用 0.3ns，Hold 用 0.1ns，这是 SMIC 180nm 的经验值。实际含义：DC 在计算 setup slack 时会把可用时间从 10ns 缩短到 9.7ns，相当于给时钟树留余量。

**clock_transition**：时钟信号的上升/下降时间。180nm 工艺 0.15ns 是合理值。影响时钟到 FF clock pin 的延迟计算。

**为什么不用 create_generated_clock**：本设计只有一个时钟域，没有分频/倍频，不需要。

### 4.2 输入输出延迟

```tcl
set INPUT_DELAY  [expr ${CLK_PERIOD} * 0.3]   # 3.0ns
set OUTPUT_DELAY [expr ${CLK_PERIOD} * 0.3]   # 3.0ns
set_input_delay  ${INPUT_DELAY}  -clock sys_clk ${ALL_INPUTS}
set_output_delay ${OUTPUT_DELAY} -clock sys_clk [all_outputs]
```

**物理含义**：假设上游寄存器在时钟沿后 3ns 才把数据稳定送到本模块输入端，那么本模块内部组合逻辑只有 10 - 3 - 0.3(uncertainty) = 6.7ns 可用。

**30% 规则**：input/output delay 各占 30% 是常用经验值，表示"上下游各占 30%，本模块留 40%"。实际项目中这个值应该来自系统级时序预算（timing budget）。

### 4.3 复位处理

```tcl
set_ideal_network [get_ports rst]
set_false_path -from [get_ports rst]
```

**set_ideal_network**：告诉 DC 复位信号不需要插 buffer，不计算其传播延迟。复位是异步信号，不在时序路径上。
**set_false_path**：从 rst 出发的路径不做时序分析。如果不加，DC 会试图优化复位到 FF 的路径，浪费编译时间且无意义。

### 4.4 设计规则约束

```tcl
set_max_transition 1.0 [current_design]   # 最大转换时间 1ns
set_max_fanout 16 [current_design]        # 最大扇出 16
set_max_area 0                            # 0 = 尽量小，不设硬限制
```

**max_transition**：信号上升/下降时间超过 1ns 会导致短路电流增大、功耗上升、时序变差。SMIC 180nm 1ns 是合理上限。
**max_fanout**：一个驱动最多驱动 16 个负载。超过后 DC 会自动插 buffer tree。
**set_max_area 0**：不是"面积为 0"，而是"在满足时序的前提下尽量优化面积"。

---

## 五、compile_ultra：核心编译命令

```tcl
compile_ultra -gate_clock -no_autoungroup
compile_ultra -incremental -gate_clock
```

**compile_ultra** vs **compile**：`compile_ultra` 使用更激进的优化算法（包括 retiming、constant propagation、datapath optimization），是现代 DC 的标准选择。

**-gate_clock**：自动插入时钟门控（Clock Gating）。DC 会分析哪些寄存器组的使能条件相同，插入 ICG（Integrated Clock Gating）单元。本设计最终插入了 158+ 个 ICG 实例，覆盖 UB 存储阵列、VPU 流水级和 PE 寄存器。

**-no_autoungroup**：禁止 DC 自动打平层次。保留层次有两个好处：①面积报告按模块分层，便于分析热点；②后续 P&R 可以按层次做 floorplan。

**-incremental**：第二遍编译，在第一遍结果基础上做增量优化，主要修复 DRC 违例（transition/fanout）和小的时序违例，不重新做全局优化。速度快，效果好。

**为什么跑两遍**：第一遍 `compile_ultra` 做全局优化，可能引入新的 DRC 违例（为了满足时序而用了大驱动单元，fanout 超标）。第二遍 `-incremental` 专门修这些问题。

---

## 六、扫频脚本：二分搜索思路

```tcl
set MIN_PERIOD 3.0    # 333MHz 上限
set MAX_PERIOD 15.0   # 67MHz 下限
set TOLERANCE  0.1    # 精度 0.1ns

while {[expr $high - $low] > $TOLERANCE} {
    set mid [expr ($low + $high) / 2.0]
    # 重新读入 unmapped.ddc，重新约束，重新编译
    # 如果 WNS >= 0 (时序满足): best_period = mid, high = mid (试更高频率)
    # 如果 WNS < 0  (时序违例): low = mid (降低频率)
}
```

**为什么保存 unmapped.ddc**：每次迭代都从未映射的设计重新开始，避免上一次编译的优化结果影响下一次。如果从已映射的网表继续，DC 的优化空间会受限。

**二分搜索的收敛性**：初始范围 15-3=12ns，每次缩小一半，0.1ns 精度需要 log2(12/0.1) ≈ 7 次迭代。实际跑了约 7-8 次找到 164MHz（6.09ns）。

**WNS 解读**：`report_qor` 里 `Design WNS: 0.00` 表示最差负 slack 为 0，即时序刚好满足。WNS > 0 在 DC 的 qor report 里表示违例量（正数），脚本里做了符号转换：`wns = -1 * report_wns`，所以 `wns >= 0` 表示时序满足。

**阶段结果**：原始设计基线为 `164.10MHz（6.09ns）`；插入寄存器后的第一轮本地实验先证明了 `166.67MHz（6.00ns）` 可过；继续细扫后，最终收敛到 `183.91MHz（5.44ns）`。

---

## 七、Timing Report 解读：定位关键路径

### 7.1 报告头部

```
Startpoint: vpu_data_pathway[3]  (input port clocked by sys_clk)
Endpoint:   ub_inst/.../value_updated_out_reg[10]  (rising edge FF)
Path Group: sys_clk
Path Type:  max   ← setup 检查
```

**Startpoint**：路径起点。`input port` 说明这条路径从芯片输入端口开始，受 `set_input_delay` 约束。
**Endpoint**：路径终点。`rising edge-triggered flip-flop` 说明终点是一个 FF 的 D 端。
**Path Type: max**：setup 分析（最长路径）。`min` 是 hold 分析（最短路径）。

### 7.2 路径时序分解

```
clock sys_clk (rise edge)          0.00    0.00
clock network delay (ideal)        0.00    0.00   ← 理想时钟，无 CTS
input external delay               3.60    3.60   ← set_input_delay 3ns + uncertainty 0.3ns
vpu_data_pathway[3] (in)           0.00    3.60   ← 输入端口，无延迟
...组合逻辑链...
value_updated_out_reg[10]/D        0.00    X.XX   ← 到达时间
---
data required time                        10.00   ← 时钟周期
clock uncertainty                         -0.30
library setup time                        -0.XX
---
slack = required - arrival = 0.00         ← 刚好满足
```

**关键路径分析**：从 timing report 看到路径经过：
1. VPU 内部组合逻辑（NOR4、INV、AOI22、NAND2、AO22）→ 约 1.1ns
2. VPU 输出到 UB 输入（跨模块连线）→ 约 0ns（wire load model）
3. gradient_descent 内的 fxp_mul → 约 1.5ns（乘法器 partial product 树）
4. fxp_zoom（截位取整）→ 约 0.8ns（进位链）

**瓶颈识别**：路径在 `fxp_mul` 的 `res_zoom` 子模块里花了大量时间（进位链 ADDHX2M 串联），这是 45 级逻辑深度的主要来源。插入流水线寄存器的位置就选在 VPU 输出到 UB 写入之间，把这条跨模块长路径切断。

### 7.3 逻辑深度 vs 时序

QoR report 显示：
```
Levels of Logic:    60.00   ← 原始版本（100MHz 约束下）
Critical Path:       7.96ns
```

Pipeline 版本在第一轮就已经证明可到 `166.67MHz`，后续继续细扫收敛到 `183.91MHz`。**逻辑深度和频率的关系**：每级逻辑约 0.15-0.2ns（SMIC 180nm 典型单元延迟），45 级 ≈ 6.75-9ns，与实测 6.57ns 吻合；插入寄存器后，关键路径被拆分，最终文档归纳逻辑深度约降到 38 级。

---

## 八、Area Report 解读：识别面积热点

### 8.1 层次化面积报告结构

```
report_area -hierarchy
```

输出格式：
```
Hierarchical cell          Absolute    Percent   Combi-      Noncombi-
                           Total       Total     national    national
ub_inst                    583K        76.4%     ...         ...
  gradient_descent[0]       ...
  gradient_descent[1]       ...
vpu_inst                   130K        17.0%
systolic_inst               68K         8.9%
```

**Percent 列**：直接告诉你哪个模块是面积热点。UB 占 76.4% 是因为它包含：
- 128×16bit register file（128 个 16-bit 寄存器 = 2048 个 FF）
- 2 个 gradient_descent 模块（各含一个 fxp_mul，约 12K μm² 每个）

**Combinational vs Noncombinational**：
- Combinational：组合逻辑（AND/OR/MUX 等）
- Noncombinational：时序逻辑（FF、latch、ICG）
- 比例约 80%/20% 是正常的数字设计比例

### 8.2 面积优化决策过程

**第一步：识别热点**
从层次化报告看到 UB register file 是主要热点（76.4%）。

**第二步：分析可优化空间**
UB 深度 128 entry，但实际使用模式分析后发现 32 entry 足够覆盖 2×2 脉动阵列的数据流水需求。

**第三步：缩减 buffer 深度**
128→32 entry，register file 从 2048 FF 降到 512 FF，面积从 839K 降到约 600K μm²。

**第四步：operand isolation**
对 VPU 流水级的乘法器输入端加 operand isolation：当使能信号无效时，强制输入为 0，避免无效翻转。DC 的 `-gate_clock` 已经做了 clock gating，operand isolation 进一步降低了组合逻辑的动态功耗。效果：-3.2% 功耗（-0.41mW）。

**最终结果**：总面积 839K → 454K μm²（-46%），动态功耗降低 2.73mW（-9.4%），频率不变 183.91MHz。

---

## 九、Power Report 解读

```
                          Switch   Int      Leak     Total    %
tpu_SYSTOLIC_ARRAY_WIDTH2  1.978   10.778  1.98e+06  12.758  100.0
  vpu_inst                 0.828    3.080  3.94e+05   3.908   30.6
  ub_inst                  ...                        8.05    63.1
  systolic_inst            ...                        0.80     6.3
```

**三种功耗**：
- **Switching Power（开关功耗）**：信号翻转充放电，`P = α·C·V²·f`，α 是翻转率
- **Internal Power（内部功耗）**：单元内部短路电流，主要在输入翻转瞬间
- **Leakage Power（静态功耗）**：单位 pW，SMIC 180nm 漏电较小，总计约 1.98mW

**UB 占 63.1%** 的原因：register file 有大量 FF，每个 FF 的 internal power 不小；加上 gradient_descent 的乘法器翻转率高。

**Clock Gating 效果**：158+ ICG 实例，当 UB 某行不被访问时，对应 FF 的时钟被门控，switching power 大幅降低。这是 UB 功耗"只有"63% 而不是更高的原因。

---

## 十、DRC 检查：report_constraint

```tcl
report_constraint -all_violators > reports/constraints_violators.rpt
```

DRC 零违例意味着：
- 所有信号 transition time < 1ns（`set_max_transition 1.0`）
- 所有 net fanout ≤ 16（`set_max_fanout 16`）
- 无 max_capacitance 违例

**如果有 DRC 违例怎么处理**：
1. Transition 违例：加 `-incremental` 重跑，DC 会自动插 buffer
2. Fanout 违例：`set_dont_touch` 保护关键路径，让 DC 优先修 fanout
3. 顽固违例：手动 `size_cell` 换大驱动单元，或 `insert_buffer`

---

## 十一、输出文件的用途

```tcl
write -format verilog -hierarchy -output outputs/tpu_syn.v   # 门级网表，给 P&R
write -format ddc     -hierarchy -output outputs/tpu_syn.ddc # DC 内部格式，可重读
write_sdc outputs/tpu_syn.sdc                                # 综合后约束，给 P&R
write_sdf outputs/tpu_syn.sdf                                # 标准延迟格式，给后仿
```

**change_names -rules verilog**：把 DC 内部的特殊字符（`[`, `]`, `/`）替换为 Verilog 合法字符，否则网表里的 bus 信号名会导致后续工具报错。

---

## 十二、我的思考过程（面试时这样讲）

1. **为什么选 100MHz 作为初始目标**：SMIC 180nm 典型数字设计频率范围 50-200MHz，100MHz 是保守但合理的起点，先验证功能正确性，再做极限频率探索。

2. **为什么关键路径在 VPU→UB**：VPU 的 leaky_relu_derivative 需要做 Q8.8 定点乘法，乘法器本身就有 16×16 bit partial product 树（约 30 级逻辑），加上后面的 fxp_zoom 截位（进位链），总共 45 级。这条路径跨越了 VPU 和 UB 两个模块边界，没有寄存器切断。

3. **为什么插流水线能提频**：在 VPU 输出和 UB 写入之间插一级寄存器，把 45 级逻辑切成两段（约 22+23 级）。这一步先把设计从 `164.10MHz` 推到了已证明可过的 `166.67MHz`；后续继续细扫时钟周期，最终收敛到 `183.91MHz（5.44ns）`。代价是增加 1 个周期的延迟（latency +1），但吞吐量不变。

4. **operand isolation 和 clock gating 的区别**：Clock gating 切断时钟，FF 不翻转，节省时序逻辑功耗。Operand isolation 在组合逻辑输入端加 AND gate，当使能无效时输入强制为 0，节省组合逻辑翻转功耗。两者互补，本设计都用了。
