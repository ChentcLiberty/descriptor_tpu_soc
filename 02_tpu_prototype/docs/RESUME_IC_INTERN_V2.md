# 陈韦东

📞 15155358906 | ✉️ 15155358906@163.com | 🎂 2002-09 | 🏛️ 中共党员 | 📍 成都

---

## 个人优势

- 有半年及以上实习时间，可全职实习
- 基础较扎实，能把 RTL/验证问题落到代码、波形和结果
- 项目真实，做过 AI 加速器原型的系统集成、验证闭环和时序优化

---

## 教育经历

**电子科技大学** | 硕士 | 光电科学与工程学院 | 电子信息（前10%） | 2024.09 - 2027.06
- 专业课程：处理器设计实验、面向FPGA的数字逻辑设计、半导体器件、模拟集成电路

**合肥师范学院** | 本科 | 电子信息与集成电路学院 | 电子信息（前3%） | 2020.06 - 2024.06
- 奖项证书：国家励志奖学金 | 全国大学生数学竞赛安徽赛区一等奖 | CET6 | 优秀学生一等奖学金 | 优良学风先进个人 | 三好学生
- GPA：4.0/5.0

---

## 项目经历

### 一、Titan-TPU V2 — MLP脉动阵列加速器 RTL 设计与验证（个人项目） | 2025.09 - 至今

**项目简述**：基于 tiny-tpu 2×2 Weight Stationary 原型，补充 AXI-Lite SoC 前端、IMEM/sequencer 控制链路，以及 forward / backward / 参数更新 / 多 epoch 训练验证闭环。使用 SystemVerilog / cocotb / Python / VCS / Verdi / Synopsys DC 完成系统集成、验证收敛与综合优化。

**个人完成**：
1. **SoC 集成与控制链路**：实现 `src_axi/tpu_frontend_axil.sv` 与 `src_axi/tpu_soc.sv`，完成 AXI-Lite 解码、寄存器堆、IMEM 装载和 4 状态 sequencer（IDLE / DISPATCH / WAIT / ADVANCE）；定义 32-bit 指令格式并配套 `compiler/scheduler.py` / `compiler/encode_instrs.py`，生成 59 条 MLP 指令覆盖 forward / backward / weight update。
2. **端到端验证闭环**：基于 cocotb + NumPy 建立 Q8.8 参考模型，编写 `test/test_tpu_soc_axil_e2e.py` 与 `test/test_tpu_soc_axil_train_convergence.py`；2026-04-02 复跑结果中，单次 e2e 对 `H1 + dZ2 + dZ1 + UB 更新后参数` 共 41 个检查点全部通过，多 epoch 训练在 12 个 epoch 后实现 `loss 0.2529 -> 0.1777`，最终 XOR 预测达到 `(0,1,1,0)`。
3. **系统级 debug 收敛**：定位并修复 6 类关键问题，包括 Icarus 对 unpacked array output 的 host write 失效、`vpu_data_pathway` 不能保持、sequencer `wait_after` 逻辑错误、权重 shadow load 建立时间不足等；形成从现象、信号定位到回归验证的完整 debug 闭环。
4. **综合与 PPA 权衡**：基于 SMIC 180nm `tt_1v8_25c` 编写综合/扫频脚本与 SDC 约束；在独立 pipeline 变体中对 VPU writeback / UB write 接口插入一级寄存器，将频率由 `164.10 MHz` 提升到 `183.91 MHz`。回到满足算法容量需求的 `UB depth=64` 基线配置后，扫频确认 `160 MHz` 可过（`6.25 ns`，`WNS/TNS=0/0`、`0` 条 timing violation）；为支持算法需存储 `>32` 个数，将 UB 深度调整为 `64` 并在 `100 MHz` 约束下重跑层次化 area/power report，总面积为 `518.54K μm²`、总功耗 `13.84 mW`，其中 UB 占面积 `67.2%`、功耗 `59.9%`。

**技术栈**：SystemVerilog | cocotb | Python | NumPy | VCS + Verdi | Synopsys DC | SMIC 180nm PDK | Makefile | Git

---

### 二、基于 Verilog 的 RISC-V CPU 设计与实现（队长） | 2025.03 - 至今

**项目简述**：设计并实现支持 RV32I 指令子集的 5 级流水线 CPU，涵盖取指（IF）、译码（ID）、执行（EX）、访存（MEM）、写回（WB）阶段。通过模块化设计实现核心功能，包括控制信号生成、ALU 运算、数据冒险处理，并通过 ModelSim 仿真验证功能正确性。

**个人完成**：
1. **数据通路设计**：基于 MIPS 指令子集完成流水线分阶段设计，分离指令存储器（IM）与数据存储器（DM），优化资源冲突，确保流水线无结构冒险。
2. **数据冒险处理**：
   - **转发机制**：设计旁路逻辑（Forwarding Unit），通过检测 EX/MEM 与 MEM/WB 流水段寄存器的相关性，解决 ALU 结果依赖的 RAW 冒险。
   - **阻塞机制**：针对 Load-use 冒险，插入硬件阻塞（Stall）并优化流水线控制信号清零逻辑，确保数据一致性。
3. **仿真验证**：使用 ModelSim 完成功能仿真，验证 lw、sw、R-type 及分支指令的正确性。

**后续计划**：扩展中断处理功能，基于 AMBA 总线协议完成外设扩展。

---

### 三、基于 16×16 路由器（Router）功能验证平台开发 | 2025.03 - 至今

**项目简述**：设计并实现基于 SystemVerilog 的验证平台，用于验证 16 输入 16 输出路由器的功能正确性、时序一致性及端口仲裁机制。通过覆盖率驱动验证（CDV）方法，完成随机化测试、结果比对及覆盖率收敛，确保设计符合协议规范。

**个人完成**：
1. **验证环境搭建**：构建分层验证架构，包括 Generator（生成随机化数据包）、Driver（驱动 DUT 输入）、Receiver（监测 DUT 输出）、Scoreboard（功能比对与覆盖率统计）。实现端口仲裁机制（Semaphore），解决多驱动端口冲突问题，确保数据包按优先级传输。
2. **随机测试用例开发**：覆盖 16 个端口的全路由组合、有效载荷长度（2-4字节）及边界条件。

**后续计划**：搭建 UVM 验证平台。

---

## 知识技能

- **知识**：熟悉数模电相关知识，有 FPGA 上板经验，熟悉 Linux 操作系统，了解 APB/AHB/AXI/AXI-Lite 总线协议，熟悉芯片设计基本知识（代码规范、典型电路如状态机、FIFO），熟悉 AI 加速器脉动阵列架构（Weight Stationary 数据流、定点数运算）
- **语言**：熟悉 Verilog/SystemVerilog，了解 UVM 验证方法学，掌握 Clocking Block、SVA 断言、Constrained Random 等验证技术
- **软件**：熟悉 VCS、Verdi、Design Compiler，熟悉 Vivado、Quartus、ModelSim、ISE、Gvim
- **脚本**：了解 Shell、Tcl、Makefile 构建系统，熟悉 Python（cocotb 验证、NumPy 参考模型、指令调度/编码脚本）
- **工具**：Git 版本控制，覆盖率收集与分析（line/cond/fsm/tgl/branch）

---

## 个人总结

偏工程型实习生风格，习惯先给结论，再补证据和边界。能把问题落到代码、波形、测试结果和 debug 过程，具备独立定位和修复 RTL Bug 的能力；熟悉 Reference Model、Scoreboard、Coverage 等验证方法学，也能围绕综合和时序问题给出可验证的优化动作。
