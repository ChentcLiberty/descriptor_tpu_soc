# CPU+TPU 呼吸识别 SoC RTL 架构图讲解稿

生成时间：2026-05-22

## 一句话总览

当前主线已经不是 stub 过渡方案，而是固定到 `tpu_stage2_real_wrapper + real TPU`。CPU 负责 raw preprocess、descriptor 组织和 launch 调度；TPU 侧由 `tpu_stage2_real_wrapper` 统一接管 descriptor fetch、shared SRAM 读写和 `net_id` 分流，其中 `NET_ID=0/1/2` 走 `tpu_stage2_fullcore_wrapper`，`NET_ID=3` 走 `tpu_stage2_cnn_frontend_wrapper`。

需要明确边界：当前还不是 raw 全硬件化。`raw signal -> preprocess` 仍在 CPU 软件路径，进入 shared SRAM 之后的 CNN front-end、MLP/classifier 和 writeback 才是当前已经闭合的 RTL 主线。

## 新生成代码有哪些

1. `docs/render_breath_soc_rtl_arch_ppt.py`

   用 `python-pptx` 生成 4 页当前主线架构图：SoC 总图、TPU 控制面、descriptor/shared SRAM 数据面、两条执行子路径。

2. `docs/render_breath_soc_rtl_arch_explained_ppt.py`

   复用上面的 4 页图，再追加 2 页讲解顺序和文件说明，同时生成这份 Markdown 讲稿。

3. `docs/CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`

   这是脚本输出的讲稿落盘文件，供答辩或共享材料直接引用。

## 新生成文件不是 RTL 功能代码

这些脚本只负责产出 PPT/Markdown 文档，不参与综合和仿真，也不会改变硬件行为。图里引用的当前主线 RTL 主要是：

- `panda_soc_stage2_base_top.v`
- `cpu_tpu_axil_splitter.v`
- `tpu_ctrl_axil_regs.v`
- `panda_soc_shared_mem_subsys.v`
- `tpu_stage2_real_wrapper.v`
- `tpu_stage2_fullcore_wrapper.v`
- `tpu_stage2_cnn_frontend_wrapper.v`

## 每页怎么讲

### P19 CPU+TPU 呼吸识别 SoC RTL 架构总图

先讲系统分工：Panda RISC-V CPU 负责启动程序、准备 raw preprocess 结果、写 descriptor 和发起 TPU_CTRL；`tpu_stage2_real_wrapper` 负责从 shared SRAM 读取 descriptor/input/param，并按 `net_id` 分流到 fullcore TPU 或 CNN front-end；结果再统一写回 shared SRAM。

这一页要强调两条面：

- 控制面：CPU DBUS -> AXI-Lite splitter -> TPU_CTRL
- 数据面：CPU dcache AXI 与 TPU AXI master 共用 `panda_soc_shared_mem_subsys`

### P20 TPU 控制面 RTL 细节

讲 `cpu_tpu_axil_splitter.v` 的地址分流：`0x4000_4000` 起的 4KB 走 TPU_CTRL，其他 legacy 外设继续走 AXI-APB bridge。写通道靠 `write_busy_reg` 保持 AW/W 同路，读通道靠 `read_busy_reg` 保证返回数据来自同一路。

讲 `tpu_ctrl_axil_regs.v` 的寄存器：

- `CTRL` 产生 `launch_pulse` / `soft_reset_pulse`
- `STATUS` 回读 `busy/done/error`
- `MODE/NET_ID/DESC_LO/DESC_HI` 描述任务
- `PERF_CYCLE` 在 busy 期间计数

### P21 Descriptor 与 Shared SRAM 数据面

讲 `tpu_stage2_real_wrapper.v` 的角色：它先 peek descriptor 第 0 个 word 拿到 `net_id`，然后统一完成 descriptor fetch、blob fetch、执行分流和 writeback。共享内存子系统还是 `panda_soc_shared_mem_subsys.v`，也就是 CPU dcache AXI 与 TPU AXI master 通过 `axi_interconnect` 访问 `axi_ram`。

这一页要明确两个现状：

- 当前主线已经没有 `tpu_desc_fetch_dma_stub.v`
- `panda_soc_stage2_base_top` 对外的 `tpu_status_* / tpu_axi_*` 兼容口也已经移除

### P22 Stage2 执行子路径 RTL 细节

这里不要再讲 `tpu_mlp_compute_stub.v`，而是讲现在真正存在的两条执行子路径：

- `NET_ID=0/1/2`：`tpu_stage2_fullcore_wrapper.v`
  负责 fullcore TPU 路，包括 `tpu_frontend_local + tpu` 的 MLP/classifier 执行。
- `NET_ID=3`：`tpu_stage2_cnn_frontend_wrapper.v`
  负责 CNN front-end 路，包括 `conv1..4 + FiLM + mean`，把 `cnn_out[256]` 写回 shared SRAM。

这页的核心口径是：同一套 `descriptor + launch/done + shared SRAM` 机制下，现在已经有两条真实 RTL 路，而不是一条 stub 路。

### P23 RTL 架构图讲解顺序

这一页是答辩索引。推荐顺序：

1. 先定边界：CPU 做 raw preprocess 和调度，TPU 做 CNN front-end 与 classifier
2. 再讲控制面：MMIO TPU_CTRL 怎么发起任务
3. 再讲数据面：real wrapper 怎么从 shared SRAM 拉数和写回
4. 最后讲执行面：`NET_ID=0/1/2` 和 `NET_ID=3` 两条真实路径

### P24 新生成代码与文件说明

这一页强调：新增的是架构表达和讲稿，不是新的 RTL 功能模块。真实验证依据仍然是 CPU boot 回归、`NET_ID=3` focused 回归、stable/extended 套件和 UVM smoke。

## 常见追问回答

问：现在跑通的是整个呼吸识别算法的 RTL 验证吗？

答：不是 raw 全链路 RTL。当前跑通的是 raw preprocess + TPU 的整机路径，其中 raw preprocess 仍在 CPU，shared SRAM 之后的 CNN front-end、MLP/classifier 和 writeback 已经进入 RTL 主线。

问：现在是不是已经完全不用 stub 了？

答：是。当前 stage2 顶层已经固定到 real wrapper 和 real TPU 路，legacy stub RTL/TB 已经从主线删除，只剩历史文档里还保留了早期阶段记录。

问：为什么还要画 shared SRAM？

答：这是 CPU 和 TPU 之间的核心交换区。CPU 写 descriptor 和 blob，real wrapper 根据 descriptor 发 AXI 读写 shared SRAM，再把结果写回给 CPU 或 testbench 校验。

问：这次新增代码会影响硬件验证结果吗？

答：不会。这次新增的是 PPT 绘图脚本和讲稿，不参与综合和仿真。硬件验证结果来自现有 RTL/testbench/regression。
