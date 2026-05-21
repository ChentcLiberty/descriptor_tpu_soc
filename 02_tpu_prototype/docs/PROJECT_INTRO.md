# 项目介绍口径：TinyTPU AXI-Lite SoC 闭环验证

> 更新时间：2026-04-02
> 推荐作为主项目使用

## 一句话结论

**我把一个原来主要靠 testbench 直驱的 tiny-tpu RTL，补成了带 AXI-Lite 前端和 IMEM sequencer 的 SoC 原型，并把 forward、backward、参数更新和多 epoch 训练闭环验证跑通了。**

## 30 秒版本

“这个项目我做的核心不是单个算子，而是把 tiny-tpu 从裸 RTL 形态补成 SoC 可控、可验证的原型。我加了 AXI-Lite 前端和 sequencer，用 59 条 IMEM 指令驱动当前 2x2、Q8.8 的 2-layer MLP 流程；验证上我做了两层，一层是单次 e2e，2026-04-02 复跑 `make test_tpu_soc_axil_e2e` 是 41/41 PASS；另一层是多 epoch 收敛，12 个 epoch 后 loss 从 0.2529 降到 0.1777，最终 XOR 预测收敛到 `(0,1,1,0)`。”

## 90 秒版本

“这个项目的目标，是把原来的 tiny-tpu RTL 核变成一个能从寄存器配置、加载指令、启动执行、再到结果回读的 SoC 化原型。我的主要工作分三块。第一块是接口和控制链路，我在 `src_axi/tpu_frontend_axil.sv` 里做了 AXI-Lite 解码、寄存器堆、sequencer 和 IMEM 装载，在 `src_axi/tpu_soc.sv` 里把前端和 TPU 核接起来。第二块是指令化执行，我用 `compiler/scheduler.py` 生成当前 2x2 tiny-tpu 的 stage-level schedule，再编码成 `compiler/out/imem.hex`，现在是 59 条指令。第三块是验证闭环，我用 cocotb 写了 `test/test_tpu_soc_axil_e2e.py` 和 `test/test_tpu_soc_axil_train_convergence.py`。前者会检查 H1、dZ2、dZ1 和 UB 中更新后的 W1/B1/W2/B2，2026-04-02 复跑是 41/41 PASS；后者会重复跑 12 个 epoch，看系统是否真的收敛，结果是 loss 从 0.2529 降到 0.1777，最终预测是 `(0,1,1,0)`。所以我更愿意把这个项目定义成‘系统集成 + 验证闭环 + bug 收敛’，而不是只做了一个接口壳。”

## 3 分钟版本

“这个项目最开始的问题是，原始 tiny-tpu 更偏 testbench 直接驱动内部端口，能验证模块和部分流程，但离一个 SoC 形态的研发项目还有一层。我做的第一步，是补一条 AXI-Lite 控制路径，让外部可以通过寄存器写数据、写 IMEM、启动 sequencer。这里最核心的文件是 `src_axi/tpu_frontend_axil.sv` 和 `src_axi/tpu_soc.sv`。前端负责 AXI 解码、寄存器堆、指令分发和状态机控制，SoC 顶层负责把 frontend 和原始 TPU 核连接起来。

第二步，我把当前原型的执行流程做成了指令化。`compiler/scheduler.py` 会针对当前 2x2、2-lane、Q8.8 的 2-layer MLP 生成 schedule，再编码到 `compiler/out/imem.hex`。现在仓库里的 IMEM 一共 59 条指令。这个阶段我比较注意边界，我会明确说这是 stage-level scheduler，目标是把当前 tiny-tpu 原型驱动起来，不会把它讲成一个通用编译器。

第三步，也是我觉得最有说服力的一步，是验证闭环。我不是只看一个 H1 输出，而是写了两个层级的 cocotb 用例。`test/test_tpu_soc_axil_e2e.py` 会先通过 AXI-Lite 把 X、Y、W1、B1、W2、B2 装到 UB，再加载 IMEM、启动 sequencer，然后把硬件输出和 numpy 参考模型对齐，检查 H1、dZ2、dZ1，以及 UB 里更新后的 W1/B1/W2/B2。这个用例我在 2026-04-02 复跑过，结果是 41/41 PASS。另一个用例 `test/test_tpu_soc_axil_train_convergence.py` 会在不重新加载数据的情况下连续触发 12 个 epoch，观察训练是不是收敛。当天复跑结果是 loss 从 0.2529 降到 0.1777，最后 XOR 预测变成 `(0,1,1,0)`。这一点对我来说很重要，因为它说明这条链路不是只跑一遍 forward，而是系统层训练闭环也能工作。

