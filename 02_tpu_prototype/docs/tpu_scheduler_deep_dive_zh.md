# `scheduler.py` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/scheduler.py`

配套产物：
- `/home/jjt/tpu-soc/compiler/out/mlp_2_2_1_q8_8.schedule.json`
- `/home/jjt/tpu-soc/compiler/out/mlp_2_2_1_q8_8.ub_map.json`

这份文档只讲 `scheduler.py`。
重点不是把 Python 语法解释一遍，而是要让你搞清楚：
**这个 scheduler 到底在把什么软件意图，翻译成什么样的硬件阶段命令。**

---

## 1. 先给这个文件定性

这个文件不是：
- 通用 AI compiler
- cycle-accurate waveform generator
- 完整中间表示框架

它是：
**面向当前 tiny-tpu 2x2/2-lane 原型的阶段级调度器。**

这个定性非常重要，因为你一旦把它误解成“完整编译器”，很多设计取舍就会看起来像缺点；但如果你知道它的目标是“先把系统闭环跑通”，它反而会显得非常合理。

---

## 2. 文件一开始就在收边界条件

### 2.1 `_validate_current_target()` 很值得看

```python
if spec.get("model_type") != "mlp":
    raise ValueError("scheduler currently supports model_type=mlp only")
if len(layers) != 2:
    raise ValueError("scheduler currently supports exactly two linear layers")
if hw.get("array_width") != 2 or hw.get("lanes") != 2:
    raise ValueError("scheduler currently targets the 2x2 / 2-lane tiny-tpu prototype")
```

这段说明三件事：

1. 当前只支持 MLP
2. 当前只支持两层
3. 当前只支持 2x2 / 2-lane 原型

这不是偷懒，而是很明确地把项目目标钉住：
**先对当前原型做一条能跑通的编译路径。**

所以这个文件的设计哲学不是“无限泛化”，而是“围绕当前 RTL 原型，把软件-硬件链条做实”。

---

## 3. 先看 allocator，而不是先看命令

### 3.1 为什么 `_tensor_map()` 很重要

```python
def _tensor_map(allocation: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {tensor["name"]: tensor for tensor in allocation["tensors"]}
```

它的作用很简单：把 UB allocator 的输出变成按名字查 tensor 的字典。

但从系统理解上，它说明 scheduler 的第一步不是直接发命令，而是：
**先知道每个 tensor 在 UB 里放哪。**

### 3.2 `ub_map.json` 就是这一步的结果

你可以在 `mlp_2_2_1_q8_8.ub_map.json` 里直接看到：

- `X` 在 `0`
- `Y` 在 `8`
- `W1` 在 `12`
- `B1` 在 `16`
- `W2` 在 `18`
- `B2` 在 `20`
- `H1` 在 `21`
- `dZ2` 在 `29`
- `dZ1` 在 `33`

这一步的意义是：
- Host 知道初始装载怎么做
- Scheduler 知道后面 stage 命令该从哪读
- UB 内更新也知道旧参数区在哪

所以 `ub_map` 不是附属产物，而是整个 schedule 的地址基础。

---

## 4. `_ub_read()` 是整个 scheduler 的核心

### 4.1 先看函数签名

```python
def _ub_read(
    stage: str,
    name: str,
    tensor: str,
    ptr_sel: int,
    addr: int,
    row: int,
    col: int,
    transpose: bool,
    *,
    vpu_path: str | None = None,
    note: str = "",
    wait_after: bool = False,
) -> dict[str, Any]:
```

这几个参数其实已经把系统语义说完了：
- `stage`：这一拍属于哪一层大阶段
- `name`：这一条具体动作叫什么
- `tensor`：逻辑上读的是哪个 tensor
- `ptr_sel`：硬件上用哪种 UB 读语义
- `addr/row/col`：读的矩阵块位置和尺寸
- `transpose`：是否转置
- `vpu_path`：这次读流对应哪个 VPU 处理路径
- `wait_after`：这次动作后要不要等系统级完成边界

所以 `_ub_read()` 的价值在于：
**它把“软件里的一步训练动作”压缩成了“硬件能理解的一条阶段命令”。**

### 4.2 生成的命令长什么样

```python
command = {
    "stage": stage,
    "name": name,
    "kind": "ub_read",
    "tensor": tensor,
    "signals": {
        "ub_rd_start_in": 1,
        "ub_ptr_select": ptr_sel,
        "ub_rd_addr_in": addr,
        "ub_rd_row_size": row,
        "ub_rd_col_size": col,
        "ub_rd_transpose": int(transpose),
    },
    "wait_after": int(wait_after),
}
```

