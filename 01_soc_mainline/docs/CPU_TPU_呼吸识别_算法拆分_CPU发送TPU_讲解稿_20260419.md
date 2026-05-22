# 从算法拆分到 CPU 发送 TPU 的讲解稿

生成时间：2026-05-22

## 推荐讲法

现在更顺的主线不是“CPU 前端 + TPU 末端”的旧说法，而是：

1. 算法怎么拆
2. CPU 保留了什么
3. TPU 现在接了什么
4. CPU 怎么把任务发给 TPU
5. TPU 收到 launch 后怎么自己分流执行

可以这样说：

> 这个呼吸识别算法当前没有做到 raw 全硬件化。CPU 仍负责 raw preprocess、feature/signal 准备和任务调度；TPU 侧已经接住了 `NET_ID=3` 的 CNN front-end，以及后续 `NET_ID=0/1/2` 的 fullcore classifier。CPU 把输入、参数和输出地址写成 descriptor，放到 shared SRAM，再通过 memory-mapped TPU_CTRL 写 `DESC_LO` 和 `CTRL.START` 发起任务。`tpu_stage2_real_wrapper` 收到 launch 后，会自己从 shared SRAM 读 descriptor，按 `net_id` 分流到 CNN front-end 或 fullcore TPU，算完再把结果写回 shared SRAM。CPU 只需要轮询 `STATUS.done`，然后读 output。

## 算法怎么拆

当前口径：

- CPU：raw window 预处理、定点化、feature/signal 准备、TPU 任务调度。
- TPU：`NET_ID=3` CNN front-end，`NET_ID=0/1/2` fullcore classifier。
- Shared SRAM：CPU 和 TPU 之间的数据交换区。
- TPU_CTRL：CPU 发起任务、TPU 返回状态的 MMIO 控制口。

要明确：当前已经不是“CNN/FiLM 全在 CPU”。现在 TPU 已经接住了 CNN front-end 的主计算链，但 raw preprocess 本身仍在 CPU。

## CPU 怎么发送给 TPU

CPU 发送一个 TPU stage 的动作可以拆成 5 步：

1. CPU 选择双缓冲区，例如 `TPU_DESC0_BASE / TPU_IN_BUF0_BASE / TPU_OUT_BUF0_BASE / TPU_SCRATCH0_BASE`。
2. CPU 把当前 stage 需要的 blob 写到 shared SRAM。对 `NET_ID=3` 来说，典型是 `signal/feature/conv/film`；对 classifier 来说，典型是 `cnn_out/fusion input/param`。
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

4. CPU 做 `fence`、dcache eviction 和 settle，保证 TPU 看到最新 shared SRAM 内容。
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

TPU 内部不是 CPU 一拍一拍喂数据，而是 wrapper 自己跑：

1. `tpu_ctrl_axil_regs.v` 收到 `CTRL.START`，产生 `launch_pulse`。
2. `tpu_stage2_real_wrapper.v` 根据 `DESC_LO` 指向的地址读 8-word descriptor。
3. wrapper 先 peek `descriptor[0]` 拿到 `net_id`。
4. wrapper 根据 descriptor 里的 `input_addr/output_addr/param_addr/scratch_addr` 和 word 数去 shared SRAM 拉对应 blob。
5. `net_id == 3` 时，wrapper 把数据送到 `tpu_stage2_cnn_frontend_wrapper.v`。
6. `net_id != 3` 时，wrapper 把数据送到 `tpu_stage2_fullcore_wrapper.v`。
7. 两条路径都把结果写回 descriptor 指定的 `output_addr` 或 `scratch_addr`。
8. `STATUS.done` 置位，CPU 轮询到 done 后读 output。

## 和代码对应关系

- `work/600_competition_5stage/software/include/tpu_desc.h`：descriptor 字段、shared SRAM buffer 地址、`net_id`、flags。
- `work/600_competition_5stage/software/lib/tpu_runtime.c`：CPU 侧 `tpu_build_desc()`、`tpu_submit_desc()`、`tpu_wait_done()`。
- `work/600_competition_5stage/software/test/breath_tpu_soc_demo/main.c`：按 stage 依次 launch `NET_ID=3` 和 classifier。
- `work/600_competition_5stage/software/test/breath_tpu_soc_demo/breath_cpu_frontend.c`：raw preprocess 和 feature/signal 准备。
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_ctrl_axil_regs.v`：MMIO 控制寄存器硬件。
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_stage2_real_wrapper.v`：descriptor fetch、net_id 分流和统一 writeback。
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_stage2_cnn_frontend_wrapper.v`：`NET_ID=3` CNN front-end。
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_stage2_fullcore_wrapper.v`：fullcore TPU classifier 路。

## 被追问时的边界回答

问：这是不是整个算法都映射到 TPU？

答：不是 raw 全链路 RTL。当前是 CPU 跑 raw preprocess，TPU 跑 `NET_ID=3` CNN front-end 和 fullcore classifier。shared SRAM 之后的主计算已经在 TPU 主线里。

问：CPU 发给 TPU 的到底是什么？

答：CPU 发的不是算法源码，也不是直接拉 RTL 内部 wire，而是 shared SRAM 中的 descriptor 和数据地址，再通过 MMIO 写 `CTRL.START`。`tpu_stage2_real_wrapper` 根据 descriptor 自己发 AXI 读写 shared SRAM，并按 `net_id` 分流。

问：为什么用 descriptor？

答：descriptor 把每个 TPU stage 的 `input/output/param/scratch` 地址、word 数和 flags 固定下来。这样 CPU 只需要按 stage 改 descriptor，wrapper 和两条执行路径都能复用同一套控制协议。
