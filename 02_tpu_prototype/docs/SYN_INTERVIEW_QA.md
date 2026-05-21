# 综合技术面 Q&A — Titan-TPU / SMIC 180nm

> 覆盖逻辑综合、时序分析、面积/功耗优化、工具使用全方位问题。
> 每题给出"能说出来的答案"，不是背书，是理解后的表达。

---

## 一、综合基础

**Q1：逻辑综合的本质是什么？**

把 RTL（行为描述）映射到工艺库的标准单元（门级网表），同时满足时序、面积、功耗约束。分三步：
1. **Translation**：RTL → 通用布尔逻辑（GTECH）
2. **Logic Optimization**：化简布尔逻辑（两级/多级优化）
3. **Technology Mapping**：把优化后的逻辑映射到目标库的具体单元

**Q2：analyze 和 elaborate 有什么区别？**

- `analyze`：语法检查，生成中间表示（.syn 文件），不展开层次，不处理参数
- `elaborate`：展开参数（`-parameters`），建立层次，生成设计数据库
- 类比：analyze = 编译，elaborate = 链接+实例化

**Q3：为什么要 uniquify？**

如果模块 A 被例化了两次（inst1 和 inst2），DC 默认共享同一份优化结果。uniquify 把它们复制成两个独立副本，DC 可以针对每个实例的具体约束分别优化。本设计的 gradient_descent 被例化了 2 次，uniquify 后两个实例可以独立优化。

**Q4：link_library 里的 `"*"` 是什么意思？**

`"*"` 表示"在当前已读入的设计中查找"。DC 解析模块引用时，先在内存中找，找不到再去 target_library 找。不加 `"*"` 会导致子模块引用失败（unresolved reference）。

**Q5：compile 和 compile_ultra 的区别？**

`compile_ultra` 是 `compile` 的超集，额外包含：
- Retiming（寄存器重定时）
- Constant propagation（常量传播）
- Datapath optimization（加法器/乘法器结构优化）
- 更激进的 area recovery

现代项目基本都用 `compile_ultra`，`compile` 只在特殊场景（如需要精确控制优化步骤）使用。

---

## 二、SDC 约束

**Q6：create_clock 的 period 和实际频率是什么关系？**

`period = 1/frequency`，单位 ns。`-period 10.0` 对应 100MHz。DC 用这个值计算 setup slack：`slack = required_time - arrival_time = period - uncertainty - library_setup - arrival`。

**Q7：set_clock_uncertainty 的 setup 和 hold 为什么不同？**

- Setup uncertainty（0.3ns）：模拟时钟树 skew + jitter，影响 setup 分析，值偏大保守
- Hold uncertainty（0.1ns）：hold 分析时 uncertainty 方向相反（让路径看起来更短），值偏小

SMIC 180nm 经验值：setup 0.2-0.5ns，hold 0.05-0.15ns。

**Q8：set_input_delay 30% 是怎么来的？**

这是时序预算（timing budget）的经验分配：上游模块占 30%，本模块占 40%，下游模块占 30%。实际项目中应该来自系统级时序分析，但在没有上下游约束时，30% 是合理的保守估计。

**Q9：set_false_path 和 set_multicycle_path 的区别？**

- `set_false_path`：完全不做时序分析，用于异步路径（复位、跨时钟域静态信号）
- `set_multicycle_path`：允许路径跨多个时钟周期，用于已知需要多拍完成的路径（如慢速接口）

本设计对 rst 用 `set_false_path`，因为复位是异步信号，不在时序路径上。

**Q10：set_max_area 0 是什么意思？**

不是"面积为 0"，而是"在满足所有时序和 DRC 约束的前提下，尽量最小化面积"。DC 会在时序收敛后做 area recovery（用小单元替换大单元）。

**Q11：set_ideal_network 用在哪里？**

用于复位、扫描使能等全局控制信号。告诉 DC 这些信号不需要插 buffer，不计算传播延迟。如果不加，DC 会把复位信号当普通信号处理，可能插入不必要的 buffer 并影响时序分析。

---

## 三、时序分析

**Q12：setup violation 和 hold violation 分别怎么修？**

| 违例类型 | 原因 | 修法 |
|---------|------|------|
| Setup violation | 组合逻辑太慢，数据来不及在时钟沿前稳定 | 换快单元、插流水线、逻辑优化 |
| Hold violation | 数据传播太快，在时钟沿后立刻变化 | 插 delay buffer、换慢单元 |

