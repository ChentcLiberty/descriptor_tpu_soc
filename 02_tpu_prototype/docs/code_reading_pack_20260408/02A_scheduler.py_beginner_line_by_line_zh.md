# `scheduler.py` 小白版逐段细讲

对应源码：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/01_scheduler.py`

原版讲解：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/02_scheduler.py_guide_zh.md`

这份新文档是给小白看的。
目标不是追求“专业术语很多”，而是让你第一次看这个文件时，能一句一句地知道：

1. 这几行代码到底在干什么
2. 它为什么要这样写
3. 它和整个 TPU 项目是什么关系
4. 你看完这一段后，脑子里应该记住什么

---

## 0. 看这个文件之前，先记住 5 句话

1. `scheduler.py` 不负责做数值计算。
2. `scheduler.py` 不直接控制每一拍时序。
3. `scheduler.py` 的职责，是把“训练流程”变成“阶段命令列表”。
4. 这些阶段命令后面会继续被编码成 `IMEM` 指令，再交给 `Frontend` 去执行。
5. 所以这个文件本质上不是在“算”，而是在“写一份硬件执行脚本”。

如果你只记一句话，就记这句：

**`scheduler.py` 是软件侧写出来的一份“训练执行流程单”。**

---

## 1. 建议你怎么打开这份代码

最好的看法不是只盯着这篇文档，而是这样看：

1. 左边打开源码  
   `/home/jjt/tpu-soc/code_reading_sources_20260409/01_scheduler.py`
2. 右边打开这篇文档  
   `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/02A_scheduler.py_beginner_line_by_line_zh.md`
3. 跟着我这里写的行号，一段一段往下对

不要一上来就问：
- 这个字段为什么是 `1100`
- 为什么这里是 `ptr_sel = 5`
- 为什么一定要 `nop(4)`

第一轮先只回答一个问题：

**“这一段代码在整个训练闭环里扮演什么角色？”**

---

## 2. 第 1 到 13 行：文件开头在做什么

对应源码：

```python
1  #!/usr/bin/env python3
2  from __future__ import annotations
4  import argparse
5  import json
6  import sys
7  from pathlib import Path
8  from typing import Any
10 if __package__ in (None, ""):
11     sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
13 from compiler.ub_allocator import allocate_from_spec, load_spec
```

### 2.1 第 1 行

```python
#!/usr/bin/env python3
```

这行是 shebang。
意思是：如果你把这个文件当脚本直接运行，系统会优先用 `python3` 来执行它。

你现在不用太在意它。
它和调度逻辑本身没关系。

### 2.2 第 2 行

```python
from __future__ import annotations
```

这行的作用是让类型标注处理得更灵活一点。
对你理解业务逻辑影响不大。

你现在只要知道：
- 它不是算法逻辑
- 它不是硬件逻辑
- 它只是 Python 侧的写法优化

### 2.3 第 4 到 8 行

```python
import argparse
import json
import sys
from pathlib import Path
from typing import Any
```

这几行是导入标准库。

分别干什么：
- `argparse`：命令行参数解析
- `json`：把 schedule 输出成 JSON
- `sys`：处理导入路径
- `Path`：更方便地处理路径
- `Any`：类型提示

这几行也不是“调度逻辑”，只是工具准备。

### 2.4 第 10 到 11 行

```python
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
```

这一段非常容易把小白看懵。

它的作用其实很简单：

**如果这个文件是被“单独运行”的，而不是作为一个 Python package 的模块导入，那么就手工把上一级目录加进 `sys.path`，这样后面的 `from compiler.ub_allocator import ...` 才能成功。**

翻成人话就是：

“我怕你直接运行这个文件时，Python 找不到同目录体系里的 `compiler` 包，所以我先帮你把路径补上。” 

### 2.5 第 13 行

```python
from compiler.ub_allocator import allocate_from_spec, load_spec
```

这一行非常重要。

它说明两件事：

1. `scheduler.py` 不是孤立工作的
2. 它在开工之前，先要依赖 `ub_allocator.py`

这两个函数分别是什么：
- `load_spec`：把模型规格 JSON 读进来
- `allocate_from_spec`：先给每个 tensor 分配 UB 地址

这说明 `scheduler.py` 的第一步不是“发命令”，而是：

**先知道模型长什么样，再知道每个张量在 UB 里放哪。**

### 2.6 这一小段你应该记住什么

看完第 `1-13` 行，你脑子里应该留下这句话：

**这个文件一开头就在搭环境，而且它明显依赖 `ub_allocator.py`，说明调度之前要先完成地址分配。**

### 2.7 小白最容易误解什么

最容易误解的是把第 `10-11` 行当成“核心逻辑”。

不是。

真正重要的是第 `13` 行，因为它告诉你：

**调度器不是从空气里生成命令，它要建立在 UB 地址分配结果之上。**

---

## 3. 第 16 到 17 行：`_tensor_map()` 在干什么

对应源码：

```python
def _tensor_map(allocation: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {tensor["name"]: tensor for tensor in allocation["tensors"]}
```

### 3.1 这一段的作用

这段代码的作用是：

**把 allocator 输出的 tensor 列表，变成一个“按名字查 tensor 信息”的字典。**

如果 allocator 原始输出像这样：

```python
[
  {"name": "X", "addr": 0, ...},
  {"name": "Y", "addr": 8, ...},
  {"name": "W1", "addr": 12, ...},
]
```

那么 `_tensor_map()` 会把它变成：

```python
{
  "X":  {"name": "X",  "addr": 0, ...},
  "Y":  {"name": "Y",  "addr": 8, ...},
  "W1": {"name": "W1", "addr": 12, ...},
}
```

### 3.2 为什么要这样做

因为后面写 schedule 时，经常要查：

- `tensors["W1"]["addr"]`
- `tensors["H1"]["addr"]`
- `tensors["dZ2"]["addr"]`

如果不先变成字典，后面每次都要去列表里遍历一遍，很麻烦。

### 3.3 这一段你应该记住什么

**调度器后面会频繁按 tensor 名字拿 UB 地址，所以先把 allocator 的结果改成“好查”的结构。**

### 3.4 容易误解什么

容易误解成：

