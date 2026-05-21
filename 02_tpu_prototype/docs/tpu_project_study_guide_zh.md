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
