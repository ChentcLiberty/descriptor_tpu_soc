# TPU 项目源码阅读顺序

这份文档只解决一件事：
**如果你要从代码开始看，这个项目到底应该按什么顺序读。**

不要上来就直接啃 `unified_buffer_v3.sv` 或 `vpu.sv`。
更高效的顺序是先把“软件怎么描述硬件动作”看明白，再看“前端怎么发命令”，最后再看“数据怎么在 UB / PE / VPU 里跑”。

---

## 一、推荐阅读顺序

### 1. `scheduler.py`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/scheduler.py`

先看它，因为它定义了系统到底按哪些“阶段命令”运行。
你需要先明白：
- forward / transition / backward / update 被拆成了哪些 stage
- `_ub_read()` / `_switch()` / `_wait()` / `_nop()` 各代表什么硬件意图
- `wait_after` 为什么存在

如果这一步没懂，后面看 RTL 很容易只看到一堆信号，看不到阶段语义。

---

### 2. `ub_allocator.py`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/ub_allocator.py`

第二个看它，因为 `scheduler` 的很多地址和 tensor 语义都建立在 UB 布局之上。
你需要先知道：
- `X / Y / W1 / B1 / W2 / B2 / H1 / dZ2 / dZ1` 在 UB 里怎么排
- 哪些 tensor 是 `ub`，哪些是 `ephemeral`
- 为什么训练阶段会引入 activation / gradient tensor

如果你不先看 allocator，后面看到 `ub_rd_addr_in=21` 这种数字不会有感觉。

---

### 3. `encode_instrs.py`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/encode_instrs.py`

第三步看它，因为它回答了一个关键问题：
**scheduler 里的阶段命令，最后是怎么编码成 IMEM 里的 32-bit 指令的。**

这里会把软件侧字段和硬件侧 decode 真正连上。

---

### 4. `control_unit.sv`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/control_unit.sv`

第四步看 control unit，因为它是 32-bit 指令在 RTL 里真正拆字段的地方。
你会看到：
- opcode
- addr / row / col
- transpose
- ptr_sel
- vpu_pathway

这一步看完，软件和硬件的位段映射就接上了。

---

### 5. `tpu_frontend_axil.sv`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_frontend_axil.sv`

第五步看 Frontend，因为它是整个系统的控制中枢。
它负责：
- AXI-Lite 寄存器
- IMEM 装载
- Sequencer
- `wait_after -> vpu_drain`
- Host 写 UB 与 control unit 写口仲裁

到这里你就会知道：
软件程序是如何变成硬件执行节奏的。

---

### 6. `tpu_soc.sv`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu_soc.sv`

第六步看顶层 SoC wrapper。
这一步主要看：
- Host AXI-Lite 怎么接进系统
- Frontend 和 TPU core 怎么焊起来
- `vpu_valid_out` 怎么回送给 Frontend 形成完成边界

这一步让你从“模块视角”切到“系统视角”。

---

### 7. `tpu.sv`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/tpu.sv`

第七步看 core 组合层。
重点是看清：
- UB 怎么给 systolic 发 input / weight
- systolic 怎么给 VPU 出 data / valid
- VPU 怎么把结果写回 UB

这一步最关键的一句话是：
`UB -> systolic -> VPU -> UB`。

---

### 8. `unified_buffer_v3.sv`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/unified_buffer_v3.sv`

第八步再看 UB。
这是整套里最难的文件，必须放到系统主线已经清楚之后再看。
重点看：
- `ptr_select`
- input/weight 发数差异
- bias / Y / H / old param 路径
- `wr_ptr_base / restore`
- in-UB gradient descent

如果你前面 1 到 7 没看明白，直接看它会非常痛苦。

---

### 9. `pe.sv`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/pe.sv`

第九步看单个 PE。
原因是你先理解单 PE 的 active/inactive weight、MAC、valid 传播，再去看阵列组合会更清楚。

---

### 10. `systolic.sv`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/systolic.sv`