Setup 是"太慢"，Hold 是"太快"。两者不能同时用同一种方法修。

**Q13：什么是 critical path？怎么找？**

Critical path 是 slack 最小（最差）的时序路径。找法：
```tcl
report_timing -max_paths 1 -delay max   # 最差 setup 路径
report_timing -max_paths 1 -delay min   # 最差 hold 路径
```

本设计关键路径：`vpu_data_pathway[3]` → `gradient_descent/fxp_mul/res_zoom` → FF，路径长 7.36ns（100MHz 约束下），经过 VPU 内部组合逻辑 + 跨模块连线 + fxp_mul 乘法器 + fxp_zoom 截位。

**Q14：timing report 里 Incr 和 Path 列分别是什么？**

- **Incr**：该段的增量延迟（本单元/连线贡献的延迟）
- **Path**：从起点到当前位置的累计延迟

看 Incr 列可以找到延迟最大的单元，是优化的切入点。

**Q15：逻辑深度（Levels of Logic）和频率的关系？**

`最大频率 ≈ 1 / (逻辑深度 × 单级延迟 + FF setup + clock uncertainty)`

SMIC 180nm 典型单元延迟 0.1-0.2ns，45 级逻辑 ≈ 4.5-9ns 组合延迟。本设计 45 级，关键路径 6.57ns，平均每级约 0.146ns，符合预期。

插流水线后，这条路径先在本地实验里证明了 `6.00ns / 166.67MHz` 可过；继续细扫后，最终收敛到 `5.44ns / 183.91MHz`。文档里通常把最终逻辑深度归纳为约 38 级。

**Q16：WNS 和 TNS 分别是什么？**

- **WNS（Worst Negative Slack）**：最差路径的 slack，负数表示违例。WNS=0 表示时序刚好满足。
- **TNS（Total Negative Slack）**：所有违例路径的 slack 之和，反映违例的"总量"。

修时序时先看 WNS 定位最差路径，再看 TNS 判断整体违例严重程度。

**Q17：为什么 slack=0 而不是正数？**

DC 的 `compile_ultra` 会在时序满足后做 area recovery（用小单元替换大单元），直到 slack 接近 0。这是正常的优化行为，不是巧合。如果想保留正 slack（timing margin），可以把 clock period 设得更紧（比如 9ns 而不是 10ns）。

---

## 四、面积分析与优化

**Q18：怎么用 report_area 找面积热点？**

```tcl
report_area -hierarchy
```

看 `Percent Total` 列，从大到小排序。本设计：
- UB：76.4%（register file + gradient_descent）
- VPU：17.0%（多个乘法器）
- Systolic：8.9%（4个PE，每个含乘法器）

热点在 UB，进一步看 UB 内部，gradient_descent 的 fxp_mul 是主要贡献者（每个约 12K μm²）。

**Q19：Combinational area 和 Noncombinational area 分别包含什么？**

- **Combinational**：AND/OR/MUX/加法器等组合逻辑单元
- **Noncombinational**：FF、latch、ICG（时钟门控单元）

本设计比例约 80%/20%，组合逻辑占主导，说明计算密集型设计（乘法器多）。如果是存储密集型设计，noncombinational 比例会更高。

**Q20：缩减 UB 深度从 128 到 32 的依据是什么？**

分析数据流：2×2 脉动阵列每次计算需要 2 行输入数据 + 2 行权重 + 2 行偏置 + 2 行输出，加上流水线 buffer，32 entry 足够覆盖一次完整的矩阵乘法操作。128 entry 是原始设计的保守估计，对于 2×2 规模是过度设计。

**Q21：operand isolation 是什么？怎么实现？**

在组合逻辑（通常是乘法器）的输入端插入 AND gate，当使能信号无效时强制输入为 0：

```
data_in_isolated = data_in & {WIDTH{enable}}
```

效果：使能无效时，乘法器输入全 0，内部不发生翻转，switching power 降低。DC 的 `compile_ultra` 可以自动做，也可以手动在 RTL 里加。本设计通过 DC 自动 operand isolation 降低了 3.2% 功耗（-0.41mW）。

---

## 五、功耗分析与优化

**Q22：动态功耗的公式是什么？各项怎么降低？**

`P_dynamic = α · C · V² · f`

