# 基于小胖达 CPU 的落地集成方案

## 一、目标

当前三周窗口内，最稳妥的路线不是重写一个全新的 SoC，而是：

- 复用 `CPU_Copetition` 里已经可用的 `panda_risc_v_min_proc_sys`
- 保留原有 `UART/GPIO/Timer/I2C` 外设路径
- 新增一个 `TPU` 的 `AXI-Lite` 地址窗口
- 用一个很薄的 `AXI-Lite splitter` 把 CPU 外设总线拆成：
  - `legacy peripheral` 路径
  - `TPU` 路径

这样能把主要精力集中在：

- CPU + TPU 联调
- 固件驱动
- MLP inference demo
- 项目边界和答辩口径

## 二、推荐模块边界

```text
                    +---------------------------+
                    |     cpu_tpu_soc_top       |
                    +-------------+-------------+
                                  |
                                  v
                    +---------------------------+
                    | panda_risc_v_min_proc_sys |
                    | CPU + ITCM/DTCM + PLIC    |
                    | + CLINT                   |
                    +-------------+-------------+
                                  |
                                  | ext peripheral AXI-Lite master
                                  v
                    +---------------------------+
                    |   cpu_tpu_axil_splitter   |
                    +-------------+-------------+
                                  |
                   +--------------+--------------+
                   |                             |
                   v                             v
        +------------------------+   +------------------------+
        | legacy periph path     |   |       tpu_soc          |
        | (APB bridge / UART /   |   |  current AXI-Lite TPU  |
        |  GPIO / TIMER / I2C)   |   |  frontend + core       |
        +------------------------+   +------------------------+
```

## 三、第一阶段地址映射

建议保持 CPU 现有外设地址不变，并新增一个 TPU 窗口：

| 地址 | 模块 | 说明 |
|---|---|---|
| `0x4000_0000 ~ 0x4000_0FFF` | GPIO | 复用现有 APB-GPIO |
| `0x4000_1000 ~ 0x4000_1FFF` | I2C | 复用现有 APB-I2C |
| `0x4000_2000 ~ 0x4000_2FFF` | TIMER | 复用现有 APB-TIMER |
| `0x4000_3000 ~ 0x4000_3FFF` | UART | 复用现有 APB-UART |
| `0x4000_4000 ~ 0x4000_4FFF` | TPU | 新增 TPU AXI-Lite 窗口 |

## 四、第一阶段必须完成的边界

### 硬件

- `panda_risc_v_min_proc_sys` 跑起来
- `UART` 正常可用
- `TPU` 作为 `0x4000_4000` 外设可访问
- CPU 能写 TPU 控制寄存器并读回结果

### 软件

- 有一个最小 `tpu_driver`
- 有一个 bare-metal `main.c`
- 有固定样本 / 固定特征 / 固定权重的 MLP inference demo

### 演示

- CPU 启动
- CPU 访问 TPU
- TPU 完成推理
- UART 打印分类结果

## 五、仲裁器在项目里的正确位置

你已经做好的多主多从仲裁器，不建议强行塞进第一阶段主通路。

第一阶段更稳的表述是：

> 当前 SoC 原型以 CPU 作为主要控制 master，通过 AXI-Lite 访问外设和 TPU。为后续扩展到 `CPU + TPU DMA` 多 master 共享内存场景，已经准备了独立设计的仲裁器模块，下一阶段会把它接入共享存储路径。

也就是说：

- 第一阶段：仲裁器是扩展资产
- 第二阶段：仲裁器才成为系统关键路径

## 六、当前不强求的项

为了保证项目能收口，第一阶段不强求：

- custom instruction
- DMA
- descriptor
- 真正多 master 共享存储
- 通用 TPU 编译器
- 任意网络支持

## 七、接下来的实现顺序

1. 写 `cpu_tpu_axil_splitter`
2. 写 `cpu_tpu_soc_top`
3. 先把 `UART + TPU` 最小闭环跑通
4. 再补驱动和 demo
