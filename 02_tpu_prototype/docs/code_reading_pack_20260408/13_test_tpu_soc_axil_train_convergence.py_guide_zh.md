# `test_tpu_soc_axil_train_convergence.py` 带行号源码批注版

源码文件：
- `/home/jjt/tpu-soc/test/test_tpu_soc_axil_train_convergence.py`

这份文档按源码行号解释测试文件。
目标是让你搞清楚：这份 test 为什么不是普通 smoke test，而是整个项目“训练闭环成立”的最终证据文件。

---

## [1-5] 文件头注释：测试目标已经写死了

开头写得很明确：

- DUT 是 `tpu_soc_top`
- 单次加载数据和 IMEM
- 重复 `start`
- 检查 XOR loss 下降
- 最终达到 `4/4` 正确分类

也就是说，这个测试从一开始就不是“打一拍看看波形”，而是系统级训练收敛验证。

---

## [12-15] 全局参数：验证标准不是模糊的

```python
FRAC_BITS = 8
TRAIN_EPOCHS = 12
LOSS_TARGET = 0.21
DEBUG_MON = False
```

这几行给出了验证的基础边界：
- 数据格式是 Q8.8
- 训练轮数是 12
- loss 目标有明确门槛

所以这份 test 不是随缘看趋势，而是有明确数值验收标准。

---

## [18-33] 固定点工具函数：软件参考模型和 RTL 语义对齐的基础

```python
def to_fxp(v): ...
def from_fxp(v): ...
def fxp(v): ...
def fxpa(a): ...
```

这一段的意义是：
- 所有参考模型计算都不直接用浮点裸值
- 而是尽量按 Q8.8 语义量化回来

这样做的价值在于：
**验证不是拿一个全浮点理想模型去硬比 RTL，而是尽量对齐硬件数值格式。**

---

## [36-47] 数据集、初始化参数、训练超参数：验证场景完全固定

这一段把：
- XOR 数据集 `X / Y`
- 初始参数 `INIT_W1 / INIT_B1 / INIT_W2 / INIT_B2`
- `LEAK`
- `INV_N2`
- `LR`
都固定下来了。

这里最重要的不是具体数值，而是它说明：
- 当前项目验证的是“固定已知可收敛的 Q8.8 初始化”
- 目标不是泛化 benchmark，而是证明这套系统训练链条本身成立

所以测试设计思路很工程化：
**先固定一个稳定可收敛点，验证整条链正确。**

---

## [50-119] 软件参考模型：这份 test 不只是驱动 DUT，还内建了对照模型

### [50-70] 前向和反向参考

```python
def leaky_relu(x): ...
def leaky_relu_d(g, h): ...
def forward_model(w1, b1, w2, b2): ...
def backward_model(h1, h2, w2): ...
```

这几段作用是：
- 用软件把 forward / backward 在 Q8.8 语义下跑一遍
- 给后续 loss、梯度、参数更新提供参考

### [77-109] 参数更新参考

```python
def apply_update_scalar(param, grad, lr=LR): ...
def update_model(w1, b1, w2, b2, h1, dz2, dz1): ...
```

这一段特别重要，因为它说明 test 不只是在看分类结果，还在用参考更新规则预测硬件参数的变化方向。

### [112-119] loss 和 prediction

```python
def mse_loss(h2): ...
def pred_bits(h2): ...
```

这意味着 test 关心两层证据：
- 连续 loss 下降
- 最终分类正确

所以这份 test 同时覆盖了“优化过程”和“最终结果”。

---

## [122-150] `axil_write / axil_read`：Host 控制链的最底层原语

```python
async def axil_write(dut, addr, data): ...
async def axil_read(dut, addr): ...
```

这两段是软件控制 DUT 的基础原语。

它们直接证明：
- 测试不是通过 testbench 私有信号偷偷改内部状态
- 而是老老实实通过 AXI-Lite 从系统正式入口写控制和读状态

所以当你说“这项目是主机可控 SoC”时，这两段就是最基础的证据。

---

## [153-160] `ub_write_cycle`：Host 如何往 UB 推一拍双 lane 数据

```python
async def ub_write_cycle(dut, d0, d1, push_mask):
    if push_mask & 1:
        await axil_write(dut, 0x020, d0 & 0xFFFF)
    if push_mask & 2:
        await axil_write(dut, 0x028, d1 & 0xFFFF)
    if push_mask:
        await axil_write(dut, 0x024, push_mask)
```

这段和 Frontend 寄存器图是完全对上的：
- `0x020`：lane0 data
- `0x028`：lane1 data
- `0x024`：UB_PUSH

也就是说，test 不只是“知道 UB 在哪”，还严格按 Frontend 暴露出来的 host-write 协议往里装数据。

---

## [162-180] `load_all_data_axil`：初始 Host 装载计划的实际落地

这一段非常重要：

```python
seq = [
    (to_fxp(x[0][0]), 0, 1),
    (to_fxp(x[1][0]), to_fxp(x[0][1]), 3),
    ...
    (to_fxp(b2[0]), to_fxp(w2[1]), 3),
]
```

它说明：
- Host 装载不是随便写一堆地址
- 而是按当前 UB 布局和双 lane push 方式，把 `X / Y / W1 / B1 / W2 / B2` 组织成具体写序列

这正是 `host_load_plan + ub_map` 在 test 侧的体现。