- **α（翻转率）**：clock gating、operand isolation 降低翻转率
- **C（负载电容）**：减少 fanout、缩短连线（P&R 阶段）
- **V（电压）**：多电压域设计（本项目未做）
- **f（频率）**：降频（与性能矛盾）

**Q23：Clock Gating 的原理和实现？**

原理：当寄存器组的数据不需要更新时，门控时钟，FF 不翻转，switching power 为 0。

实现：DC `-gate_clock` 自动识别使能条件相同的 FF 组，插入 ICG（Integrated Clock Gating）单元：
```
ICG: clk_out = clk & enable  (latch-based，避免毛刺)
```

本设计插入 158+ ICG 实例，主要在 UB 存储阵列（每行一个 ICG）、VPU 流水级（每级使能）、PE 寄存器（weight load 使能）。

**Q24：Leakage power 怎么优化？**

SMIC 180nm 漏电相对较小（本设计约 1.98mW，占总功耗 15.5%）。优化方法：
1. 使用 HVT（高阈值电压）单元替换非关键路径上的 LVT 单元
2. 多阈值电压综合：`compile_ultra -gate_clock` + `set_multi_vth_optimization`
3. 本设计未做 multi-Vth 优化，因为 SMIC 180nm PDK 提供的库以 SVT 为主

**Q25：report_power 的结果准确吗？**

综合阶段的功耗是估算值，基于：
- 默认翻转率（通常 0.1-0.2，即每个时钟周期 10-20% 的信号翻转）
- Wire load model（估算连线电容）
- 无实际仿真激励

更准确的功耗分析需要：后仿真（带 SDF）+ 实际激励的 VCD 文件 → PrimeTime PX。综合阶段的功耗报告误差可达 20-30%，用于相对比较（优化前后对比）比绝对值更有意义。

---

## 六、流水线优化

**Q26：为什么插流水线能提高频率？**

流水线把长组合逻辑路径切成多段，每段延迟更短，时钟周期可以缩短。代价：
- 增加寄存器（面积增加）
- 增加延迟（latency，从输入到输出需要更多时钟周期）
- 吞吐量不变（每个时钟周期仍然处理一个数据）

本设计在 VPU 输出到 UB 写入之间插一级寄存器，把 45 级逻辑切断。阶段结果是：先证明 `164.10MHz -> 166.67MHz`，继续细扫后最终收敛到 `183.91MHz`。

**Q27：插流水线寄存器的位置怎么选？**

原则：在关键路径的中间切断，使两段延迟尽量均衡。

实践：从 timing report 的 Incr 列找到延迟突变点。本设计关键路径在 VPU 输出（约 4.69ns）进入 gradient_descent 的 fxp_mul（后续约 2.67ns），在 VPU/UB 模块边界插寄存器是自然的切断点，不破坏模块内部逻辑。

**Q28：Retiming 和手动插流水线的区别？**

- **Retiming**：DC 自动移动寄存器位置（不改变寄存器数量），优化已有流水线的平衡性
- **手动插流水线**：在 RTL 里增加寄存器级数，改变设计的 latency

本设计用手动插流水线，因为需要在模块边界处切断，RTL 修改更直观，也便于验证（可以单独测试每一级）。

---

## 七、DRC 与工具使用

**Q29：综合阶段的 DRC 检查什么？**

- **Max Transition**：信号上升/下降时间。超标说明驱动能力不足，需要换大单元或插 buffer
- **Max Fanout**：一个驱动连接的负载数。超标需要插 buffer tree
- **Max Capacitance**：连线总电容。超标影响信号完整性和时序

本设计 DRC 零违例：`set_max_transition 1.0`，`set_max_fanout 16`，两遍 `compile_ultra` 后全部满足。

**Q30：check_design 会报什么问题？**

常见问题：
- **Unresolved references**：有模块引用但找不到定义（link 失败）
- **Multiple drivers**：同一信号被多个 always 块驱动（本设计修复过 PE 的 weight_reg_active 多驱动）
- **Unconnected ports**：端口悬空
- **Latch inference**：组合逻辑 if/case 不完整推断出 latch

**Q31：write_sdc 和原始 constraints.sdc 有什么区别？**

`write_sdc` 输出的是综合后的 SDC，包含：
- 原始约束（时钟、IO delay）
- DC 自动生成的约束（如 generated clock、dont_touch）
- 已展开的参数化约束

这个文件给 P&R 工具（ICC2/Innovus）使用，确保布局布线阶段的时序约束与综合一致。

