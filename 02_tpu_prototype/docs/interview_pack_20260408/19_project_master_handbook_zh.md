# TPU 项目总手册

这份手册把当前这套项目材料整合成一个可连续阅读的单文件版本。

配合 PPT 的建议用法：
- 主讲时看 `01_main_8p.pptx`
- 被追问时翻 `02_appendix_35p.pptx`
- 自己系统复习时，就按这份手册从前往后读

推荐阅读方式：
1. 先读“材料总索引与阅读路线图”这一部分，知道整套材料怎么用。
2. 再读“项目全景说明文”，先把主线吃透。
3. 再读“源码全景精讲”和各模块精讲，理解软件到硬件的映射。
4. 最后读带行号批注版，把关键文件真正啃下来。

一句话总结：
**这份手册的目标，不是替代 PPT，而是把 PPT 背后的项目来龙去脉、源码结构和验证证据一次性串起来。**
---

# Part 0 后续改进计划补充

这一部分专门补两件在面试里很容易被追问的事：
- 为什么当前编译器不是 cycle-accurate
- `vpu_drain` 为什么既重要又会影响性能，以及后面怎么改

---

## 0.1 当前编译器到底是什么样

当前编译器更准确地说，是一个**阶段级微程序生成器**，不是逐拍波形程序生成器。

它现在已经能做的事情包括：
- 把模型规格分配到 UB 地址空间
- 生成 `host_load_plan`
- 生成 stage-level 的 `schedule`
- 把控制语义编码成 IMEM 指令

也就是说，它已经能回答：
- 这一阶段要读哪个 tensor
- 从 UB 哪个地址读
- 读多少行、多少列
- 这条命令对应什么 `ptr_select`
- 当前 VPU 走哪条 pathway
- 阶段之间哪些地方要 `wait_after`

但它还不能精确回答：
- 某条命令发出后第几拍 UB 真正开始发数
- 第几拍 PE 波前推进到尾拍
- 第几拍 VPU 最后一拍 `valid` 才掉下去
- 第几拍写回数据在 UB 中真正可见

所以它现在是“把系统闭环跑通”的编译器，不是“把每一拍都压到最优”的编译器。

---

## 0.2 为什么说它不是 cycle-accurate

原因不是不会做，而是当前目标优先级不同：

1. 先保证软件、控制、执行和验证这条系统链能闭合。
2. 先把 `scheduler -> IMEM -> Frontend -> control_unit -> UB/PE/VPU` 跑通。
3. 先把 train convergence 做出来，证明系统语义成立。

在这个阶段，编译器只需要做到“阶段级正确”，不需要先做到“逐拍最优”。

放到当前代码里，这件事很直观：
- `scheduler.py` 生成的是 `ub_read / control / wait / nop`
- `schedule.json` 里也明确写了 `stage-level`、`not cycle-accurate`
- 代码里很多等待仍然是固定 `nop(4)` 和规则式 `wait_after`

所以现在更像：
- “写流程脚本”

而不是：
- “写每拍时序剧本”

---

## 0.3 更好的编译器可以做成什么样

### 1. 真正的 cycle-accurate latency model

编译器要知道 UB、PE、VPU 每条路径各自的真实延迟，而不是靠固定 `nop(4)` 和经验性的 `wait_after`。

也就是说，它要知道：
- 某次 `UB_RD` 发出后几拍 PE 才开始有效
- VPU 某条 pathway 会持续多少拍
- 写回数据几拍后在 UB 中稳定可读

### 2. 资源冲突建模

编译器要知道“顺序”还不够，还要知道“冲突”。

例如同一拍里，哪些事情不能重叠：
- 某个 UB 读口正在发数
- 某条写回路径正在写 UB
- shadow weight 正在装载
- active compute 正在运行
- VPU 正在占用某条 pathway

如果这些资源会抢占，就要自动避冲突；如果不会冲突，就应该允许 overlap。

### 3. 自动插入最少等待

当前很多等待是手工或规则式插入的。

更好的版本应该根据硬件模型自动算出：
- 最小安全 `nop`
- 最小必要 `wait_after`
- 哪些阶段完全不用等

目标不是“能跑就行”，而是“不多等也不少等”。

### 4. 性能导向优化

当前调度偏保守，优先保证正确性。

更强的调度器会主动做这些事：
- 重排 tile 顺序
- 尽量让 load 和 compute 重叠
- 在 drain 窗口里塞独立工作
- 压缩总 cycle

所以它的目标会从“闭环跑通”升级成“吞吐最优”。

---

## 0.4 `vpu_drain` 到底在等什么

`wait_after` 的本质，是把“命令已经发出”和“这条命令引发的后级流水真的收尾了”区分开。

在当前 Frontend 里：
- `seq_instr[23]` 就是 `wait_after`
- 如果一条指令带这个标志，sequencer 会从 `SEQ_DISPATCH` 进入 `SEQ_WAIT`
- 只有当 `vpu_drain` 到来，Frontend 才会 `ADVANCE`

而 `vpu_drain` 本身不是随便定义的，它等的是：
- `tpu_vpu_valid_in` 从 1 掉到 0
- 也就是 VPU 最后的 valid 尾拍真正吐完

当前 SoC 顶层里，`tpu_vpu_valid_in` 又是两路 `vpu_valid_out` 的 OR。

所以 `vpu_drain` 的语义很明确：
- 不是“前端把命令发完了”
- 而是“后级这波 VPU 相关流水真的吐干净了”

---

## 0.5 为什么 `wait_after -> vpu_drain` 很重要

因为真正的系统阶段边界不是 `dispatch`，而是“结果已经稳定写回，下一阶段再读也不会串”。

比如在 forward layer1 里，bias 流触发后，`H1` 还会继续经过后级路径并写回 UB。

如果这时候不等 `vpu_drain`，Frontend 可能会过早：
- 改 `vpu_pathway`
- 改 `ub_ptr_sel`
- 发下一阶段的 `UB_RD`

结果就是：
- 前一阶段尾拍还没吐完
- 后一阶段头拍已经进来了
- 两阶段的数据语义在边界处重叠

所以 `wait_after` 的价值是：
- 让阶段边界和真正的写回完成边界对齐

它是正确性机制，不是装饰性等待。

---

## 0.6 `vpu_drain` 会不会影响性能

会，而且在当前设计里它是一个比较保守的全局 barrier。

原因很简单：
- 只要一条命令打了 `wait_after`
- Frontend 就会停在 `SEQ_WAIT`
- 一直等到整条 VPU 输出都完全清空

这当然安全，但代价是吞吐会下降。

因为它等的是“后级全清空”，不是“下一条命令真正依赖的那部分已经就绪”。

所以从性能视角看，`vpu_drain` 的特点是：
- 正确性强
- 实现简单
- 边界清楚
- 但偏保守

---

## 0.7 后面怎么改，才能既保正确性又少等

### 近一步

先不大改 RTL，只改编译器和调参方式：
- 用实测 latency 表替代固定 `nop(4)`
- 减少不必要的 `wait_after`
- 把独立工作尽量塞进 drain 窗口

### 中一步

把“全局 `vpu_drain`”拆成更细的 done 条件：
- `ub_writeback_done`
- `pathway_done`
- `pe_done`
- 某类 update 完成信号

这样 Frontend 不必总等整个后级清空，而是只等当前依赖的那部分完成。

### 长一步

做真正的吞吐型架构优化：
- 双缓冲
- 更多 UB bank / 端口
- 更强的 shadow / active overlap
- 指令队列或 scoreboard

这样 load、compute、writeback 才能更充分重叠。

---

## 0.8 面试时可以怎么一句话收口

可以直接这样说：

当前编译器先做到的是阶段级正确，也就是把系统闭环跑通；它还不是 cycle-accurate 的硬件感知调度器。`vpu_drain` 在当前版本里是一个保守但安全的阶段边界，会影响吞吐，但它先保证了训练语义不串。后续更好的方向，不是简单删掉 `vpu_drain`，而是做更精确的 latency model、资源冲突建模和细粒度 done 信号，让编译器只等真正必须等的那部分。



---

# Part 1 材料总索引与阅读路线图

# TPU 项目材料总索引与阅读路线图

这份文档的目标很简单：
**把共享目录里的 PPT、总览文档、源码精讲、带行号批注版串成一套可执行的阅读顺序。**

如果你后面要做三件事：
- 快速准备面试
- 系统复习整个项目
- 被追问时快速找到对应源码

就先看这份索引。

---

## 一、共享目录里每个文件是干什么的

### 1. PPT

#### `01_main_8p.pptx`
主讲版。
只保留 8 页主线，适合正式汇报和面试主讲。

#### `02_appendix_35p.pptx`
附录版。
保留动态演示页、拆页、验证细节、追问展开页，适合老师/面试官追问时翻。

#### `03_clean_ref_rtl.pptx`
参考风格稿。
主要用来对照版式和画面风格，不是主学习材料。

#### `04_clean_ref_full.pptx`
另一份参考风格稿。
同样主要用于视觉参考，不是项目理解主线。

---

### 2. 总览类文档

#### `05_project_explainer_zh.md`
全景说明文。
适合第一次完整理解这个项目“为什么做、做了什么、最后跑成什么样”。

#### `06_interview_walkthrough_zh.md`
逐页面试讲稿。
按 `01_main_8p.pptx` 的页序往下讲，适合你熟悉主讲口径。

#### `07_study_guide_zh.md`
复习提纲。
适合自己复习，帮你抓重点，不会一上来陷进细节。

#### `08_source_deep_dive_zh.md`
源码全景精讲。
适合从“PPT 主线”切到“源码主线”，知道哪些文件最关键。

---

### 3. 关键模块精讲

#### `09_frontend_axil_deep_dive_zh.md`
专讲 `tpu_frontend_axil.sv`。
重点是寄存器、IMEM、sequencer、wait/drain、host/CU 写口仲裁。

#### `10_unified_buffer_deep_dive_zh.md`
专讲 `unified_buffer_v3.sv`。
重点是 `ptr_select`、`wr_ptr_base/restore`、input/weight 读流差异、UB 内更新。

#### `11_scheduler_deep_dive_zh.md`
专讲 `scheduler.py`。
重点是 stage-level 调度、`_ub_read()`、`_switch()`、`_wait()`、forward/backward/update 阶段含义。

---

### 4. 带行号批注版

#### `12_frontend_axil_annotated_zh.md`
对着 `tpu_frontend_axil.sv` 源码行号解释。
适合你已经知道大概逻辑，接下来要逐段读 RTL。

#### `13_unified_buffer_annotated_zh.md`
对着 `unified_buffer_v3.sv` 行号解释。
适合你要吃透 `UB` 难点。

#### `14_train_convergence_test_annotated_zh.md`
对着训练收敛测试脚本行号解释。
适合你从“验证角度”理解系统闭环如何被证明。

#### `15_tpu_soc_annotated_zh.md`
对着 `tpu_soc.sv` 行号解释。
重点看 SoC 顶层、Frontend 和 TPU core 怎么焊起来。

#### `16_tpu_core_annotated_zh.md`
对着 `tpu.sv` 行号解释。
重点看 `UB -> systolic -> VPU -> UB` 的执行核心闭环。

#### `17_control_unit_annotated_zh.md`
对着 `control_unit.sv` 行号解释。
重点看 32-bit 指令如何被拆成硬件字段。

---

## 二、如果你只剩 15 分钟，应该怎么看

### 路线 A：上台前快速过一遍

1. 先看 `01_main_8p.pptx`
2. 再看 `06_interview_walkthrough_zh.md`
3. 再看 `07_study_guide_zh.md` 里的“必须懂的点”
4. 最后扫一眼 `05_project_explainer_zh.md` 的开头和结尾

这条路线的目标不是吃透所有细节，而是保证你能把主线讲顺：
- 这个项目原来缺什么
- 你补了哪些模块
- 一轮训练怎么从 host 一路跑到结果
- 怎么证明它真的跑通了

---

## 三、如果你想系统复习整个项目，应该怎么读

### 路线 B：1 到 2 小时完整复习

1. `01_main_8p.pptx`
2. `05_project_explainer_zh.md`
3. `07_study_guide_zh.md`
4. `08_source_deep_dive_zh.md`
5. `09_frontend_axil_deep_dive_zh.md`
6. `10_unified_buffer_deep_dive_zh.md`
7. `11_scheduler_deep_dive_zh.md`
8. `12` 到 `17` 的带行号批注版
9. 最后翻 `02_appendix_35p.pptx`

这条路线适合你在面试前一天或正式答辩前，完整把项目重新过一遍。

---

## 四、如果你是按“源码阅读”来理解项目，顺序怎么排

建议按下面这个顺序读源码：

1. `scheduler.py`
2. `control_unit.sv`
3. `tpu_frontend_axil.sv`
4. `tpu_soc.sv`
5. `tpu.sv`
6. `unified_buffer_v3.sv`
7. `test_tpu_soc_axil_train_convergence.py`

这个顺序的原因是：
- 先看软件怎么生成控制语义
- 再看硬件怎么 decode 成字段
- 再看 Frontend 怎么按节奏发
- 再看 SoC 顶层怎么接系统
- 再看 core 怎么跑数据闭环
- 最后看验证怎么证明整个系统真的成立

---

## 五、如果面试官追问某个问题，你该打开哪个文件

### 1. “这个项目到底做成了什么？”
看：
- `01_main_8p.pptx`
- `05_project_explainer_zh.md`
- `06_interview_walkthrough_zh.md`

### 2. “Host 怎么控制 TPU？”
看：
- `09_frontend_axil_deep_dive_zh.md`
- `12_frontend_axil_annotated_zh.md`
- `15_tpu_soc_annotated_zh.md`

### 3. “编译器怎么和硬件对上？”
看：
- `11_scheduler_deep_dive_zh.md`
- `17_control_unit_annotated_zh.md`

### 4. “为什么说它已经是训练闭环，不是推理 demo？”
看：
- `05_project_explainer_zh.md`
- `10_unified_buffer_deep_dive_zh.md`
- `16_tpu_core_annotated_zh.md`
- `14_train_convergence_test_annotated_zh.md`

### 5. “UB 为什么最难？”
看：
- `10_unified_buffer_deep_dive_zh.md`
- `13_unified_buffer_annotated_zh.md`

### 6. “你具体修了哪些 bug？”
先看：
- `02_appendix_35p.pptx` 里的相关页
再回到：
- `09_frontend_axil_deep_dive_zh.md`
- `10_unified_buffer_deep_dive_zh.md`
- `11_scheduler_deep_dive_zh.md`

---

## 六、主讲版 8 页 PPT 对应什么源码主题

### 第 1 页：封面
作用：
- 只负责定题，不讲细节。

### 第 2 页：系统总览
你脑子里要对应：
- `scheduler.py`
- `tpu_frontend_axil.sv`
- `tpu.sv`
- `test_tpu_soc_axil_train_convergence.py`

### 第 3 页：项目级 RTL 结构
对应：
- `tpu_soc.sv`
- `tpu_frontend_axil.sv`
- `tpu.sv`

### 第 4 页：编译器与指令组织
对应：
- `scheduler.py`
- `control_unit.sv`

### 第 5 页：Unified Buffer 设计
对应：
- `unified_buffer_v3.sv`

### 第 6 页：PE 与计算阵列
对应：
- `tpu.sv`
- `systolic` 相关逻辑
- `vpu` 相关逻辑

### 第 7 页：验证波形与回归覆盖
对应：
- `test_tpu_soc_axil_train_convergence.py`
- 回归测试和波形证据

### 第 8 页：结果、边界与追问方向
对应：
- 结果总结
- 工程边界
- 追问时切到附录 `02_appendix_35p.pptx`

---

## 七、如果你要“边看 PPT 边读文档”，最省力的组合是什么

### 组合 1：主讲训练
- 打开 `01_main_8p.pptx`
- 辅助看 `06_interview_walkthrough_zh.md`

### 组合 2：项目理解
- 打开 `01_main_8p.pptx`
- 辅助看 `05_project_explainer_zh.md`

### 组合 3：源码复习
- 打开 `08_source_deep_dive_zh.md`
- 辅助看 `12-17` 带行号批注版

### 组合 4：老师追问
- 主讲时用 `01_main_8p.pptx`
- 被追问时切 `02_appendix_35p.pptx`
- 追问后自己复盘时看 `09-17`

---

## 八、最值得背下来的 8 个项目关键词

1. `AXI-Lite controllable SoC wrapper`
2. `Frontend sequencer + IMEM`
3. `32-bit instruction -> control fields`
4. `UB pointer select / restore`
5. `shadow -> active switch`
6. `UB -> systolic -> VPU -> UB`
7. `training convergence evidence`
8. `not a single-point demo, but a full closed loop`

---

## 九、最后给你的建议

如果你后面时间不多，就按这个原则：

1. 主讲只讲 `01_main_8p.pptx`
2. 被追问就翻 `02_appendix_35p.pptx`
3. 自己复习先看 `05/06/07`
4. 要吃透源码再看 `08-17`

一句话总结：
**`01/02` 负责讲，`05-08` 负责懂，`09-17` 负责深挖。**


---

# Part 2 项目全景说明文

# TinyTPU AXI-Lite SoC 项目说明文

这份文档不是给面试官看的摘要，而是给你自己看的“项目全景 + 关键细节 + 代码抓手”。
目标是让你把这套项目真正看成一条完整链路，而不是几页 PPT 或几段 RTL。

对应你当前的主讲版 PPT：
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/01_main_8p.pptx`
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/02_appendix_35p.pptx`

---

## 1. 先说结论：这个项目到底做成了什么

一句话总结：
**这个项目把原本更偏“裸核/测试台驱动”的 tiny-tpu，接成了一套可以由 AXI-Lite 主机控制、可以装载 UB 和 IMEM、可以执行 2 层 MLP 训练流程、并且能用波形和收敛结果证明正确性的完整系统。**

它不是做了一个很大的 NPU，也不是做了通用编译器，而是把下面这条链真正打通了：

1. 软件侧给出 MLP 规格。
2. 编译器把规格变成 `ub_map + schedule + imem`。
3. Host 通过 AXI-Lite 把参数、数据和指令写进 SoC。
4. Frontend 负责寄存器、IMEM、sequencer、dispatch、wait。
5. TPU core 里的 UB、PE、VPU 执行前向、反向和更新。
6. Cocotb 端到端验证 loss 下降，并最终在 XOR 上收敛。

所以它的价值不在“规模大”，而在“闭环完整”。

---

## 2. 项目的来龙去脉

### 2.1 原始 tiny-tpu 的问题

原始 tiny-tpu 更像一个“计算核心原型”：
- 有 `systolic`、`vpu`、`unified_buffer` 这些核心模块。
- 能表达 2x2 阵列、forward/backward/update 这些训练语义。
- 但系统级接口、主机控制、程序装载、验证闭环并不完整。

也就是说，原始版本更像“核是对的”，但还不是“系统可用”。

### 2.2 这个项目做了什么补全

你这套工程做的，是把它补成真正可演示、可验证的 SoC 原型：

- 加了 `tpu_soc.sv`，把前端和 core 包成一个可控顶层。
- 加了 `tpu_frontend_axil.sv`，把 AXI-Lite、寄存器、IMEM、sequencer 接起来。
- 把编译输出固定成当前 tiny-tpu 能执行的 **阶段级 schedule**。
- 把 UB 地址空间规划清楚，让训练中间结果和更新结果都能落回 UB。
- 用 `cocotb` 跑多 epoch 训练，验证 loss 下降和最终分类正确。

所以这个项目真正回答的问题是：
**tiny-tpu 怎么从“能算”变成“能被主机控制、能执行一整轮训练、还能被证明跑对”。**

---

## 3. 用 PPT 看项目，应该怎么对应

主讲版 `01_main_8p.pptx` 一共 8 页，其中：

1. 第 1 页是封面，只负责定题，不展开技术细节。
2. 第 2 页 `系统总览`：先看整条链有没有闭环。
3. 第 3 页 `项目级 RTL 结构`：看顶层模块怎么接。
4. 第 4 页 `编译器与指令组织`：看软件产物怎么落到硬件。
5. 第 5 页 `Unified Buffer 设计`：看数据在系统里怎么流。
6. 第 6 页 `PE 与计算阵列`：看真正的乘加阵列怎么工作。
7. 第 7 页 `验证波形与回归覆盖`：看是不是“真的跑对”。
8. 第 8 页 `结果、边界与追问方向`：看做到哪、没做到哪。

附录版 `02_appendix_35p.pptx` 负责展开主讲版故意压掉的细节，重点是：
- Frontend 配置面和运行面
- `wr_ptr/base/restore`
- UB-PE 时序对齐
- VPU pathway
- 关键控制 bug 修复
- Compiler / Frontend / UB / VPU / PE 的 GIF 单步演示

所以最好的理解顺序，不是先读 RTL，而是：
**PPT 主线 -> 这份说明文 -> 再回头看局部代码。**

---

## 4. 系统顶层：它到底怎么连起来

最顶层是 `tpu_soc.sv`。

代码里最核心的事情，其实就是两句：

```systemverilog
// Frontend
 tpu_frontend_axil frontend (...);

// TPU core
 tpu tpu_inst (...);
```

