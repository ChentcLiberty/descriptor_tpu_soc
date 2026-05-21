# 面试复习总纲（工程型实习生版本）

> 更新时间：2026-04-02
> 基于当前仓库代码、文档和当日复跑结果整理

## 1. 你的统一人设

不要把自己包装成“天才型选手”，统一对外呈现为：

**基础扎实、项目真实、边界清楚、能把事情做通的工程型实习生。**

面试里只守 4 条：

1. 先结论，再证据，再边界。
2. 每个亮点都带数字、文件、测试名，不空讲。
3. 不会的点直接收口，不防御。
4. 少说“我全都做了”，多说“我负责哪段、怎么验证、怎么 debug”。

## 2. 你最稳定的项目主线

一句话版本：

**我把一个原来主要靠 testbench 直驱的 tiny-tpu RTL，补成了带 AXI-Lite 前端和 sequencer 的 SoC 形态，并把 forward、backward、参数更新和多 epoch 训练闭环都验证了。**

面试时优先围绕这条线展开，不要把自己分散到太多零碎点上。

## 3. 可直接引用的硬证据

| 主题 | 结论 | 当前证据 | 边界 |
|------|------|----------|------|
| AXI-Lite SoC 集成 | 我不是只测裸 RTL，而是补了 SoC 接口和启动流程 | `src_axi/tpu_frontend_axil.sv`、`src_axi/tpu_soc.sv`、`test/dump_tpu_soc.sv` | 当前是 AXI-Lite 控制路径，不是高带宽 DMA/AXI4 数据面 |
| 指令化执行 | 我把当前 2x2 tiny-tpu 流程做成了 IMEM + sequencer 驱动 | `compiler/out/imem.hex` 共 59 条指令，`compiler/scheduler.py` 负责生成 schedule | 这是当前原型的 stage-level scheduler，不是通用编译器 |
| 端到端闭环验证 | 我验证的不只是 H1，而是 `H1 + dZ2 + dZ1 + UB 更新后参数` 的单次闭环 | 2026-04-02 复跑 `make test_tpu_soc_axil_e2e`，`test/test_tpu_soc_axil_e2e.py` 共 41 个检查点，`41/41 PASS` | 规模固定在 Q8.8、2x2 array、2-2-1 MLP/XOR 任务 |
| 训练闭环 | 我不只是“支持训练”，我把多 epoch 收敛跑通了 | 2026-04-02 复跑 `make test_tpu_soc_axil_train_convergence`，12 个 epoch 后 `loss 0.2529 -> 0.1777`，最终预测 `(0,1,1,0)` | 多 epoch 用例更看系统层收敛，不等于每个 epoch 每个参数都和 numpy 逐 bit 完全一致 |
| Debug 能力 | 我能把 bug 收敛到具体模块、时序点和修复动作 | `docs/AXI_SOC_FULL_SUMMARY.md` 里有完整 debug 记录，典型问题包括 host write 无效、pathway 保持、wait 逻辑死锁 | 不要说成“我把整个架构重写了”，本质是基于现有 tiny-tpu 做集成和收敛 |
| 综合/时序优化 | 我做过独立 pipeline 变体验证时序收益 | `docs/SYN_CODE_CHANGES.md` 记录 `164.10MHz -> 183.91MHz`，代价是 `+1 cycle` latency | 这是实验分支/变体，不是当前默认 AXI 路径的量产结论 |

## 4. 你在面试里最该反复强调的 3 件事

### 4.1 我做的是“把系统做通”

推荐说法：

“我做的重点不是单个 PE 或单个激活模块，而是把 tiny-tpu 从原来偏 testbench 驱动的形态，补成能从 AXI-Lite 写寄存器、加载 IMEM、启动 sequencer，然后把 forward/backward/update 跑通的系统级原型。”

### 4.2 我有能追到文件和结果的验证证据

推荐说法：

“我习惯把每句项目描述落到文件和测试。比如这个项目里，SoC 前端在 `src_axi/tpu_frontend_axil.sv`，顶层在 `src_axi/tpu_soc.sv`，e2e 验证在 `test/test_tpu_soc_axil_e2e.py`，我在 2026-04-02 复跑过一次，41 个检查点全过。”

### 4.3 我知道边界，不乱扩

推荐说法：

“这个项目我会明确说边界：它现在验证得最充分的是 Q8.8、2x2 array、2-2-1 MLP/XOR 这条链路。我不会把它讲成通用大模型加速器，也不会把 stage-level scheduler 讲成完整编译器。”

## 5. 固定表达模板

### 模板 A：讲亮点

“结论先说，我把 XX 做通了。证据上，我改了哪些文件、跑了哪些测试、结果是多少。边界上，这个结论适用于什么范围，不适用于什么范围。”

### 模板 B：讲 bug

“现象是 XX，先怎么定位，最后定位到哪个模块/信号。修复动作是什么。修完后我用哪个测试确认问题收敛。”

### 模板 C：讲边界

“这个点我了解原理，但我真正做深的是 XX 范围；再往外一层我可以讲思路，但不会说成自己已经做过实现。”

## 6. 不要这样讲

下面这些说法风险高：

- “我做了完整 TPU 编译器。”
- “我把训练和推理都 fully verified 了，任何规模都行。”
- “综合从 164MHz 直接优化到 183.91MHz，默认设计就是这个结果。”
- “所有模块都是我从零设计的。”

更稳的替代说法：

- “我做的是当前 tiny-tpu 原型的 scheduler / IMEM 驱动链路。”
- “我把当前 2x2、Q8.8、XOR/2-layer MLP 这条闭环验证做扎实了。”
- “我做过一个独立 pipeline 变体，综合文档里能看到 164.10MHz 到 183.91MHz 的提升。”
- “我的贡献重点是 SoC 接口、时序/控制收敛、验证闭环和 bug 定位。”

## 7. 建议的主副项目排序

主项目优先讲：

1. AXI-Lite SoC 集成 + e2e 验证 + 训练闭环
2. 一个最能体现工程能力的 bug 收敛故事
3. 如果面试官追问综合，再补 pipeline timing 优化

不要一上来就讲很多模块细节，先让面试官接受你的定位：

**“这是个能把系统做通、讲得清证据、边界也守得住的人。”**
