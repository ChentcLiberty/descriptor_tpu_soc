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
