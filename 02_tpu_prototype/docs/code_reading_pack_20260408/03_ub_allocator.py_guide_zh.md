# `ub_allocator.py` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/ub_allocator.py`

这份文档只讲 `ub_allocator.py`。
它的核心任务不是调度，而是回答一个更基础的问题：
**训练过程中这些 tensor 到底放在 UB 的什么位置。**

---

## 1. 先给这个文件定性

这个文件不是编译器的“后处理小工具”，而是整个软件到硬件链路的地址起点。

因为后面这些东西都依赖它：
- `scheduler.py` 生成 `ub_rd_addr_in`
- `schedule.json` 里的每个 tensor 地址
- Host 初始装载顺序
- 后面 UB RTL 里不同语义区域的读写

一句话说：
**没有 allocator，后面的 stage schedule 只有张量名，没有物理落点。**

---

## 2. 这个文件解决的不是“优化”，而是“落位”

它主要做三件事：

1. 读 model spec
2. 推导当前模型在训练过程中需要哪些 tensor
3. 给所有落在 UB 里的 tensor 分配连续地址

所以这个文件的关注点不是 latency，也不是冲突，而是：
- 需要哪些 tensor
- 哪些 tensor 必须落 UB
- 哪些 tensor 可以是 ephemeral
- UB 总深度够不够

---

## 3. `load_spec()` 在先收边界

```python
def load_spec(path: str | Path) -> dict[str, Any]:
    ...
    if spec.get("model_type") != "mlp":
        raise ValueError(...)
```

这一步不是花哨逻辑，但很重要。
它明确要求 spec 里必须有：
- `model_type`
- `layers`
- `hardware_target`
- `data_format`

也就是说，allocator 不是凭空猜布局，而是严格围绕模型规格和硬件规格工作。

---

## 4. `infer_tensor_catalog()` 是这个文件最核心的部分

这一段决定了：
**训练闭环里到底有哪些 tensor。**

它会先生成：
- `X`
- `Y`
- 每层的 `W{i}`
- 每层的 `B{i}`
- 每层的 `H{i}`

如果训练打开，还会再生成：
- `dZ{i}`
- 对中间层还会生成 `dH{i}`

这一步非常关键，因为它把“模型结构”翻译成了“硬件运行时要存哪些数据”。

---

## 5. 为什么有些 tensor 是 `ub`，有些是 `ephemeral`

这里最值得注意的是：
- 有些 activation 会被放进 UB
- 有些 activation/gradient 会被标成 `ephemeral`

这说明 allocator 已经在做一个工程判断：
**不是所有中间结果都值得落 UB。**

例如：
- 如果某个 tensor 后面还会被别的阶段再次读到，就要落 UB
- 如果只是流水里暂时经过一次，可能可以不落 UB

这会直接影响：
- UB 占用
- Host 装载计划
- scheduler 之后能不能从 UB 再读到这个 tensor

---

## 6. `allocate_from_spec()` 的分配策略其实很朴素

它用的是最直接的 cursor 递增法：
- 遇到 `storage == "ub"` 的 tensor 就分配地址
- 地址连续递增
- 最后检查有没有超过 `ub_depth_words`

这不复杂，但很合理。
因为当前项目的首要目标不是做复杂 memory packing，而是先把训练闭环跑通。

所以这里的策略是：
- 简单
- 稳定
- 容易和 `schedule.json` / UB RTL 对齐

而不是先做很激进的地址复用优化。

---

## 7. 为什么这个文件对理解 UB 很重要

如果你后面准备看 `unified_buffer_v3.sv`，这个文件必须先懂。

因为在 RTL 里你会不断看到：
- `X` 从哪里读
- `W1` / `W2` 从哪里读
- `H1` 写回到哪里
- `dZ2` / `dZ1` 之后从哪里再读出来

这些地址不是 RTL 自己拍脑袋定义的，而是从 allocator 这一步来的。

也就是说：
**UB RTL 里的很多“地址语义”，上游起点就在这个 Python 文件。**

---

## 8. 这个文件和 `scheduler.py` 的关系

两者关系可以这样记：
- `ub_allocator.py` 决定“东西放哪”
- `scheduler.py` 决定“什么时候从哪读、什么时候往哪写”

所以如果你先看 scheduler，再回头看 allocator，会突然发现很多神秘数字其实都能解释。

---

## 9. 如果以后要升级，这个文件会怎么演进

后面它最可能增强的方向是：
- 更复杂的 tensor 复用策略
- 更智能的 UB 空间回收
- 多 bank / 多端口感知的布局
- 更泛化的模型支持，不只 2-layer MLP

但当前版本已经足够完成它的第一使命：
**把训练闭环里需要持久化的数据可靠落位。**

---

## 一页总结

如果你只记 `ub_allocator.py` 的 5 个点，就记：

1. 它是软件侧地址起点，不是小工具。
2. 它先定义训练过程中到底有哪些 tensor。
3. 它区分 `ub` 和 `ephemeral`，这是工程语义，不只是字段。
4. 它用连续 cursor 分配地址，简单但稳定。
5. 它给后面的 `scheduler.py` 和 `unified_buffer_v3.sv` 提供了地址基础。

最后一句话：
**`ub_allocator.py` 的价值，不在于复杂，而在于它把模型里的张量世界第一次落成了硬件 UB 能理解的地址世界。**