这里最重要的是 `signals`。
它说明 scheduler 输出不是抽象图，而是已经很贴近前端/UB 控制字段了。

你可以把它理解成：
- 软件侧先想“我现在要让硬件干什么”
- scheduler 再翻译成“具体要把哪些字段送给 Frontend/UB”

这就是软件和 RTL 的握手点。

---

## 5. `_switch()`、`_wait()`、`_nop()` 三种辅助命令说明了什么

### 5.1 `_switch()`

```python
def _switch(stage: str, name: str, note: str = "") -> dict[str, Any]:
    return {
        "stage": stage,
        "name": name,
        "kind": "control",
        "signals": {"sys_switch_in": 1},
    }
```

这说明 scheduler 知道阵列权重有 shadow/active 切换语义。
所以它不会把“load weight”和“开始算”混成同一件事。

### 5.2 `_wait()`

```python
def _wait(stage: str, name: str, event: str, note: str = "") -> dict[str, Any]:
```

它表示 scheduler 不只是发命令，还知道哪里必须形成系统同步点。
这和 Frontend 里的 `wait_after -> vpu_drain` 是一一对应的。

### 5.3 `_nop()`

```python
def _nop(stage: str, name: str) -> dict[str, Any]:
    return {"stage": stage, "name": name, "kind": "nop", "signals": {}}
```

`nop` 不是凑数，而是为了让：
- weight 装载波前走完
- shadow buffer 准备好
- 后续 `switch` 生效时，阵列状态已经稳定

这也是典型的“系统节奏感”设计，而不是单算子设计。

---

## 6. `forward_layer1`：第一层前向其实已经把整个系统思路讲透了

看这组命令：

```python
_ub_read("forward_layer1", "load_w1_shadow", "W1", 1, ... , True)
_nop(...)
_switch("forward_layer1", "activate_w1")
_ub_read("forward_layer1", "stream_x", "X", 0, ... , vpu_path="1100")
_ub_read("forward_layer1", "stream_b1", "B1", 2, ... , vpu_path="1100", wait_after=True)
_wait("forward_layer1", "wait_h1_writeback", "vpu_drain")
```

这整组动作其实已经把系统执行模式完全暴露了：

1. 先把 `W1^T` 从 UB 装到 shadow weight path
2. 用 `nop` 留出装载时间
3. `switch` 把 shadow 切成 active
4. 再把 `X` 从左边界流进 systolic
5. bias `B1` 同时流入 VPU
6. VPU 用 `1100` 路径做 bias + leaky relu
7. 最后等 `vpu_drain`，确保 `H1` 已经写回 UB

这说明 scheduler 输出的不是“数学表达式”，而是一串**带时序语义的系统动作脚本**。

---

## 7. `transition_layer2`：为什么这一步最能体现训练语义

看这组命令：

```python
_ub_read("transition_layer2", "load_w2_shadow", "W2", 1, ... , True)
_switch("transition_layer2", "activate_w2")
_ub_read("transition_layer2", "stream_h1", "H1", 0, ... , vpu_path="1111")
_ub_read("transition_layer2", "stream_b2", "B2", 2, ... , vpu_path="1111")
_ub_read("transition_layer2", "stream_y",  "Y",  3, ... , vpu_path="1111")
_ub_read("transition_layer2", "load_old_b2", "B2", 5, ... , wait_after=True)
_wait("transition_layer2", "wait_dz2_writeback", "vpu_drain")
```

这里发生的已经不只是 forward：
- H1 进入第二层
- B2 进入 bias 路径
- Y 进入 loss 路径
- old B2 进入更新路径
- VPU pathway 设成 `1111`

这表示一件事：
**训练过渡阶段把 forward、loss gradient、bias update 三件事捏在了同一个系统阶段里。**

所以 `1111` 不是一个随便挑的值，而是“第二层前向 + 损失 + 更新准备”的路径语义。

---

## 8. `backward_layer1`：为什么说明它不是推理系统

看这段：

```python
_ub_read("backward_layer1", "load_w2_backward", "W2", 1, ... , False)
_switch("backward_layer1", "activate_w2_backward")
_ub_read("backward_layer1", "load_old_b1", "B1", 5, ... , vpu_path="0001")
_ub_read("backward_layer1", "stream_dz2", "dZ2", 0, ... , vpu_path="0001")
_ub_read("backward_layer1", "stream_h1_for_derivative", "H1", 4, ... , vpu_path="0001", wait_after=True)
_wait("backward_layer1", "wait_dz1_writeback", "vpu_drain")
```

