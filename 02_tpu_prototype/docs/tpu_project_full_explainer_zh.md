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
