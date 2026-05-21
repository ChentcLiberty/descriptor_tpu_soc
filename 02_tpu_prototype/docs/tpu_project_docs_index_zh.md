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