这已经很完整地体现了训练反向传播：
- 读取非转置的 `W2`
- 输入 `dZ2`
- 输入 `H1` 给导数路径
- 读取旧 `B1` 为 bias 更新做准备
- 最终写回 `dZ1`

所以从这一步开始，这个系统已经完全不是 inference accelerator，而是 training accelerator prototype。

---

## 9. `update_w1_tile_* / update_w2_tile_*`：为什么 outer product 也在系统里完成

后面的循环最值得看：

```python
for tile_index, (tile_start, tile_rows) in enumerate(_tile_ranges(batch_size, tile_width)):
```

这说明 weight update 不是整块一次做完，而是按 tile 来做。

### 9.1 W1 update 的思路

```python
"load_x_tile_to_top"
"activate_x_tile"
"load_dz1_tile_transposed"
"load_old_w1"
"wait_w1_update"
```

这意味着：
- 用 `X` tile 作为顶部输入
- 用 `dZ1^T` 作为左边输入
- systolic 做 outer product
- 同时从 UB 取旧 `W1`
- 在 UB 内 gradient_descent 更新

### 9.2 W2 update 的思路

```python
"load_h1_tile_to_top"
"activate_h1_tile"
"load_dz2_tile_transposed"
"load_old_w2"
"wait_w2_update"
```

逻辑完全类似，只是换成 `H1` 和 `dZ2`。

这两段非常重要，因为它们说明：
**这个 tiny-tpu 原型连参数更新都不是软件旁路算好再写回，而是系统内部自己跑 outer product + update。**

---

## 10. `host_load_plan` 为什么不是附属信息

看最后返回：

```python
host_load_plan = [
    {
        "tensor": tensor["name"],
        "addr": tensor["addr"],
        "shape": tensor["shape"],
        "words": tensor["words"],
    }
    for tensor in allocation["tensors"]
    if tensor["storage"] == "ub" and tensor["role"] in {"input", "label", "weight", "bias"}
]
```

它的意义是：
- 编译器不只是生成运行阶段命令
- 还明确告诉 Host，哪些 tensor 要提前装进 UB

你在 `schedule.json` 里可以直接看到：
- `X` -> `addr 0`
- `Y` -> `addr 8`
- `W1` -> `addr 12`
- `B1` -> `addr 16`
- `W2` -> `addr 18`
- `B2` -> `addr 20`

这就是 test 里 `load_all_data_axil()` 的依据。

所以 `host_load_plan` 是 software/runtime 和 hardware schedule 的接缝，不是附加信息。

---

## 11. `schedule.json` 到底代表什么

输出的 `schedule.json` 里最重要的是三部分：

1. `host_load_plan`
2. `ub_allocation`
3. `commands`

可以这样理解：

- `host_load_plan`：初始静态区怎么装
- `ub_allocation`：整个 UB 地址空间怎么分
- `commands`：运行时每个 stage 做什么

所以这个 JSON 其实就是“软件意图降成硬件动作脚本”的完整中间产物。

---

## 12. 这份 scheduler 和 PPT 哪几页最对应

它最直接对应的是：

1. `编译器与指令组织`
2. `Unified Buffer 设计`
3. `UB 读流与 PE 时序对齐`
4. `VPU 单独展开`
5. `逐拍计算动态`

原因很简单：
`scheduler.py` 决定了这些页里讲的：
- 哪些 tensor 什么时候读
- 用哪种语义读
- VPU 走哪条路径
- 哪一步后要等
- 哪一步是 load shadow，哪一步是 switch，哪一步是真正 stream compute

---

## 13. 这个文件最该记住的 10 个点

1. 它不是通用 compiler，而是当前 tiny-tpu 原型的阶段级调度器。
2. 它先做 `ub_allocation`，再做 stage 命令。
3. `_ub_read()` 是整个文件最核心的 helper。
4. `ptr_sel` 是软件到 UB 数据语义的直接映射。
5. `_switch()` 表示阵列权重 load/activate 两阶段分离。
6. `_wait()` 表示系统级阶段边界。
7. `forward_layer1` 已经能看出整套系统的执行节奏。
8. `transition_layer2` 最能体现训练路径，不只是前向。
9. update tile 阶段说明参数更新也在系统内部完成。
10. `host_load_plan` 是 Host runtime 和硬件 schedule 的接缝。

---

## 14. 最后一句话

如果只让我用一句话概括 `scheduler.py`，那就是：

**它把“训练一轮 MLP”的软件意图，翻译成了当前 tiny-tpu 原型能稳定执行的阶段级硬件动作脚本。**
