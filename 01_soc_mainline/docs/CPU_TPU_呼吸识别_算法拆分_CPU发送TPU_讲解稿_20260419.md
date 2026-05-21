# 从算法拆分到 CPU 发送 TPU 的讲解稿

生成时间：2026-04-19

## 推荐讲法

先不要从 RTL 模块名开始讲。更顺的主线是：算法怎么拆，CPU 做什么，TPU 做什么，CPU 怎么把任务发给 TPU，TPU 收到后怎么自己搬数和计算。

可以这样说：

> 这个呼吸识别算法我没有一开始就把全部计算都塞进 TPU。当前拆法是 CPU 负责前端，TPU 负责后面的 MLP/Classifier。CPU 先完成定点预处理、CNN/FiLM 或特征前端，整理出要送给 MLP/Classifier 的输入向量；然后 CPU 把输入、参数地址和输出地址写成一个 descriptor，放到 shared SRAM；最后通过 memory-mapped TPU_CTRL 寄存器写 `DESC_LO` 和 `CTRL.START`，把这个任务 launch 给 TPU。TPU 收到 launch 后，descriptor DMA 会自己从 shared SRAM 读 descriptor、读 input、读 param，把数据送进 Q8.8 MLP compute block，算完再把 output 写回 shared SRAM。CPU 只需要轮询 STATUS.done，然后读 output。

## 算法怎么拆

当前口径：

- CPU：原始窗口预处理、定点化、CNN/FiLM/特征前端、TPU 任务调度。
- TPU：MLP_KEY 分支、MLP_OTHER 分支、Classifier head，对应一串 Q8.8 linear tile 任务。
- Shared SRAM：CPU 和 TPU 之间的数据交换区。
- TPU_CTRL：CPU 发起任务、TPU 返回状态的 MMIO 控制口。

要明确：当前不是完整 CNN/FiLM 都进 TPU。当前已经做 RTL 验证的是 MLP/Classifier 任务链和 CPU+TPU 数据闭环。

## CPU 怎么发送给 TPU

CPU 发送一个 TPU stage 的动作可以拆成 5 步：

1. CPU 选择双缓冲区，例如 `TPU_DESC0_BASE / TPU_IN_BUF0_BASE / TPU_OUT_BUF0_BASE / TPU_SCRATCH0_BASE`。
2. CPU 把 input vector 写入 shared SRAM，把参数池 param pool 放在固定 shared SRAM 地址。
3. CPU 写 8-word descriptor：

```c
TPUDesc {
    net_id,
    input_addr,
    output_addr,
    param_addr,
    scratch_addr,
    input_words,
    output_words,
    flags
};
```

4. CPU 做 `fence`、dcache eviction 和 settle，保证 TPU DMA 看到最新 shared SRAM 内容。
5. CPU 通过 MMIO 写 TPU 控制寄存器：

```c
tpu_reg_write(runtime, TPU_REG_CTRL, TPU_CTRL_SOFT_RESET_MASK);
tpu_reg_write(runtime, TPU_REG_MODE, TPU_MODE_INFER);
tpu_reg_write(runtime, TPU_REG_NET_ID, desc->net_id);
tpu_reg_write(runtime, TPU_REG_DESC_LO, runtime->active_desc_addr);
tpu_reg_write(runtime, TPU_REG_DESC_HI, 0u);
tpu_reg_write(runtime, TPU_REG_CTRL, TPU_CTRL_START_MASK);
```

寄存器基地址是 `TPU_CTRL_BASEADDR = 0x4000_4000`。`DESC_LO` 偏移是 `0x10`，`CTRL.START` 是 bit0，`STATUS.done` 是 bit1。

## TPU 收到任务后怎么跑

TPU 内部不是 CPU 一拍一拍喂数据，而是 DMA 自己跑：

1. `tpu_ctrl_axil_regs.v` 收到 `CTRL.START`，产生 `launch_pulse`。
2. `tpu_desc_fetch_dma_stub.v` 进入 FSM，先从 `DESC_LO` 指向的 shared SRAM 地址读 8-word descriptor。
3. DMA 根据 descriptor 里的 `input_addr/input_words` 读 input blob。
4. DMA 根据 `param_addr` 和 `flags/input_words/output_words` 读 param blob。
5. DMA 把 input/param 以 `valid` 流送给 `tpu_mlp_compute_stub.v`。
6. compute block 生成 packed Q8.8 output word。
7. DMA 把 output word 写回 descriptor 里的 `output_addr`。
8. `STATUS.done` 置位，CPU 轮询到 done 后读 output。

## 和代码对应关系

- `work/600_competition_5stage/software/include/tpu_desc.h`：descriptor 字段、shared SRAM buffer 地址、net_id、flags。
- `work/600_competition_5stage/software/include/tpu_regs.h`：TPU_CTRL MMIO 地址和寄存器 bit。
- `work/600_competition_5stage/software/lib/tpu_runtime.c`：CPU 侧 `tpu_build_desc()`、`tpu_submit_desc()`、`tpu_wait_done()`。
- `work/600_competition_5stage/software/test/breath_tpu_soc_demo/main.c`：按 stage 依次 launch MLP_KEY、MLP_OTHER、classifier schedule。
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_ctrl_axil_regs.v`：MMIO 控制寄存器硬件。
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_desc_fetch_dma_stub.v`：descriptor DMA FSM。
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_mlp_compute_stub.v`：Q8.8 MLP compute block。

## 被追问时的边界回答

问：这是不是整个算法都映射到 TPU？

答：不是。当前拆法是 CPU 跑前端，TPU 跑 MLP/Classifier。TPU RTL 已经验证的是 descriptor DMA + Q8.8 MLP/Classifier 链路。

问：CPU 发给 TPU 的到底是什么？

答：CPU 发的不是算法源码，也不是直接拉 RTL 内部 wire，而是 shared SRAM 中的 descriptor 和数据地址，再通过 MMIO 写 `CTRL.START`。TPU 根据 descriptor 自己发 AXI 读写 shared SRAM。

问：为什么用 descriptor？

答：descriptor 把每个 TPU stage 的 input/output/param 地址、word 数和 flags 固定下来。这样 CPU 只需要按 stage 改 descriptor，TPU 侧 DMA/compute 逻辑可以复用。
