# Recommended Magic Plan

更新时间：2026-05-18

## 结论

当前最划算的路线不是：

- 导入一个完整开源 CNN/NPU 项目替换现有 SoC
- 重新做一套新 CPU 或新总线
- 把现有 TPU fullcore 主线推倒重来

当前最划算的路线是：

**在现有 stage2 主线上，新增一个小而专用的 `cnn_frontend` 执行块，只硬件化 CPU 软件里最慢的 `CNN/FiLM` 路径。**

## 为什么这条路最对

你已经有这些资产：

- `descriptor + launch/done/status/error`
- shared SRAM
- CPU boot 路径
- MLP / classifier 的 stable RTL 回归
- fullcore wrapper 主线

真正慢的是：

- CPU 软件 `conv1/conv2/FiLM/conv3/conv4`

所以收益最大的切法不是“换 SoC”，而是“只把慢热点抠出来做硬件”。

## 建议接法

利用已经预留的 `NET_ID_CNN1D_RESERVED = 3`，把它正式落成：

```text
NET_ID=3  -> CNN front-end task
NET_ID=0  -> MLP_KEY
NET_ID=1  -> MLP_OTHER
NET_ID=2  -> CLASSIFIER
```

CPU 运行节奏改成：

```text
raw signal / raw features
  -> launch NET_ID=3
  -> CNN front-end hardware writes cnn_out[256] into shared SRAM
  -> launch NET_ID=0 / 1 / 2 as today
```

这样：

- `MLP_KEY / MLP_OTHER / CLASSIFIER` 主线不动
- `descriptor ABI` 基本不动
- CPU 只少做最耗时的 CNN/FiLM 循环

## Descriptor 建议

第一版不要设计成“通用卷积 descriptor”，否则会把问题又做大。

第一版建议 `NET_ID=3` 解释成固定 front-end 流水：

```c
typedef struct {
    uint32_t net_id;        // 固定为 NET_ID_CNN1D_RESERVED
    uint32_t input_addr;    // raw/normalized signal base
    uint32_t output_addr;   // cnn_out[256] output base
    uint32_t param_addr;    // 可忽略或固定保留
    uint32_t scratch_addr;  // intermediate buffers
    uint32_t input_words;   // 默认 500 word = 1000 x int16/q8.8
    uint32_t output_words;  // 默认 128 word = 256 x int16/q8.8
    uint32_t flags;         // debug / preload / mode bits
} tpu_desc_t;
```

另加一个固定 `feature_addr` 来源，建议两种二选一：

### 方案 A

- 继续放在 shared SRAM 固定地址
- `cnn_frontend` 直接从固定 `FEATURE_BASE` 读 `key_features[2]`

优点：

- 第一版最简单

缺点：

- 不够优雅

### 方案 B

- 复用 `scratch_addr` 作为 feature block 基址

优点：

- 更干净

缺点：

- CPU 侧布局和 golden/export 脚本要一起改

第一版建议先用 **方案 A**。

## 模块切分建议

### `tpu_stage2_cnn_frontend_wrapper.v`

作用：

- 保持 stage2 外部接口风格
- 负责 descriptor fetch / AXI read / AXI write / done/error
- 内部例化真正执行核

说明：

- 这层风格应该尽量抄你现在的 `tpu_stage2_real_wrapper`，不要另起风格

### `cnn_frontend_engine.v`

作用：

- 执行固定 front-end 图
- 只关心局部状态机和本地 buffer

内部可分：

- `cnn_fetch_fsm`
- `conv1d_core`
- `pool_relu_core`
- `film_core`
- `mean_reduce_core`
- `cnn_writeback_fsm`

### `conv1d_core.v`

建议不是做成完全通用大核，而是：

- 支持 `kernel in {7,5,3}`
- 支持 `same padding`
- 支持 `in_ch/out_ch` 由微码或局部寄存器配置
- 输入输出都按 Q8.8 / int16

### `film_core.v`

只做当前真正需要的：

```text
gamma,beta from key_features[2]
x := relu((1 + gamma) * x + beta)
```

其中 `gamma/beta` 的生成不建议一开始单独做大矩阵硬件核。  
第一版可以：

- 直接在 `cnn_frontend_engine` 里顺序跑两个小 linear：
  - `2 -> 64`
  - `64 -> 128`

因为这部分规模比 4 层 conv 小很多，不是主瓶颈。

## 数据流建议

### 第一版：本地 scratch buffer

最稳的实现不是一上来就追求 full streaming，而是：

1. 从 shared SRAM 拉 `signal[1000]` 到本地 buffer
2. `conv1 + relu + pool` 写本地 buffer
3. `conv2 + film + relu + pool` 写本地 buffer
4. `conv3 + relu + pool` 写本地 buffer
5. `conv4 + relu + mean` 产出 `cnn_out[256]`
6. 回写 shared SRAM

优点：

- RTL 最直
- debug 最容易
- 和当前 SoC/descriptor 习惯最一致

缺点：

- 周期数不是最优

但这和你当前阶段的目标一致：先把 CPU 软件热点卸下来，而不是一开始做到最强。

### 第二版：流式 window/buffer

等第一版稳定后，再考虑：

- line/window buffer
- conv/pool 级间 streaming
- AXIS glue

这一步才值得吸收 `PULP hwpe-stream` / `axi_stream` / `verilog-axis` 的积木。

## 推荐开发顺序

### Phase 0

- 补一份固定 front-end 单样本 golden
- 对齐 `cnn_out[256]` 的 shared SRAM watchpoint

### Phase 1

- 只做 `conv1 + relu + pool`
- 跑局部 TB
- 对齐 Python golden 中间结果

### Phase 2

- 加 `conv2 + FiLM + pool`
- 先不接整机，只对局部 buffer 验证

### Phase 3

- 加 `conv3 + conv4 + mean`
- 形成完整 `cnn_out[256]`

### Phase 4

- 接入 stage2 wrapper
- CPU 发起 `NET_ID=3`
- shared SRAM writeback

### Phase 5

- 接回 `NET_ID=0/1/2` 现有主线
- 跑 `fixture` 与 `raw` 两种路径

## 不建议现在做的事

- 不建议先接 `NVDLA / Gemmini / Coral`
- 不建议先重做 Panda CPU
- 不建议先搞通用 CNN compiler / 通用 layer graph
- 不建议先追求完整 AXIS 化
- 不建议先动稳定的 classifier/MLP/fullcore 主线

## 一句话落地建议

先把 `NET_ID=3` 从“保留编号”变成“固定 `CNN/FiLM` front-end 硬件任务”，这就是当前最小、最稳、最可能迅速出结果的魔改路线。

## 当前进度补记

截至 `2026-05-18`，本实验目录里已经落下了完整 front-end 原型 RTL：

- wrapper 已能读取 descriptor
- wrapper 已能读取 `signal / feature / conv1 / conv2 / conv3 / conv4 / film` 所需参数块
- engine 已按本地 C 语义执行 `conv1 + relu + maxpool2`
- engine 已按本地 C 语义执行 `film linear + conv2 + film + relu + maxpool2`
- engine 已按本地 C 语义执行 `conv3 + relu + maxpool2`
- engine 已按本地 C 语义执行 `conv4 + relu + global mean`
- phase1 结果已能回写到 `scratch_addr`
- final `cnn_out` 结果已能回写到 `output_addr`
- 小尺寸参数化 VCS smoke 已通过 `phase1 + final output` 数值验证

这意味着当前状态已经从“方向评估/占位脚手架”推进到“完整 front-end 真实数据通路闭合”，下一步就应该是 `NET_ID=3` 接回 stage2 主线。