“这一步是不是在重新分配 UB？”

不是。

它没有分配任何地址。
它只是把已有结果换了个更顺手的查法。

---

## 4. 第 20 到 24 行：`_tile_ranges()` 在干什么

对应源码：

```python
def _tile_ranges(total_rows: int, tile_rows: int) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for start in range(0, total_rows, tile_rows):
        ranges.append((start, min(tile_rows, total_rows - start)))
    return ranges
```

### 4.1 这段是在做什么

这段代码是在把“大批量数据”切成一块一块的 tile。

比如：
- 总共有 `5` 行数据
- 每次硬件方便处理 `2` 行

那么它会切成：

```python
[(0, 2), (2, 2), (4, 1)]
```

意思是：
- 从第 `0` 行开始，拿 `2` 行
- 从第 `2` 行开始，拿 `2` 行
- 从第 `4` 行开始，拿 `1` 行

### 4.2 为什么需要它

因为阵列宽度是有限的。
硬件不是想处理多大 batch 就能一次全吞下去。

所以在更新权重时，经常需要做：

**按 tile 分块，把一部分样本的贡献先算出来，再处理下一块。**

### 4.3 这一段你应该记住什么

**`_tile_ranges()` 不是 TPU 专有神秘函数，它只是一个“把大任务切小块”的工具函数。**

### 4.4 容易误解什么

容易误解成：

“是不是 forward、backward 也都在这里做 tile？”

在这个文件里，最明显用到它的是后面的权重更新阶段。
因为权重更新要做外积，按 tile 处理比较自然。

---

## 5. 第 27 到 60 行：`_ub_read()` 是整个文件最核心的辅助函数