完整上下文在：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_soc.sv`

更完整一点的片段是：

```systemverilog
tpu_frontend_axil #(
    .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
) frontend (
    .s_axil_aclk    (s_axil_aclk),
    .s_axil_aresetn (s_axil_aresetn),
    ...
    .ub_wr_host_data_out_0       (ub_wr_host_data_0),
    .ub_wr_host_valid_out_0      (ub_wr_host_valid_0),
    .ub_wr_ptr_restore_out       (ub_wr_ptr_restore),
    .sys_switch_out              (sys_switch),
    .ub_rd_start_out             (ub_rd_start),
    .ub_ptr_sel_out              (ub_ptr_sel),
    .vpu_data_pathway_out        (vpu_data_pathway)
);

 tpu #(
    .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
) tpu_inst (
    .ub_wr_host_data_in         (ub_wr_host_data),
    .ub_wr_host_valid_in        (ub_wr_host_valid),
    .ub_wr_ptr_restore_in       (ub_wr_ptr_restore),
    .ub_rd_start_in             (ub_rd_start),
    .ub_ptr_select              ({6'h0, ub_ptr_sel}),
    .vpu_data_pathway           (vpu_data_pathway),
    .sys_switch_in              (sys_switch),
    ...
);
```

这说明顶层做的不是运算，而是**桥接**：
- 上面对接 AXI-Lite Host。
- 中间把控制信号从 frontend 解码出来。
- 下面把这些控制信号送进 tpu core。

所以 `tpu_soc` 的价值，是把“主机世界”和“计算世界”接起来。

---

## 5. Frontend：这个项目真正的控制中枢

### 5.1 它做什么

`tpu_frontend_axil.sv` 不是一个简单寄存器块，而是四个功能叠在一起：

1. AXI-Lite 寄存器映射
2. IMEM 存储
3. 指令 sequencer
4. 指令译码和控制脉冲发射

代码开头其实已经把寄存器地图写得很清楚：

```systemverilog
//   0x00  CTRL       bit0=step   write-1 dispatches INSTR_W0 for one cycle
//                   bit1=start  write-1 starts auto-run from imem[0..imem_len-1]
//   0x04  STATUS     bit0=busy
//                   bit1=running
//   0x10  INSTR_W0   32-bit opcode instruction (step mode staging)
//   0x20  UB_DATA    bits[15:0] = 16-bit word to write into UB
//   0x24  UB_PUSH    write-1 drives ub_wr_host_valid for one cycle
//   0x30  IMEM_ADDR
//   0x34  IMEM_W0
//   0x40  IMEM_WE
//   0x44  IMEM_LEN
```

文件位置：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`

### 5.2 它为什么重要

项目里最关键的一个变化，是把“测试台里手工打信号”变成“前端自动按程序推进”。

这段状态机就是核心：

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
```

配合下面这段：

```systemverilog
case (seq_state)
    SEQ_IDLE: begin
        if (step_pulse) begin
            seq_instr       <= instr_w0_reg;
            seq_instr_pulse <= 1'b1;
            busy_reg        <= 1'b1;
            seq_state       <= SEQ_WAIT;
        end else if (start_pulse) begin
            pc          <= '0;
            seq_instr   <= imem[0];
            seq_running <= 1'b1;
            busy_reg    <= 1'b1;
            seq_state   <= SEQ_DISPATCH;
        end
    end

    SEQ_DISPATCH: begin
        seq_instr_pulse <= 1'b1;
        if (seq_needs_wait)
            seq_state <= SEQ_WAIT;
        else
            seq_state <= SEQ_ADVANCE;
    end

    SEQ_WAIT: begin
        if (vpu_drain) begin
            if (seq_running)
                seq_state <= SEQ_ADVANCE;
            else begin
                busy_reg  <= 1'b0;
                seq_state <= SEQ_IDLE;
            end
        end
    end
endcase
```

这里的思想很关键：
- `DISPATCH` 只负责把指令打一拍出去。
- 真正的“完成边界”不在 dispatch，而在 `vpu_drain`。
- 所以 sequencer 的 wait 语义是**系统级完成**，不是某个局部信号完成。

这也是为什么 PPT 里一直强调：
**`wait_after` 是系统同步点，不是装饰字段。**

---

## 6. 编译器：不是通用 compiler，但已经够驱动这套原型

### 6.1 它到底输出什么

当前编译链不是 cycle-accurate compiler，也不是完整 IR 框架。
它做的是更实用的事情：

1. 给 tensor 分配 UB 地址
2. 生成阶段级 schedule
3. 把 stage 命令编码成 IMEM 能执行的 32-bit 指令

`scheduler.py` 里最核心的 helper 是 `_ub_read()`：

```python
def _ub_read(stage, name, tensor, ptr_sel, addr, row, col, transpose, *,
             vpu_path=None, note="", wait_after=False):
    command = {
        "stage": stage,
        "name": name,
        "kind": "ub_read",
        "tensor": tensor,
        "signals": {
            "ub_rd_start_in": 1,
            "ub_ptr_select": ptr_sel,
            "ub_rd_addr_in": addr,
            "ub_rd_row_size": row,
            "ub_rd_col_size": col,
            "ub_rd_transpose": int(transpose),
        },
        "wait_after": int(wait_after),
    }
```

文件位置：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/scheduler.py`

这段代码很重要，因为它说明：
**编译器最终不是在“描述张量”，而是在“描述硬件下一步该从 UB 的哪一块读、怎么读、读完要不要等”。**

### 6.2 schedule 真长什么样

生成出来的 schedule 文件在：
- `/home/jjt/tpu-soc/compiler/out/mlp_2_2_1_q8_8.schedule.json`

其中一段典型命令是：

```json
{
  "stage": "forward_layer1",
  "name": "load_w1_shadow",
  "kind": "ub_read",
  "tensor": "W1",
  "signals": {
    "ub_rd_start_in": 1,
    "ub_ptr_select": 1,
    "ub_rd_addr_in": 12,
    "ub_rd_row_size": 2,
    "ub_rd_col_size": 2,
    "ub_rd_transpose": 1
  },
  "wait_after": 0,
  "note": "Load W1^T through the top boundary into the PE shadow weight path."
}
```

这个命令其实就可以翻译成人话：
- 从 UB 地址 `12` 开始读 `W1`
- 这是 **权重流**，所以 `ptr_select=1`
- 读的时候做转置
- 目的是从阵列顶部装权重，而不是从左边喂输入

### 6.3 为什么 schedule 设计成 stage-level

因为当前项目的目标不是做“最强编译器”，而是先把闭环打通。

`scheduler.py` 里也写了假设：
- 当前还是 stage-level command list
- 不是 cycle-accurate waveform program
- 当前目标是 2 层 MLP + 2x2 / 2-lane 原型

这反而是合理的：
**你先证明系统能跑通，再去追求更细粒度的编译优化。**

---

## 7. UB：这个项目真正的数据中枢

### 7.1 为什么叫 Unified Buffer

因为它不是普通 SRAM，而是全系统的数据汇合点。

在 `unified_buffer_v3.sv` 里可以看到：

```systemverilog
// Write ports from VPU to UB
input logic [15:0] ub_wr_data_in [SYSTOLIC_ARRAY_WIDTH],
input logic ub_wr_valid_in [SYSTOLIC_ARRAY_WIDTH],

// Write ports from host to UB
input logic [15:0] ub_wr_host_data_in [SYSTOLIC_ARRAY_WIDTH],
input logic ub_wr_host_valid_in [SYSTOLIC_ARRAY_WIDTH],
input logic ub_wr_ptr_restore_in,

// Read instruction input from instruction memory
input logic ub_rd_start_in,
input logic [8:0] ub_ptr_select,
```

它同时承担：
- host 装载输入/标签/参数
- systolic array 读取输入和权重
- VPU 写回激活和梯度
- in-UB gradient descent 更新旧参数

所以这不是一个“存储模块”，而是一个**数据路由中心**。

### 7.2 UB 地址规划

当前分配结果在：
- `/home/jjt/tpu-soc/compiler/out/mlp_2_2_1_q8_8.ub_map.json`

关键布局是：

- `X` 在 `0`
- `Y` 在 `8`
- `W1` 在 `12`
- `B1` 在 `16`
- `W2` 在 `18`
- `B2` 在 `20`
- `H1` 在 `21`
- `dZ2` 在 `29`
- `dZ1` 在 `33`

也就是说，前面是静态输入和参数区，后面是运行时激活和梯度区。

### 7.3 `wr_ptr_base / restore` 为什么关键

这一段是这个项目里很容易被忽略、但其实很关键的设计点。

代码在：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`

关键逻辑是：

```systemverilog
logic [15:0] wr_ptr;
logic [15:0] wr_ptr_base;

if (ub_wr_host_valid_in[0] || ub_wr_host_valid_in[1]) begin
    wr_ptr_base <= wr_ptr_next;
end
if (ub_wr_ptr_restore_in) begin
    wr_ptr <= wr_ptr_base;
end else begin
    wr_ptr <= wr_ptr_next;
end
```

这段逻辑解决的问题是：
**训练过程中的写回，不能覆盖 host 一开始装进去的参数。**

思路不是把 UB 硬切银行，而是：
- host 装载阶段不断推进 `wr_ptr`
- 同时把“静态参数区的尾巴”记成 `wr_ptr_base`
- 每轮训练开始时，用 `ub_wr_ptr_restore_in` 把写指针恢复到这个边界

于是：
- 前面一段仍然是静态参数区
- 后面一段才是本轮运行时 writeback / update 区

这就是 PPT 里那页 `wr_ptr / base / restore` 的真正含义。

### 7.4 `ptr_select` 为什么重要

`ub_ptr_select` 决定这次 UB 读流要读什么。

代码里是这样分派的：

```systemverilog
case (ub_ptr_select)
    0: begin ... end // input
    1: begin ... end // weight
    2: begin ... end // bias
    3: begin ... end // Y
    4: begin ... end // H
    5: begin ... end // old bias for update
    6: begin ... end // old weight for update
endcase
```

这说明 UB 不是只有一种读法，而是同一块存储被复用了多种语义：
- 左边喂 input
- 顶部喂 weight
- VPU 取 bias / Y / H
- gradient descent 再读旧参数

所以 schedule 里的 `ptr_select` 是理解整个项目的钥匙之一。

---

## 8. PE / Systolic：真正的算力核心

`tpu.sv` 的职责很清楚，就是把三块核心接起来：

```systemverilog
unified_buffer ub_inst(...);
systolic systolic_inst(...);
vpu vpu_inst(...);
```

文件位置：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu.sv`

这三块分别做：
- `unified_buffer`：把数据按语义送出来
- `systolic`：做矩阵乘法 / 外积
- `vpu`：做 bias、激活、loss、导数等训练路径处理

PPT 里 `PE 与计算阵列` 那页，其实主要是讲 systolic 这一段。

它的执行模型可以概括成：
- input 从左往右传播
- weight 从上往下装入
- psum 向下沉
- valid 波前沿着阵列推进

所以你后面看到的波形页，本质上就是在证明：
**这个波前模型真的发生了，而且和 UB 发数 / VPU drain 是对齐的。**

---

## 9. VPU：不是黑盒后处理，而是训练路径单元

很多人会把 VPU 看成“算完之后顺手做一点后处理”。
但在这个项目里，VPU 其实是训练路径的重要一环。

从 `tpu.sv` 的接口能看出来，VPU 吃的是：
- systolic 输出
- bias
- Y
- H
- leak factor
- inverse batch scale
- pathway bits

也就是说，VPU 不是固定做一件事，而是通过 `vpu_data_pathway` 切换不同路径。

在 PPT 里你已经把它总结成三类：
- `1100`：forward
- `1111`：transition / loss / derivative
- `0001`：backward derivative

所以 VPU 的定位更准确地说是：
**一个可重组的训练路径单元。**

---

## 10. 一轮训练是怎么跑完的

如果你想真正理解项目，最重要的是把“一轮训练”串起来。

可以按 scheduler 的阶段顺序看：

### 10.1 forward layer1
- 先把 `W1^T` 装到 shadow weight path
- `switch` 把 shadow 切到 active
- 流出 `X`
- 流出 `B1`
- VPU 走 `1100` 路径
- 写回 `H1`

### 10.2 transition layer2
- 装 `W2^T`
- 再把 `H1` 流进阵列
- `B2` 和 `Y` 也送进 VPU
- VPU 走 `1111` 路径
- 直接把 `dZ2` 写回 UB
- 同时在 UB 内更新 `B2`

### 10.3 backward layer1
- 用 `W2` 非转置反向传播
- 读 `dZ2`
- 读 `H1` 供导数使用
- VPU 走 `0001` 路径
- 写回 `dZ1`
- 同时在 UB 内更新 `B1`

### 10.4 update W1 / W2
- 用 systolic 做外积 tile
- 同时再从 UB 取旧权重
- gradient_descent 模块在 UB 内就地更新

这就是为什么我一直说，这不是“推理 demo”，而是**训练闭环**。

---

## 11. 验证：怎么证明这不是看起来能跑

验证入口文件在：
- `/home/jjt/tpu-soc/test/test_tpu_soc_axil_train_convergence.py`

这个测试不是只打一拍看看波形，而是完整做了：

1. AXI-Lite 配置寄存器
2. AXI-Lite 把全部输入/标签/参数写进 UB
3. AXI-Lite 把 IMEM 指令写进去
4. 连续多 epoch 触发训练
5. 检查 loss 下降
6. 检查最终 XOR 4/4 分类正确

比如 Host 装载 UB 数据就是：

```python
async def load_all_data_axil(dut, x, y, w1, b1, w2, b2):
    seq = [
        (to_fxp(x[0][0]), 0, 1),
        (to_fxp(x[1][0]), to_fxp(x[0][1]), 3),
        ...
        (to_fxp(b2[0]), to_fxp(w2[1]), 3),
    ]
    for d0, d1, mask in seq:
        await ub_write_cycle(dut, d0, d1, mask)
```

启动一轮训练是：

```python
async def run_one_epoch(dut, epoch_idx):
    await axil_write(dut, 0x000, 0x2)
    for attempt in range(200):
        await ClockCycles(dut.s_axil_aclk, 500)
        status = await axil_read(dut, 0x004)
        if not (status & 0x1):
            return
```

读回硬件里的参数看更新结果是：

```python
def read_hw_params(dut):
    ub = dut.dut.tpu_inst.ub_inst.ub_memory
    w1_words = [int(ub[12 + i].value) & 0xFFFF for i in range(4)]
    b1_words = [int(ub[16 + i].value) & 0xFFFF for i in range(2)]
    w2_words = [int(ub[18 + i].value) & 0xFFFF for i in range(2)]
    b2_words = [int(ub[20].value) & 0xFFFF]
```

这段测试的意义非常大，因为它证明了三件事：

1. AXI-Lite 控制链是真的通的。
2. RTL 执行链是真的通的。
3. 数值语义是真的对的。

也就是说，项目不是“接口通了”，而是“训练真的在跑”。

---

## 12. 这个项目最容易被问的 5 个点

### 12.1 为什么编译器不是 cycle-accurate？

因为当前目标是先把系统闭环跑通。
当前编译器已经能把模型规格落成 UB 布局、stage-level schedule 和 IMEM 控制字，这对 2x2 原型已经够用了。

### 12.2 为什么 UB 里要做 gradient descent？

因为更新旧参数本质上就是“读旧值 + 读梯度 + 写回新值”，最自然的地方就是 UB 内部。
这样不用再把旧参数搬出 UB 再搬回来。

### 12.3 为什么 `wait_after` 很重要？

因为真正的系统完成边界不是 `dispatch`，而是 `vpu_drain`。
如果不等到 drain，后面的阶段会和前一阶段尾拍重叠，整个系统就不稳定。

### 12.4 为什么要单独讲 `wr_ptr_base / restore`？

因为这是参数区不被覆盖的关键。
如果没有这个边界恢复机制，训练写回会直接踩掉一开始 host 装进去的参数和数据区。

### 12.5 这个项目现在的边界在哪？

当前边界很明确：
- 2x2 / 2-lane tiny-tpu 原型
- 2 层 MLP
- Q8.8
- stage-level schedule
- 没有 DMA / IRQ / ICG / 更大规模阵列扩展

但这些边界不影响它作为“完整闭环原型”的价值。

---

## 13. 你应该怎么继续读这个项目

我建议按这个顺序看：

1. 先看主讲版 PPT：`01_main_8p.pptx`
2. 再看这份文档，把主线和代码对起来
3. 再读这 5 个文件：
   - `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_soc.sv`
   - `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`
   - `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu.sv`
   - `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`
   - `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/scheduler.py`
4. 最后看 `test_tpu_soc_axil_train_convergence.py`

这样你的理解顺序会是：
**系统闭环 -> 控制链 -> 数据链 -> 编译链 -> 验证链**

而不是一上来就掉进某个 always_ff 或某个波形细节里出不来。

---

## 14. 最后的理解口径

如果你只能记一句话，那就记这句：

**这个项目不是在做一个“大而全”的 TPU，而是在把 tiny-tpu 原型真正接成一套“可被主机驱动、可执行训练、可被验证证明”的系统。**

如果你还能再多记一句，那就是：

**它最难的地方不是 PE 做 MAC，而是 compiler、Frontend、UB、VPU、sequencer、wait 边界和验证证据，最后全都能对上。**


---

# Part 3 面试逐页讲稿

# TinyTPU AXI-Lite SoC 面试讲解稿

这份文档配合主讲版 PPT 使用：
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/01_main_8p.pptx`
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/02_appendix_35p.pptx`

目标不是把所有细节一次讲完，而是让你在 8 页内把项目讲成一条完整闭环。

---

## 总体讲法

整套 8 页只讲一条主线：

1. 这是一个把 tiny-tpu 原型接成 SoC 闭环的项目。
2. 软件侧先产出 `ub_map + schedule + imem`。
3. Host 通过 AXI-Lite 装载数据和指令。
4. Frontend 负责寄存器、IMEM、sequencer 和 dispatch/wait。
5. TPU core 里的 UB、PE、VPU 执行前向、反向和更新。
6. Cocotb 用波形、loss 下降和 XOR 收敛证明系统真的跑对。

如果被问深一点，就切附录，不要在主讲版里自己展开太多。

---

## 第 1 页 封面

### 这一页要讲什么

先定题，不讲细节。

### 可以直接念

大家好，我这次讲的是 TinyTPU AXI-Lite SoC 项目。
这个项目的重点不是把阵列做大，而是把一个原本更像裸核原型的 tiny-tpu，真正接成一套可由主机控制、可执行训练、可用验证证明正确的系统。
今天主讲版我只讲 8 页，先把闭环讲清楚，细节我放在附录里。

### 面试官此时最可能想知道什么

- 你到底做的是核，还是系统？
- 你做的是推理，还是训练？
- 这东西是 demo，还是可验证的完整链路？

### 这页结束时要落下的结论

这不是单点 RTL demo，而是一个训练闭环 SoC 原型。

---

## 第 2 页 系统总览

### 这一页要讲什么

先把全局链路一次带完，不钻 RTL 细节。

### 可以直接念

这页先看全局。
整个项目可以拆成四层：软件与编译、SoC 前端控制、TPU 核心执行、验证与结果。
软件侧先把 MLP 规格降成 `ub_map`、`schedule` 和 `imem`；Host 再通过 AXI-Lite 把参数、数据和指令装进系统；Frontend 负责按程序推进；下面的 UB、PE、VPU 完成前向、反向和参数更新；最后验证侧看波形、loss 和最终 XOR 分类结果。
所以这套东西的价值不在规模大，而在每一层都能接上，最后形成闭环。

### 如果被打断，可以补哪一句

你可以把它理解成“软件、控制、执行、验证”四段真正接通了，而不是单独一个 PE 能算。

### 对应代码抓手

- `tpu_soc.sv`
- `tpu_frontend_axil.sv`
- `scheduler.py`
- `test_tpu_soc_axil_train_convergence.py`

### 这页结束时要落下的结论

先接受一个判断：这个项目最重要的是闭环，不是单个模块的复杂度。

---

## 第 3 页 项目级 RTL 结构

### 这一页要讲什么

解释 SoC 顶层怎么连，别一上来扎进 UB 内部。

### 可以直接念

这页我只回答一个问题：模块到底怎么连。
最顶层是 `tpu_soc.sv`，它上面对 AXI-Lite Host，下边接 `tpu_frontend_axil` 和 `tpu` core。
Frontend 负责把寄存器、IMEM 和 sequencer 组织成控制脉冲，比如 `ub_rd_start`、`ub_ptr_sel`、`ub_wr_ptr_restore`、`vpu_data_pathway` 这些信号；`tpu` 再把这些控制送进 UB、systolic 和 VPU。
所以 `tpu_soc` 自己不做计算，它的价值是把主机世界和计算世界桥接起来。

### 可以直接给出的代码片段

```systemverilog
tpu_frontend_axil frontend (...);
tpu tpu_inst (...);
```

### 如果被追问“你具体改了什么”

重点不是新写一个大核，而是把原有 tiny-tpu 的核真正装进一个可控顶层，并把控制信号闭环接通。

### 对应代码抓手

- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_soc.sv`

### 这页结束时要落下的结论

顶层结构已经从“测试台驱动核心”变成“主机可控的 SoC 原型”。

---

## 第 4 页 编译器与指令组织

### 这一页要讲什么

说明软件不是黑盒，硬件不是硬写死，二者中间靠 schedule 和 IMEM 接起来。

### 可以直接念

这页我想说明，软件和硬件之间并不是脱节的。
当前编译链虽然不是通用编译器，但已经能把 2 层 MLP 的规格降成三类产物：`ub_map` 负责地址布局，`schedule` 负责阶段级动作，`imem` 负责最终送给 Frontend 的控制字。
像 `forward_layer1` 这种 stage，本质上就是告诉硬件：这一步该从 UB 哪块读、按什么语义读、读完要不要等。
所以编译器在这里做的不是学术化 IR，而是非常实用的“把软件意图翻译成当前硬件能执行的控制序列”。

### 可以直接给出的代码片段

```python
def _ub_read(stage, name, tensor, ptr_sel, addr, row, col, transpose, *,
             vpu_path=None, note="", wait_after=False):
    command = {
        "stage": stage,
        "name": name,
        "kind": "ub_read",
        "tensor": tensor,
        "signals": {
            "ub_rd_start_in": 1,
            "ub_ptr_select": ptr_sel,
            "ub_rd_addr_in": addr,
        },
        "wait_after": int(wait_after),
    }
```

### 如果被追问“为什么不是 cycle-accurate compiler”

因为当前目标是先把系统闭环打通；对 2x2 原型来说，stage-level schedule 已经足够证明软件到硬件的链路是通的。

### 对应代码抓手

- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/scheduler.py`
- `/home/jjt/tpu-soc/compiler/out/mlp_2_2_1_q8_8.schedule.json`
- `/home/jjt/tpu-soc/compiler/out/mlp_2_2_1_q8_8.ub_map.json`

### 这页结束时要落下的结论

这个项目不是手工打一堆控制信号，而是已经有一条“模型规格 -> schedule/imem -> RTL 执行”的路径。

---

## 第 5 页 Unified Buffer 设计

### 这一页要讲什么

把 UB 讲成系统的数据中枢，而不是一块普通 SRAM。

### 可以直接念

这页最重要的一句话是：UB 不是普通缓存，而是这个系统的数据中枢。
Host 装载输入、标签和初始参数都进 UB；PE 读取输入和权重也从 UB 来；VPU 写回激活和梯度也回到 UB；甚至参数更新也是在 UB 内部完成的。
所以 UB 真正解决的问题，不是“存下来”，而是“同一块存储怎么承载多种语义的数据流”。
这里最关键的两个设计点，一个是 `ub_ptr_select`，它决定当前读流到底在读 input、weight、bias、Y 还是旧参数；另一个是 `wr_ptr_base / restore`，它保证训练过程中的写回不会踩掉 host 一开始装进去的静态参数区。

### 可以直接给出的代码片段

```systemverilog
case (ub_ptr_select)
    0: begin ... end // input
    1: begin ... end // weight
    2: begin ... end // bias
    3: begin ... end // Y
    4: begin ... end // H
    5: begin ... end // old bias
    6: begin ... end // old weight
endcase
```

```systemverilog
if (ub_wr_host_valid_in[0] || ub_wr_host_valid_in[1])
    wr_ptr_base <= wr_ptr_next;
if (ub_wr_ptr_restore_in)
    wr_ptr <= wr_ptr_base;
else
    wr_ptr <= wr_ptr_next;
```

### 如果被追问“为什么更新放在 UB 里”

因为更新就是读旧值、读梯度、写回新值，最自然的位置就是 UB 内部，这样不用再搬出去绕一圈。

### 对应代码抓手

- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`
- `/home/jjt/tpu-soc/compiler/out/mlp_2_2_1_q8_8.ub_map.json`

### 这页结束时要落下的结论

UB 是整个项目真正的数据中枢，也是这套系统能跑训练闭环的关键。

---

## 第 6 页 PE 与计算阵列

### 这一页要讲什么

告诉面试官真正的算力核心是什么，但不要把重点误导成“只有 MAC 最难”。

### 可以直接念

这页讲真正的算力核心，也就是 systolic array。
在 `tpu.sv` 里，`tpu` 其实就是把 `unified_buffer`、`systolic` 和 `vpu` 三块接起来。PE 负责乘加，阵列的执行模型是 input 从左往右流、weight 从上往下装、psum 向下沉，valid 作为波前在阵列里推进。
但是我想强调，这个项目真正难的地方并不是 PE 会不会做 MAC，而是这套阵列怎么和 UB 的发数、VPU 的 drain、Frontend 的 wait 边界对齐起来。
所以这一页既是在讲算力核心，也是在给后面的波形证据页做铺垫。

### 可以直接给出的代码片段

```systemverilog
unified_buffer ub_inst(...);
systolic systolic_inst(...);
vpu vpu_inst(...);
```

### 如果被追问“VPU 和 PE 怎么分工”

PE 负责阵列乘加；VPU 负责 bias、激活、loss、导数这些训练路径上的后处理和控制切换。

### 对应代码抓手

- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu.sv`

### 这页结束时要落下的结论

PE 是算力核心，但系统价值来自 PE、UB、VPU 和控制边界一起对上。

---

## 第 7 页 验证波形与回归覆盖

### 这一页要讲什么

这一页要把“看起来能跑”变成“真的跑对”。

### 可以直接念

这页是整套里最关键的证据页。
如果前面几页讲的是设计意图，这一页讲的就是真实证据。波形上可以把 sequencer 脉冲、UB 发数、阵列 valid 波前、VPU drain 对起来；测试上不是只打一拍，而是完整通过 AXI-Lite 装载 UB 和 IMEM，连续跑多轮 epoch，然后检查 loss 下降和最终 XOR 分类正确。
所以它证明的不是单个模块能动，而是软件、控制、执行和验证这四段真的闭环了。

### 可以直接给出的代码片段

```python
async def run_one_epoch(dut, epoch_idx):
    await axil_write(dut, 0x000, 0x2)
    for attempt in range(200):
        await ClockCycles(dut.s_axil_aclk, 500)
        status = await axil_read(dut, 0x004)
        if not (status & 0x1):
            return
```

### 如果被追问“怎么证明不是假收敛”

这里不是只看一个波形点，而是同时看 AXI-Lite 装载、RTL 执行、loss 变化和最终分类结果，证据是分层叠起来的。

### 对应代码抓手

- `/home/jjt/tpu-soc/test/test_tpu_soc_axil_train_convergence.py`

### 这页结束时要落下的结论

这套系统不是看起来会动，而是真的完成了训练闭环并给出了证据。

---

## 第 8 页 结果、边界与追问方向

### 这一页要讲什么

收束全场，同时主动交代边界，让项目显得清楚而不是虚张声势。

### 可以直接念

最后我先给一句结论，这不是单点 demo，而是一条完整闭环。
这套系统已经能从模型规格出发，经过编译、AXI-Lite 装载、Frontend 调度、UB/PE/VPU 执行，再到 loss 下降和 XOR 收敛，形成完整训练路径。
它的边界也很明确：当前还是 2x2、2 层 MLP、Q8.8、stage-level schedule，还没有做到 DMA、IRQ、更大阵列扩展这些系统化增强。但我觉得对这个项目来说，先把闭环做实，比一开始追求规模更重要。
如果老师继续追问，我就切附录展开 Frontend、控制 bug 修复、VPU pathway 和 GIF 单步页。

### 这一页最适合主动说出的边界

- 当前是 2x2 / 2-lane 原型
- 当前是 2 层 MLP
- 当前 schedule 还是 stage-level
- 还没有 DMA / IRQ / 更大规模阵列扩展

### 这页结束时要落下的结论

项目最核心的价值，不是规模，而是把 tiny-tpu 接成一条可控、可执行、可验证的完整训练闭环。

---

## 最后给你一个答辩节奏建议

如果你只有 3 分钟：
- 第 2 页讲闭环
- 第 3 页讲顶层桥接
- 第 5 页讲 UB 是数据中枢
- 第 7 页讲波形和收敛证据
- 第 8 页讲结论和边界

如果你有 5 分钟：
- 再加第 4 页编译器
- 再加第 6 页 PE / VPU / 波前传播

如果老师开始追问：
- 问控制，就切 Frontend 和 `wait_after`
- 问数据，就切 UB 和 `wr_ptr_restore`
- 问训练语义，就切 VPU pathway
- 问执行时序，就切 GIF 单步页

一句话策略：
**主讲版只讲闭环，细节一律放到附录里接。**


---

# Part 4 自己复习提纲

# TinyTPU AXI-Lite SoC 复习提纲

这份文档给你自己复习项目用。
定位和 [tpu_project_full_explainer_zh.md](/home/jjt/tpu-soc/docs/tpu_project_full_explainer_zh.md) 不一样：
- 那份是完整说明文，适合系统阅读。
- 这份是复习提纲，适合你快速建立脑图、抓代码入口、准备回答问题。

配合文件：
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/01_main_8p.pptx`
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/02_appendix_35p.pptx`
- `/home/jjt/tpu-soc/docs/tpu_project_full_explainer_zh.md`

---

## 1. 先建立一句话脑图

一句话版本：
**这个项目把原来更偏裸核原型的 tiny-tpu，接成了一套能被 AXI-Lite Host 控制、能执行 2 层 MLP 训练、并能用波形和收敛结果证明正确性的 SoC 闭环。**

再展开成 6 步：

1. `scheduler.py` 根据模型规格生成 `ub_map + schedule + imem`
2. Host 通过 AXI-Lite 写寄存器、UB、IMEM
3. `tpu_frontend_axil.sv` 负责 sequencer 和 dispatch/wait
4. `tpu_soc.sv` 把 frontend 和 `tpu` core 接起来
5. `tpu.sv` 里由 `UB + systolic + VPU` 执行 forward/backward/update
6. `test_tpu_soc_axil_train_convergence.py` 验证 loss 下降和 XOR 收敛

你只要先把这 6 步背住，项目主线就不会散。

---

## 2. 这个项目和原始 tiny-tpu 的差别

原始 tiny-tpu 更像：
- 有核
- 能表达训练语义
- 但系统入口和验证闭环不完整

这个项目补上的，是系统化部分：
- SoC 顶层
- AXI-Lite 前端
- IMEM 装载
- stage-level 编译产物
- UB 地址规划
- Cocotb 端到端训练验证

所以你在回答“我做了什么”时，不要只说“我改了 UB/PE”，而要说：
**我把 tiny-tpu 从一个偏计算核心原型，补成了一套真正可控、可执行、可验证的系统。**

---

## 3. 看代码时的正确顺序

### 第一层：先看顶层闭环

1. `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_soc.sv`
2. `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`
3. `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu.sv`

这一层只回答三个问题：
- 顶层怎么接？
- 控制从哪里来？
- 核心执行链怎么分成 UB / systolic / VPU？

### 第二层：再看数据和控制关键点

4. `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`
5. `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/scheduler.py`

这一层回答：
- UB 里数据怎么分区、怎么读、怎么更新？
- schedule 怎么把软件意图降成硬件动作？

### 第三层：最后看验证

6. `/home/jjt/tpu-soc/test/test_tpu_soc_axil_train_convergence.py`

这一层回答：
- Host 端到底怎么写寄存器、UB、IMEM？
- 一轮训练怎么触发？
- 怎么证明 loss 下降和最终收敛？

---

## 4. 每个关键文件你到底要看什么

### 4.1 `tpu_soc.sv`

只抓一件事：顶层桥接。

重点看这些信号：
- `ub_wr_host_data_*`
- `ub_wr_host_valid_*`
- `ub_wr_ptr_restore`
- `ub_rd_start`
- `ub_ptr_sel`
- `vpu_data_pathway`
- `sys_switch`

记忆方法：
**Frontend 产生命令，tpu_soc 负责转接，tpu core 负责执行。**

### 4.2 `tpu_frontend_axil.sv`

只抓两块：
- 寄存器地图
- sequencer 状态机

最重要的不是 AXI-Lite 握手细节，而是这几个状态：

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
```

你要理解的是：
- `DISPATCH` 只是打一拍控制
- `WAIT` 才是真正的系统同步点
- `wait_after` 最后靠 `vpu_drain` 来收边界

### 4.3 `scheduler.py`

只抓 `_ub_read()` 和 `build_schedule()`。

核心理解：
- compiler 没有做很玄的事
- 它就是把阶段意图翻译成“从 UB 哪读、怎么读、读完要不要等”

```python
def _ub_read(stage, name, tensor, ptr_sel, addr, row, col, transpose, *,
             vpu_path=None, note="", wait_after=False):
```

看到这个函数时你要直接联想到：
- `ptr_sel` 决定语义
- `addr/row/col` 决定数据块
- `wait_after` 决定阶段边界

### 4.4 `unified_buffer_v3.sv`

只抓三个点：
- `ub_ptr_select`
- `wr_ptr_base / restore`
- gradient descent update

这三个点分别对应：
- 这次读的到底是什么语义
- 写回为什么不会踩掉静态参数区
- 旧参数怎么在 UB 内更新

### 4.5 `tpu.sv`

只抓一句话：

```systemverilog
unified_buffer ub_inst(...);
systolic systolic_inst(...);
vpu vpu_inst(...);
```

这说明 `tpu` 不是复杂控制器，而是执行核心的组合点。

### 4.6 `test_tpu_soc_axil_train_convergence.py`

只抓四个 helper：
- `axil_write`
- `load_all_data_axil`
- `imem_load`
- `run_one_epoch`

你看懂这四个函数，就能看懂“软件怎么把硬件跑起来”。

---

## 5. 你必须真的搞懂的 5 个点

### 5.1 `wait_after` 为什么不是装饰位

因为系统真正的完成边界不在 dispatch，而在 `vpu_drain`。
如果不等这一拍，后续阶段可能和前一阶段尾拍重叠。

### 5.2 `wr_ptr_restore` 为什么值得单独讲一页

因为 host 装载的静态区和训练时产生的运行时写回区要隔开。
`wr_ptr_base` 记住静态区边界，`restore` 每轮把写指针拉回边界后面。

### 5.3 为什么说 UB 是数据中枢

因为 input、weight、bias、H、Y、旧参数、新参数、梯度都围着 UB 转。
UB 不只是存储，而是数据流交汇点。

### 5.4 为什么这个项目不是“只有 PE 很难”

PE 的 MAC 只是算力核心的一部分。
更难的是：
- 编译输出怎么落地
- Frontend 怎么推进
- UB 怎么按语义供数
- VPU 怎么对齐路径
- wait 边界怎么保证系统级正确

### 5.5 为什么验证页很关键

因为它把“看起来会动”升级成“真的跑对”。
没有这一页，你只能证明模块响应了控制；有这一页，你才能证明训练闭环真的成立。

---

## 6. 用一轮训练把全项目串起来

你可以按这条顺序背：

### Step 1 软件准备

- 读模型规格
- 生成 `ub_map`
- 生成 `schedule`
- 编成 `imem`

### Step 2 Host 装载

- 用 AXI-Lite 写 UB
- 写 IMEM
- 写启动寄存器

### Step 3 Frontend 推进

- 取指
- dispatch
- 如果需要就 wait
- 等 `vpu_drain` 再 advance

### Step 4 Core 执行

- UB 送 input / weight / bias / Y / H / old params
- systolic 做 forward / backward / outer product
- VPU 做 pathway 相关的训练语义
- UB 写回激活、梯度和更新结果

### Step 5 验证收尾

- 波形能对上
- loss 下降
- XOR 最终收敛

如果你能把这 5 步顺着讲出来，项目就已经讲清楚了。

---

## 7. 你可以直接记的代码片段

### 顶层桥接

```systemverilog
tpu_frontend_axil frontend (...);
tpu tpu_inst (...);
```

### Sequencer 状态机

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
```

### Compiler 阶段命令

```python
command = {
    "stage": stage,
    "name": name,
    "kind": "ub_read",
    "signals": {
        "ub_rd_start_in": 1,
        "ub_ptr_select": ptr_sel,
        "ub_rd_addr_in": addr,
    },
    "wait_after": int(wait_after),
}
```

### UB 读语义分流

```systemverilog
case (ub_ptr_select)
    0: begin ... end // input
    1: begin ... end // weight
    2: begin ... end // bias
    3: begin ... end // Y
    4: begin ... end // H
    5: begin ... end // old bias
    6: begin ... end // old weight
endcase
```

### 验证入口

```python
async def run_one_epoch(dut, epoch_idx):
    await axil_write(dut, 0x000, 0x2)
```

这些代码你不需要逐字背，但你最好能看到一眼就知道自己在讲哪一层。

---

## 8. 常见追问怎么答

### 问：你的主要贡献是什么？

答法：
不是只改一个 PE 或一个寄存器，而是把 tiny-tpu 从偏裸核原型接成完整 SoC 闭环，包括前端控制、顶层集成、UB 语义、编译产物落地和训练验证。

### 问：最难的点是什么？

答法：
最难的不是单个 MAC，而是 compiler、Frontend、UB、VPU、wait 边界和验证证据最后都能对上。

### 问：现在的边界是什么？

答法：
当前还是 2x2、2 层 MLP、Q8.8、stage-level schedule，还没有做 DMA、IRQ 和更大规模阵列扩展。

### 问：为什么你觉得这个项目是完整的？

答法：
因为它已经从模型规格一路走到 Host 装载、RTL 执行、波形证据、loss 下降和最终分类正确，而不是只停在某一级。

---

## 9. 最后给你一个复习方法

### 第一遍

只看：
- 主讲版 PPT
- 这份提纲

目标：把主线讲顺。

### 第二遍

看：
- `tpu_soc.sv`
- `tpu_frontend_axil.sv`
- `scheduler.py`
- `unified_buffer_v3.sv`

目标：把控制链和数据链看明白。

### 第三遍

看：
- `test_tpu_soc_axil_train_convergence.py`
- 附录 PPT

目标：把证据链和追问点补齐。

最后一句提醒：
**你不是在背模块说明书，你是在建立一张“软件 -> 前端 -> 核心 -> 验证”的脑图。**


---

# Part 5 源码全景精讲

# TinyTPU AXI-Lite SoC 源码精讲版

这份文档是“逐文件源码精讲版”。
如果前面三份文档分别是：
- `05_project_explainer_zh.md`：全景说明文
- `06_interview_walkthrough_zh.md`：按 8 页主讲版逐页讲
- `07_study_guide_zh.md`：复习提纲

那么这份文档的定位就是：
**带着你按文件把项目重新走一遍，知道每个关键文件到底在解决什么问题，关键代码为什么要那样写。**

建议配合这几份材料一起看：
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/01_main_8p.pptx`
- `/mnt/hgfs/wdchenaic/tpu_interview_ppt/02_appendix_35p.pptx`
- `/home/jjt/tpu-soc/docs/tpu_project_full_explainer_zh.md`
- `/home/jjt/tpu-soc/docs/tpu_project_interview_walkthrough_zh.md`
- `/home/jjt/tpu-soc/docs/tpu_project_study_guide_zh.md`

---

## 1. 先把“源码地图”建立起来

这个项目最关键的源码，其实就 6 个入口：

1. `src_axi/tpu_soc.sv`
2. `src_axi/tpu_frontend_axil.sv`
3. `compiler/scheduler.py`
4. `src_axi/tpu.sv`
5. `src_axi/unified_buffer_v3.sv`
6. `test/test_tpu_soc_axil_train_convergence.py`

它们分别回答的问题是：

1. 顶层到底怎么把 Host、Frontend、TPU core 接起来？
2. AXI-Lite 怎么变成寄存器、IMEM、sequencer 和控制脉冲？
3. 软件侧怎么把模型意图降成当前 RTL 能执行的阶段级命令？
4. TPU core 内部到底由哪三块组成？
5. 为什么 UB 是整个系统的数据中枢，训练更新又是怎么在里面做的？
6. 怎么证明这套系统不只是“看起来会动”，而是真的能跑训练闭环？

这 6 个文件不是平行关系，而是一条链：

`Host / cocotb -> AXI-Lite frontend -> tpu_soc -> tpu -> UB / systolic / VPU -> wave / loss / convergence`

所以阅读方式不要按“哪个文件最长先看哪个”，而要按“控制怎么进去，数据怎么流，结果怎么出来”来读。

---

## 2. `tpu_soc.sv`：顶层桥接层

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_soc.sv`

### 2.1 这个文件的角色

`tpu_soc.sv` 本身不做复杂计算，它做的是桥接。
它把：
- 上面的 AXI-Lite Host
- 中间的 Frontend
- 下面的 TPU core
接成一层真正可控的顶层。

源码开头的注释已经把它的定位写得很直接：

```systemverilog
// TinyTPU SoC Top
// Wraps tpu_frontend_axil + tpu into a single AXI-Lite controlled accelerator.
```

所以理解这个文件的第一原则是：
**它是系统整合层，不是算法层。**

### 2.2 最核心的两实例

真正决定结构的，其实就是这两块：

```systemverilog
tpu_frontend_axil #(
    .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
) frontend (...);

 tpu #(
    .SYSTOLIC_ARRAY_WIDTH(SYSTOLIC_ARRAY_WIDTH)
) tpu_inst (...);
```

你可以把它理解成：
- `frontend` 负责“把主机命令翻译成 TPU 控制语义”
- `tpu_inst` 负责“真正执行 UB + systolic + VPU 的运算链”

### 2.3 为什么中间有一堆桥接信号

看这组信号就很清楚：

```systemverilog
logic [15:0] ub_wr_host_data_0, ub_wr_host_data_1;
logic        ub_wr_host_valid_0, ub_wr_host_valid_1;
logic        ub_wr_ptr_restore;
logic        sys_switch;
logic        ub_rd_start;
logic [2:0]  ub_ptr_sel;
logic [3:0]  vpu_data_pathway;
```

这些信号不是随便拉的，它们正好对应这套系统的关键控制面：
- host 写 UB
- write pointer restore
- systolic shadow/active 权重切换
- UB 读流启动
- 当前读流语义选择
- VPU 路径选择

所以 `tpu_soc` 干的事情，本质上是把“主机的寄存器世界”变成“核内部能理解的控制世界”。

### 2.4 为什么有零扩展

这里有一段很容易在阅读时忽略，但很重要：

```systemverilog
.ub_ptr_select              ({6'h0, ub_ptr_sel}),
.ub_rd_addr_in              ({10'h0, ub_rd_addr}),
.ub_rd_row_size             ({12'h0, ub_rd_row_size}),
.ub_rd_col_size             ({14'h0, ub_rd_col_size}),
```

这段说明两件事：

1. Frontend 输出的是当前项目足够用的窄控制信号。
2. TPU core/UB 接口保留了更宽的表达能力。

也就是说，当前 SoC 顶层不是在追求“最完美的接口设计”，而是在做一个**够用且稳定的桥接适配层**。

### 2.5 读这个文件时你应该抓什么

你不需要在 `tpu_soc.sv` 里研究算法。
你只需要抓三件事：

1. `frontend` 和 `tpu_inst` 是怎么接起来的。
2. 哪些信号是真正跨模块传递系统语义的。
3. 这个顶层为什么说明项目已经从“裸核原型”变成“主机可控 SoC”。

### 2.6 一句话总结

`tpu_soc.sv` 的价值不是“做了很多逻辑”，而是它让整套系统第一次有了真正的顶层闭环入口。

---

## 3. `tpu_frontend_axil.sv`：控制中枢

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`

### 3.1 这个文件到底是什么

很多人第一次看它，会把它当成“一个 AXI-Lite 寄存器模块”。
这不够准确。

它实际上叠了 4 个角色：

1. AXI-Lite 寄存器块
2. IMEM 装载入口
3. Sequencer
4. 指令译码后的控制脉冲发生器

所以它不是边角料，而是**整个系统的控制中枢**。

### 3.2 先看寄存器地图

文件开头直接给了寄存器定义：

```systemverilog
//   0x00  CTRL       bit0=step
//                   bit1=start
//   0x04  STATUS     bit0=busy
//                   bit1=running
//   0x10  INSTR_W0   32-bit opcode instruction
//   0x20  UB_DATA
//   0x24  UB_PUSH
//   0x30  IMEM_ADDR
//   0x34  IMEM_W0
//   0x40  IMEM_WE
//   0x44  IMEM_LEN
//   0x50  LEAK
//   0x54  INV_BATCH
//   0x58  LR
```

这张表已经把项目的控制思路暴露得很清楚：
- `CTRL/STATUS` 控制运行状态
- `INSTR_W0` 支持 step 模式临时打一条指令
- `IMEM_*` 支持 auto-run 模式按程序执行
- `UB_*` 支持 host 直接装载数据
- `LEAK / INV_BATCH / LR` 支持训练参数配置

所以你从这张寄存器图就能看出来：
**这个前端不是只为推理设计的，而是为训练路径设计的。**

### 3.3 step 和 start 两种模式

看这句：

```systemverilog
assign ub_wr_ptr_restore_out = start_pulse;
```

这句很关键。
说明每次 `start` 自动运行一轮时，前端会同时触发 `wr_ptr_restore`。
这意味着：
- `step` 更像单步 debug / staging
- `start` 才是“从 host 装载区边界开始，执行完整一轮程序”的正式运行入口

所以 `start` 不是只拉高 busy，而是在系统语义上代表：
**从一个干净的运行边界重新开始。**

### 3.4 Sequencer 是这文件的核心

最值得看的代码是状态机：

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
```

配合这段：

```systemverilog
case (seq_state)
    SEQ_IDLE: begin
        if (step_pulse) begin
            seq_instr       <= instr_w0_reg;
            seq_instr_pulse <= 1'b1;
            busy_reg        <= 1'b1;
            seq_state       <= SEQ_WAIT;
        end else if (start_pulse) begin
            pc          <= '0;
            seq_instr   <= imem[0];
            seq_running <= 1'b1;
            busy_reg    <= 1'b1;
            seq_state   <= SEQ_DISPATCH;
        end
    end

    SEQ_DISPATCH: begin
        seq_instr_pulse <= 1'b1;
        if (seq_needs_wait)
            seq_state <= SEQ_WAIT;
        else
            seq_state <= SEQ_ADVANCE;
    end
```

这一段说明：
- `IDLE` 决定是走 step 还是 auto-run
- `DISPATCH` 只打一拍控制脉冲
- `WAIT` 决定系统同步边界
- `ADVANCE` 才推进 PC

所以它不是普通 PC+IMEM，而是带系统同步语义的 sequencer。

### 3.5 `wait_after` 真正靠什么收边界

看这里：

```systemverilog
logic seq_needs_wait;
assign seq_needs_wait = seq_instr[23];
```

再看：

```systemverilog
if (vpu_drain) begin
    if (seq_running)
        seq_state <= SEQ_ADVANCE;
    else begin
        busy_reg  <= 1'b0;
        seq_state <= SEQ_IDLE;
    end
end
```

这两段拼起来，你就会明白：

- `wait_after` 不是装饰位
- `dispatch` 也不是完成边界
- 真正的系统完成边界是 `vpu_drain`

这就是为什么这项目一直强调“系统级 wait 语义”。
它不是为了写好看，而是为了防止阶段之间尾拍互相踩踏。

### 3.6 一个很容易忽略的细节：VPU pathway latch

这里还有一段值得注意：

```systemverilog
if (seq_instr_pulse && seq_instr[2:0] == 3'b010)
    vpu_pathway_reg <= seq_instr[22:19];
```

这表示：
- VPU pathway 在 UB_RD dispatch 时被 latch 住
- 后续会持续保持，而不是每拍都重新给

这跟 PPT 里讲的 `1100 / 1111 / 0001` 三条路径正好对应。
说明 Frontend 不只是发“读 UB”命令，还负责把 VPU 路径语义稳定地带过去。

### 3.7 一句话总结

`tpu_frontend_axil.sv` 的本质，不是 AXI 壳，而是把“主机寄存器世界”翻译成“系统执行节奏”的控制中枢。

---

## 4. `scheduler.py`：把软件意图降成硬件阶段命令

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/scheduler.py`

### 4.1 不要误解它的定位

这不是一个通用编译器，也不是 cycle-accurate program compiler。
它更像一个：
**当前 tiny-tpu 原型的阶段级调度器。**

文件里 `_validate_current_target()` 已经明确写死了当前边界：

```python
if len(layers) != 2:
    raise ValueError("scheduler currently supports exactly two linear layers")
if hw.get("array_width") != 2 or hw.get("lanes") != 2:
    raise ValueError("scheduler currently targets the 2x2 / 2-lane tiny-tpu prototype")
```

这说明它不是想装成通用框架，而是很诚实地服务当前项目目标。

### 4.2 `_ub_read()` 是理解它的钥匙

最关键的 helper 是：

```python
def _ub_read(
    stage: str,
    name: str,
    tensor: str,
    ptr_sel: int,
    addr: int,
    row: int,
    col: int,
    transpose: bool,
    *,
    vpu_path: str | None = None,
    note: str = "",
    wait_after: bool = False,
) -> dict[str, Any]:
```

生成的命令结构是：

```python
command = {
    "stage": stage,
    "name": name,
    "kind": "ub_read",
    "tensor": tensor,
    "signals": {
        "ub_rd_start_in": 1,
        "ub_ptr_select": ptr_sel,
        "ub_rd_addr_in": addr,
        "ub_rd_row_size": row,
        "ub_rd_col_size": col,
        "ub_rd_transpose": int(transpose),
    },
    "wait_after": int(wait_after),
}
```

这段非常重要，因为它说明编译器输出的核心，不是高层 tensor graph，而是：
- 从 UB 哪读
- 读什么语义
- 读多大块
- 要不要转置
- 读完要不要等系统收边界

也就是说，schedule 已经非常贴近硬件控制接口了。

### 4.3 三类辅助命令

文件里除了 `_ub_read()`，还有：

```python
def _switch(...):
def _wait(...):
def _nop(...):
```

这意味着 scheduler 输出的不是单一“读命令流”，而是一套阶段级动作脚本：
- load weight tile
- nop 让装载波前走完
- switch shadow -> active
- stream input / bias / Y / H
- wait `vpu_drain`

这正是 PPT 里“编译器与指令组织”那页在讲的内容。

### 4.4 `forward_layer1` 怎么体现项目主线

看这一段：

```python
commands.append(
    _ub_read(
        "forward_layer1",
        "load_w1_shadow",
        "W1",
        1,
        tensors["W1"]["addr"],
        hidden_dim,
        input_dim,
        True,
        note="Load W1^T through the top boundary into the PE shadow weight path.",
    )
)
...
commands.append(_switch("forward_layer1", "activate_w1"))
...
commands.append(
    _ub_read(
        "forward_layer1",
        "stream_x",
        "X",
        0,
        tensors["X"]["addr"],
        batch_size,
        input_dim,
        False,
        vpu_path="1100",
    )
)
```

这里几乎把系统思想全说透了：
- 权重先装 shadow
- 再 `switch` 成 active
- 然后输入从左边流进 systolic
- 同时 VPU pathway 设成 `1100`

这已经不是“某个算子怎么实现”的问题，而是**系统如何把一层前向执行成一串可控步骤**。

### 4.5 `transition_layer2` 为什么特别能说明训练语义

看这里：

```python
"stream_h1" ... vpu_path="1111"
"stream_b2" ... vpu_path="1111"
"stream_y"  ... vpu_path="1111"
"load_old_b2" ... ptr_sel=5 ... wait_after=True
```

这表示这一步不是单纯 forward，而是：
- 第二层 forward
- loss gradient
- bias update
三件事绑在同一阶段里。

所以 `1111` 这条路径的意义，不是一个随便的 bit pattern，而是整个训练过渡阶段的语义编码。

### 4.6 backward 和 update 为什么有说服力

后面这几段尤其能体现“这是训练，不是推理”：

```python
"stream_dz2" ... vpu_path="0001"
"stream_h1_for_derivative" ... ptr_sel=4 ... wait_after=True
```

和：

```python
stage = f"update_w1_tile_{tile_index}"
...
"load_old_w1" ... ptr_sel=6 ... wait_after=True
```

这说明：
- backward 需要 `dZ2`、`H1`、旧 bias
- weight update 需要 outer product tile 和旧权重
- 更新并不是在外部软件算好再写回，而是通过 UB 内 gradient descent 在系统内部完成

### 4.7 `host_load_plan` 为什么关键

最终 `build_schedule()` 还返回：

```python
"host_load_plan": host_load_plan,
"ub_allocation": allocation,
"commands": commands,
```

这说明 scheduler 不只是给 RTL 看，它同时也在告诉 Host：
- 先把哪些 tensor 装到 UB 哪些地址
- 然后再按什么阶段序列执行

这一步正是软件和硬件握手的结合点。

### 4.8 一句话总结

`scheduler.py` 的真正价值，是把“模型训练意图”变成“当前 tiny-tpu 原型可以稳定执行的阶段级硬件动作脚本”。

---

## 5. `tpu.sv`：执行核心组合点

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu.sv`

### 5.1 这个文件没有你想象得复杂

第一次看 `tpu.sv`，很容易期待里面有大量复杂控制。
其实没有。
它做的事情非常明确：

```systemverilog
unified_buffer ub_inst(...);
systolic systolic_inst(...);
vpu vpu_inst(...);
```

这说明 `tpu.sv` 是一个**执行核心组合点**。
它不是编译器，不是前端，不是 sequencer，而是把三块执行资源接成一条数据链。

### 5.2 数据怎么从 UB 走进阵列和 VPU

你看接口就会发现它其实把路径切得很清楚：

- UB -> systolic 左边：`ub_rd_input_*`
- UB -> systolic 上边：`ub_rd_weight_*`
- UB -> VPU：`ub_rd_bias_*`, `ub_rd_Y_*`, `ub_rd_H_*`
- systolic -> VPU：`sys_data_out_*`, `sys_valid_out_*`
- VPU -> UB：`vpu_data_out_*`, `vpu_valid_out_*`

所以 `tpu.sv` 是整个项目里“数据流最直观”的文件。

### 5.3 Host 写进来的数据怎么落到 UB

这段也很重要：

```systemverilog
input logic [15:0] ub_wr_host_data_in [0:SYSTOLIC_ARRAY_WIDTH-1],
input logic ub_wr_host_valid_in [0:SYSTOLIC_ARRAY_WIDTH-1],
input logic ub_wr_ptr_restore_in,
```

这说明 Host 不需要直接懂 UB 内部结构，它只要：
- 把数据写进 frontend 暴露的寄存器
- frontend 再把 host write path 接到 UB

所以 `tpu.sv` 是“执行核心组合点”，但同时也是“host data injection 的落点”。

### 5.4 VPU 写回为什么又回到 UB

这里：

```systemverilog
assign ub_wr_data_in[0] = vpu_data_out_1;
assign ub_wr_data_in[1] = vpu_data_out_2;
assign ub_wr_valid_in[0] = vpu_valid_out_1;
assign ub_wr_valid_in[1] = vpu_valid_out_2;
```

这段就是训练闭环的核心证据之一。
因为它说明：
- systolic/VPU 处理出来的中间结果和梯度
- 不会飘在模块外面
- 而是重新写回 UB，供后续阶段再读

这就是为什么我一直说，这不是推理 demo，而是训练闭环。

### 5.5 `sys_switch_in` 为什么从顶层一路传到 systolic

看这句：

```systemverilog
.sys_switch_in(sys_switch_in)
```

说明前端发出的 `SWITCH` 指令，最终是为了控制阵列里的 shadow/active weight 切换。
这也解释了 scheduler 里为什么经常出现：
- load shadow
- nop
- switch
- stream input

因为阵列权重装载不是瞬时完成的，系统必须明确地区分：
- 先准备
- 再生效

### 5.6 一句话总结

`tpu.sv` 不是“最聪明”的模块，但它是最能把系统数据流看清楚的模块：所有训练数据最终都要经过它这里完成闭环。

---

## 6. `unified_buffer_v3.sv`：真正的数据中枢

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`

### 6.1 为什么说 UB 是整个项目最关键的文件之一

如果只看模块名，很多人会把它想成“普通 buffer”。
这会严重低估它。

这个 UB 同时承担：
- host 参数/数据装载
- systolic input 流
- systolic weight 流
- VPU bias/Y/H 读流
- 中间结果写回
- gradient descent in-place update

所以这不是一个普通 RAM wrapper，而是一个：
**以同一块存储承载多语义训练数据流的中枢。**

### 6.2 内部状态为什么这么多

开头这几组寄存器很能说明问题：

```systemverilog
logic [15:0] wr_ptr;
logic [15:0] wr_ptr_base;
...
logic [15:0] rd_input_ptr;
logic signed [15:0] rd_weight_ptr;
logic [15:0] rd_bias_ptr;
logic [15:0] rd_Y_ptr;
logic [15:0] rd_H_ptr;
logic [15:0] rd_grad_bias_ptr;
logic [15:0] rd_grad_weight_ptr;
logic [15:0] grad_descent_ptr;
```

它们不是冗余，而是因为 UB 真正承载了多类独立语义的读写机：
- input 读机
- weight 读机
- bias/Y/H 读机
- old bias / old weight 更新读机
- writeback 和 update 写机

也就是说，UB 已经不是被动存储，而是半个数据调度器。

### 6.3 `ub_ptr_select` 是理解 UB 的第一钥匙

看初始化分派：

```systemverilog
case (ub_ptr_select)
    0: begin ... end
    1: begin ... end
    2: begin ... end
    3: begin ... end
    4: begin ... end
    5: begin ... end
    6: begin ... end
endcase
```

它们实际对应：
- `0` input
- `1` weight
- `2` bias
- `3` Y
- `4` H
- `5` old bias for update
- `6` old weight for update

这说明同一块 UB 被复用成多种“逻辑视图”。
所以 scheduler 里的 `ptr_sel` 不是普通 selector，而是**数据语义选择器**。

### 6.4 `wr_ptr_base / restore` 是第二把钥匙

这段必须看懂：

```systemverilog
if (ub_wr_host_valid_in[0] || ub_wr_host_valid_in[1]) begin
    wr_ptr_base <= wr_ptr_next;
end
if (ub_wr_ptr_restore_in) begin
    wr_ptr <= wr_ptr_base;
end else begin
    wr_ptr <= wr_ptr_next;
end
```

这段逻辑的价值在于：

- Host 初始装载会不断推进 `wr_ptr`
- 同时把“静态区尾部”记在 `wr_ptr_base`
- 每次新一轮 `start` 时，Frontend 把 `ub_wr_ptr_restore_out` 拉起来
- UB 再把 `wr_ptr` 拉回静态区后面

于是运行时写回区永远从一个干净边界开始，避免踩掉初始参数和输入区。

这就是 PPT 那页 `wr_ptr / base / restore` 的核心。
如果你只能记住 UB 一个机制，就记这个。

### 6.5 weight 和 input 为什么读法不一样

看这两段指针逻辑：

```systemverilog
rd_input_ptr_next = rd_input_ptr;
...
rd_input_ptr_next = rd_input_ptr_next + 1;
```

和：

```systemverilog
if(rd_weight_transpose) begin
    ...
    rd_weight_ptr_next = rd_weight_ptr_next + rd_weight_skip_size;
end else begin
    ...
    rd_weight_ptr_next = rd_weight_ptr_next - rd_weight_skip_size;
end
```

这说明：
- input 更像左边界顺序流
- weight 更像顶部装载，需要考虑 transpose 和 column/row 映射

也就是说，UB 对 input 和 weight 的读，不只是地址不同，而是**传播方向和阵列接口语义都不同**。

### 6.6 为什么要单独处理 hold cycle

例如 input 读逻辑：

```systemverilog
else if (rd_input_time_counter + 1 == rd_input_row_size + rd_input_col_size) begin
    // Hold cycle: preserve outputs from last active cycle
```

而 weight 读逻辑又不同：

```systemverilog
// Do not hold weight valids high for an extra cycle.
// The systolic loader samples on every asserted valid...
```

这恰好说明了系统时序对齐的难点：
- input 流最后一拍可能需要 hold
- weight 流最后一拍如果多 hold，反而会误装最后一个权重

所以项目里“UB 发数和 PE 时序对齐”并不是抽象问题，而是在这些 always_ff 里非常具体地体现出来。

### 6.7 gradient descent 为什么在 UB 内完成

看这里：

```systemverilog
gradient_descent gradient_descent_inst (
    .lr_in(learning_rate_in),
    .grad_in(ub_wr_data_in[i]),
    .value_old_in(value_old_in[i]),
    .grad_descent_valid_in(grad_descent_valid_in[i]),
    .grad_bias_or_weight(grad_bias_or_weight),
    .value_updated_out(value_updated_out[i]),
    .grad_descent_done_out(grad_descent_done_out[i])
);
```

这说明更新路径是：
- VPU/阵列产生梯度流
- UB 同时从 memory 里取旧参数 `value_old_in`
- gradient_descent 模块在 UB 内部算更新值
- 再写回 `ub_memory`

所以参数更新不需要跑回软件侧，也不需要独立 DMA/ALU 再兜一圈。
这正是当前 tiny-tpu 原型设计里非常聪明的一点：
**把更新尽量留在数据中枢里完成。**

### 6.8 代码里的 bug 修复痕迹也很有价值

比如这段注释：

```systemverilog
// Weight updates need the final systolic beat as well.
// The current counter is already one cycle ahead ...
// so "+1 <" drops the last lane1 update for W2 and W1 column 2.
```

这说明项目不是只把 happy path 跑通，而是真正遇到过训练路径上的边界问题，然后在 UB 更新时序里修掉了。

还有这段：

```systemverilog
// Bias update old values are consumed by gradient_descent one cycle later, so preload
// the next bias wavefront once the derivative stream has started.
```

说明 bias update 也不是简单直连，而是有时序预取对齐问题。

这些注释本身就是很好的“工程细节证据”。

### 6.9 一句话总结

`unified_buffer_v3.sv` 不是存储模块，而是这套训练闭环里最像“数据控制中枢”的地方。

---

## 7. `test_tpu_soc_axil_train_convergence.py`：最终证据链

文件：
- `/home/jjt/tpu-soc/test/test_tpu_soc_axil_train_convergence.py`

### 7.1 这个测试为什么重要

如果没有这个测试，前面所有模块都可能只是“能响应控制”。
有了这个测试，才能证明：
- Host 真能通过 AXI-Lite 控制系统
- 系统真能连续执行完整训练阶段
- loss 真会下降
- XOR 真能收敛

所以它不是普通单元测试，而是整个项目的**系统级证据页落地文件**。

### 7.2 它先定义了数值语义

开头先定义：

```python
FRAC_BITS = 8
TRAIN_EPOCHS = 12
LOSS_TARGET = 0.21
```

再定义：
- `to_fxp / from_fxp / fxp`
- XOR 数据集 `X / Y`
- 初始化参数 `INIT_W1 / INIT_B1 / INIT_W2 / INIT_B2`
- `LEAK / INV_N2 / LR`

这说明测试不是只看信号 toggling，而是对照固定 Q8.8 数值语义在跑。

### 7.3 Host 侧控制入口很清楚

这几个 helper 很关键：

```python
async def axil_write(dut, addr, data):
async def axil_read(dut, addr):
async def ub_write_cycle(dut, d0, d1, push_mask):
```

它们把 Host 世界的动作写得很明白：
- 写寄存器
- 读状态
- 分 lane 往 UB 推数据

所以当你讲“AXI-Lite 真能控制系统”时，不要空说，直接说这几个 helper 就够了。

### 7.4 UB 装载是怎么做的

这段特别能体现 Host 和 UB 的对应关系：

```python
async def load_all_data_axil(dut, x, y, w1, b1, w2, b2):
    seq = [
        (to_fxp(x[0][0]), 0, 1),
        (to_fxp(x[1][0]), to_fxp(x[0][1]), 3),
        ...
        (to_fxp(b2[0]), to_fxp(w2[1]), 3),
    ]
```

这里你能直接看到：
- host 不是随便写 UB
- 它是按照当前 compiler/UB 约定的布局，把 X/Y/W1/B1/W2/B2 组织成具体 lane push 序列

这就是 `host_load_plan` 在测试侧的具体落实。

### 7.5 IMEM 装载怎么发生

```python
async def imem_load(dut, hex_path):
    lines = Path(hex_path).read_text().strip().splitlines()
    instrs = [int(line.strip(), 16) for line in lines if line.strip()]
    for i, instr in enumerate(instrs):
        await axil_write(dut, 0x030, i)
        await axil_write(dut, 0x034, instr)
        await axil_write(dut, 0x040, 1)
```

这段跟 frontend 寄存器图完全对上：
- `0x30` 设地址
- `0x34` 写指令字
- `0x40` commit
- `0x44` 写 `IMEM_LEN`

所以“编译器 -> IMEM -> Frontend”的链路在这里真正闭合了。

### 7.6 一轮训练怎么启动

```python
async def run_one_epoch(dut, epoch_idx):
    await axil_write(dut, 0x000, 0x2)
    for attempt in range(200):
        await ClockCycles(dut.s_axil_aclk, 500)
        status = await axil_read(dut, 0x004)
        if not (status & 0x1):
            return
```

这段代码非常有代表性：
- `0x000` 写 `0x2` 就是 `CTRL.start=1`
- 后面轮询 `STATUS.busy`
- busy 清掉代表 sequencer 这一轮执行完

所以系统运行边界在软件侧也是可观测的。

### 7.7 为什么 `read_hw_params()` 很有价值

```python
def read_hw_params(dut):
    ub = dut.dut.tpu_inst.ub_inst.ub_memory
    w1_words = [int(ub[12 + i].value) & 0xFFFF for i in range(4)]
    ...
```

这说明测试不是只看输出分类，而是还能直接读 UB 里的参数区，看硬件内部参数更新结果。

也就是说，验证证据是分层的：
- 寄存器级
- 波形级
- 参数内存级
- loss 级
- 最终分类级

这就是项目说服力强的原因之一。

### 7.8 一句话总结

`test_tpu_soc_axil_train_convergence.py` 不是附属脚本，而是这整个项目“闭环成立”的最终证明文件。

---

## 8. 把 6 个文件串成“一轮训练”

现在把它们连起来：

### Step 1 软件准备

`scheduler.py` 根据模型规格生成：
- `ub_map`
- `schedule`
- `imem`

### Step 2 Host 装载

测试通过 `axil_write()`、`load_all_data_axil()`、`imem_load()` 把：
- 参数/输入/标签装进 UB
- 指令装进 IMEM

### Step 3 Frontend 启动

`tpu_frontend_axil.sv` 收到 `CTRL.start` 后：
- 把 `pc` 置零
- 取 `imem[0]`
- `seq_running=1`
- 同时拉起 `ub_wr_ptr_restore_out`

### Step 4 顶层桥接

`tpu_soc.sv` 把：
- `ub_rd_start`
- `ub_ptr_sel`
- `sys_switch`
- `vpu_data_pathway`
- `ub_wr_ptr_restore`
这些语义信号送进 `tpu_inst`

### Step 5 Core 执行

`tpu.sv` 中：
- UB 发 input/weight/bias/Y/H/old params
- systolic 做 forward/backward/outer product
- VPU 做激活、loss、导数路径
- VPU 结果重新写回 UB

### Step 6 参数更新

`unified_buffer_v3.sv` 中：
- 读旧 bias / 旧 weight
- 接收梯度流
- gradient_descent 算更新值
- 原地写回 `ub_memory`

### Step 7 验证

`test_tpu_soc_axil_train_convergence.py`：
- 轮询状态
- 看 loss 下降
- 看最终 XOR 分类
- 必要时读回 UB 参数区

这就是整个项目“来龙去脉”的代码化版本。

---

## 9. 这套源码里最该记住的 10 句话

1. `tpu_soc.sv` 不是计算模块，而是系统桥接层。
2. `tpu_frontend_axil.sv` 不只是寄存器壳，而是控制中枢。
3. `start_pulse` 同时意味着正式运行和 `wr_ptr_restore`。
4. `wait_after` 真正靠 `vpu_drain` 收边界。
5. `scheduler.py` 输出的是阶段级硬件动作脚本，不是抽象 IR。
6. `ptr_sel` 是 UB 数据语义选择器，不只是地址修饰。
7. `tpu.sv` 是执行数据流的组合点。
8. UB 不只是 memory，而是训练数据中枢。
9. gradient descent 在 UB 内做，说明更新路径已经系统内闭环。
10. `test_tpu_soc_axil_train_convergence.py` 是项目成立的最终证据文件。

---

## 10. 你怎么用这份文档

如果你现在的目标是理解项目，而不是背 PPT，我建议这样用：

1. 先看 `01_main_8p.pptx`
2. 再读 `05_project_explainer_zh.md`
3. 然后读这份 `源码精讲版`
4. 最后直接打开源码文件对着看

如果你现在的目标是准备面试：

1. 先用 `06_interview_walkthrough_zh.md` 讲顺 8 页
2. 再用这份 `源码精讲版` 补充你能接住追问的底层依据
3. 最后用 `07_study_guide_zh.md` 做考前复习

最后一句提醒：
**这项目最难的地方不是某一行 RTL，而是这 6 个文件最后能拼成一条完整训练闭环。**


---

# Part 6 Frontend AXI-Lite 模块精讲

# `tpu_frontend_axil.sv` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`

这份文档只讲一个文件：`tpu_frontend_axil.sv`。
目标不是把每个 AXI 信号都解释一遍，而是让你真正理解：
**为什么这个文件是整个项目的控制中枢，它到底怎么把 Host 的寄存器写操作，变成 TPU 可以执行的一轮程序。**

---

## 1. 先给这个文件一个定位

很多人第一次看它，会把它误解成“AXI-Lite 外壳”。
这不对。

它至少叠了 4 个角色：

1. AXI-Lite slave 寄存器接口
2. IMEM 装载器
3. Sequencer
4. 指令译码后的控制脉冲分发器

所以这个文件不是边角料，而是：
**Host 世界进入 TPU 系统的控制入口。**

---

## 2. 文件开头已经把系统意图写出来了

最值得先看的不是 always_ff，而是顶部注释：

```systemverilog
// TinyTPU AXI-Lite Frontend (step mode + IMEM + sequencer)
```

这句话已经把三层能力讲清楚了：
- `step mode`：单步调试/打 staging 指令
- `IMEM`：把程序装起来
- `sequencer`：按程序自动推进

如果没有这三层，这个项目就只能停留在 testbench 手工打信号。

---

## 3. 寄存器地图就是控制语义地图

开头的寄存器定义非常关键：

```systemverilog
//   0x00  CTRL       bit0=step
//                   bit1=start
//   0x04  STATUS     bit0=busy
//                   bit1=running
//   0x10  INSTR_W0   32-bit opcode instruction
//   0x20  UB_DATA
//   0x24  UB_PUSH
//   0x30  IMEM_ADDR
//   0x34  IMEM_W0
//   0x40  IMEM_WE
//   0x44  IMEM_LEN
//   0x50  LEAK
//   0x54  INV_BATCH
//   0x58  LR
```

你可以把它直接翻译成人话：

- `CTRL`：开始跑，或者单步打一条
- `STATUS`：现在是不是还在执行
- `INSTR_W0`：step 模式临时放一条指令
- `UB_DATA/UB_PUSH`：Host 往 UB 里塞数据
- `IMEM_*`：Host 往程序存储里塞指令
- `LEAK / INV_BATCH / LR`：训练路径的参数配置

这个寄存器图已经说明，这个前端不是为“纯推理加速器”设计的，而是为当前 tiny-tpu 训练原型设计的。

---

## 4. 输出端口其实就是整个系统的控制面

文件的 output 很值得专门看一次：

```systemverilog
output logic [15:0] ub_wr_host_data_out_0,
output logic        ub_wr_host_valid_out_0,
output logic [15:0] ub_wr_host_data_out_1,
output logic        ub_wr_host_valid_out_1,
output logic        ub_wr_ptr_restore_out,

output logic        sys_switch_out,
output logic        ub_rd_start_out,
output logic        ub_rd_transpose_out,
output logic [1:0]  ub_rd_col_size_out,
output logic [3:0]  ub_rd_row_size_out,
output logic [5:0]  ub_rd_addr_out,
output logic [2:0]  ub_ptr_sel_out,
output logic [3:0]  vpu_data_pathway_out,
```

这批信号其实就是 PPT 里的“控制主链”。
它们大致分成三类：

1. Host 写 UB 的入口
2. UB 读流的控制字段
3. systolic/VPU 的运行语义字段

也就是说，Frontend 做的不是“协议搬运”，而是“控制语义发射”。

---

## 5. `clk_out` / `rst_out` 和 `start -> restore` 这两句值得单独记

先看：

```systemverilog
assign clk_out = s_axil_aclk;
assign rst_out = ~s_axil_aresetn;
assign ub_wr_ptr_restore_out = start_pulse;
```

前两句很好理解：
- TPU core 直接复用 AXI-Lite 时钟
- AXI-Lite 的低有效 reset 翻成 TPU 用的高有效 reset

第三句特别关键：

```systemverilog
assign ub_wr_ptr_restore_out = start_pulse;
```

这表示每次 `CTRL.start` 触发 auto-run 时，前端会同时触发 `wr_ptr_restore`。
也就是说：
- `start` 不只是“开始跑”
- 它还意味着“把运行时写指针恢复到静态参数区边界之后”

所以从系统语义上讲，`start` 其实等于：
**从一个干净边界重新开始一轮程序。**

---

## 6. 文件里真正的灵魂：Sequencer

### 6.1 状态定义本身就已经说明问题

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
```

这 4 个状态的意义是：

- `IDLE`：等 step/start
- `DISPATCH`：打一拍控制脉冲
- `WAIT`：等系统级完成边界
- `ADVANCE`：PC 前进到下一条

重点是：这里不是简单“取指-执行”，而是显式把系统同步边界单独做成一个状态。

### 6.2 `wait_after` 是怎么来的

```systemverilog
logic seq_needs_wait;
assign seq_needs_wait = seq_instr[23];
```

这说明前端直接把指令 bit23 当成 `wait_after`。
这和 PPT 里讲的“编译器会在 stage 边界插入 wait 语义”完全对应。

所以如果你被问“wait_after 最后落在哪里”，答案就是：
**落在 Frontend sequencer 的 `seq_instr[23]` 上。**

### 6.3 `IDLE` 同时支持 step 和 auto-run

看这段：

```systemverilog
SEQ_IDLE: begin
    seq_running <= 1'b0;
    if (step_pulse) begin
        seq_instr       <= instr_w0_reg;
        seq_instr_pulse <= 1'b1;
        busy_reg        <= 1'b1;
        seq_state       <= SEQ_WAIT;
    end else if (start_pulse) begin
        pc          <= '0;
        seq_instr   <= imem[0];
        seq_running <= 1'b1;
        busy_reg    <= 1'b1;
        seq_state   <= SEQ_DISPATCH;
    end
end
```

这里特别值得注意：
- `step` 走的是“打一条 staging 指令”
- `start` 走的是“PC 置零，从 IMEM[0] 开始自动运行”

所以这个前端同时支持：
- 调试模式
- 程序模式

这就是为什么它比普通寄存器接口更像一个小控制器。

### 6.4 `DISPATCH` 只负责打一拍，不负责收尾

```systemverilog
SEQ_DISPATCH: begin
    seq_instr_pulse <= 1'b1;
    if (seq_needs_wait)
        seq_state <= SEQ_WAIT;
    else
        seq_state <= SEQ_ADVANCE;
end
```

这段很重要，因为它强调：
**dispatch 只负责把控制发出去，不负责判断“这一步是否真的完成”。**

真正的完成边界要看后面 `WAIT`。

### 6.5 `WAIT` 不是等 dispatch 结束，而是等 `vpu_drain`

```systemverilog
if (vpu_drain) begin
    if (seq_running)
        seq_state <= SEQ_ADVANCE;
    else begin
        busy_reg  <= 1'b0;
        seq_state <= SEQ_IDLE;
    end
end
```

这段就是整套系统最关键的控制语义之一。

它说明：
- 一个 stage 完成，不是“脉冲发出去了”
- 也不是“UB 开始读了”
- 而是“VPU 最后的 valid 已经 drain 掉了”

所以 `wait_after` 在这套系统里是**系统级同步点**，不是装饰字段。

### 6.6 `ADVANCE` 才是程序边界管理

```systemverilog
if (pc + 1 < {{($clog2(IMEM_DEPTH)-6){1'b0}}, imem_len_reg}) begin
    pc        <= pc + 1;
    seq_instr <= imem[pc + 1];
    seq_state <= SEQ_DISPATCH;
end else begin
    seq_running <= 1'b0;
    busy_reg    <= 1'b0;
    seq_state   <= SEQ_IDLE;
end
```

这段说明 sequencer 并不是无限流，而是明确受 `IMEM_LEN` 约束。
程序跑到最后，会：
- 清 `running`
- 清 `busy`
- 回到 `IDLE`

所以 Host 侧轮询 `STATUS.busy` 就能知道一轮程序什么时候跑完。

---

## 7. `vpu_drain` 是怎么构出来的

代码里用了一个很典型的 edge-detect：

```systemverilog
vpu_valid_prev <= tpu_vpu_valid_in;
vpu_drain      <= vpu_valid_prev && !tpu_vpu_valid_in;
```

意思很直接：
- 这拍之前还有 VPU valid
- 这拍已经没有了
- 那就说明上一段尾拍排空了

所以 `vpu_drain` 的本质是：
**VPU 有效流从 1 掉到 0 的收尾沿。**

这就是 sequencer 用来判断“当前 stage 真正完成”的系统证据。

---

## 8. AXI-Lite 写通道：别钻握手细节，要抓“写了以后系统发生了什么”

### 8.1 写状态机只是标准壳

写通道状态机：

```systemverilog
typedef enum logic [1:0] {
    W_IDLE      = 2'b00,
    W_WAIT_W    = 2'b01,
    W_WAIT_AW   = 2'b10,
    W_RESP      = 2'b11
} w_state_t;
```

这个状态机本身没什么特别的，它主要负责把 AW/W 两拍拼起来，最后产生 `wr_fire`。

### 8.2 真正重要的是寄存器写 decode

```systemverilog
if (wr_fire) begin
    case (aw_lat)
        12'h000: begin
            if (wd_lat[0]) step_pulse  <= 1'b1;
            if (wd_lat[1]) start_pulse <= 1'b1;
        end
        12'h010: instr_w0_reg    <= wd_lat;
        12'h020: ub_data0_reg    <= wd_lat[15:0];
        12'h024: begin
            if (wd_lat[0]) ub_push0_pulse <= 1'b1;
            if (wd_lat[1]) ub_push1_pulse <= 1'b1;
        end
        12'h028: ub_data1_reg    <= wd_lat[15:0];
        12'h030: imem_addr_reg   <= wd_lat[$clog2(IMEM_DEPTH)-1:0];
        12'h034: imem_w0_reg     <= wd_lat;
        12'h040: if (wd_lat[0]) imem[imem_addr_reg] <= imem_w0_reg;
        12'h044: imem_len_reg    <= wd_lat[5:0];
        12'h050: leak_factor_reg   <= wd_lat[15:0];
        12'h054: inv_batch_n2_reg  <= wd_lat[15:0];
        12'h058: learning_rate_reg <= wd_lat[15:0];
    endcase
end
```

这段就是整个 Host 控制面的落点。

你可以按用途理解：
- `0x000`：发 step/start 脉冲
- `0x020/0x024/0x028`：往 UB lane0/lane1 装数据
- `0x030/0x034/0x040/0x044`：装 IMEM 程序
- `0x050/0x054/0x058`：装训练参数

所以你如果想回答“Host 到底怎么控制系统”，答案基本就在这段里。

---

## 9. AXI-Lite 读通道：为什么 `STATUS` 值得记

读通道本身也不难，但 `STATUS` 返回值很关键：

```systemverilog
12'h004: s_axil_rdata <= {30'h0, seq_running, busy_reg};
```

也就是说：
- bit0 = `busy`
- bit1 = `running`

这解释了测试里为什么可以用轮询 `0x004` 的方式等待一轮训练完成。

如果你需要一句非常实战的话术：
**软件侧不是盲等固定周期，而是通过 `STATUS` 观察 sequencer 是否真正结束。**

---

## 10. `control_unit` 在这里扮演什么角色

这一段容易被忽略：

```systemverilog
logic [31:0] instr_to_cu;
assign instr_to_cu = seq_instr_pulse ? seq_instr : '0;

control_unit cu_inst (
    .instruction                 (instr_to_cu),
    .sys_switch_in               (sys_switch_out),
    .ub_rd_start_in              (ub_rd_start_out),
    ...
    .ub_ptr_sel                  (ub_ptr_sel_out),
    .vpu_data_pathway            (cu_vpu_data_pathway),
```

它说明 Frontend 自己并不手写所有字段 decode，而是：
- sequencer 决定“什么时候把一条指令发给 control_unit”
- control_unit 决定“这条指令拆成哪些硬件字段”
- Frontend 再把这些字段组织成系统输出口

所以 Frontend 其实是“sequencer + register file + AXI + mux + decode glue”的组合。

---

## 11. `vpu_pathway_reg` 为什么要 latch

代码里有一句：

```systemverilog
if (seq_instr_pulse && seq_instr[2:0] == 3'b010)
    vpu_pathway_reg <= seq_instr[22:19];
```

后面输出又是：

```systemverilog
assign vpu_data_pathway_out = vpu_pathway_reg;
```

这说明 VPU pathway 不是“打一拍就没了”，而是要在一个阶段里持续保持。

这很合理，因为 VPU 路径决定的是：
- forward
- transition/loss
- backward derivative

这些都不是单拍动作，而是一段流的语义。

所以这句 latch 是为了让 `1100 / 1111 / 0001` 这些路径码在阶段期间稳定生效。

---

## 12. Host UB_PUSH 和 control_unit 的 UB_WR_HOST 为什么要做 mux

这一段很容易考：

```systemverilog
assign ub_wr_host_valid_out_0 = ub_push0_pulse ? 1'b1        : cu_ub_valid_0;
assign ub_wr_host_valid_out_1 = ub_push1_pulse ? 1'b1        : cu_ub_valid_1;
assign ub_wr_host_data_out_0  = ub_push0_pulse ? ub_data0_reg : cu_ub_data_0;
assign ub_wr_host_data_out_1  = ub_push1_pulse ? ub_data1_reg : cu_ub_data_1;
```

这里体现的是：
- Host 可以通过寄存器直接往 UB 推数据
- control_unit 也可能通过指令语义发起 UB_WR_HOST
- 两条路径最终共用同一个 UB host write 口
- 但如果当前有 AXI `UB_PUSH`，它优先

这段 mux 非常工程化，它解决的是“一个写口，两种来源”的问题。

如果你被问“为什么要这样设计”，可以直接答：
**因为系统既要支持 Host 直接装数据，也要支持指令驱动的 host-write 语义，所以最终在前端统一仲裁。**

---

## 13. 把整个文件压成一句流程图

你可以把 `tpu_frontend_axil.sv` 理解成下面这条链：

1. AXI-Lite 写寄存器
2. 寄存器更新 `CTRL / UB / IMEM / training params`
3. `step` 或 `start` 产生脉冲
4. Sequencer 取指并决定 `dispatch / wait / advance`
5. `control_unit` 拆字段
6. Frontend 输出 `ub_rd_start / ptr_sel / pathway / switch / ub_wr_host_*`
7. TPU core 执行
8. Frontend 用 `vpu_drain` 收 stage 边界

这就是整个文件的骨架。

---

## 14. 你最该记住的 8 个点

1. 它不是 AXI 壳，而是控制中枢。
2. `start_pulse` 同时触发一轮正式运行和 `wr_ptr_restore`。
3. `step` 是临时单步，`start` 是程序模式。
4. `wait_after` 直接落在 `seq_instr[23]`。
5. `DISPATCH` 只打一拍，不代表阶段完成。
6. 真正的阶段完成边界是 `vpu_drain`。
7. `vpu_pathway` 会被 latch，在阶段期间持续有效。
8. Host 的 `UB_PUSH` 和 control_unit 的 `UB_WR_HOST` 在这里做统一仲裁。

---

## 15. 最后一句话

如果只让我用一句话概括这个文件，那就是：

**`tpu_frontend_axil.sv` 把 Host 的寄存器写操作，翻译成了 tiny-tpu 整个系统可以按阶段稳定执行的控制节奏。**


---

# Part 7 Unified Buffer 模块精讲

# `unified_buffer_v3.sv` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`

这份文档只讲 `unified_buffer_v3.sv`。
如果你真的想理解这个项目最难的工程点，这个文件必须吃透。
因为它不是一块普通 RAM，而是：
**整个 tiny-tpu 训练闭环里的数据中枢、读写仲裁点和参数更新落点。**

---

## 1. 先把这个文件的定位讲清楚

表面上看，它叫 `unified_buffer`。
但在这个项目里，它实际上承担了 6 件事：

1. Host 装载输入、标签、初始参数
2. 给 systolic 左边提供 input 流
3. 给 systolic 上边提供 weight 流
4. 给 VPU 提供 bias / Y / H 流
5. 接收 VPU 写回的激活或梯度
6. 在内部完成 gradient descent 更新并写回旧参数

所以这个模块的真实身份不是“buffer”，而是：
**多语义训练数据流的中枢。**

---

## 2. 为什么内部状态这么多

一眼看上去最吓人的，是这一大片内部寄存器：

```systemverilog
logic [15:0] wr_ptr;
logic [15:0] wr_ptr_base;

logic [15:0] rd_input_ptr;
logic signed [15:0] rd_weight_ptr;
logic [15:0] rd_bias_ptr;
logic [15:0] rd_Y_ptr;
logic [15:0] rd_H_ptr;
logic [15:0] rd_grad_bias_ptr;
logic [15:0] rd_grad_weight_ptr;
logic [15:0] grad_descent_ptr;
```

它们不是设计糟糕，而是因为这个模块内部其实住着多台“读写机”：
- input 读机
- weight 读机
- bias 读机
- Y 读机
- H 读机
- old bias / old weight 更新读机
- writeback 写机
- gradient_descent 写回写机

所以你第一眼不要把它当“简单 memory controller”，而要把它当“以同一块存储实现多语义训练流水的数据中枢”。

---

## 3. 顶部接口已经说明它为什么不普通

### 3.1 写口就有两类来源

```systemverilog
input logic [15:0] ub_wr_data_in [SYSTOLIC_ARRAY_WIDTH],
input logic ub_wr_valid_in [SYSTOLIC_ARRAY_WIDTH],

input logic [15:0] ub_wr_host_data_in [SYSTOLIC_ARRAY_WIDTH],
input logic ub_wr_host_valid_in [SYSTOLIC_ARRAY_WIDTH],
input logic ub_wr_ptr_restore_in,
```

这表示：
- 一类写来自 VPU/执行路径
- 一类写来自 Host/前端装载路径

换句话说，UB 同时面对“初始化装载”和“运行时写回”两类写流。

### 3.2 读口也不是一种读法

```systemverilog
input logic ub_rd_start_in,
input logic ub_rd_transpose,
input logic [8:0] ub_ptr_select,
input logic [15:0] ub_rd_addr_in,
input logic [15:0] ub_rd_row_size,
input logic [15:0] ub_rd_col_size,
```

这说明每次读都不是单纯给个地址，而是带着完整语义：
- 读什么类型的数据
- 从哪读
- 读几行几列
- 是否转置

所以它的读取不是“地址访问”，而是“阶段级数据流启动”。

---

## 4. `ub_ptr_select` 是理解 UB 的第一钥匙

### 4.1 指令启动时的 case 分发

最值得看的就是读命令初始化：

```systemverilog
if (ub_rd_start_in) begin
    case (ub_ptr_select)
        0: begin ... end
        1: begin ... end
        2: begin ... end
        3: begin ... end
        4: begin ... end
        5: begin ... end
        6: begin ... end
    endcase
end
```

它们分别对应：

- `0`：input
- `1`：weight
- `2`：bias
- `3`：Y
- `4`：H
- `5`：old bias for update
- `6`：old weight for update

这说明同一块 `ub_memory` 会被不同执行单元以不同语义访问。

所以 `ptr_select` 的本质不是“小字段修饰地址”，而是：
**告诉 UB 这次我要启动哪一种数据流。**

### 4.2 这和编译器怎么对应

`scheduler.py` 里 `_ub_read()` 生成的就是：

```python
"ub_ptr_select": ptr_sel,
```

也就是说，软件侧 stage 命令和 UB 内部 case 分发是一一对上的。

这是整个项目软件到硬件对齐最关键的一环之一。

---

## 5. `wr_ptr` / `wr_ptr_base` / `restore` 是第二钥匙

### 5.1 这段必须背下来

```systemverilog
if (ub_wr_host_valid_in[0] || ub_wr_host_valid_in[1]) begin
    wr_ptr_base <= wr_ptr_next;
end
if (ub_wr_ptr_restore_in) begin
    wr_ptr <= wr_ptr_base;
end else begin
    wr_ptr <= wr_ptr_next;
end
```

### 5.2 这段到底解决什么问题

Host 一开始会把：
- `X`
- `Y`
- `W1`
- `B1`
- `W2`
- `B2`
装进 UB。

训练过程中，VPU 又会写回：
- `H1`
- `dZ2`
- `dZ1`
- 更新后的参数

如果没有边界恢复机制，运行时写回就可能把静态区踩掉。

### 5.3 这个机制的完整语义

它的语义是：

1. Host 写入时，`wr_ptr` 前进
2. 同时把静态区尾部记在 `wr_ptr_base`
3. 每次新一轮 `start`，Frontend 拉起 `ub_wr_ptr_restore_out`
4. UB 把 `wr_ptr` 拉回 `wr_ptr_base`
5. 本轮写回区重新从静态区后面开始

这就是为什么 PPT 要专门做一页 `wr_ptr / base / restore`。
这不是小实现细节，而是整个训练闭环成立的基础。

---

## 6. host 写和 VPU 写为什么能共存

### 6.1 写地址不是简单自增，而是按 lane 计算

```systemverilog
always_comb begin
    wr_ptr_next = wr_ptr;
    for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
        wr_lane_addr[j] = wr_ptr_next;
        if (ub_wr_valid_in[j] || ub_wr_host_valid_in[j]) begin
            wr_ptr_next = wr_ptr_next + 1;
        end
    end
end
```

这说明：
- 写指针前进不是固定每拍加 1
- 而是根据 lane 是否真的 valid 决定
- 每个 lane 在当前拍有自己的目标地址

### 6.2 真正写 memory 的逻辑

```systemverilog
for (int j = SYSTOLIC_ARRAY_WIDTH-1; j >= 0; j--) begin
    if (ub_wr_valid_in[j]) begin
        ub_memory[wr_lane_addr[j]] <= ub_wr_data_in[j];
    end else if (ub_wr_host_valid_in[j]) begin
        ub_memory[wr_lane_addr[j]] <= ub_wr_host_data_in[j];
    end
end
```

这里体现的是优先级：
- 同一 lane 同一拍如果 VPU 写 valid 存在，优先写运行时数据
- 否则才写 Host 数据

这说明 UB 不是两个完全隔离的写通道，而是统一写入一个地址空间。

---

## 7. input 读流：为什么像左边界波前

### 7.1 指针推进很直观

```systemverilog
rd_input_ptr_next = rd_input_ptr;
...
rd_input_ptr_next = rd_input_ptr_next + 1;
```

input 更像顺序流，从左侧送入阵列。

### 7.2 为什么有 transpose 版本

```systemverilog
if(ub_rd_transpose) begin
    rd_input_row_size <= ub_rd_col_size;
    rd_input_col_size <= ub_rd_row_size;
end else begin
    rd_input_row_size <= ub_rd_row_size;
    rd_input_col_size <= ub_rd_col_size;
end
```

这表示 input 读流本身也支持转置语义。
虽然在当前主线里更常见的是 weight transpose，但这个接口本身保留了更通用的矩阵块流能力。

### 7.3 为什么最后要 hold 一拍

```systemverilog
else if (rd_input_time_counter + 1 == rd_input_row_size + rd_input_col_size) begin
    // Hold cycle: preserve outputs from last active cycle
```

这里的 hold cycle 说明 input 流的最后一拍需要在系统里保持一下，帮助后级稳定采样。

这也是“时序对齐不是抽象概念”的一个具体例子。

---

## 8. weight 读流：为什么比 input 更复杂

### 8.1 weight 读流的指针不是简单加一

看这段：

```systemverilog
if(rd_weight_transpose) begin
    ...
    rd_weight_ptr_next = rd_weight_ptr_next + rd_weight_skip_size;
end else begin
    ...
    rd_weight_ptr_next = rd_weight_ptr_next - rd_weight_skip_size;
end
```

这说明 weight 流不是普通顺序读，而是为了适配：
- 顶部装权重
- 行列映射
- transpose/non-transpose 两种模式

所以 weight 路径天然比 input 路径复杂。

### 8.2 `ub_rd_col_size_out` 为什么要单独送出去

```systemverilog
ub_rd_col_size_out <= ub_rd_row_size;   // transpose case
...
ub_rd_col_size_out <= ub_rd_col_size;   // normal case
```

这意味着 systolic 阵列不仅需要 weight 数据本身，还需要知道当前这批权重对应多少列，方便阵列内部控制。

所以 UB 在送 weight 时，不是纯 data plane，还顺带承担了 shape/control plane 的一部分。

### 8.3 为什么 weight 不能像 input 一样 hold valid

源码里直接写了注释：

```systemverilog
// Do not hold weight valids high for an extra cycle.
// The systolic loader samples on every asserted valid,
// so preserving the final pulse overwrites PE22 with the last lane1 weight.
```

这句话非常关键。
它说明：
- input 最后一拍 hold 是合理的
- weight 如果 hold，反而会导致阵列重复采最后一拍权重
- 最终覆盖错误位置的 PE shadow/active 值

这就是为什么 PPT 里专门讲了“UB 读时序和 PE 计算时序对齐”。

---

## 9. bias / Y / H 读流：为什么又是三种不同语义

后半段可以看到三组逻辑：

```systemverilog
// READING LOGIC (Bias)
// READING LOGIC (Y)
// READING LOGIC (H)
```

它们的共同点是：
- 都从 `ub_memory` 读
- 都按 wavefront/time_counter 推进

但语义完全不同：
- bias 给 VPU bias 模块
- Y 给 loss 路径
- H 给 activation derivative 路径

这说明 UB 真正服务的不是一个后级，而是同时服务 systolic 和 VPU 的多条训练子路径。

---

## 10. gradient descent 这块为什么说明项目已经不是推理 demo

### 10.1 文件里直接实例化了 gradient_descent

```systemverilog
gradient_descent gradient_descent_inst (
    .lr_in(learning_rate_in),
    .grad_in(ub_wr_data_in[i]),
    .value_old_in(value_old_in[i]),
    .grad_descent_valid_in(grad_descent_valid_in[i]),
    .grad_bias_or_weight(grad_bias_or_weight),
    .value_updated_out(value_updated_out[i]),
    .grad_descent_done_out(grad_descent_done_out[i])
);
```

它说明更新路径是系统内完成的：
- 执行路径产生梯度
- UB 读旧参数
- gradient_descent 算新参数
- 再写回 UB

这不是把梯度扔回软件再更新，而是在 RTL 系统内部闭环完成训练更新。

### 10.2 bias update 和 weight update 不是一回事

源码专门把两种更新分开处理：

- `rd_grad_bias_*`
- `rd_grad_weight_*`
- `grad_bias_or_weight`

说明 bias update 和 weight outer-product update 在时间结构上不同，不能混成一个简单路径。

### 10.3 `grad_descent_ptr` 的意义

```systemverilog
if (!(ub_rd_start_in && (ub_ptr_select == 5 || ub_ptr_select == 6))) begin
    grad_descent_ptr <= grad_descent_ptr_next;
end
```

这句说明 update 写回区也有自己的写指针管理，而且要避免在刚启动更新那一拍覆盖 freshly loaded base pointer。

这正是很典型的工程细节：
项目里真正难的往往不是公式，而是边界拍次序。

---

## 11. bias update 为什么要 preload old values

这段注释非常值得记：

```systemverilog
// Bias update old values are consumed by gradient_descent one cycle later, so preload
// the next bias wavefront once the derivative stream has started.
```

这说明 bias 更新并不是“梯度一来就直接减”，而是：
- 旧 bias 值和梯度到达的时间存在相对拍次关系
- 所以需要提前 preload 下一波 old values

也就是说，bias update 本质上也是一个精细的时序对齐问题。

---

## 12. weight update 的 bug 修复痕迹为什么很重要

源码这段注释很值钱：

```systemverilog
// Weight updates need the final systolic beat as well.
// The current counter is already one cycle ahead of the accepted output wavefront,
// so "+1 <" drops the last lane1 update for W2 and W1 column 2.
```

这段说明：
- 设计不是一次就全对
- 项目里真的遇到过“最后一个 lane 更新丢失”的训练边界 bug
- 最后是靠重新审视 `time_counter` 和 wavefront 接受关系修掉的

这类注释恰恰说明你做的是工程项目，不是拼一堆 happy-path 模块。

---

## 13. 这个文件和 PPT 各页怎么对应

这个文件几乎对应了附录里半套内容：

1. `Unified Buffer 设计`
2. `wr_ptr / base / restore`
3. `UB 读流与 PE 时序对齐`
4. `UB 内梯度下降更新`

换句话说，如果你能把这个文件讲懂，这 4 页其实就是同一件事的四个角度：
- 存什么
- 怎么读
- 怎么不踩静态区
- 怎么做更新

---

## 14. 你最该记住的 10 个点

1. UB 不是普通 SRAM，而是多语义训练数据中枢。
2. `ptr_select` 决定这次读流到底在读什么语义。
3. `wr_ptr_base / restore` 保证运行时写回不踩静态参数区。
4. Host 写和 VPU 写共享一个地址空间。
5. input 流像左边界顺序波前。
6. weight 流比 input 更复杂，因为要支持顶部装载和 transpose。
7. input 的最后一拍可以 hold，weight 的最后一拍不能乱 hold。
8. bias / Y / H 都要从 UB 读，但语义完全不同。
9. gradient descent 在 UB 内完成，说明训练更新已经系统内闭环。
10. 这个文件里的时序注释，本身就是项目工程难点的最好证据。

---

## 15. 最后一句话

如果只让我用一句话概括 `unified_buffer_v3.sv`，那就是：

**它把一块存储器变成了 tiny-tpu 训练闭环里的数据中枢、时序对齐点和参数更新落点。**


---

# Part 8 Scheduler 模块精讲

# `scheduler.py` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/scheduler.py`

配套产物：
- `/home/jjt/tpu-soc/compiler/out/mlp_2_2_1_q8_8.schedule.json`
- `/home/jjt/tpu-soc/compiler/out/mlp_2_2_1_q8_8.ub_map.json`

这份文档只讲 `scheduler.py`。
重点不是把 Python 语法解释一遍，而是要让你搞清楚：
**这个 scheduler 到底在把什么软件意图，翻译成什么样的硬件阶段命令。**

---

## 1. 先给这个文件定性

这个文件不是：
- 通用 AI compiler
- cycle-accurate waveform generator
- 完整中间表示框架

它是：
**面向当前 tiny-tpu 2x2/2-lane 原型的阶段级调度器。**

这个定性非常重要，因为你一旦把它误解成“完整编译器”，很多设计取舍就会看起来像缺点；但如果你知道它的目标是“先把系统闭环跑通”，它反而会显得非常合理。

---

## 2. 文件一开始就在收边界条件

### 2.1 `_validate_current_target()` 很值得看

```python
if spec.get("model_type") != "mlp":
    raise ValueError("scheduler currently supports model_type=mlp only")
if len(layers) != 2:
    raise ValueError("scheduler currently supports exactly two linear layers")
if hw.get("array_width") != 2 or hw.get("lanes") != 2:
    raise ValueError("scheduler currently targets the 2x2 / 2-lane tiny-tpu prototype")
```

这段说明三件事：

1. 当前只支持 MLP
2. 当前只支持两层
3. 当前只支持 2x2 / 2-lane 原型

这不是偷懒，而是很明确地把项目目标钉住：
**先对当前原型做一条能跑通的编译路径。**

所以这个文件的设计哲学不是“无限泛化”，而是“围绕当前 RTL 原型，把软件-硬件链条做实”。

---

## 3. 先看 allocator，而不是先看命令

### 3.1 为什么 `_tensor_map()` 很重要

```python
def _tensor_map(allocation: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {tensor["name"]: tensor for tensor in allocation["tensors"]}
```

它的作用很简单：把 UB allocator 的输出变成按名字查 tensor 的字典。

但从系统理解上，它说明 scheduler 的第一步不是直接发命令，而是：
**先知道每个 tensor 在 UB 里放哪。**

### 3.2 `ub_map.json` 就是这一步的结果

你可以在 `mlp_2_2_1_q8_8.ub_map.json` 里直接看到：

- `X` 在 `0`
- `Y` 在 `8`
- `W1` 在 `12`
- `B1` 在 `16`
- `W2` 在 `18`
- `B2` 在 `20`
- `H1` 在 `21`
- `dZ2` 在 `29`
- `dZ1` 在 `33`

这一步的意义是：
- Host 知道初始装载怎么做
- Scheduler 知道后面 stage 命令该从哪读
- UB 内更新也知道旧参数区在哪

所以 `ub_map` 不是附属产物，而是整个 schedule 的地址基础。

---

## 4. `_ub_read()` 是整个 scheduler 的核心

### 4.1 先看函数签名

```python
def _ub_read(
    stage: str,
    name: str,
    tensor: str,
    ptr_sel: int,
    addr: int,
    row: int,
    col: int,
    transpose: bool,
    *,
    vpu_path: str | None = None,
    note: str = "",
    wait_after: bool = False,
) -> dict[str, Any]:
```

这几个参数其实已经把系统语义说完了：
- `stage`：这一拍属于哪一层大阶段
- `name`：这一条具体动作叫什么
- `tensor`：逻辑上读的是哪个 tensor
- `ptr_sel`：硬件上用哪种 UB 读语义
- `addr/row/col`：读的矩阵块位置和尺寸
- `transpose`：是否转置
- `vpu_path`：这次读流对应哪个 VPU 处理路径
- `wait_after`：这次动作后要不要等系统级完成边界

所以 `_ub_read()` 的价值在于：
**它把“软件里的一步训练动作”压缩成了“硬件能理解的一条阶段命令”。**

### 4.2 生成的命令长什么样

```python
command = {
    "stage": stage,
    "name": name,
    "kind": "ub_read",
    "tensor": tensor,
    "signals": {
        "ub_rd_start_in": 1,
        "ub_ptr_select": ptr_sel,
        "ub_rd_addr_in": addr,
        "ub_rd_row_size": row,
        "ub_rd_col_size": col,
        "ub_rd_transpose": int(transpose),
    },
    "wait_after": int(wait_after),
}
```

这里最重要的是 `signals`。
它说明 scheduler 输出不是抽象图，而是已经很贴近前端/UB 控制字段了。

你可以把它理解成：
- 软件侧先想“我现在要让硬件干什么”
- scheduler 再翻译成“具体要把哪些字段送给 Frontend/UB”

这就是软件和 RTL 的握手点。

---

## 5. `_switch()`、`_wait()`、`_nop()` 三种辅助命令说明了什么

### 5.1 `_switch()`

```python
def _switch(stage: str, name: str, note: str = "") -> dict[str, Any]:
    return {
        "stage": stage,
        "name": name,
        "kind": "control",
        "signals": {"sys_switch_in": 1},
    }
```

这说明 scheduler 知道阵列权重有 shadow/active 切换语义。
所以它不会把“load weight”和“开始算”混成同一件事。

### 5.2 `_wait()`

```python
def _wait(stage: str, name: str, event: str, note: str = "") -> dict[str, Any]:
```

它表示 scheduler 不只是发命令，还知道哪里必须形成系统同步点。
这和 Frontend 里的 `wait_after -> vpu_drain` 是一一对应的。

### 5.3 `_nop()`

```python
def _nop(stage: str, name: str) -> dict[str, Any]:
    return {"stage": stage, "name": name, "kind": "nop", "signals": {}}
```

`nop` 不是凑数，而是为了让：
- weight 装载波前走完
- shadow buffer 准备好
- 后续 `switch` 生效时，阵列状态已经稳定

这也是典型的“系统节奏感”设计，而不是单算子设计。

---

## 6. `forward_layer1`：第一层前向其实已经把整个系统思路讲透了

看这组命令：

```python
_ub_read("forward_layer1", "load_w1_shadow", "W1", 1, ... , True)
_nop(...)
_switch("forward_layer1", "activate_w1")
_ub_read("forward_layer1", "stream_x", "X", 0, ... , vpu_path="1100")
_ub_read("forward_layer1", "stream_b1", "B1", 2, ... , vpu_path="1100", wait_after=True)
_wait("forward_layer1", "wait_h1_writeback", "vpu_drain")
```

这整组动作其实已经把系统执行模式完全暴露了：

1. 先把 `W1^T` 从 UB 装到 shadow weight path
2. 用 `nop` 留出装载时间
3. `switch` 把 shadow 切成 active
4. 再把 `X` 从左边界流进 systolic
5. bias `B1` 同时流入 VPU
6. VPU 用 `1100` 路径做 bias + leaky relu
7. 最后等 `vpu_drain`，确保 `H1` 已经写回 UB

这说明 scheduler 输出的不是“数学表达式”，而是一串**带时序语义的系统动作脚本**。

---

## 7. `transition_layer2`：为什么这一步最能体现训练语义

看这组命令：

```python
_ub_read("transition_layer2", "load_w2_shadow", "W2", 1, ... , True)
_switch("transition_layer2", "activate_w2")
_ub_read("transition_layer2", "stream_h1", "H1", 0, ... , vpu_path="1111")
_ub_read("transition_layer2", "stream_b2", "B2", 2, ... , vpu_path="1111")
_ub_read("transition_layer2", "stream_y",  "Y",  3, ... , vpu_path="1111")
_ub_read("transition_layer2", "load_old_b2", "B2", 5, ... , wait_after=True)
_wait("transition_layer2", "wait_dz2_writeback", "vpu_drain")
```

这里发生的已经不只是 forward：
- H1 进入第二层
- B2 进入 bias 路径
- Y 进入 loss 路径
- old B2 进入更新路径
- VPU pathway 设成 `1111`

这表示一件事：
**训练过渡阶段把 forward、loss gradient、bias update 三件事捏在了同一个系统阶段里。**

所以 `1111` 不是一个随便挑的值，而是“第二层前向 + 损失 + 更新准备”的路径语义。

---

## 8. `backward_layer1`：为什么说明它不是推理系统

看这段：

```python
_ub_read("backward_layer1", "load_w2_backward", "W2", 1, ... , False)
_switch("backward_layer1", "activate_w2_backward")
_ub_read("backward_layer1", "load_old_b1", "B1", 5, ... , vpu_path="0001")
_ub_read("backward_layer1", "stream_dz2", "dZ2", 0, ... , vpu_path="0001")
_ub_read("backward_layer1", "stream_h1_for_derivative", "H1", 4, ... , vpu_path="0001", wait_after=True)
_wait("backward_layer1", "wait_dz1_writeback", "vpu_drain")
```

这已经很完整地体现了训练反向传播：
- 读取非转置的 `W2`
- 输入 `dZ2`
- 输入 `H1` 给导数路径
- 读取旧 `B1` 为 bias 更新做准备
- 最终写回 `dZ1`

所以从这一步开始，这个系统已经完全不是 inference accelerator，而是 training accelerator prototype。

---

## 9. `update_w1_tile_* / update_w2_tile_*`：为什么 outer product 也在系统里完成

后面的循环最值得看：

```python
for tile_index, (tile_start, tile_rows) in enumerate(_tile_ranges(batch_size, tile_width)):
```

这说明 weight update 不是整块一次做完，而是按 tile 来做。

### 9.1 W1 update 的思路

```python
"load_x_tile_to_top"
"activate_x_tile"
"load_dz1_tile_transposed"
"load_old_w1"
"wait_w1_update"
```

这意味着：
- 用 `X` tile 作为顶部输入
- 用 `dZ1^T` 作为左边输入
- systolic 做 outer product
- 同时从 UB 取旧 `W1`
- 在 UB 内 gradient_descent 更新

### 9.2 W2 update 的思路

```python
"load_h1_tile_to_top"
"activate_h1_tile"
"load_dz2_tile_transposed"
"load_old_w2"
"wait_w2_update"
```

逻辑完全类似，只是换成 `H1` 和 `dZ2`。

这两段非常重要，因为它们说明：
**这个 tiny-tpu 原型连参数更新都不是软件旁路算好再写回，而是系统内部自己跑 outer product + update。**

---

## 10. `host_load_plan` 为什么不是附属信息

看最后返回：

```python
host_load_plan = [
    {
        "tensor": tensor["name"],
        "addr": tensor["addr"],
        "shape": tensor["shape"],
        "words": tensor["words"],
    }
    for tensor in allocation["tensors"]
    if tensor["storage"] == "ub" and tensor["role"] in {"input", "label", "weight", "bias"}
]
```

它的意义是：
- 编译器不只是生成运行阶段命令
- 还明确告诉 Host，哪些 tensor 要提前装进 UB

你在 `schedule.json` 里可以直接看到：
- `X` -> `addr 0`
- `Y` -> `addr 8`
- `W1` -> `addr 12`
- `B1` -> `addr 16`
- `W2` -> `addr 18`
- `B2` -> `addr 20`

这就是 test 里 `load_all_data_axil()` 的依据。

所以 `host_load_plan` 是 software/runtime 和 hardware schedule 的接缝，不是附加信息。

---

## 11. `schedule.json` 到底代表什么

输出的 `schedule.json` 里最重要的是三部分：

1. `host_load_plan`
2. `ub_allocation`
3. `commands`

可以这样理解：

- `host_load_plan`：初始静态区怎么装
- `ub_allocation`：整个 UB 地址空间怎么分
- `commands`：运行时每个 stage 做什么

所以这个 JSON 其实就是“软件意图降成硬件动作脚本”的完整中间产物。

---

## 12. 这份 scheduler 和 PPT 哪几页最对应

它最直接对应的是：

1. `编译器与指令组织`
2. `Unified Buffer 设计`
3. `UB 读流与 PE 时序对齐`
4. `VPU 单独展开`
5. `逐拍计算动态`

原因很简单：
`scheduler.py` 决定了这些页里讲的：
- 哪些 tensor 什么时候读
- 用哪种语义读
- VPU 走哪条路径
- 哪一步后要等
- 哪一步是 load shadow，哪一步是 switch，哪一步是真正 stream compute

---

## 13. 这个文件最该记住的 10 个点

1. 它不是通用 compiler，而是当前 tiny-tpu 原型的阶段级调度器。
2. 它先做 `ub_allocation`，再做 stage 命令。
3. `_ub_read()` 是整个文件最核心的 helper。
4. `ptr_sel` 是软件到 UB 数据语义的直接映射。
5. `_switch()` 表示阵列权重 load/activate 两阶段分离。
6. `_wait()` 表示系统级阶段边界。
7. `forward_layer1` 已经能看出整套系统的执行节奏。
8. `transition_layer2` 最能体现训练路径，不只是前向。
9. update tile 阶段说明参数更新也在系统内部完成。
10. `host_load_plan` 是 Host runtime 和硬件 schedule 的接缝。

---

## 14. 最后一句话

如果只让我用一句话概括 `scheduler.py`，那就是：

**它把“训练一轮 MLP”的软件意图，翻译成了当前 tiny-tpu 原型能稳定执行的阶段级硬件动作脚本。**


---

# Part 9 Frontend AXI-Lite 带行号批注版

# `tpu_frontend_axil.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`

这份文档的目标不是再讲概念，而是直接对着源码行号读。
你可以打开源文件，然后按下面的行段往下看。

---

## [4-27] 文件头注释：这个模块到底想做什么

这一段最值钱的不是语法，而是它把模块定位一次讲清楚了：

- `step mode + IMEM + sequencer`
- AXI-Lite 寄存器图
- 32-bit 指令格式

这说明这个模块从设计之初就不是“纯寄存器壳”，而是：
1. 支持单步调试
2. 支持程序化自动运行
3. 支持把控制字拆成 UB / systolic / VPU 能理解的字段

如果你只记一句话：
**这 20 多行注释已经定义了整个前端的系统职责。**

---

## [29-85] 模块端口：整个系统的控制面都从这里出去

这一段最该看的是 output：

- `ub_wr_host_data_out_*`
- `ub_wr_host_valid_out_*`
- `ub_wr_ptr_restore_out`
- `sys_switch_out`
- `ub_rd_start_out`
- `ub_rd_transpose_out`
- `ub_rd_col_size_out`
- `ub_rd_row_size_out`
- `ub_rd_addr_out`
- `ub_ptr_sel_out`
- `vpu_data_pathway_out`
- `inv_batch_size_times_two_out`
- `vpu_leak_factor_out`
- `learning_rate_out`

这批信号几乎就是 PPT 里“控制主链”的原始来源。

理解方法：
- Host 世界通过 AXI-Lite 写寄存器
- 这个模块把寄存器语义变成系统控制口
- 下游 `tpu_soc -> tpu -> UB / systolic / VPU` 再消费这些控制口

所以这段端口定义不是形式化声明，而是整套 SoC 控制面的边界定义。

---

## [87-89] 三条 assign：最短但最关键的语义桥接

```systemverilog
assign clk_out = s_axil_aclk;
assign rst_out = ~s_axil_aresetn;
assign ub_wr_ptr_restore_out = start_pulse;
```

前两句是时钟/复位桥接。
第三句最重要：

- 每次 `CTRL.start=1`
- 前端除了启动 sequencer
- 还会同步触发 `wr_ptr_restore`

这就是为什么 `start` 在系统语义上不只是“开始跑”，而是“从静态参数区边界后重新开始一轮”。

这三句很短，但直接把 Host 控制语义和 UB 内部运行边界接起来了。

---

## [94-113] 前端内部寄存器：分成 4 组看

这段定义不要散看，最好分组理解：

1. staged instruction
- `instr_w0_reg`

2. host 写 UB staging
- `ub_data0_reg`
- `ub_data1_reg`
- `ub_push0_pulse`
- `ub_push1_pulse`

3. sequencer / status
- `step_pulse`
- `start_pulse`
- `busy_reg`

4. training params / IMEM
- `leak_factor_reg`
- `inv_batch_n2_reg`
- `learning_rate_reg`
- `imem_addr_reg`
- `imem_w0_reg`
- `imem_len_reg`

也就是说，这一段内部状态正好覆盖了：
- 指令 staging
- 数据 staging
- 程序执行状态
- 训练参数配置

这也是为什么我一直说，这个前端不是寄存器壳，而是一个小控制器。

---

## [122-139] Sequencer 状态和 `wait_after`

这几行是前端灵魂：

```systemverilog
typedef enum logic [1:0] {
    SEQ_IDLE     = 2'b00,
    SEQ_DISPATCH = 2'b01,
    SEQ_WAIT     = 2'b10,
    SEQ_ADVANCE  = 2'b11
} seq_state_t;
...
assign seq_needs_wait = seq_instr[23];
```

关键点有两个：

1. sequencer 把“系统同步边界”单独抽成 `WAIT` 状态。
2. 编译器的 `wait_after` 最终直接落成 `seq_instr[23]`。

所以这里是 software schedule 和 hardware sequencer 真正对接的地方。

---

## [141-180] sequencer 前半段：`IDLE` 和 `DISPATCH`

这一段决定了 step 和 auto-run 的分岔。

### [160-173] `SEQ_IDLE`

```systemverilog
if (step_pulse) begin
    ...
end else if (start_pulse) begin
    pc          <= '0;
    seq_instr   <= imem[0];
    seq_running <= 1'b1;
    ...
end
```

这说明：
- `step` 只打一条 staging 指令
- `start` 才进入程序模式，从 `imem[0]` 开始

### [176-180] `SEQ_DISPATCH`

```systemverilog
seq_instr_pulse <= 1'b1;
if (seq_needs_wait)
    seq_state <= SEQ_WAIT;
else
    seq_state <= SEQ_ADVANCE;
```

这里最重要的认知是：
**dispatch 只负责把控制打一拍送给 `control_unit`，不代表这一阶段真的执行完。**

---

## [181-204] sequencer 后半段：`WAIT` 和 `ADVANCE`

这段一定要和上一段一起看。

### [184-191] `SEQ_WAIT`

```systemverilog
if (vpu_drain) begin
    if (seq_running)
        seq_state <= SEQ_ADVANCE;
    else begin
        busy_reg  <= 1'b0;
        seq_state <= SEQ_IDLE;
    end
end
```

这一段说明阶段完成边界不是 dispatch，不是 UB 发数开始，也不是 systolic 有输出，而是：
**VPU 的最后一个有效输出已经 drain 掉。**

### [195-204] `SEQ_ADVANCE`

```systemverilog
if (pc + 1 < {{($clog2(IMEM_DEPTH)-6){1'b0}}, imem_len_reg}) begin
    pc        <= pc + 1;
    seq_instr <= imem[pc + 1];
    seq_state <= SEQ_DISPATCH;
end else begin
    seq_running <= 1'b0;
    busy_reg    <= 1'b0;
    seq_state   <= SEQ_IDLE;
end
```

这说明前端的程序边界不是硬编码条数，而是看 `IMEM_LEN`。

软件侧为什么能轮询 `STATUS.busy` 判定完成，就是因为这里会在结束时清 `busy_reg`。

---

## [152-157] `vpu_drain` 边沿检测：系统级 wait 的证据源

虽然位置在 sequencer always_ff 内部，但这几行值得单独讲：

```systemverilog
vpu_valid_prev <= tpu_vpu_valid_in;
vpu_drain      <= vpu_valid_prev && !tpu_vpu_valid_in;
...
if (seq_instr_pulse && seq_instr[2:0] == 3'b010)
    vpu_pathway_reg <= seq_instr[22:19];
```

前两句构造 `vpu_drain`，后两句 latch `vpu_pathway`。

它们分别代表：
- “这一阶段什么时候真正结束”
- “这一阶段 VPU 应该按什么训练路径工作”

所以这 6 行虽然小，但直接决定系统节奏和训练语义。

---

## [215-249] 寄存器写 decode：Host 到系统语义的第一跳

这段是软件控制面的核心落点。

### [230-233] `CTRL`

```systemverilog
12'h000: begin
    if (wd_lat[0]) step_pulse  <= 1'b1;
    if (wd_lat[1]) start_pulse <= 1'b1;
end
```

软件写 `0x000`：
- bit0 触发单步
- bit1 触发自动运行

### [234-240] `INSTR_W0 / UB_DATA / UB_PUSH / lane1 data`

这几项对应：
- step 模式暂存指令
- lane0/lane1 的 host 数据 staging
- 再用 `UB_PUSH` 脉冲把它们真正送出去

### [241-244] `IMEM_ADDR / IMEM_W0 / IMEM_WE / IMEM_LEN`

这一组负责把程序写进 IMEM。
其中：
- `0x030` 设地址
- `0x034` 写 staging instruction
- `0x040` commit 进 `imem[imem_addr_reg]`
- `0x044` 设置程序长度

### [145-147] 训练参数

- `0x050` -> `leak_factor_reg`
- `0x054` -> `inv_batch_n2_reg`
- `0x058` -> `learning_rate_reg`

这说明前端不只是调度器，还负责把训练路径参数送进系统。

---

## [157-186] AXI-Lite 读通道：软件侧可观测性从哪里来

这段最重要的不是读协议本身，而是：

```systemverilog
12'h004: s_axil_rdata <= {30'h0, seq_running, busy_reg};
```

这表示：
- bit0 = `busy`
- bit1 = `running`

测试里轮询 `STATUS`，本质上就是在读这里。

所以如果你要回答“软件怎么知道一轮跑完了”，答案不是“估时钟周期”，而是“直接轮询前端导出的 `STATUS`”。

---

## [191-215] `control_unit` 接入：sequencer 和字段 decode 的接缝

```systemverilog
logic [31:0] instr_to_cu;
assign instr_to_cu = seq_instr_pulse ? seq_instr : '0;

control_unit cu_inst (
    .instruction                 (instr_to_cu),
    .sys_switch_in               (sys_switch_out),
    .ub_rd_start_in              (ub_rd_start_out),
    ...
);
```

这里说明前端内部又分两层：

1. sequencer 决定什么时候发一条指令
2. `control_unit` 决定这条指令拆成哪些硬件字段

所以 Frontend 不是手写 decode 的一团逻辑，而是：
- sequencing
- register file
- AXI-Lite
- decode glue
的组合。

---

## [218-228] UB host write mux：为什么要统一仲裁两条写路径

这一段非常工程化：

```systemverilog
assign ub_wr_host_valid_out_0 = ub_push0_pulse ? 1'b1        : cu_ub_valid_0;
assign ub_wr_host_valid_out_1 = ub_push1_pulse ? 1'b1        : cu_ub_valid_1;
assign ub_wr_host_data_out_0  = ub_push0_pulse ? ub_data0_reg : cu_ub_data_0;
assign ub_wr_host_data_out_1  = ub_push1_pulse ? ub_data1_reg : cu_ub_data_1;
```

它解决的问题是：
- Host 可以通过寄存器直接装 UB
- 指令本身也可能有 `UB_WR_HOST` 语义
- 但最终对 UB 来说就只有一条 host-write 入口

所以这里必须做 mux / arbitration。
而且 AXI `UB_PUSH` 优先，说明系统优先相信 Host 的显式装载动作。

---

## 一页总结

如果你只想记这份文件的核心线索，就记这 6 句：

1. 行 `4-27` 定义了它是 `step + IMEM + sequencer` 前端。
2. 行 `66-84` 定义了整个系统的主要控制输出口。
3. 行 `87-89` 说明 `start` 会同步触发 `wr_ptr_restore`。
4. 行 `122-204` 定义了 `wait_after -> vpu_drain` 的系统级执行边界。
5. 行 `128-147` 定义了 Host 如何写 `CTRL / UB / IMEM / training params`。
6. 行 `225-228` 定义了 Host `UB_PUSH` 和指令 `UB_WR_HOST` 的统一仲裁。

最后一句话：
**这个文件最重要的价值，不是“支持 AXI-Lite”，而是把软件的寄存器写操作变成了一条按阶段稳定推进的系统执行节奏。**


---

# Part 10 Unified Buffer 带行号批注版

# `unified_buffer_v3.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`

这份文档是给你对着源码逐段看的。
重点不是再讲“UB 很重要”，而是直接标出：哪几段在解决什么问题，为什么是整个训练闭环的关键。

---

## [19-37] 顶部接口：它一开始就不是普通 RAM

这一段端口已经说明它和普通 SRAM wrapper 不同：

- `ub_wr_data_in / ub_wr_valid_in`：运行时写回入口
- `ub_wr_host_data_in / ub_wr_host_valid_in`：Host 装载入口
- `ub_wr_ptr_restore_in`：运行边界恢复控制
- `ub_rd_start_in / ub_ptr_select / ub_rd_addr_in / row / col / transpose`：阶段级读流入口
- `learning_rate_in`：训练更新参数入口

如果一个 buffer 模块既有 Host 写、执行路径写、阶段级读流、训练更新参数，那它就已经不是“内存块”，而是“数据中枢”。

---

## [68-72] `ub_memory` 和 debug 区：真正的数据都在这里流转

```systemverilog
logic [15:0] ub_memory [0:UNIFIED_BUFFER_WIDTH-1];
```

后面所有：
- host 装载
- 中间结果写回
- old params 读取
- update 写回
最后都围着这块 `ub_memory` 转。

所以从系统角度看，`ub_memory` 就是这套 tiny-tpu 训练原型的公共数据场。

---

## [94-158] 内部状态：为什么这文件看起来像住了半个控制器

这段变量最多，但也是最能说明问题的一段。

### [94-96] 写指针

- `wr_ptr`
- `wr_ptr_next`
- `wr_ptr_base`

这一组是 host/static 区和运行时写回区边界管理的基础。

### [99-148] 各类读机

- `rd_input_*`
- `rd_weight_*`
- `rd_bias_*`
- `rd_Y_*`
- `rd_H_*`
- `rd_grad_bias_*`
- `rd_grad_weight_*`

这说明 UB 内部不是“一个读口多用”，而是维护了多组带时间计数的逻辑视图。

### [150-161] gradient descent 状态

- `value_old_in`
- `grad_descent_valid_in`
- `value_updated_out`
- `grad_descent_done_out`
- `grad_descent_ptr`
- `grad_bias_or_weight`

这一组直接说明更新逻辑就在 UB 内部。

如果你只想抓一句：
**这段状态定义说明 UB 已经不是被动存储，而是多语义训练数据流的内部控制点。**

---

## [177-190] `gradient_descent` 实例：更新路径系统内闭环的铁证

```systemverilog
gradient_descent gradient_descent_inst (
    .lr_in(learning_rate_in),
    .grad_in(ub_wr_data_in[i]),
    .value_old_in(value_old_in[i]),
    .grad_descent_valid_in(grad_descent_valid_in[i]),
    .grad_bias_or_weight(grad_bias_or_weight),
    .value_updated_out(value_updated_out[i]),
    .grad_descent_done_out(grad_descent_done_out[i])
);
```

这段意味着：
- 梯度直接从运行时写回流 `ub_wr_data_in` 来
- 旧值从 UB memory 里读
- 学习率也是前端传下来的系统参数
- 更新值不出模块，直接又写回 UB

所以这套设计不是“软件算梯度，硬件只做 forward”，而是：
**参数更新也在 RTL 系统内部完成。**

---

## [214-236] `grad_descent_valid_in`：这里藏着一个关键 bug 修复点

```systemverilog
if ((rd_grad_bias_row_size != 0 || rd_grad_bias_col_size != 0) &&
    (rd_grad_bias_time_counter + 1 < rd_grad_bias_row_size + rd_grad_bias_col_size)) begin
    ...
end else if (rd_grad_weight_time_counter < rd_grad_weight_row_size + rd_grad_weight_col_size) begin
    // Weight updates need the final systolic beat as well.
    // ... "+1 <" drops the last lane1 update for W2 and W1 column 2.
```

这一段说明：
- bias update 和 weight update 的 valid 条件并不一样
- 尤其 weight update，最后一个 systolic beat 也必须接住
- 这里曾经真实出现过“最后一个 lane 更新丢失”的 bug

所以这段不是小优化，而是训练路径是否完整的关键。

---

## [221-300] 指针组合逻辑：UB 真正的“内部交通规则”

### [221-230] 写地址生成

```systemverilog
wr_ptr_next = wr_ptr;
for (...) begin
    wr_lane_addr[j] = wr_ptr_next;
    if (ub_wr_valid_in[j] || ub_wr_host_valid_in[j])
        wr_ptr_next = wr_ptr_next + 1;
end
```

它说明写地址不是简单每拍加一，而是：
- 按 lane 是否真的 valid 决定
- host 写和运行时写共用一套地址前进逻辑

### [232-303] input / weight / Y / H / grad weight 的 per-lane 地址生成

这几段最重要的认知不是公式，而是：
- input 更像左边界顺序流
- weight 更像顶部装载，且要考虑 transpose
- Y/H 也是各自独立的读流
- old weight update 读流又是一条单独的路径

这说明 UB 不是“地址 + 数据”，而是“多种矩阵流的 lane 级地址调度器”。

---

## [316-323] bias preload 相位：一个很工程化的时序补偿

```systemverilog
rd_grad_bias_value_phase = rd_grad_bias_time_counter;
if (rd_grad_bias_started || ub_wr_valid_in[0] || ub_wr_valid_in[1]) begin
    rd_grad_bias_value_phase = rd_grad_bias_time_counter + 1;
end
```

这段对应源码里的注释：bias old values 要比梯度消费时机早一拍准备。

这说明 bias 更新并不是数学上“grad 来了减一下”这么简单，而是：
- 旧 bias 值
- 梯度到达
- update 单元消费
三者之间存在拍次错位

这段就是为了解这个时序错位。

---

## [326-340] `grad_descent_ptr_next`：bias 和 weight 两种更新写法不同

```systemverilog
if (grad_bias_or_weight) begin
    ... grad_descent_ptr_next = grad_descent_ptr_next + 1;
end else begin
    gd_wr_lane_addr[j] = grad_descent_ptr + j;
end
```

这里的关键是：
- bias update 和 weight update 在写回地址推进方式上不同
- weight 类更新按完成 beat 前进
- bias 类更新更像固定 lane 对应固定位置

所以这里再次体现：bias update 和 weight outer-product update 不是一回事，不能用一个统一时序强行糊过去。

---

## [344-420] reset / 初始化：为什么这文件状态这么重

这一长段 reset 说明了一个事实：

- UB 内部维护了大量“当前阶段读流状态”
- 一次 reset 不只是清 memory
- 还要清：input/weight/bias/Y/H/update 各类指针和时间计数

也就是说，这个模块在行为上已经非常接近一个“小数据引擎”。

---

## [420-482] `ub_rd_start_in` 的 case：软件 `ptr_select` 在这里落地

这是整个文件最该精读的一段。

```systemverilog
if (ub_rd_start_in) begin
    case (ub_ptr_select)
        0: begin ... end
        1: begin ... end
        2: begin ... end
        3: begin ... end
        4: begin ... end
        5: begin ... end
        6: begin ... end
    endcase
end
```

对应关系是：
- `0` input
- `1` weight
- `2` bias
- `3` Y
- `4` H
- `5` old bias for update
- `6` old weight for update

所以 `scheduler.py` 里 `_ub_read(... ptr_sel=...)` 的语义，最终就在这里变成具体启动哪一种内部读流。

这是 software schedule 和 RTL 数据流真正接起来的地方。

---

## [485-500] host 写 / VPU 写 / `wr_ptr_base` / `restore`

这一段是 PPT 那页 `wr_ptr / base / restore` 的源码本体。

```systemverilog
if (ub_wr_valid_in[j])
    ub_memory[wr_lane_addr[j]] <= ub_wr_data_in[j];
else if (ub_wr_host_valid_in[j])
    ub_memory[wr_lane_addr[j]] <= ub_wr_host_data_in[j];
...
if (ub_wr_host_valid_in[0] || ub_wr_host_valid_in[1])
    wr_ptr_base <= wr_ptr_next;
if (ub_wr_ptr_restore_in)
    wr_ptr <= wr_ptr_base;
else
    wr_ptr <= wr_ptr_next;
```

这段做了三件事：
1. 统一处理 host 写和执行路径写
2. 记录静态装载区边界 `wr_ptr_base`
3. 每轮 `start` 时恢复写指针

如果没有这段，训练过程中的写回很容易踩坏最初装进去的参数和数据区。

---

## [503-512] update 写回到 UB：参数更新真正落地的位置

```systemverilog
if (grad_descent_done_out[j]) begin
    ub_memory[gd_wr_lane_addr[j]] <= value_updated_out[j];
end
```

这几行就是“参数更新最后真的写回到哪里”的答案：
直接写回 `ub_memory`。

所以当你说“这项目是训练闭环”时，不是抽象意义，而是源码里真有这一拍。

---

## [515-542] input 读流：为什么最后一拍会 hold

```systemverilog
if (rd_input_time_counter + 1 < rd_input_row_size + rd_input_col_size) begin
    ...
end else if (rd_input_time_counter + 1 == rd_input_row_size + rd_input_col_size) begin
    // Hold cycle
```

这一段说明 input 流的最后一拍会保留一下，给后级稳定采样。

所以“UB 到 PE 时序对齐”不是 PPT 里的说法，而是这里非常具体的 `hold cycle` 逻辑。

---

## [545-583] weight 读流：为什么最后一拍不能像 input 那样 hold

源码里直接说了：

```systemverilog
// Do not hold weight valids high for an extra cycle.
// ... preserving the final pulse overwrites PE22 with the last lane1 weight.
```

这段特别值钱，因为它说明：
- input 和 weight 都是数据流
- 但它们对“最后一拍”的时序需求不同
- weight 如果 hold，阵列会把最后一个权重重复采样，造成错误覆盖

这正是系统工程和算法描述最大的区别：
算法看起来都只是“送矩阵”，真正实现时每条流的尾拍语义都可能不同。

---

## [622-742] bias / Y / H / gradient 读流：VPU 三条子路径都依赖 UB

这段是 VPU 相关读流主体：

- [622-641] bias
- [644-664] Y
- [667-687] H
- [690-742] gradient descent old-value feed

这一段说明：
- VPU 不是黑盒后处理
- 它依赖 UB 给它提供 bias、Y、H、old params 多种流
- UB 因此不仅服务阵列，也同时服务训练路径单元 VPU

这就是为什么我一直强调 UB 是系统级中枢，而不是“阵列前面的内存”。

---

## 一页总结

如果你只想记这份文件最关键的 8 个落点，就记：

1. 行 `19-37`：它从接口上就已经不是普通 RAM。
2. 行 `94-158`：它内部维护了多类读机和更新状态。
3. 行 `177-190`：gradient descent 直接实例化在 UB 内。
4. 行 `214-236`：这里藏着更新路径最后一拍 bug 修复逻辑。
5. 行 `221-340`：这是所有 lane 地址和 pointer 交通规则。
6. 行 `420-482`：`ptr_select` 在这里真正落成不同语义读流。
7. 行 `485-500`：`wr_ptr_base / restore` 保住静态参数区边界。
8. 行 `545-583`：weight 流尾拍不能乱 hold，这是时序对齐的关键证据。

最后一句话：
**这个文件最难的地方不是“读写 memory”，而是把多种训练语义的数据流、更新流和边界时序，全部在同一块 UB 里对齐。**


---

# Part 11 训练收敛测试带行号批注版

# `test_tpu_soc_axil_train_convergence.py` 带行号源码批注版

源码文件：
- `/home/jjt/tpu-soc/test/test_tpu_soc_axil_train_convergence.py`

这份文档按源码行号解释测试文件。
目标是让你搞清楚：这份 test 为什么不是普通 smoke test，而是整个项目“训练闭环成立”的最终证据文件。

---

## [1-5] 文件头注释：测试目标已经写死了

开头写得很明确：

- DUT 是 `tpu_soc_top`
- 单次加载数据和 IMEM
- 重复 `start`
- 检查 XOR loss 下降
- 最终达到 `4/4` 正确分类

也就是说，这个测试从一开始就不是“打一拍看看波形”，而是系统级训练收敛验证。

---

## [12-15] 全局参数：验证标准不是模糊的

```python
FRAC_BITS = 8
TRAIN_EPOCHS = 12
LOSS_TARGET = 0.21
DEBUG_MON = False
```

这几行给出了验证的基础边界：
- 数据格式是 Q8.8
- 训练轮数是 12
- loss 目标有明确门槛

所以这份 test 不是随缘看趋势，而是有明确数值验收标准。

---

## [18-33] 固定点工具函数：软件参考模型和 RTL 语义对齐的基础

```python
def to_fxp(v): ...
def from_fxp(v): ...
def fxp(v): ...
def fxpa(a): ...
```

这一段的意义是：
- 所有参考模型计算都不直接用浮点裸值
- 而是尽量按 Q8.8 语义量化回来

这样做的价值在于：
**验证不是拿一个全浮点理想模型去硬比 RTL，而是尽量对齐硬件数值格式。**

---

## [36-47] 数据集、初始化参数、训练超参数：验证场景完全固定

这一段把：
- XOR 数据集 `X / Y`
- 初始参数 `INIT_W1 / INIT_B1 / INIT_W2 / INIT_B2`
- `LEAK`
- `INV_N2`
- `LR`
都固定下来了。

这里最重要的不是具体数值，而是它说明：
- 当前项目验证的是“固定已知可收敛的 Q8.8 初始化”
- 目标不是泛化 benchmark，而是证明这套系统训练链条本身成立

所以测试设计思路很工程化：
**先固定一个稳定可收敛点，验证整条链正确。**

---

## [50-119] 软件参考模型：这份 test 不只是驱动 DUT，还内建了对照模型

### [50-70] 前向和反向参考

```python
def leaky_relu(x): ...
def leaky_relu_d(g, h): ...
def forward_model(w1, b1, w2, b2): ...
def backward_model(h1, h2, w2): ...
```

这几段作用是：
- 用软件把 forward / backward 在 Q8.8 语义下跑一遍
- 给后续 loss、梯度、参数更新提供参考

### [77-109] 参数更新参考

```python
def apply_update_scalar(param, grad, lr=LR): ...
def update_model(w1, b1, w2, b2, h1, dz2, dz1): ...
```

这一段特别重要，因为它说明 test 不只是在看分类结果，还在用参考更新规则预测硬件参数的变化方向。

### [112-119] loss 和 prediction

```python
def mse_loss(h2): ...
def pred_bits(h2): ...
```

这意味着 test 关心两层证据：
- 连续 loss 下降
- 最终分类正确

所以这份 test 同时覆盖了“优化过程”和“最终结果”。

---

## [122-150] `axil_write / axil_read`：Host 控制链的最底层原语

```python
async def axil_write(dut, addr, data): ...
async def axil_read(dut, addr): ...
```

这两段是软件控制 DUT 的基础原语。

它们直接证明：
- 测试不是通过 testbench 私有信号偷偷改内部状态
- 而是老老实实通过 AXI-Lite 从系统正式入口写控制和读状态

所以当你说“这项目是主机可控 SoC”时，这两段就是最基础的证据。

---

## [153-160] `ub_write_cycle`：Host 如何往 UB 推一拍双 lane 数据

```python
async def ub_write_cycle(dut, d0, d1, push_mask):
    if push_mask & 1:
        await axil_write(dut, 0x020, d0 & 0xFFFF)
    if push_mask & 2:
        await axil_write(dut, 0x028, d1 & 0xFFFF)
    if push_mask:
        await axil_write(dut, 0x024, push_mask)
```

这段和 Frontend 寄存器图是完全对上的：
- `0x020`：lane0 data
- `0x028`：lane1 data
- `0x024`：UB_PUSH

也就是说，test 不只是“知道 UB 在哪”，还严格按 Frontend 暴露出来的 host-write 协议往里装数据。

---

## [162-180] `load_all_data_axil`：初始 Host 装载计划的实际落地

这一段非常重要：

```python
seq = [
    (to_fxp(x[0][0]), 0, 1),
    (to_fxp(x[1][0]), to_fxp(x[0][1]), 3),
    ...
    (to_fxp(b2[0]), to_fxp(w2[1]), 3),
]
```

它说明：
- Host 装载不是随便写一堆地址
- 而是按当前 UB 布局和双 lane push 方式，把 `X / Y / W1 / B1 / W2 / B2` 组织成具体写序列

这正是 `host_load_plan + ub_map` 在 test 侧的体现。

如果你被问“你怎么证明 Host 和 UB 布局是对上的”，就看这段。

---

## [182-190] `imem_load`：编译产物怎么真正装进系统

```python
async def imem_load(dut, hex_path):
    ...
    for i, instr in enumerate(instrs):
        await axil_write(dut, 0x030, i)
        await axil_write(dut, 0x034, instr)
        await axil_write(dut, 0x040, 1)
    await axil_write(dut, 0x044, len(instrs))
```

这一段和 Frontend 寄存器图一一对应：
- `0x030` -> `IMEM_ADDR`
- `0x034` -> `IMEM_W0`
- `0x040` -> `IMEM_WE`
- `0x044` -> `IMEM_LEN`

所以“编译器 -> imem.hex -> Frontend -> sequencer”这条链，在测试里是真正走通的。

---

## [193-202] `run_one_epoch`：一轮训练的正式软件入口

```python
await axil_write(dut, 0x000, 0x2)
...
status = await axil_read(dut, 0x004)
if not (status & 0x1):
    return
```

这几行是整个系统控制闭环的浓缩：
- 写 `0x000 = 0x2` 等于 `CTRL.start=1`
- 然后轮询 `STATUS.busy`
- busy 清掉，就说明 sequencer 这一轮完成

这说明测试不是靠固定 delay 猜 DUT 什么时候跑完，而是按系统正式状态位判断完成边界。

这非常关键，因为它体现了真正的 SoC 式控制，而不是 testbench 硬等拍数。

---

## [205-215] `read_hw_params`：为什么证据链不只看输出分类

```python
def read_hw_params(dut):
    ub = dut.dut.tpu_inst.ub_inst.ub_memory
    w1_words = [int(ub[12 + i].value) & 0xFFFF for i in range(4)]
    ...
```

这一段说明 test 还能直接读回 UB 中的参数区：
- `W1` 从 `12` 开始
- `B1` 从 `16` 开始
- `W2` 从 `18` 开始
- `B2` 在 `20`

这和 `ub_map.json` 完全对得上。

所以 test 的证据链是分层的：
1. AXI-Lite 控制链通
2. 程序真正执行完
3. 内部参数区真的发生更新
4. loss 下降
5. 最终 XOR 分类正确

这比只看最终分类要强得多。

---

## [218-232] 测试启动：复位和总线初始化做得很标准

这一段先：
- 启时钟
- 拉低 reset
- 清 AXI 控制信号
- 再释放 reset

这意味着测试不是从一个脏状态开始跑，而是把 SoC 顶层当成正规硬件来初始化。

这一点虽然不花哨，但很重要：
系统级验证的第一步永远是先把边界条件做干净。

---

## [234-243] 训练参数和 IMEM 装载：软件真的在走完整系统入口

```python
await axil_write(dut, 0x050, to_fxp(LEAK))
await axil_write(dut, 0x054, to_fxp(INV_N2))
await axil_write(dut, 0x058, to_fxp(LR))
...
await load_all_data_axil(...)
...
n = await imem_load(...)
```

这一段说明测试真正做了三类装载：
1. 训练超参数
2. UB 静态数据
3. IMEM 程序

这就意味着 DUT 运行前的软件准备已经完整闭环，而不是只打一条 start。

---

## [245-253] 初始参考 loss：为什么 test 能证明“下降”

```python
_, init_h2 = forward_model(ref_w1, ref_b1, ref_w2, ref_b2)
init_loss = mse_loss(init_h2)
init_pred = pred_bits(init_h2)
```

这几行计算的是硬件运行前的软件参考初始状态。

它的作用是给后面“loss 下降”提供基线。
没有基线，你只能说“最后结果还行”；有了基线，你才能说“训练过程确实在优化”。

---

## [258-260 以及后续主体] 主测试循环：真正验证的是连续多 epoch 收敛

虽然这里你当前看到的摘录只到 `monitor_lrd` 开头，但前面已经足够说明测试结构：

- 初始化系统
- 装载 UB
- 装载 IMEM
- 建软件参考初值
- 多轮 `run_one_epoch`
- 观察 loss history 和 prediction history
- 最后要求 XOR 正确分类

也就是说，这个 test 的核心不是“一轮跑没跑完”，而是“重复 start 后整个训练闭环能否持续收敛”。

这正是项目最有说服力的地方。

---

## 一页总结

如果你只想记这份 test 最关键的 8 个落点，就记：

1. 行 `1-5`：它从目标上就是多 epoch 收敛验证，不是 smoke test。
2. 行 `18-33`：固定点工具保证参考模型和硬件语义尽量对齐。
3. 行 `36-47`：数据集、初始化和超参数都是固定的可验证场景。
4. 行 `122-150`：AXI-Lite 是正式系统入口，不是测试私线。
5. 行 `162-180`：Host 按 UB 布局真正把 `X/Y/W1/B1/W2/B2` 装进去。
6. 行 `182-190`：`imem.hex` 真正通过前端寄存器装进系统。
7. 行 `193-202`：一轮训练用 `CTRL.start` 启动，用 `STATUS.busy` 收边界。
8. 行 `205-215`：test 不只看输出，还直接读回 UB 参数区验证更新。

最后一句话：
**这份 test 的价值，不是证明某个模块会动，而是证明“编译产物装载 -> 前端调度 -> 核心执行 -> 参数更新 -> loss 下降 -> XOR 收敛”这整条链真的成立。**


---

# Part 12 TPU SoC 顶层带行号批注版

# `tpu_soc.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_soc.sv`

这份文档按源码行号解释 `tpu_soc.sv`。
它的重点不是算法，而是：
**这个顶层为什么说明项目已经从“裸核原型”变成了“主机可控 SoC 原型”。**

---

## [4-11] 文件头注释：顶层定位直接写明了

这里最关键的两句是：
- `Wraps tpu_frontend_axil + tpu`
- `CPU controls TPU via AXI-Lite`

这说明这个文件从设计目的上就不是“再包装一下”，而是要把：
- Host
- Frontend
- TPU core
真正接成一个 AXI-Lite 可控加速器。

所以如果你要一句话概括 `tpu_soc.sv`：
**它是系统桥接层，不是算法层。**

---

## [13-52] 顶层端口：SoC 的外部边界在这里定义

这一段主要有两类接口：

1. AXI-Lite slave
- `aw* / w* / b* / ar* / r*`

2. 对外可观测输出
- `vpu_data_out_*`
- `vpu_valid_out_*`
- `sys_data_out_21/22`
- `sys_valid_out_21/22`

这说明：
- Host 是通过标准 AXI-Lite 入口控制系统
- 同时系统还把关键执行结果暴露出来，便于观察和验证

也就是说，这个顶层不是封死的黑盒，而是：
**可控、可观测的系统外壳。**

---

## [54-84] 前端和 core 之间的内部桥接信号

这一段最值得注意的是这两组：

### host write 相关
- `ub_wr_host_data_0/1`
- `ub_wr_host_valid_0/1`
- `ub_wr_ptr_restore`

### 控制语义相关
- `sys_switch`
- `ub_rd_start`
- `ub_rd_transpose`
- `ub_rd_col_size`
- `ub_rd_row_size`
- `ub_rd_addr`
- `ub_ptr_sel`
- `vpu_data_pathway`
- `inv_batch_size_times_two`
- `vpu_leak_factor`
- `learning_rate`

这些信号本质上就是：
**Frontend 生成的系统控制语义，在顶层中转后送给 TPU core。**

所以 `tpu_soc` 的价值不是“做逻辑运算”，而是“做语义桥接”。

---

## [60-66] host write lane 桥接：为什么标量要转成数组

```systemverilog
logic [15:0] ub_wr_host_data [0:SYSTOLIC_ARRAY_WIDTH-1];
logic        ub_wr_host_valid [0:SYSTOLIC_ARRAY_WIDTH-1];
assign ub_wr_host_data[0]  = ub_wr_host_data_0;
assign ub_wr_host_data[1]  = ub_wr_host_data_1;
assign ub_wr_host_valid[0] = ub_wr_host_valid_0;
assign ub_wr_host_valid[1] = ub_wr_host_valid_1;
```

这里的意义很实际：
- Frontend 暴露的是 lane0/lane1 标量端口
- `tpu.sv` 侧接口是 unpacked array
- 顶层在这里做格式适配

这说明 `tpu_soc` 还承担了接口整形的角色。

换句话说，它不是“直连”，而是“带接口适配的桥接”。

---

## [86-139] Frontend 实例：系统控制链从这里开始

```systemverilog
tpu_frontend_axil #( ... ) frontend ( ... );
```

这一段最关键的不是实例化本身，而是它把：
- AXI-Lite 全部总线口
- `tpu_vpu_valid_in`
- host write 输出
- sequencer/control 输出

全都接起来了。

### [117] `tpu_vpu_valid_in`

```systemverilog
.tpu_vpu_valid_in (vpu_valid_out_1 | vpu_valid_out_2),
```

这句很重要，因为它说明：
- 前端判断阶段结束要看 VPU valid drain
- 而这个证据来自 core 输出
- 所以顶层要把 core 的 valid OR 回送给 Frontend

这就是完整闭环的一部分：
**前端发命令，core 执行，core 再把“执行结束证据”反馈给前端。**

### [122-138] 前端输出

这里接出的就是：
- host 写 UB
- `wr_ptr_restore`
- `sys_switch`
- UB 读流控制字段
- VPU 路径字段
- 训练超参数

这些信号正是后续 `tpu_inst` 真正要消费的控制语义。

---

## [141-188] TPU core 实例：系统执行链从这里开始

```systemverilog
tpu #( ... ) tpu_inst ( ... );
```

这里最该关注的是：
- 前端出来的所有控制字段都在这里被送进 `tpu_inst`
- `tpu_inst` 再往 UB / systolic / VPU 分发

这段连接体现的是：
**`tpu_soc` 是把前端控制链和执行核心链真正焊起来的那一层。**

### [152-154] host write / restore

```systemverilog
.ub_wr_host_data_in         (ub_wr_host_data),
.ub_wr_host_valid_in        (ub_wr_host_valid),
.ub_wr_ptr_restore_in       (ub_wr_ptr_restore),
```

这表明 Host 初始装载路径和 `start -> restore` 路径，最终都落到 UB。

### [156-161] 窄信号到宽接口的零扩展

```systemverilog
.ub_ptr_select              ({6'h0, ub_ptr_sel}),
.ub_rd_addr_in              ({10'h0, ub_rd_addr}),
.ub_rd_row_size             ({12'h0, ub_rd_row_size}),
.ub_rd_col_size             ({14'h0, ub_rd_col_size}),
```

这一段很有代表性。
说明：
- Frontend 输出的是当前项目足够用的窄控制字段
- TPU core/UB 接口保留了更宽的表达能力
- 顶层负责做桥接适配

所以 `tpu_soc` 还是“接口宽度/语义兼容层”。

### [163-168] 训练超参数和路径语义

```systemverilog
.learning_rate_in           (learning_rate),
.vpu_data_pathway           (vpu_data_pathway),
.sys_switch_in              (sys_switch),
.vpu_leak_factor_in         (vpu_leak_factor),
.inv_batch_size_times_two_in(inv_batch_size_times_two),
```

这说明前端不是只给地址和 start，而是把：
- 学习率
- VPU pathway
- switch
- leak
- inv batch
这些训练语义一起送进 core。

所以它已经不是“命令触发器”，而是一套完整训练控制面。

---

## [170-187] 对外观测端口：为什么说这个 SoC 顶层是可观测的

这里把：
- VPU data/valid
- systolic 输出 data/valid
- UB 读 input/weight 输出
都接出来了。

这意味着：
- 顶层不是纯黑盒
- 验证和波形观察有足够抓手
- 所以你才能做 PPT 里的波形证据页和时序分析页

这也是系统工程很重要的一点：
**不是只要能跑，还要能观测和定位。**

---

## 一页总结

如果你只想记 `tpu_soc.sv` 的 6 个点，就记：

1. 行 `4-11`：它从设计目标上就是 `frontend + tpu` 的 SoC 包装层。
2. 行 `13-52`：定义了 Host AXI-Lite 和对外可观测输出这两个系统边界。
3. 行 `54-84`：定义了前端和 core 之间最关键的控制语义桥接信号。
4. 行 `60-66`：做了 host write lane 的接口适配。
5. 行 `86-139`：把 Frontend 接进系统，并用 `vpu_valid_out` 反馈阶段完成证据。
6. 行 `141-188`：把前端的控制语义真正送进 TPU core，并做必要的宽度适配。

最后一句话：
**`tpu_soc.sv` 的价值，不是实现算法，而是让 Host、Frontend、TPU core 第一次形成一个可控、可观测、可验证的完整系统顶层。**


---

# Part 13 TPU Core 带行号批注版

# `tpu.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu.sv`

这份文档按源码行号解释 `tpu.sv`。
它的重点不是复杂控制，而是让你看清楚：
**这一个文件如何把 UB、systolic、VPU 组合成真正的执行核心闭环。**

---

## [4-53] 顶层接口：这就是执行核心对外的系统边界

这一段端口很能说明 `tpu.sv` 的定位。

输入分成四类：
1. Host -> UB 写入
2. UB 读流控制字段
3. 训练参数
4. VPU pathway / switch

输出分成三类：
1. VPU 写回结果
2. systolic 输出
3. UB 读出的 input/weight 流

所以这个文件本质上不是控制器，而是：
**执行核心的数据通路组合层。**

---

## [55-74] VPU 写回先回 UB：训练闭环最核心的一跳

```systemverilog
logic [15:0] ub_wr_data_in [0:SYSTOLIC_ARRAY_WIDTH-1];
logic ub_wr_valid_in [0:SYSTOLIC_ARRAY_WIDTH-1];
...
assign ub_wr_data_in[0] = vpu_data_out_1;
assign ub_wr_data_in[1] = vpu_data_out_2;
assign ub_wr_valid_in[0] = vpu_valid_out_1;
assign ub_wr_valid_in[1] = vpu_valid_out_2;
```

这几行非常重要。
因为它说明：
- 执行路径产生的激活/梯度
- 不是丢到模块外就结束
- 而是重新写回 UB

这就是为什么我一直说这不是推理 demo，而是训练闭环。
没有这几行，就没有后续 `H1 / dZ2 / dZ1 / updated params` 在系统里的连续流转。

---

## [76-128] `ub_inst`：执行核心真正的数据中枢入口

```systemverilog
unified_buffer #( ... ) ub_inst ( ... );
```

这里连接的其实就是整个项目的数据主场：

### 写入口
- `ub_wr_data_in / ub_wr_valid_in`：来自 VPU 写回
- `ub_wr_host_data_in / ub_wr_host_valid_in`：来自 Host 初始装载
- `ub_wr_ptr_restore_in`：来自 Frontend 的运行边界恢复

### 读控制
- `ub_rd_start_in`
- `ub_rd_transpose`
- `ub_ptr_select`
- `ub_rd_addr_in`
- `ub_rd_row_size`
- `ub_rd_col_size`

### 输出给执行单元
- input 流给 systolic 左边界
- weight 流给 systolic 上边界
- bias/Y/H 流给 VPU
- `ub_rd_col_size_out` 给 systolic 做内部控制

这说明 `tpu.sv` 并不自己生成数据，它依赖 UB 把所有训练语义的数据流组织出来。

---

## [130-155] `systolic_inst`：PE 阵列真正的乘加核心

```systemverilog
systolic systolic_inst (
    .sys_data_in_11(ub_rd_input_data_out_0),
    .sys_data_in_21(ub_rd_input_data_out_1),
    .sys_start(ub_rd_input_valid_out_0),
    ...
    .sys_weight_in_11(ub_rd_weight_data_out_0),
    .sys_weight_in_12(ub_rd_weight_data_out_1),
    .sys_accept_w_1(ub_rd_weight_valid_out_0),
    .sys_accept_w_2(ub_rd_weight_valid_out_1),
    .sys_switch_in(sys_switch_in),
    .ub_rd_col_size_in(ub_rd_col_size_out),
    .ub_rd_col_size_valid_in(ub_rd_col_size_valid_out)
);
```

这段把阵列输入分得很清楚：
- 左边界送 input
- 上边界送 weight
- `sys_switch_in` 控制 shadow -> active
- `ub_rd_col_size_*` 告诉阵列当前 tile/shape 语义

所以你可以把这段直接理解成：
**UB 负责供数，systolic 负责乘加和波前传播。**

### 一个很容易忽略的点

```systemverilog
.sys_start(ub_rd_input_valid_out_0)
```

这说明阵列启动直接依赖 UB input valid，而不是另起一条全局 start。
也就是说，阵列启动时机和 UB 数据波前是直接绑定的。

这正是“UB 发数和 PE 时序对齐”的源码根基之一。

---

## [157-184] `vpu_inst`：训练路径单元，不是附属后处理

```systemverilog
vpu vpu_inst (
    .vpu_data_pathway(vpu_data_pathway),
    .vpu_data_in_1(sys_data_out_21),
    .vpu_data_in_2(sys_data_out_22),
    .vpu_valid_in_1(sys_valid_out_21),
    .vpu_valid_in_2(sys_valid_out_22),
    .bias_scalar_in_1(ub_rd_bias_data_out_0),
    .bias_scalar_in_2(ub_rd_bias_data_out_1),
    .lr_leak_factor_in(vpu_leak_factor_in),
    .Y_in_1(ub_rd_Y_data_out_0),
    .Y_in_2(ub_rd_Y_data_out_1),
    .inv_batch_size_times_two_in(inv_batch_size_times_two_in),
    .H_in_1(ub_rd_H_data_out_0),
    .H_in_2(ub_rd_H_data_out_1),
    .vpu_data_out_1(vpu_data_out_1),
    .vpu_data_out_2(vpu_data_out_2),
    .vpu_valid_out_1(vpu_valid_out_1),
    .vpu_valid_out_2(vpu_valid_out_2)
);
```

这段最重要的认知是：
- VPU 不是阵列后的“随手处理一下”
- 它吃的不只是 systolic 输出
- 还同时吃 bias、Y、H、leak、inv_batch 等训练语义输入

所以 VPU 是一个真正的训练路径单元：
- `1100` forward
- `1111` transition/loss
- `0001` backward derivative

这些路径码之所以有意义，就是因为这一段接口把训练所需的所有输入都接齐了。

---

## [71-74 + 179-183] 为什么 `tpu.sv` 真正闭成环了

把两段合起来看：

```systemverilog
assign ub_wr_data_in[0] = vpu_data_out_1;
assign ub_wr_data_in[1] = vpu_data_out_2;
...
.vpu_data_out_1(vpu_data_out_1),
.vpu_data_out_2(vpu_data_out_2),
.vpu_valid_out_1(vpu_valid_out_1),
.vpu_valid_out_2(vpu_valid_out_2)
```

这说明系统内部形成了：
- UB -> systolic -> VPU -> UB

这就是完整的数据闭环。

而且这个闭环里还同时容纳：
- Host 初始装载
- shadow/active 权重切换
- VPU 路径切换
- learning rate / leak / inv batch 参数

所以 `tpu.sv` 虽然代码不长，但它是整个训练执行核心真正的组合中心。

---

## 一页总结

如果你只想记 `tpu.sv` 的 6 个点，就记：

1. 行 `4-53`：定义了执行核心的系统边界，输入是控制和数据，输出是结果和中间流。
2. 行 `55-74`：VPU 写回先回 UB，这是训练闭环最核心的一跳。
3. 行 `76-128`：`ub_inst` 是整个执行核心的数据中枢入口。
4. 行 `130-155`：`systolic_inst` 只管阵列乘加和波前传播，不负责全局控制。
5. 行 `157-184`：`vpu_inst` 是训练路径单元，不是附属后处理。
6. 行 `71-74 + 179-183`：整个系统在这个文件里真正形成 `UB -> systolic -> VPU -> UB` 数据闭环。

最后一句话：
**`tpu.sv` 的价值，不是实现复杂控制，而是把 UB、PE 阵列、VPU 三块真正接成一个可执行训练闭环的核心数据通路。**


---

# Part 14 Control Unit 带行号批注版

# `control_unit.sv` 带行号源码批注版

源码文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/control_unit.sv`

这份文档按源码行号解释 `control_unit.sv`。
它的重点不是讨论综合技巧，而是要解释：
**Frontend 发出去的一条 32-bit 指令，在这里是怎么被拆成真正的 UB / systolic / VPU 控制字段的。**

---

## [1-15] 端口定义：它不是“控制器”，更像“字段拆包器”

如果你直接看端口，会发现它没有时钟，也没有状态机，几乎全是组合式输出：

- 输入：`instruction`
- 输出：`sys_switch_in`
- 输出：`ub_rd_start_in`
- 输出：`ub_rd_transpose`
- 输出：`ub_wr_host_valid_in_1/2`
- 输出：`ub_rd_col_size`
- 输出：`ub_rd_row_size`
- 输出：`ub_rd_addr_in`
- 输出：`ub_ptr_sel`
- 输出：`ub_wr_host_data_in_1/2`
- 输出：`vpu_data_pathway`
- 透传：`inv_batch_size_times_two_in`、`vpu_leak_factor_in`

这说明它做的不是复杂时序控制，而是：
**把 32-bit 指令拆成后级模块能理解的字段。**

---

## [18-21] 指令拆字段：一眼看懂 32-bit 指令格式怎么落地

```systemverilog
wire [2:0] opcode  = instruction[2:0];
wire [15:0] imm16  = instruction[18:3];
wire [5:0]  ub_addr = instruction[8:3];
wire [3:0]  ub_row  = instruction[12:9];
wire [1:0]  ub_col  = instruction[14:13];
```

这一段很关键，因为它把前面 Frontend 注释里的“指令格式”真正落到了电路字段上。

你可以直接对应：
- `opcode`
- `addr`
- `row`
- `col`
- `imm16`

所以从编译器视角看，scheduler 生成的 32-bit 控制字，最终就是在这里被拆出来的。

---

## [23-40] always @(*)：整个模块就是纯组合 decode

```systemverilog
always @(*) begin
    ...
    case (opcode)
        3'b000: begin ... end
        3'b001: begin ... end
        3'b010: begin ... end
        3'b011: begin ... end
        default: begin ... end
    endcase
end
```

这说明 `control_unit` 没有内部状态，不记历史，不决定节奏。
它只做一件事：
**当前拍来的这条指令，到底该翻译成什么控制字段。**

所以系统节奏是 Frontend sequencer 决定的；字段语义是这里 decode 的。

---

## [24-35] 默认值：为什么 decode 模块一定要先清零

这一段会先把输出默认清零：

- `sys_switch_in = 0`
- `ub_rd_start_in = 0`
- `ub_rd_transpose = 0`
- `ub_wr_host_valid_in_1/2 = 0`
- `ub_rd_col_size = 0`
- `ub_rd_row_size = 0`
- `ub_rd_addr_in = 0`
- `ub_ptr_sel = 0`
- `ub_wr_host_data_in_1/2 = 0`
- `vpu_data_pathway = 0`

这个模式很重要，因为这说明 decode 的语义是：
- 只有命中的 opcode 字段才会被显式驱动
- 其他控制默认不动作

所以它天然适合被 sequencer 以单拍 pulse 驱动。

---

## [42-44] `NOP`：空操作就是所有字段都保持默认零

```systemverilog
3'b000: begin
    // NOP
end
```

这说明 NOP 的本质不是“做点什么”，而是“什么也不驱动”。

结合 scheduler 里的 `_nop()`，你就会明白：
- compiler 插入 NOP 不是为了表达算法
- 而是为了在系统时序上留空拍，让装载波前、路径切换、下游状态稳定下来

---

## [46-48] `SWITCH`：阵列权重激活边界就在这三行里

```systemverilog
3'b001: begin
    sys_switch_in = 1'b1;
end
```

这三行非常短，但意义很大。

它说明：
- 一条 `SWITCH` 指令
- 最终只会拉起 `sys_switch_in`
- 后续由 `systolic` 内部完成 shadow -> active 权重切换

所以 scheduler 里那种：
- load weight shadow
- nop
- switch
- stream input

在 RTL 上真正落地，就是先发若干 UB_RD 和 NOP，再在这里打一拍 `sys_switch_in`。

---

## [49-57] `UB_RD`：整个项目最重要的指令类型

```systemverilog
3'b010: begin
    ub_rd_start_in   = 1'b1;
    ub_rd_addr_in    = ub_addr;
    ub_rd_row_size   = ub_row;
    ub_rd_col_size   = ub_col;
    ub_rd_transpose  = instruction[15];
    ub_ptr_sel       = instruction[18:16];
    vpu_data_pathway = instruction[22:19];
end
```

这 7 行几乎就是整个系统的核心 decode。

它说明一条 `UB_RD` 指令会同时决定：
1. 启动一次 UB 读流
2. 从哪里读
3. 读多大块
4. 是否转置
5. 这次读是什么语义（input/weight/bias/Y/H/old params）
6. 这次执行对应哪条 VPU 路径

换句话说：
**一条 `UB_RD` 不只是“读 memory”，而是一次完整的阶段级执行配置。**

这也是为什么 `_ub_read()` 是 scheduler 的核心 helper。

---

## [58-63] `UB_WR_HOST`：为什么指令也能触发 Host 写口

```systemverilog
3'b011: begin
    ub_wr_host_valid_in_1 = 1'b1;
    ub_wr_host_valid_in_2 = 1'b1;
    ub_wr_host_data_in_1  = imm16;
    ub_wr_host_data_in_2  = imm16;
end
```

这一段说明指令集里还保留了 `UB_WR_HOST` 语义。

虽然当前主线更常用的是 AXI 侧 `UB_PUSH`，但这段 RTL 说明：
- 指令自身也可以编码一个 host-write 类动作
- 最终会走到 Frontend 里的 host write mux

所以你看 Frontend 那段 mux 就能明白：
为什么它要仲裁 AXI `UB_PUSH` 和 CU `UB_WR_HOST` 两条来源。

---

## [49-57] 和 scheduler 的一一对应关系

如果你把这一段和 `scheduler.py` 对起来看，会发现一一映射：

scheduler 输出：
```python
"signals": {
    "ub_rd_start_in": 1,
    "ub_ptr_select": ptr_sel,
    "ub_rd_addr_in": addr,
    "ub_rd_row_size": row,
    "ub_rd_col_size": col,
    "ub_rd_transpose": int(transpose),
}
```

`control_unit` decode：
```systemverilog
ub_rd_start_in   = 1'b1;
ub_rd_addr_in    = ub_addr;
ub_rd_row_size   = ub_row;
ub_rd_col_size   = ub_col;
ub_rd_transpose  = instruction[15];
ub_ptr_sel       = instruction[18:16];
vpu_data_pathway = instruction[22:19];
```

这就是软件和硬件字段真正严丝合缝对上的地方。

---

## 这个文件最该记住的 6 个点

1. 它是纯组合 decode，不决定系统节奏。
2. Frontend sequencer 决定什么时候发指令，它决定这条指令拆成什么字段。
3. `NOP` 的本质是所有输出保持默认零。
4. `SWITCH` 最终只拉起 `sys_switch_in`，为阵列权重激活服务。
5. `UB_RD` 是最重要的 opcode，因为它同时编码 UB 读流和 VPU 路径语义。
6. `UB_WR_HOST` 的存在解释了 Frontend 为什么要仲裁两类 host write 来源。

最后一句话：
**`control_unit.sv` 的价值，不在于复杂，而在于它是软件 32-bit 控制字和硬件执行字段之间那一层最直接、最关键的映射。**
