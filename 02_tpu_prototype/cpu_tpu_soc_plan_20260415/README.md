# CPU+TPU 呼吸识别系统规划文档

这组文档把当前项目从“验证导向的 TinyTPU 原型”收敛为“面向比赛和面试可落地的 CPU+TPU 异构 SoC 项目”。

当前目标不是做通用编译器，也不是一次性做完 `custom instruction + descriptor + DMA + CNN + 训练` 全套，而是先做一个边界完整、可演示、可继续扩展的第一阶段版本。

## 第一阶段总目标

- 处理器通过 `AXI-Lite` 或等价 MMIO 接口控制 TPU
- CPU 负责预处理、特征提取、控制流和结果展示
- TPU 负责固定小规模 MLP 的推理
- 保留 `infer/train` 模式位和后续扩展位
- 为后续 `descriptor / DMA / custom instruction / 1D CNN` 预留架构空间

## 文档目录

- `01_项目定位与总体架构.md`
  说明项目目标、系统分层、为什么保留 frontend、不把所有任务都塞给 TPU。
- `02_接口分层与寄存器设计.md`
  说明 `TPU App Wrapper`、`frontend`、应用层寄存器、debug 页、descriptor、DMA 演进路径。
- `03_两到三周实施计划.md`
  说明比赛阶段的范围锁定、每周交付目标、风险回退方案、后续路线。
- `04_答辩与面试口径.md`
  说明“算子”“通用 TPU 编译器”“NVIDIA 为什么能直接跑算法”“嵌入式是什么”等答辩口径。
- `05_嵌入式软件与演示路径.md`
  说明在当前硬件基础上怎么做嵌入式固件、demo 流程和软件目录组织。

## 当前范围锁定

- 必做：
  - CPU + TPU 联调
  - `AXI-Lite` 控制面
  - 固定 MLP inference 闭环
  - 呼吸识别 demo
- 可选：
  - `infer/train` 模式切换框架
  - 小规模 MLP 训练闭环
- 后续：
  - descriptor
  - DMA
  - custom instruction
  - 1D CNN

## 一句话项目定义

基于 `CPU + TPU + AXI-Lite` 的呼吸识别异构加速系统：CPU 负责预处理与控制，TPU 负责规则的神经网络计算，并逐步扩展到训练、descriptor、DMA 和更通用网络支持。