**Q32：write_sdf 是什么？给谁用？**

SDF（Standard Delay Format）包含综合后网表中每个单元和连线的延迟信息，用于：
- **后仿真（Gate-level simulation）**：在 VCS/ModelSim 中用 `$sdf_annotate` 加载，验证门级网表功能和时序
- 本设计用 VCS + SDF 做了门级仿真验证，确认 RTL 功能在综合后保持正确

---

## 八、项目相关深挖

**Q33：你的关键路径具体在哪里？为什么在那里？**

关键路径：`vpu_data_pathway[3]`（输入端口）→ VPU 内部 NOR4/INV/AOI22/NAND2/AO22 组合逻辑 → `vpu_data_out_1[8]`（VPU 输出）→ `ub_inst/gradient_descent[0]/fxp_mul/res_zoom`（UB 内乘法器截位）→ FF。

原因：
1. VPU 的 leaky_relu_derivative 需要 Q8.8 × Q8.8 定点乘法，乘法器 partial product 树本身就有约 30 级逻辑
2. fxp_zoom 截位模块有进位链（ADDHX2M 串联），又贡献约 15 级
3. 这条路径跨越 VPU 和 UB 两个模块，中间没有寄存器切断

**Q34：你是怎么发现 UB 是面积热点的？**

运行 `report_area -hierarchy`，看 Percent 列：UB 占 76.4%，远超 VPU（17%）和 Systolic（8.9%）。进一步展开 UB 的层次，发现 register file（128×16bit = 2048 FF）和 gradient_descent 的 fxp_mul（每个约 12K μm²）是主要贡献者。

**Q35：operand isolation 的 -3.2% 功耗是怎么测出来的？**

对比两次综合结果的 `report_power`：
- 优化前：总功耗 X mW
- 加 operand isolation 后：总功耗 X - 0.41mW

差值 0.41mW / X mW ≈ 3.2%。注意这是综合阶段的估算值，基于默认翻转率，实际效果需要后仿真验证。

**Q36：你的综合结果 slack=0，这是真的时序收敛吗？**

是的，但需要说明：
1. 这是 TT corner（典型角），sign-off 需要跑 SS corner（慢角，高温低压）
2. 没有做 CTS（时钟树综合），用的是 ideal clock，实际 P&R 后时钟树会引入 skew
3. 没有做 SI（信号完整性）分析，串扰可能影响时序
4. 综合阶段用的是 wire load model，实际连线延迟在 P&R 后才准确

所以这个结果是"综合阶段时序收敛"，完整的 sign-off 还需要 P&R + STA。

**Q37：如果让你继续优化，下一步做什么？**

1. **SS corner 验证**：用 `ss_1v62_125c.db` 重跑，确认慢角时序是否满足
2. **多阈值电压**：对非关键路径换 HVT 单元，降低漏电功耗
3. **更激进的流水线**：在 fxp_mul 内部再插一级寄存器，进一步提频
4. **P&R**：用 ICC2 做布局布线，获得真实的连线延迟，做 sign-off STA
5. **功耗分析**：用实际仿真 VCD 做 PrimeTime PX，获得准确功耗数据

---

## 九、快问快答（面试高频）

| 问题 | 简答 |
|------|------|
| setup time 是什么？ | FF 在时钟沿前数据必须稳定的最短时间 |
| hold time 是什么？ | FF 在时钟沿后数据必须保持稳定的最短时间 |
| 什么是 slack？ | required time - arrival time，正数表示满足，负数表示违例 |
| 什么是 timing arc？ | 单元内部从输入到输出的延迟路径，库文件里查 |
| 什么是 wire load model？ | 根据 fanout 估算连线电容的模型，综合阶段用，P&R 后用实际值替换 |
| ICG 单元为什么用 latch？ | latch-based ICG 在时钟低电平时锁存使能，避免时钟毛刺 |
| 什么是 dont_touch？ | 告诉 DC 不要优化某个单元/网络，用于保护关键路径或特殊单元 |
| 什么是 size_only？ | 只允许换同功能不同驱动强度的单元，不改变逻辑结构 |
| 综合和 P&R 的分工？ | 综合：逻辑优化+单元映射；P&R：物理布局+连线+时钟树 |
| 为什么需要 uniquify？ | 让 DC 对每个实例独立优化，避免共享模块的约束冲突 |