项目里比较能体现工程能力的部分是 debug。比如我遇到过 UB host write 完全无效的问题，最后定位到 Icarus 对 unpacked array output port 的处理有问题，所以把 host valid 从 array port 改成 scalar bridge；也遇到过 `vpu_data_pathway` 只在 dispatch 当拍有效，导致后面几拍流水线数据全 bypass，最后通过寄存器保持修掉；还有 sequencer 的 wait 逻辑如果用隐式条件，会把前一个阶段的 drain 提前消费掉，最后改成显式 `wait_after` 位来控制。这些问题我都能讲到现象、定位过程、修复动作和怎么验证收敛。

所以如果总结这个项目，我不会把它说成大而全的 TPU 架构项目，而会说它是一个比较完整的系统集成和验证项目：接口补齐了、控制链路补齐了、验证闭环补齐了，关键 bug 也能收敛到模块和信号级别。”

## 你在这个项目里的贡献，建议这样说

“我的贡献重点有三块：一是 SoC 前端和控制链路，二是当前原型的 IMEM/scheduler 驱动方式，三是用 cocotb 把单次 e2e 和多 epoch 训练闭环都验证起来，并在这个过程中把几类关键 bug 收敛掉。”

## 最值得讲的 3 个 bug 故事

### 1. Host write 无效

“现象是 cocotb 已经通过 AXI 写了 UB data/push，但 `wr_ptr` 不动、UB memory 还是 0。后面往下看发现不是测试脚本问题，而是 frontend 到 TPU 的 host valid 信号没真正被 UB 采到。根因和 Icarus 对 unpacked array output port 的处理有关，我最后在 `src_axi/tpu_frontend_axil.sv` 和 `src_axi/tpu_soc.sv` 之间把 host valid 拆成 scalar bridge，再接回 array 输入，问题就收敛了。”

### 2. VPU pathway 不保持

“现象是指令 dispatch 当拍 pathway 是对的，但过几拍以后 VPU 通路变成全 0，导致本来应该经过 bias/leaky_relu 的数据直接 bypass。这个问题如果只看当前拍的控制信号会很难发现，因为 systolic 输出本来就会晚几拍到。我最后在 sequencer 侧把 `vpu_data_pathway` 做成寄存器保持，在 `UB_RD` dispatch 时锁存，后面流水线阶段继续用保持值，输出就正常了。”

### 3. Wait 条件导致 sequencer 卡死

“一开始我用比较隐式的规则去推 `needs_wait`，结果不同阶段共用了同一个 drain 事件，前一条指令把 drain 消耗掉以后，后一条还在等，就会永久卡住。我后来把等待语义改成 IMEM 里的显式 `wait_after` 位，只给真正需要等待的指令打标，sequencer 状态机就稳定了。”

## 如果面试官追问“你怎么证明训练是可信的”

建议回答：

“我做了两层验证。单次 e2e 用例是强对齐的，会逐项比 H1、dZ2、dZ1 和更新后的参数，2026-04-02 复跑是 41/41 PASS。多 epoch 用例主要看系统层收敛，目标是 loss 持续下降并收敛到 XOR 正确分类。因为 fixed-point 截断和多轮累积误差的存在，我不会把多 epoch 的目标定义成每一拍都和 numpy 完全一致，而是定义成训练行为正确、趋势正确、最终任务结果正确。”

## 如果面试官追问“编译器是不是你做的”

建议回答：

“我会把边界说清楚。我做的是当前 tiny-tpu 原型的 schedule 生成和 IMEM 编码链路，核心文件是 `compiler/scheduler.py` 和 `compiler/encode_instrs.py`。它能把当前 2-layer MLP 的执行流程落成 59 条指令，但我不会把它讲成完整的通用编译器。”

## 如果面试官追问“还有没有别的亮点”

可以补第二条线：

“我还做过一个独立 pipeline 变体，在 `src/pipeline_exp/` 里插了 VPU 到 UB 的一级寄存器，综合文档 `docs/SYN_CODE_CHANGES.md` 里记录的结果是 Fmax 从 164.10MHz 提到 183.91MHz，代价是额外 1 个 cycle latency。这个点更偏综合和时序优化，我一般放在第二项目或者追问时再讲。”

## 边界一定要守住

不要扩成这些说法：

- 通用 TPU 架构
- 完整编译器
- 任意规模训练都 fully verified
- 默认设计已经拿到 183.91MHz

更稳的说法是：

**当前 tiny-tpu 原型、当前数据格式、当前网络规模、当前验证链路，我做得比较扎实。**