第十步看 systolic array 组合。
这里你主要看：
- 4 个 PE 怎么连
- 输入从左向右传播
- 权重从上向下传播
- `sys_switch` 怎么沿阵列传播
- `ub_rd_col_size` 怎么决定启用几列

---

### 11. `vpu.sv`
文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/src_axi/vpu.sv`

第十一步看 VPU。
这一步最重要的是理解：
- 为什么 VPU 不是简单后处理
- `1100 / 1111 / 0001 / 0000` pathway 在干什么
- bias / leaky_relu / loss / lr_d 这些模块是怎么串起来的
- 为什么 `vpu_valid_out` 能作为阶段完成证据

---

### 12. `test_tpu_soc_axil_train_convergence.py`
文件：
- `/home/jjt/tpu-soc/test/test_tpu_soc_axil_train_convergence.py`

最后看验证。
因为你前面先把软件、控制、执行链都看懂了，再来看测试，才知道它到底证明了什么。

这一步主要回答：
- Host 怎样装载 UB 和 IMEM
- 怎样启动 Frontend
- 怎样轮询状态
- 怎样把系统结果读回
- 为什么说 train convergence 是系统级语义证据

---

## 二、为什么不建议一开始就看这些文件

### 1. `bias_parent.sv / leaky_relu_parent.sv / loss_parent.sv / leaky_relu_derivative_parent.sv`
这些文件当然重要，但它们更适合在你已经理解 `vpu.sv` 总路径之后再下钻。

### 2. `fixedpoint.sv`
它重要，但它属于算子底座，不是项目主线入口。
第一次读不建议先从这里开始。

### 3. `unified_buffer_v2 / unified_buffer_fixed / unified_buffer.sv`
这些更适合做演进对比，不适合作为当前主实现入口。

---

## 三、每一步要解决什么问题

### 第 1 到 3 步：软件怎么描述硬件动作
- `scheduler.py`
- `ub_allocator.py`
- `encode_instrs.py`

### 第 4 到 6 步：命令怎么进系统、系统怎么控起来
- `control_unit.sv`
- `tpu_frontend_axil.sv`
- `tpu_soc.sv`

### 第 7 到 11 步：数据在硬件里怎么真正跑
- `tpu.sv`
- `unified_buffer_v3.sv`
- `pe.sv`
- `systolic.sv`
- `vpu.sv`

### 第 12 步：怎么证明整个系统真的跑对
- `test_tpu_soc_axil_train_convergence.py`

---

## 四、配套详细说明文档

按上面顺序，对应看这些说明文档：

1. `scheduler.py` -> `02_scheduler.py_guide_zh.md`
2. `ub_allocator.py` -> `03_ub_allocator.py_guide_zh.md`
3. `encode_instrs.py` -> `04_encode_instrs.py_guide_zh.md`
4. `control_unit.sv` -> `05_control_unit.sv_guide_zh.md`
5. `tpu_frontend_axil.sv` -> `06_tpu_frontend_axil.sv_guide_zh.md`
6. `tpu_soc.sv` -> `07_tpu_soc.sv_guide_zh.md`
7. `tpu.sv` -> `08_tpu.sv_guide_zh.md`
8. `unified_buffer_v3.sv` -> `09_unified_buffer_v3.sv_guide_zh.md`
9. `pe.sv` -> `10_pe.sv_guide_zh.md`
10. `systolic.sv` -> `11_systolic.sv_guide_zh.md`
11. `vpu.sv` -> `12_vpu.sv_guide_zh.md`
12. `test_tpu_soc_axil_train_convergence.py` -> `13_test_tpu_soc_axil_train_convergence.py_guide_zh.md`

---

## 五、最实用的阅读建议

1. 先按顺序看，不要跳读。
2. 每看完一个文件，都回答一句“它在系统里负责什么”。
3. 遇到地址、指针、pathway，不要死记，先回到上游文件找语义来源。
4. 第一次看代码，主目标不是逐行吃透，而是把控制链和数据链连起来。

一句话总结：
**先看软件如何描述动作，再看系统如何发动作，最后看数据如何在硬件里完成闭环。**