对应源码：

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
    command: dict[str, Any] = {
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
    if vpu_path is not None:
        command["signals"]["vpu_data_pathway"] = vpu_path
    if note:
        command["note"] = note
    return command
```

这段一定要认真看。

### 5.1 第 27 到 40 行：函数参数在表达什么

这一大串参数，其实就是在描述：

**“我要让 UB 发出一条什么样的数据流，这条数据流会走向哪里，后面要不要等它收尾。”**

每个参数的直白解释：

- `stage`
  - 这条命令属于哪个大阶段
  - 例如 `forward_layer1`

- `name`
  - 这条动作的具体名字
  - 例如 `stream_x`

- `tensor`
  - 逻辑上读的是哪个张量
  - 例如 `X`、`W1`、`B1`

- `ptr_sel`
  - 读 UB 时用哪种“读语义”
  - 它不是普通的数学值，而是硬件那边约定好的模式码

- `addr`
  - 从 UB 的哪个地址开始读

- `row`
  - 这一块读多少行

- `col`
  - 这一块读多少列

- `transpose`
  - 要不要按转置的方式去理解/输出这块数据

- `vpu_path`
  - 这条数据流如果会经过 VPU，要走哪条 VPU 路径

- `note`
  - 给人看的备注，不是给硬件看的

- `wait_after`
  - 这条命令发完之后，要不要把它当成“阶段边界”

### 5.2 第 41 到 55 行：构造命令对象

这里开始真的在“造命令”。

```python
command: dict[str, Any] = {
    "stage": stage,
    "name": name,
    "kind": "ub_read",
    "tensor": tensor,
    "signals": {...},
    "wait_after": int(wait_after),
}
```

这几项分别代表：

- `stage`
  - 把命令归类到某个阶段

- `name`
  - 方便调试和讲解

- `kind: "ub_read"`
  - 明确告诉后续流程：这是一条 UB 读命令

- `tensor`
  - 这条命令对应的软件语义对象是谁

- `signals`
  - 这是最重要的一项
  - 它已经非常接近硬件控制字段了

- `wait_after`
  - 后面 Frontend 会据此决定是否进入等待状态

### 5.3 第 46 到 53 行：`signals` 里每个字段什么意思

```python
"signals": {
    "ub_rd_start_in": 1,
    "ub_ptr_select": ptr_sel,
    "ub_rd_addr_in": addr,
    "ub_rd_row_size": row,
    "ub_rd_col_size": col,
    "ub_rd_transpose": int(transpose),
},
```

这是整个 scheduler 最像“硬件接口”的地方。

逐个看：

- `ub_rd_start_in: 1`
  - 表示“发起一次 UB 读”
  - 就像一个启动脉冲

- `ub_ptr_select: ptr_sel`
  - 告诉 UB 用哪种读口/读语义
  - 这是跟后端 RTL 强相关的字段

- `ub_rd_addr_in: addr`
  - 起始地址

- `ub_rd_row_size: row`
  - 读几行

- `ub_rd_col_size: col`
  - 读几列

- `ub_rd_transpose: int(transpose)`
  - 是否转置
  - 布尔值被转成 `0/1`

### 5.4 `ptr_sel` 可以先怎么粗理解

这份文件里没有把所有 `ptr_sel` 语义写成注释大全，但从它的使用方式，你可以先这样理解：

- `0`
  - 普通数据主流
  - 比如 `X`、`H1`、`dZ2` 之类主输入流

- `1`
  - 更偏向“顶部装载/权重侧装载”语义
  - 比如装 `W1`、装 `W2`、更新时把 tile 装到 top boundary

- `2`
  - bias 流

- `3`
  - label `Y` 流

- `4`
  - 某种专门给导数路径用的辅助流
  - 这里体现在 `H1` 符号/导数相关读流

- `5`
  - 读旧 bias，给 UB 内更新使用

- `6`
  - 读旧 weight，给 UB 内梯度下降更新使用

你现在先不用死记这些数字。
第一轮只要记住：

**`ptr_sel` 是“同样是读 UB，但我要按哪种硬件语义去读”。**

### 5.5 第 54 行：为什么要 `int(wait_after)`

```python
"wait_after": int(wait_after),
```

因为 JSON 输出里更喜欢明确的 `0/1`，而不是 Python 的 `True/False`。

另外，这也说明这个字段不是“纯文档注释”，而是会继续被后续流程消费的正式字段。

### 5.6 第 56 到 57 行：`vpu_path` 不是每条命令都有

```python
if vpu_path is not None:
    command["signals"]["vpu_data_pathway"] = vpu_path
```

这表示：

- 有些 UB 读不仅仅是“把数据拿出来”
- 它还要告诉 VPU 后面走哪条处理路径

但不是所有命令都需要这个字段，所以这里做成可选项。

### 5.7 第 58 到 59 行：`note` 是给人看的

```python
if note:
    command["note"] = note
```

这一点对小白很重要。

`note` 不是硬件控制信号。
它不会直接被拿去驱动 RTL。
它只是为了让你打开 `schedule.json` 时，知道这条命令想表达什么。

### 5.8 第 60 行：返回命令

```python
return command
```

这一行的意思是：

**把“本来只是你脑子里想象的一次读操作”，真正做成一条结构化命令。**

### 5.9 这一段你应该记住什么

看完 `_ub_read()`，你应该记住：

**scheduler 不是直接在跑硬件，它是在拼一个命令字典。这个字典已经很接近后面要送进 Frontend/IMEM 的控制信息。**

### 5.10 小白最容易误解什么

最容易误解成：

“调用 `_ub_read()` 就已经把数据从 UB 读出来了。”

不是。

这里还没有任何真实硬件动作发生。
它只是先写下一条“以后要这么做”的命令。

---

## 6. 第 63 到 72 行：`_switch()` 在做什么

对应源码：

```python
def _switch(stage: str, name: str, note: str = "") -> dict[str, Any]:
    command: dict[str, Any] = {
        "stage": stage,
        "name": name,
        "kind": "control",
        "signals": {"sys_switch_in": 1},
    }
    if note:
        command["note"] = note
    return command
```

### 6.1 它的作用

这条命令的本质是：

**发一个“切换”控制动作。**

这里最重要的字段是：

```python
"signals": {"sys_switch_in": 1}
```

它表示：

“我现在要触发系统里那个 shadow/active 的切换动作。”

### 6.2 为什么需要 `switch`

因为权重装载和权重使用通常不是同一个时刻。

典型节奏是：

1. 先把权重装进 shadow 区
2. 等它稳定
3. 再 `switch`
4. 后续计算用 active 区的权重

所以 `switch` 的存在说明这个设计不是：

“边装权重边立刻拿来算”

而是：

**“先准备好，再正式启用。”**

### 6.3 这一段你应该记住什么

**`_switch()` 表示权重或数据路径存在“预装载态”和“正式生效态”的切换。**

---

## 7. 第 75 到 84 行：`_wait()` 在做什么

对应源码：

```python
def _wait(stage: str, name: str, event: str, note: str = "") -> dict[str, Any]:
    command: dict[str, Any] = {
        "stage": stage,
        "name": name,
        "kind": "wait",
        "event": event,
    }
    if note:
        command["note"] = note
    return command
```

### 7.1 它的作用

这不是“空转”，而是：

**明确告诉系统：这里必须等某个事件发生，才能往下走。**

比如后面经常出现：

```python
_wait(..., "vpu_drain", ...)
```

意思就是：

“我不只是把命令发出去了，我还要等 VPU 尾拍真的吐干净。” 

### 7.2 为什么它重要

因为在这个系统里：

- `dispatch` 不等于真正完成
- 数据经过 PE、VPU、写回 UB 都要时间
- 如果前一个阶段尾拍还没收干净，下一个阶段就上来，会把语义搞混

所以这里的 `wait` 是阶段边界。

### 7.3 这一段你应该记住什么

**`_wait()` 代表系统同步点，不是普通占位符。**

---

## 8. 第 87 到 104 行：`_validate_current_target()` 在收什么边界

对应源码：

```python
def _validate_current_target(spec: dict[str, Any]) -> None:
    layers = spec["layers"]
    hw = spec["hardware_target"]

    if spec.get("model_type") != "mlp":
        raise ValueError(...)
    if len(layers) != 2:
        raise ValueError(...)
    if hw.get("array_width") != 2 or hw.get("lanes") != 2:
        raise ValueError(...)
    if int(spec["input_dim"]) > 2:
        raise ValueError(...)
    if int(layers[0]["out_dim"]) > 2:
        raise ValueError(...)
    if int(layers[1]["out_dim"]) > 2:
        raise ValueError(...)
    if not bool(spec.get("training", {}).get("enabled", True)):
        raise ValueError(...)
```

### 8.1 第 88 到 89 行

```python
layers = spec["layers"]
hw = spec["hardware_target"]
```

先把后面要频繁用到的部分单独拿出来。

这没有复杂逻辑，就是让后面代码更短更清楚。

### 8.2 第 91 到 92 行

```python
if spec.get("model_type") != "mlp":
    raise ValueError(...)
```

这里只支持 `mlp`。

意思不是“世界上只能做 MLP”，而是：

**当前这个 scheduler 的目标范围，明确限定在 MLP。**

### 8.3 第 93 到 94 行

```python
if len(layers) != 2:
    raise ValueError(...)
```

这里只支持两层线性层。

也就是说，这个调度器不是为了泛化各种层数，而是针对当前项目的两层 MLP 原型来写的。

### 8.4 第 95 到 96 行

```python
if hw.get("array_width") != 2 or hw.get("lanes") != 2:
    raise ValueError(...)
```

这里只支持 `2x2 / 2-lane` 原型。

这非常关键。
它说明很多后面的写法之所以简单，是因为硬件规模被定死了。

### 8.5 第 97 到 102 行

```python
if int(spec["input_dim"]) > 2:
...
if int(layers[0]["out_dim"]) > 2:
...
if int(layers[1]["out_dim"]) > 2:
...
```

这几行继续收紧维度边界。

也就是说：
- 输入维度不要超过 2
- hidden 维度不要超过 2
- 输出维度不要超过 2

这就是为什么这个 scheduler 看起来很“敢写死”。
因为它服务的就是当前这个小原型。

### 8.6 第 103 到 104 行

```python
if not bool(spec.get("training", {}).get("enabled", True)):
    raise ValueError(...)
```

这里说明：

**这个 scheduler 的目标不是推理，而是训练流程。**

所以后面才会出现：
- `dZ2`
- `dZ1`
- 更新 `W1`
- 更新 `W2`

### 8.7 这一段你应该记住什么

看完这段，你应该记住：

**这个 scheduler 非常明确地把目标钉死在“2 层 MLP + 2x2/2-lane 原型 + 训练流程”。**

这不是缺点。
这是一种工程上非常务实的做法。

### 8.8 小白最容易误解什么

最容易误解成：

“它写死这么多条件，是不是代码很差？”

不一定。

对当前这个项目来说，它是在先保正确、先把闭环打通。
不是先做一个庞大但不落地的通用编译器框架。

---

## 9. 第 107 到 108 行：`_nop()` 为什么存在

对应源码：

```python
def _nop(stage: str, name: str) -> dict[str, Any]:
    return {"stage": stage, "name": name, "kind": "nop", "signals": {}}
```

### 9.1 它不是废话

很多小白第一次看到 `nop` 会觉得：

“这不是啥都没干吗？”

在硬件节奏里不是这么看的。

`nop` 的意义是：

**给前面的装载、波前推进、shadow 准备、切换生效留时间。**

### 9.2 为什么这里重要

你后面会看到很多地方都有：

```python
for i in range(4):
    commands.append(_nop(...))
```

这表示当前调度器没有做真正精细的 cycle-accurate 延迟建模，
而是采用一种比较简单、比较保守的方式：

**固定插入若干拍空操作，确保后续动作更安全。**

### 9.3 这一段你应该记住什么

**`nop` 在这里不是无意义填充，而是“保守的时序缓冲”。**

---

## 10. 第 111 到 123 行：`build_schedule()` 开始正式干活

对应源码：

```python
def build_schedule(spec: dict[str, Any]) -> dict[str, Any]:
    _validate_current_target(spec)
    allocation = allocate_from_spec(spec)
    tensors = _tensor_map(allocation)

    batch_size = int(spec["batch_size"])
    input_dim = int(spec["input_dim"])
    hidden_dim = int(spec["layers"][0]["out_dim"])
    output_dim = int(spec["layers"][1]["out_dim"])
    tile_width = int(spec["hardware_target"]["array_width"])

    commands: list[dict[str, Any]] = []
```

### 10.1 第 112 行：先校验

```python
_validate_current_target(spec)
```

先检查这个模型规格是不是当前 scheduler 能处理的。

这一步的含义是：

**不先确认边界，后面就不要瞎生成命令。**

### 10.2 第 113 行：先做 UB 分配

```python
allocation = allocate_from_spec(spec)
```

先调用 allocator。

这一步非常关键。
因为如果你不知道：

- `W1` 在 UB 哪
- `H1` 在 UB 哪
- `dZ2` 在 UB 哪

后面所有调度命令都无从谈起。

### 10.3 第 114 行：把 allocation 变成好查的字典

```python
tensors = _tensor_map(allocation)
```

这一步前面已经讲过。
就是为了后面能直接写：

```python
tensors["W1"]["addr"]
```

### 10.4 第 116 到 120 行：把关键维度拿出来

```python
batch_size = ...
input_dim = ...
hidden_dim = ...
output_dim = ...
tile_width = ...
```

这几行的作用是：

**把后面要频繁使用的模型尺寸和硬件尺寸单独拿出来。**

其中：
- `batch_size`：一批样本有几行
- `input_dim`：输入特征维数
- `hidden_dim`：隐藏层维数
- `output_dim`：输出层维数
- `tile_width`：阵列宽度，也影响 tile 大小

### 10.5 第 122 行：准备命令列表

```python
commands: list[dict[str, Any]] = []
```

这行的意义很朴素：

**后面所有阶段命令，都会不断 append 到这个列表里。**

最终这个列表就是 `schedule.json` 里最核心的 `commands`。

### 10.6 这一段你应该记住什么

**`build_schedule()` 的开头做了三件事：先检查输入，再拿到地址，再准备命令列表。**

---

## 11. 第 124 到 177 行：第一层前向 `forward_layer1`

源码块：

```python
# Forward layer 1: H1 = act(X @ W1^T + B1)
...
```

这一段非常值得反复看。
因为它已经把整个系统的基本节奏暴露出来了。

---

### 11.1 第 124 行注释：先告诉你数学目标

```python
# Forward layer 1: H1 = act(X @ W1^T + B1)
```

这句注释很重要。

它先告诉你：

**这一整个阶段的数学目标，是生成 `H1`。**

别小看这句注释。
因为你后面看到很多命令，很容易迷失在细节里。
这句注释就是你理解这段代码的总纲。

---

### 11.2 第 125 到 137 行：先装 `W1` 到 shadow 路径

```python
commands.append(
    _ub_read(
        "forward_layer1",
        "load_w1_shadow",
        "W1",
        1,
        tensors["W1"]["addr"],
        hidden_dim,
        input_dim,
        True,
        note="Load W1^T through the top boundary into the PE shadow weight path.",
    )
)
```

逐个理解：

- `stage = "forward_layer1"`
  - 表示这条命令属于第一层前向阶段

- `name = "load_w1_shadow"`
  - 这条命令不是正式开始算，而是先把 `W1` 装进 shadow 路径

- `tensor = "W1"`
  - 读的是 `W1`

- `ptr_sel = 1`
  - 这里表示一种偏“顶部装入/权重装载”的语义

- `addr = tensors["W1"]["addr"]`
  - 从 UB 里 `W1` 对应的地址开始读

- `row = hidden_dim`
- `col = input_dim`
  - 读出的矩阵形状和 `W1` 对应

- `transpose = True`
  - 这里很关键
  - 说明为了适配当前阵列的数据流方向，这里是按 `W1^T` 的方式送进去

### 11.3 为什么不是立刻算

因为 systolic array 很多时候要先把权重预装进去，再让输入数据流进来。

所以第一步不是：

“让 `X` 进来”

而是：

**“先把 `W1` 准备好。”**

---

### 11.4 第 138 到 139 行：固定插 4 个 `nop`

```python
for i in range(4):
    commands.append(_nop("forward_layer1", f"nop_w1_load_{i}"))
```

这段的意思很简单：

“装完 `W1` 以后，我先等几拍，让它稳定。”

这里的 `4` 不是高深数学推导出来的最优值。
它更像当前版本里一个保守、可工作的经验值。

你现在要记住的是：

**当前 scheduler 不是 cycle-accurate latency model，而是用固定 `nop(4)` 先把系统跑通。**

---

### 11.5 第 140 行：切到 active

```python
commands.append(_switch("forward_layer1", "activate_w1"))
```

这一步表示：

**前面装在 shadow 的 `W1`，现在正式切成 active，后面计算会用它。**

所以到这里为止，阵列的“权重准备工作”才算完成。

---

### 11.6 第 141 到 154 行：开始送 `X`

```python
commands.append(
    _ub_read(
        "forward_layer1",
        "stream_x",
        "X",
        0,
        tensors["X"]["addr"],
        batch_size,
        input_dim,
        False,
        vpu_path="1100",
        note="Run the first layer forward path: systolic -> bias -> leaky_relu.",
    )
)
```

这一段代表：

**权重准备好了，现在开始把输入 `X` 送进系统。**

关键点：

- `ptr_sel = 0`
  - 这里是主数据流语义

- `row = batch_size`
- `col = input_dim`
  - 说明送的是一批样本的输入矩阵

- `transpose = False`
  - 输入 `X` 这边不做转置

- `vpu_path = "1100"`
  - 这说明这条数据流后面会配合某条特定 VPU 路径
  - 当前语义可以粗理解为“第一层前向：matmul 后接 bias 和激活”

### 11.7 为什么 `X` 和 `W1` 是分两步

因为这套架构里：

- `W1` 更像先装到阵列内部的权重侧
- `X` 更像后面流进去的输入激活侧

这也是为什么你看到的流程是：

1. 先 `load_w1_shadow`
2. 再 `switch`
3. 最后 `stream_x`

---

### 11.8 第 155 到 169 行：再送 `B1`

```python
commands.append(
    _ub_read(
        "forward_layer1",
        "stream_b1",
        "B1",
        2,
        tensors["B1"]["addr"],
        batch_size,
        hidden_dim,
        False,
        vpu_path="1100",
        wait_after=True,
        note="Bias stream for layer 1. VPU writeback is expected to append H1 to UB.",
    )
)
```

这一步非常关键。

它在做的是：

**把 `B1` 作为 bias 流送进去，让 VPU 完成 bias 加法和激活，并把结果 `H1` 写回 UB。**

为什么这里要单独送 `B1`？

因为：
- systolic 主要负责矩阵乘
- bias 和激活更适合在 VPU 路径里做

所以第一层前向不是只有一条数据流，而是几部分协同：

1. `W1` 准备好
2. `X` 经过阵列做主乘法
3. `B1` 进入 VPU 参与 bias + activation
4. 结果写回 UB 形成 `H1`

### 11.9 为什么这里 `wait_after=True`

因为这条命令之后，阶段边界很重要。

这时不是只要“命令发出去了”就算完。
而是要等：

**VPU 尾拍真的吐干净，并且 `H1` 真写回 UB。**

---

### 11.10 第 170 到 177 行：等 `vpu_drain`

```python
commands.append(
    _wait(
        "forward_layer1",
        "wait_h1_writeback",
        "vpu_drain",
        note="H1 should now be available in the UB activation region.",
    )
)
```

这一步就是在说：

**“我现在不急着进入下一阶段，我先等 `H1` 真正落到 UB 里。”**

这里的 `vpu_drain` 你先粗理解成：

“VPU 这波流水尾拍彻底吐完。”

为什么要等？

因为下一阶段要用 `H1`。
如果还没写回完就进入下一阶段，后面读到的就可能不是完整正确的 `H1`。

---

### 11.11 这一整个阶段你应该记住什么

`forward_layer1` 的真实节奏是：

1. 先把 `W1` 装到 shadow
2. 等几拍
3. 切到 active
4. 送 `X`
5. 送 `B1`
6. 等 VPU 把 `H1` 真正写回 UB

你把这一段看懂，后面很多段都会好理解很多。

---

## 12. 第 179 到 259 行：第二层前向加过渡 `transition_layer2`

源码注释：

```python
# Layer 2 forward + transition: dZ2 comes out directly from the 1111 path.
```

这句注释已经非常关键了。
它告诉你：

**这一阶段不只是做第二层前向，它还顺便把后面反向会用到的 `dZ2` 给弄出来。**

---

### 12.1 第 180 到 191 行：先装 `W2`

逻辑和第一层很像：

```python
load_w2_shadow
```

意思就是：

1. 先从 UB 把 `W2` 读出来
2. 按权重装载语义送入阵列
3. 暂时放在 shadow

这里 `transpose=True`，说明这也是按适合当前阵列方向的转置方式去送。

---

### 12.2 第 193 到 195 行：继续保守地等 4 拍，然后 `switch`

还是同一个节奏：

1. 装权重
2. `nop(4)`
3. `activate_w2`

你会发现这个文件的一个重要风格就是：

**凡是需要切换到新的权重工作集，都会走“装载 -> 稳定 -> 切换”这一套固定节奏。**

---

### 12.3 第 196 到 209 行：送 `H1`

```python
stream_h1
```

这是第二层前向的主输入。

也就是说，上一阶段算出来并写回 UB 的 `H1`，现在被拿出来当作下一层输入。

这里 `vpu_path="1111"`，表示这条路径不是第一层的前向路径了，而是第二层前向加 loss/gradient 相关路径。

---

### 12.4 第 210 到 221 行：送 `B2`

```python
stream_b2
```

和前面 `B1` 的角色类似，它是第二层的 bias。

这再次说明：

**矩阵乘和 bias/激活/损失相关操作，在这个系统里是分工协作的，不是全都在同一个模块里完成。**

---

### 12.5 第 223 到 235 行：送 `Y`

```python
stream_y
```

这一步很容易让小白疑惑：

“为什么前向阶段突然要送 label `Y`？”

因为这个阶段已经不是单纯“算 `H2`”了。
它同时还要为 loss 和梯度准备输入。

所以 `Y` 会被送入后级逻辑，让系统在这一阶段里直接产生训练要用的 `dZ2`。

源码里的 `note` 写得很清楚：

```python
Loss module consumes Y while H2 stays transient in the VPU pipeline.
```

意思是：

- `Y` 会被 loss 模块消费
- `H2` 不一定要完整落地成一个长期存放的 UB tensor
- 它更多是作为 VPU 管线里的中间态参与 loss/gradient 计算

---

### 12.6 第 237 到 250 行：加载旧 `B2`

```python
load_old_b2
```

这步是当前项目里很有工程味的一步。

它不是在做第二层主前向，而是在准备：

**一边让 `dZ2` 往外流，一边让 UB 内部做 bias 的原地更新。**

这里 `ptr_sel = 5`，说明它不再是普通主数据流，而是“读旧 bias 给更新路径用”的特殊语义。

### 12.7 为什么它也有 `wait_after=True`

因为这一步后面牵涉两个东西同时收尾：

1. `dZ2` 要真正稳定写回 UB
2. `B2` 的原地更新要完成

所以这里不能发完就立刻往下走。

---

### 12.8 第 252 到 259 行：等待 `dZ2` 写回完成

```python
wait_dz2_writeback
```

这一步本质是在说：

**“现在第二层的 forward/loss/gradient 这组动作已经发出去了，但我要等它们全部真正收尾。”**

等完之后，系统认为：

- `dZ2` 已经可用了
- `B2` 已经更新好了

这样下一阶段 backward 才有安全的输入基础。

---

### 12.9 这一整个阶段你应该记住什么

`transition_layer2` 的重点不是单纯“第二层前向”。

而是：

**第二层前向、loss、`dZ2` 生成、`B2` 更新被揉在了同一组阶段命令里。**

这就是训练闭环味道很强的地方。

---

## 13. 第 261 到 328 行：第一层反向 `backward_layer1`

源码注释：

```python
# Backward layer 1: dZ1 = act'(dZ2 @ W2, H1)
```

这里的数学目标是：

**生成 `dZ1`。**

也就是把第二层传回来的梯度继续往前传。

---

### 13.1 第 262 到 273 行：重新装 `W2`，但这次是 backward 用法

```python
load_w2_backward
```

这里特别要注意：

```python
transpose = False
```

为什么前面装 `W2` 是 `True`，这里又是 `False`？

因为 forward 和 backward 的矩阵乘语义不一样。

前向时，为了适配当前阵列路径，需要按一种方向送；
反向时，`dZ2 @ W2` 的使用方式又变了，所以这里明确写了：

```python
note="Backward uses W2 without transpose."
```

这告诉你：

**同一个权重张量，在不同阶段、不同数学语义下，送给阵列的方向可以不同。**

---

### 13.2 第 275 到 277 行：还是 `nop(4)` 再 `switch`

又是一模一样的节奏：

1. 装进去
2. 等几拍
3. 切生效

你应该开始形成一个稳定印象：

**这个 scheduler 在“准备权重工作集”这件事上，采用的是非常固定而保守的模板。**

---

### 13.3 第 278 到 291 行：先加载旧 `B1`

```python
load_old_b1
```

这一步的意义是：

**在真正的导数主数据流开始之前，先把 `B1` 的更新路径准备好。**

这里：
- `ptr_sel = 5`
- `vpu_path = "0001"`

说明当前这条路径不是普通前向，而是在为 backward 相关的导数和更新路径服务。

---

### 13.4 第 292 到 305 行：送 `dZ2`

```python
stream_dz2
```

这一条就是反向传播的主梯度输入流。

为什么是 `dZ2`？

因为第二层已经把误差梯度算出来了，
现在要继续往第一层方向传播，所以自然要把 `dZ2` 喂给系统。

源码里的 `note` 说：

```python
Run the derivative-only VPU path for layer 1 backward propagation.
```

你可以把它理解成：

**这一阶段主要是在做“第一层的反向导数传播”。**

---

### 13.5 第 306 到 320 行：再送 `H1` 作为导数参考

```python
stream_h1_for_derivative
```

这里为什么还要送 `H1`？

因为第一层用过激活函数。
反向时要算激活函数的导数，通常需要知道前向时激活值的符号或状态。

所以这一步的作用是：

**把 `H1` 重新拿出来，给激活导数路径当参考。**

这里用的是：

- `ptr_sel = 4`
- `vpu_path = "0001"`

这说明它是比普通主流更特殊的一种辅助导数输入流。

源码的 `note` 也写得很直白：

```python
Start the H1 sign stream immediately after dH1 so the derivative stage sees aligned activations while B1 is already armed.
```

你先不用死抠里面每个词。
只要记住：

**为了正确做第一层激活的反向导数，系统不只要 `dZ2`，还要参考 `H1`。**

### 13.6 为什么这里也 `wait_after=True`

因为这一步结束后，`dZ1` 需要真正产生并写回 UB。

如果不等，就可能出现：
- `dZ1` 还没写完
- 后面的更新阶段就开始读

那就会错。

---

### 13.7 第 321 到 328 行：等待 `dZ1` 写回完成

```python
wait_dz1_writeback
```

这一步在系统语义上表示：

**“到这里为止，第一层反向传播才算真的结束。”**

收尾后，系统应该满足：

- `dZ1` 在 UB 里可用
- `B1` 更新已经到位

这样下一组权重更新阶段才有基础。

---

### 13.8 这一整个阶段你应该记住什么

`backward_layer1` 的核心不是一句“反向传播”就完了。

它实际做的是：

1. 重新配置 `W2` 的 backward 使用方式
2. 送入 `dZ2`
3. 补送 `H1` 做激活导数参考
4. 同时推进 `B1` 更新
5. 等到 `dZ1` 真正写回 UB

---

## 14. 第 330 到 380 行：更新 `W1`

源码注释：

```python
# Weight update for W1: dW1 = dZ1^T @ X
```

这里进入的是参数更新阶段。

---

### 14.1 第 331 行：按 tile 遍历 batch

```python
for tile_index, (tile_start, tile_rows) in enumerate(_tile_ranges(batch_size, tile_width)):
```

这行的意思是：

**把整个 batch 切成若干 tile，一块一块处理。**

为什么要这样做？

因为阵列大小有限，不一定能一次吞下所有 batch 行。

即便当前这个例子里 batch 很小，这里也提前写成 tile 化逻辑，说明作者在结构上已经考虑了“按块更新”。

---

### 14.2 第 332 到 333 行：算 tile 在 UB 里的起始地址

```python
x_addr = tensors["X"]["addr"] + tile_start * input_dim
dz1_addr = tensors["dZ1"]["addr"] + tile_start * hidden_dim
```

这两行很好理解：

- `X` 每行长度是 `input_dim`
- `dZ1` 每行长度是 `hidden_dim`

如果当前 tile 从第 `tile_start` 行开始，
那它在 UB 里的地址就要往后偏移：

- `tile_start * input_dim`
- `tile_start * hidden_dim`

所以这两行是在算“当前 tile 的地址窗口”。

---

### 14.3 第 334 行：给每个 tile 起一个 stage 名

```python
stage = f"update_w1_tile_{tile_index}"
```

这表示：

**每个 tile 虽然都是更新 `W1`，但在 schedule 里会被记录成不同的小阶段。**

这样调试的时候更清楚。

---

### 14.4 第 335 到 347 行：把 `X` tile 送到顶部

```python
load_x_tile_to_top
```

这一步是把当前 tile 的 `X` 当成外积的一边，送入阵列顶部。

这里：
- `ptr_sel = 1`
- `transpose = False`

说明它按“顶部输入侧”的语义送入。

源码 `note` 也写得很清楚：

```python
Use the top boundary as one side of the outer-product update tile.
```

---

### 14.5 第 348 到 350 行：还是等 4 拍再切

依然是熟悉的模板：

1. 装一边
2. 等几拍
3. 激活

这再次说明当前 scheduler 在时序建模上仍然偏保守模板化。

---

### 14.6 第 351 到 364 行：把 `dZ1` tile 以转置方式送入

```python
load_dz1_tile_transposed
```

这里的数学目标是：

```text
dW1 = dZ1^T @ X
```

所以你看到：

- 读的是 `dZ1`
- `transpose = True`

这正好对应外积更新里的矩阵方向要求。

源码 `note` 里写的是：

```python
Pure systolic outer-product tile for dW1.
```

意思是：

**这一块主要是让 systolic array 负责外积更新的核心乘加。**

---

### 14.7 第 365 到 379 行：把旧 `W1` 读出来给 UB 内更新用

```python
load_old_w1
```

这一条很重要。

它说明这个系统的权重更新不是只算出一个梯度矩阵就结束，
而是还要做：

**旧权重 + 梯度 -> 新权重**

这里：
- `ptr_sel = 6`
- `tensor = "W1"`
- `wait_after = True`

表达的是：

**把旧 `W1` 拿出来，交给 UB 内部的 gradient descent/update 路径做原地更新。**

为什么地址没有像 `X` 和 `dZ1` 那样随着 tile 变化？

因为：

- `X` 和 `dZ1` 是按 batch tile 切块取样本
- `W1` 是同一份全局参数矩阵

每个 tile 都是在拿一部分样本贡献去更新同一份 `W1`。

---

### 14.8 第 380 行：等待 `W1` 更新完成

```python
commands.append(_wait(stage, "wait_w1_update", "vpu_drain"))
```

这一步是当前 tile 的收尾。

意思是：

**等这个 tile 对 `W1` 的更新真正完成，再处理下一个 tile 或下一阶段。**

---

### 14.9 这一整个阶段你应该记住什么

更新 `W1` 的基本节奏是：

1. 从 batch 里切一块样本
2. 取出对应的 `X` tile
3. 取出对应的 `dZ1` tile
4. 用 systolic 做外积
5. 再拿旧 `W1` 做原地梯度更新
6. 等更新完成

---

## 15. 第 382 到 432 行：更新 `W2`

源码注释：

```python
# Weight update for W2: dW2 = dZ2^T @ H1
```

这一段和更新 `W1` 的结构几乎平行。

这很好。
因为一旦你理解了 `W1` 更新，这段就不是全新世界了。

---

### 15.1 第 383 行：还是按 tile 遍历

```python
for tile_index, (tile_start, tile_rows) in enumerate(_tile_ranges(batch_size, tile_width)):
```

完全同样的思路：

**按 batch 维度切 tile。**

---

### 15.2 第 384 到 385 行：算 `H1` 和 `dZ2` 的 tile 地址

```python
h1_addr = tensors["H1"]["addr"] + tile_start * hidden_dim
dz2_addr = tensors["dZ2"]["addr"] + tile_start * output_dim
```

也是同样逻辑：

- `H1` 每行宽度是 `hidden_dim`
- `dZ2` 每行宽度是 `output_dim`

所以 tile 地址就要按行偏移。

---

### 15.3 第 387 到 398 行：把 `H1` tile 送到顶部

```python
load_h1_tile_to_top
```

这里的意义和 `load_x_tile_to_top` 对称：

**更新 `W2` 时，外积的一边由 `H1` tile 提供。**

---

### 15.4 第 400 到 402 行：`nop(4)` 再 `switch`

还是同样节奏。
这已经可以视为这个 scheduler 的模板化写法。

---

### 15.5 第 403 到 416 行：把 `dZ2` tile 转置送入

```python
load_dz2_tile_transposed
```

对应数学式：

```text
dW2 = dZ2^T @ H1
```

所以：
- 读 `dZ2`
- `transpose = True`

这和上面 `dW1 = dZ1^T @ X` 是完全平行的结构。

---

### 15.6 第 417 到 431 行：读取旧 `W2`

```python
load_old_w2
```

和 `load_old_w1` 一个道理。

它不是在重新给阵列送主输入，
而是在为 UB 内的参数更新路径准备旧权重值。

这里同样：
- `ptr_sel = 6`
- `wait_after = True`

说明这是“读旧 weight 给更新逻辑”的语义。

---

### 15.7 第 432 行：等待 `W2` 更新完成

```python
commands.append(_wait(stage, "wait_w2_update", "vpu_drain"))
```

这就是一个 tile 的结束点。

---

### 15.8 这一整个阶段你应该记住什么

更新 `W2` 和更新 `W1` 本质一样，只是参与外积的张量换成了：

- `dZ2`
- `H1`

你可以把这两段一起看成：

**“训练阶段最后的参数更新模板”。**

---

## 16. 第 434 到 443 行：`host_load_plan` 在干什么

对应源码：

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

### 16.1 这段的作用

这段不是给阵列看的。
它是给 host 侧看的。

意思是：

**在真正启动 TPU 之前，主机应该先把哪些 tensor 装进 UB。**

### 16.2 为什么只选这些角色

筛选条件是：

- `storage == "ub"`
- `role in {"input", "label", "weight", "bias"}`

也就是说，host 预装载的主要是：

- 输入 `X`
- 标签 `Y`
- 权重 `W1/W2`
- bias `B1/B2`

为什么没有：
- `H1`
- `dZ2`
- `dZ1`

因为这些不是 host 一开始就有的静态输入，
而是运行过程中由硬件逐步产生出来的中间结果。

### 16.3 这一段你应该记住什么

**schedule 不只描述“TPU 执行什么”，也描述“Host 开始前要准备什么”。**

---

## 17. 第 445 到 457 行：最终返回的 schedule 长什么样

对应源码：

```python
return {
    "scheduler_version": "0.1",
    "spec_name": spec["name"],
    "target": "tiny-tpu-2x2-stage-schedule",
    "assumptions": [...],
    "host_load_plan": host_load_plan,
    "ub_allocation": allocation,
    "commands": commands,
}
```

### 17.1 每个字段什么意思

- `scheduler_version`
  - 当前调度器版本号

- `spec_name`
  - 这份 schedule 对应哪个模型规格

- `target`
  - 目标平台说明

- `assumptions`
  - 很重要
  - 这里明确写出当前实现的假设和限制

- `host_load_plan`
  - 主机预装载计划

- `ub_allocation`
  - UB 地址分配结果

- `commands`
  - 核心中的核心
  - 真正的阶段命令列表

### 17.2 为什么 `assumptions` 重要

里面有一句很关键：

```python
"command list is stage-level and not a cycle-accurate waveform program yet"
```

这句是在主动承认：

**当前输出的是阶段级命令，不是逐拍波形程序。**

这不是缺点描述。
这是对当前设计定位的诚实说明。

### 17.3 这一段你应该记住什么

**`build_schedule()` 的产物不是单独一个命令，而是一整份调度说明书：包括主机怎么装、UB 怎么分、每个阶段发什么命令。**

---

## 18. 第 460 到 491 行：命令行入口

对应源码：

```python
def _build_arg_parser() -> argparse.ArgumentParser:
    ...

def main() -> int:
    ...

if __name__ == "__main__":
    raise SystemExit(main())
```

### 18.1 `_build_arg_parser()`

这里定义了命令行怎么用这个脚本。

核心参数：

- `spec`
  - 模型规格 JSON 路径

- `-o / --output`
  - 可选输出路径

### 18.2 `main()`

这里做的事是：

1. 解析参数
2. 读 spec
3. 调 `build_schedule(spec)`
4. 把结果转成 JSON 字符串
5. 要么写文件，要么直接打印到标准输出

这是一个非常标准的脚本入口流程。

### 18.3 最后一段

```python
if __name__ == "__main__":
    raise SystemExit(main())
```

表示：

如果这个文件是直接运行的，就执行 `main()`。

---

## 19. 把整个文件连起来，再说一遍

如果你现在已经把上面全部看完了，可以用这条主线重新理解 `scheduler.py`：

1. 先读模型规格 `spec`
2. 检查这个规格是不是当前原型支持的范围
3. 先做 UB 地址分配
4. 把 tensor 地址整理成方便查询的字典
5. 按训练流程，逐阶段往 `commands` 里塞命令
6. 同时生成 host 预装载计划
7. 最后输出成一份 `schedule.json`

所以它做的不是：

- 自动求导
- RTL 仿真
- 每拍驱动波形

它做的是：

**把训练流程翻译成一份“硬件接下来该怎么一步一步跑”的阶段级脚本。**

---

## 20. 这个文件和后面几个文件怎么接上

你看完 `scheduler.py` 后，应该知道它不是终点。
它只是中间一环。

后面的关系是：

1. `scheduler.py`
   - 生成 `schedule.json`
2. `encode_instrs.py`
   - 把这些阶段命令编码成更靠近 `IMEM` 的格式
3. `control_unit.sv`
   - 解析指令字段
4. `tpu_frontend_axil.sv`
   - 按顺序 dispatch，必要时 `wait`
5. `tpu.sv`
   - 把 UB、systolic、VPU 这些模块接起来执行

也就是说：

**`scheduler.py` 是软件侧“安排流程”的起点。**

---

## 21. 小白脑图式总结

最后用最简单的话，把这份文件再压一遍。

### 21.1 输入是什么

- 一个模型规格 JSON
- 里面包含：
  - 输入维度
  - 两层 MLP 结构
  - batch 大小
  - 硬件目标参数

### 21.2 中间做了什么

1. 检查规格是否合法
2. 给 tensor 分配 UB 地址
3. 按训练流程生成阶段命令
4. 给主机生成预装载计划

### 21.3 输出是什么

一份 schedule 字典，里面有：

- `ub_allocation`
- `host_load_plan`
- `commands`

### 21.4 它真正解决了什么问题

它解决的是：

**“软件世界里的一次两层 MLP 训练流程，怎么被拆成硬件世界里一条一条可执行的阶段命令。”**

### 21.5 你现在最该记住的一句话

**`scheduler.py` 不是在算结果，它是在安排‘谁先做、谁后做、什么时候等、什么时候切换、什么时候更新’。**

---

## 22. 你看完这份后，下一步应该看什么

建议顺序：

1. 先再回头扫一眼  
   `/home/jjt/tpu-soc/code_reading_sources_20260409/13_mlp_2_2_1_q8_8.schedule.json`

2. 然后去看  
   `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/03_ub_allocator.py_guide_zh.md`

3. 如果你还想继续按“小白版”深挖，下一个最适合这样重写的文件是：
   - `ub_allocator.py`
   - 然后是 `encode_instrs.py`

如果你继续，我下一份最值的是给你做：

**`03_ub_allocator.py` 的同风格小白逐段细讲版。**
