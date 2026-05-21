# Local Frontend Shape

更新时间：2026-05-18

## 作用

把当前 `CPU-front-end` 真实在做的算法子图写清楚，避免后续误选一个不匹配的开源 CNN 项目。

## 当前本地算法骨架

来自本地 golden/export 脚本：

```text
raw signal[1000]
  -> standardize
  -> conv1 same pad=3, kernel=7
  -> relu
  -> maxpool2
  -> conv2 same pad=2, kernel=5
  -> FiLM from key_features[2]
  -> relu
  -> maxpool2
  -> conv3 same pad=1, kernel=3
  -> relu
  -> maxpool2
  -> conv4 same pad=1, kernel=3
  -> relu
  -> mean(axis=1)
  -> cnn_out[256]
```

并行还有两条 feature 分支：

```text
key_features[2]
  -> MLP 2 -> 32 -> 64 -> 128 -> 64 -> 32

other_features[6]
  -> MLP 6 -> 32 -> 32
```

最终融合：

```text
concat[
  perceptron_out[32],
  key_features[2],
  cnn_out[256],
  other_out[32]
] = 322
  -> classifier 322 -> 256 -> 128 -> 64 -> 4
```

## 从 shared SRAM manifest 反推的 CNN/FiLM 尺寸

当前导出的参数区大小与脚本逻辑一致，可反推出：

- `conv1`: `1 -> 32`, `kernel=7`
  - weight words=`112` => `224` 个 Q8.8 值 => `32 * 1 * 7`
  - bias words=`16` => `32` 个 Q8.8 bias
- `conv2`: `32 -> 64`, `kernel=5`
  - weight words=`5120` => `10240` 个 Q8.8 值 => `64 * 32 * 5`
  - bias words=`32` => `64` 个 Q8.8 bias
- `conv3`: `64 -> 128`, `kernel=3`
  - weight words=`12288` => `24576` 个 Q8.8 值 => `128 * 64 * 3`
  - bias words=`64` => `128` 个 Q8.8 bias
- `conv4`: `128 -> 256`, `kernel=3`
  - weight words=`49152` => `98304` 个 Q8.8 值 => `256 * 128 * 3`
  - bias words=`128` => `256` 个 Q8.8 bias
- `FiLM l0`: `2 -> 64`
  - weight words=`64` => `128` 个 Q8.8 值 => `64 * 2`
  - bias words=`32` => `64`
- `FiLM l2`: `64 -> 128`
  - weight words=`4096` => `8192` 个 Q8.8 值 => `128 * 64`
  - bias words=`64` => `128`

## 中间张量长度

- input signal length = `1000`
- after `conv1 + pool2` => `32 x 500`
- after `conv2 + FiLM + pool2` => `64 x 250`
- after `conv3 + pool2` => `128 x 125`
- after `conv4 + mean` => `256`

## 对硬件方案的直接约束

### 1. 不需要通用 2D CNN

当前热点是：

- 单通道 `1D conv`
- kernel size 只需 `{7, 5, 3}`
- pool 只需 `maxpool2`
- activation 只需 `ReLU`
- 还需要一个 `FiLM affine`：
  - `x := (1 + gamma) * x + beta`

### 2. 第一版不应该碰 classifier/MLP 壳

TPU 侧 `MLP_KEY / MLP_OTHER / CLASSIFIER` 已经稳定回归。  
真正慢的是 CPU 软件里的 `CNN/FiLM`，所以第一版最值钱的是只把这一段下沉。

### 3. 最小可行 RTL 子集

建议第一版只做：

- `signal fetch`
- `conv1d_same`
- `bias + relu`
- `maxpool2`
- `film_apply`
- `global mean`
- `cnn_out writeback`

### 4. 最自然的接法

最自然的不是另起一套 SoC，而是：

```text
stage2 descriptor / launch
  -> cnn_frontend wrapper
  -> shared SRAM fetch
  -> local conv/pool/film engine
  -> shared SRAM writeback (256-d cnn_out)
  -> 后续仍由现有 TPU MLP/classifier 主线消费
```

这条接法能最大程度复用你现在已经跑稳的：

- `launch/done/error/status`
- shared SRAM 地址布局
- CPU boot / descriptor / DMA 回归
- classifier fullcore 路线