如果你被问“你怎么证明 Host 和 UB 布局是对上的”，就看这段。

---

## [182-190] `imem_load`：编译产物怎么真正装进系统

```python
async def imem_load(dut, hex_path):
    ...
    for i, instr in enumerate(instrs):
        await axil_write(dut, 0x030, i)
        await axil_write(dut, 0x034, instr)
        await axil_write(dut, 0x040, 1)
    await axil_write(dut, 0x044, len(instrs))
```

这一段和 Frontend 寄存器图一一对应：
- `0x030` -> `IMEM_ADDR`
- `0x034` -> `IMEM_W0`
- `0x040` -> `IMEM_WE`
- `0x044` -> `IMEM_LEN`

所以“编译器 -> imem.hex -> Frontend -> sequencer”这条链，在测试里是真正走通的。

---

## [193-202] `run_one_epoch`：一轮训练的正式软件入口

```python
await axil_write(dut, 0x000, 0x2)
...
status = await axil_read(dut, 0x004)
if not (status & 0x1):
    return
```

这几行是整个系统控制闭环的浓缩：
- 写 `0x000 = 0x2` 等于 `CTRL.start=1`
- 然后轮询 `STATUS.busy`
- busy 清掉，就说明 sequencer 这一轮完成

这说明测试不是靠固定 delay 猜 DUT 什么时候跑完，而是按系统正式状态位判断完成边界。

这非常关键，因为它体现了真正的 SoC 式控制，而不是 testbench 硬等拍数。

---

## [205-215] `read_hw_params`：为什么证据链不只看输出分类

```python
def read_hw_params(dut):
    ub = dut.dut.tpu_inst.ub_inst.ub_memory
    w1_words = [int(ub[12 + i].value) & 0xFFFF for i in range(4)]
    ...
```

这一段说明 test 还能直接读回 UB 中的参数区：
- `W1` 从 `12` 开始
- `B1` 从 `16` 开始
- `W2` 从 `18` 开始
- `B2` 在 `20`

这和 `ub_map.json` 完全对得上。

所以 test 的证据链是分层的：
1. AXI-Lite 控制链通
2. 程序真正执行完
3. 内部参数区真的发生更新
4. loss 下降
5. 最终 XOR 分类正确

这比只看最终分类要强得多。

---

## [218-232] 测试启动：复位和总线初始化做得很标准

这一段先：
- 启时钟
- 拉低 reset
- 清 AXI 控制信号
- 再释放 reset

这意味着测试不是从一个脏状态开始跑，而是把 SoC 顶层当成正规硬件来初始化。

这一点虽然不花哨，但很重要：
系统级验证的第一步永远是先把边界条件做干净。

---

## [234-243] 训练参数和 IMEM 装载：软件真的在走完整系统入口

```python
await axil_write(dut, 0x050, to_fxp(LEAK))
await axil_write(dut, 0x054, to_fxp(INV_N2))
await axil_write(dut, 0x058, to_fxp(LR))
...
await load_all_data_axil(...)
...
n = await imem_load(...)
```

这一段说明测试真正做了三类装载：
1. 训练超参数
2. UB 静态数据
3. IMEM 程序

这就意味着 DUT 运行前的软件准备已经完整闭环，而不是只打一条 start。

---

## [245-253] 初始参考 loss：为什么 test 能证明“下降”

```python
_, init_h2 = forward_model(ref_w1, ref_b1, ref_w2, ref_b2)
init_loss = mse_loss(init_h2)
init_pred = pred_bits(init_h2)
```

这几行计算的是硬件运行前的软件参考初始状态。

它的作用是给后面“loss 下降”提供基线。
没有基线，你只能说“最后结果还行”；有了基线，你才能说“训练过程确实在优化”。

---

## [258-260 以及后续主体] 主测试循环：真正验证的是连续多 epoch 收敛

虽然这里你当前看到的摘录只到 `monitor_lrd` 开头，但前面已经足够说明测试结构：

- 初始化系统
- 装载 UB
- 装载 IMEM
- 建软件参考初值
- 多轮 `run_one_epoch`
- 观察 loss history 和 prediction history
- 最后要求 XOR 正确分类

也就是说，这个 test 的核心不是“一轮跑没跑完”，而是“重复 start 后整个训练闭环能否持续收敛”。

这正是项目最有说服力的地方。

---

## 一页总结

如果你只想记这份 test 最关键的 8 个落点，就记：

1. 行 `1-5`：它从目标上就是多 epoch 收敛验证，不是 smoke test。
2. 行 `18-33`：固定点工具保证参考模型和硬件语义尽量对齐。
3. 行 `36-47`：数据集、初始化和超参数都是固定的可验证场景。
4. 行 `122-150`：AXI-Lite 是正式系统入口，不是测试私线。
5. 行 `162-180`：Host 按 UB 布局真正把 `X/Y/W1/B1/W2/B2` 装进去。
6. 行 `182-190`：`imem.hex` 真正通过前端寄存器装进系统。
7. 行 `193-202`：一轮训练用 `CTRL.start` 启动，用 `STATUS.busy` 收边界。
8. 行 `205-215`：test 不只看输出，还直接读回 UB 参数区验证更新。

最后一句话：
**这份 test 的价值，不是证明某个模块会动，而是证明“编译产物装载 -> 前端调度 -> 核心执行 -> 参数更新 -> loss 下降 -> XOR 收敛”这整条链真的成立。**
