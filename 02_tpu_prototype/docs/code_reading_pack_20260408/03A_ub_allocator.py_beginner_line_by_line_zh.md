# `ub_allocator.py` 小白版逐段细讲

对应源码：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/02_ub_allocator.py`

原版讲解：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/03_ub_allocator.py_guide_zh.md`

配套输出示例：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/14_mlp_2_2_1_q8_8.ub_map.json`

这份文档是给小白看的。
你可以把它当成 `ub_allocator.py` 的“边看代码边解释”版本。

先给一句总定义：

**`ub_allocator.py` 的任务不是调度计算，而是先把训练过程中要用到的张量，落到 UB 里的具体地址。**

---

## 0. 先记住 5 句话

1. `ub_allocator.py` 不负责控制 TPU 什么时候算。
2. `ub_allocator.py` 不负责生成 IMEM 指令。
3. 它负责回答“有哪些 tensor”和“这些 tensor 放在 UB 哪里”。
4. 后面的 `scheduler.py` 会依赖这里生成的地址。
5. 所以它是软件到硬件链路里的“地址起点”。

如果你只记一句话，就记：

**allocator 先决定东西放哪，scheduler 再决定什么时候读这些东西。**

---

## 1. 建议你怎么打开

左边打开源码：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/02_ub_allocator.py`

右边打开这篇文档：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/03A_ub_allocator.py_beginner_line_by_line_zh.md`

再顺手打开输出结果：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/14_mlp_2_2_1_q8_8.ub_map.json`

这三个文件一起看，你会更容易理解。

阅读时先不要纠结 Python 语法细节。
第一轮只回答一个问题：

**“这个 tensor 为什么要存在，它为什么要放在 UB 或者不放在 UB？”**

---

## 2. 第 1 到 8 行：文件开头在准备工具

对应源码：

```python
1  #!/usr/bin/env python3
2  from __future__ import annotations
4  import argparse
5  import json
6  from dataclasses import asdict, dataclass, replace
7  from pathlib import Path
8  from typing import Any
```

### 2.1 第 1 行

```python
#!/usr/bin/env python3
```

这行表示这个文件可以作为 Python 脚本直接运行。
你现在不用重点看它。
它不是 allocator 的核心逻辑。

### 2.2 第 2 行

```python
from __future__ import annotations
```

这行是 Python 类型标注相关的兼容写法。
它不会影响 UB 地址怎么分配。

### 2.3 第 4 到 8 行

```python
import argparse
import json
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Any
```

这些是后面会用到的工具。

逐个解释：

- `argparse`
  - 让这个脚本支持命令行参数
  - 比如传入 spec 文件路径和输出路径

- `json`
  - 读取模型 spec
  - 输出 UB map JSON

- `dataclass`
  - 用来定义 `TensorSpec`
  - 让每个 tensor 的信息结构更清楚

- `asdict`
  - 把 dataclass 对象转成普通 dict
  - 方便最后输出 JSON

- `replace`
  - 复制一个 dataclass 对象并修改其中字段
  - 后面分配地址时会用到

- `Path`
  - 处理文件路径

- `Any`
  - 类型标注用，不是业务逻辑

### 2.4 这一段你应该记住什么

**开头这些 import 是工具准备。真正和 UB 地址分配直接相关的，是 `dataclass/asdict/replace/json` 这几项。**

---

## 3. 第 11 到 19 行：`TensorSpec` 定义一个 tensor 应该有哪些信息

对应源码：

```python
@dataclass
class TensorSpec:
    name: str
    role: str
    shape: list[int]
    words: int
    storage: str
    addr: int | None
    dtype: str
```

### 3.1 `@dataclass` 是什么

`@dataclass` 可以先粗理解成：

**帮你快速定义一种“数据表格里的行”。**

这里每一个 `TensorSpec` 对象，就代表一个 tensor 的记录。

比如最后输出的 `ub_map.json` 里会有：

```json
{
  "name": "X",
  "role": "input",
  "shape": [4, 2],
  "words": 8,
  "storage": "ub",
  "addr": 0,
  "dtype": "Q8.8"
}
```

这就是一个 `TensorSpec` 最后转成 JSON 后的样子。

### 3.2 `name`

```python
name: str
```

`name` 是 tensor 名字。

例子：
- `X`
- `Y`
- `W1`
- `B1`
- `H1`
- `dZ2`

你可以把它理解成“逻辑名字”。

### 3.3 `role`

```python
role: str
```

`role` 是 tensor 的角色。

例子：
- `input`：输入
- `label`：标签
- `weight`：权重
- `bias`：偏置
- `activation`：激活
- `gradient_activation`：激活梯度
- `gradient_hidden`：隐藏梯度

`name` 是“它叫什么”，`role` 是“它干什么”。

### 3.4 `shape`

```python
shape: list[int]
```

`shape` 是形状。

比如：
- `X` 是 `[4, 2]`
  - 表示 4 个样本，每个样本 2 个输入特征
- `W1` 是 `[2, 2]`
  - 表示第一层 2 个输出，每个输出连接 2 个输入
- `B2` 是 `[1]`
  - 表示第二层 1 个 bias

### 3.5 `words`

```python
words: int
```

`words` 是这个 tensor 要占多少个 UB word。

例子：
- shape `[4, 2]`，就是 `4 * 2 = 8` 个 word
- shape `[2, 2]`，就是 `2 * 2 = 4` 个 word
- shape `[1]`，就是 `1` 个 word

### 3.6 `storage`

```python
storage: str
```

`storage` 表示这个 tensor 存不存到 UB。

当前主要有两类：

- `ub`
  - 会真正分配 UB 地址
  - 后面可以被 scheduler 从 UB 里读出来

- `ephemeral`
  - 临时中间值
  - 不给它分配长期 UB 地址
  - 可能只在流水线里短暂经过

这个字段非常重要。
后面你会看到 `H1` 是 `ub`，但 `H2` 是 `ephemeral`。

### 3.7 `addr`

```python
addr: int | None
```

`addr` 是 UB 地址。

如果 `storage == "ub"`，后面会分配一个整数地址。
比如：
- `X` 地址是 `0`
- `Y` 地址是 `8`
- `W1` 地址是 `12`

如果 `storage == "ephemeral"`，地址就是 `None`，输出到 JSON 里就是 `null`。

### 3.8 `dtype`

```python
dtype: str
```

`dtype` 是数据格式。
当前例子里是 `Q8.8`。

你可以先理解成：

**16-bit 定点数，其中 8 位是小数部分。**

### 3.9 这一段你应该记住什么

**`TensorSpec` 是 allocator 的基本记录单位。它不是数据本身，而是“这个 tensor 在系统里的元信息”。**

---

## 4. 第 22 到 26 行：`_product()` 用来算 tensor 占多少 word

对应源码：

```python
def _product(shape: list[int]) -> int:
    total = 1
    for dim in shape:
        total *= dim
    return total
```

### 4.1 这一段在做什么

它把 shape 里的数字乘起来。

比如：

```python
_product([4, 2])
```

结果是：

```text
8
```

因为 `4 * 2 = 8`。

### 4.2 为什么需要它

因为 allocator 要知道每个 tensor 占多少 UB word。

比如：
- `X` shape 是 `[4, 2]`，占 `8` 个 word
- `W1` shape 是 `[2, 2]`，占 `4` 个 word
- `B2` shape 是 `[1]`，占 `1` 个 word

### 4.3 当前代码里为什么很多地方没用 `_product()`

你会发现后面有些地方直接写：

```python
words=batch_size * input_dim
```

而不是调用 `_product()`。

这说明当前版本里 `_product()` 更像一个准备好的通用工具，但在这份小模型 allocator 里很多 shape 很简单，所以直接写乘法也足够清楚。

### 4.4 这一段你应该记住什么

**UB 分配必须先知道每个 tensor 的大小，`_product()` 就是用 shape 算大小的工具。**

---

## 5. 第 29 到 33 行：`_dtype_tag()` 把数据格式变成字符串

对应源码：

```python
def _dtype_tag(data_format: dict[str, Any]) -> str:
    width = int(data_format["width_bits"])
    frac = int(data_format["frac_bits"])
    int_bits = width - frac
    return f"Q{int_bits}.{frac}"
```

### 5.1 第 30 行

```python
width = int(data_format["width_bits"])
```

从 spec 里取总位宽。

当前例子里：

```json
"width_bits": 16
```

所以 `width = 16`。

### 5.2 第 31 行

```python
frac = int(data_format["frac_bits"])
```

从 spec 里取小数位数。

当前例子里：

```json
"frac_bits": 8
```

所以 `frac = 8`。

### 5.3 第 32 行

```python
int_bits = width - frac
```

整数位数 = 总位宽 - 小数位数。

当前例子：

```text
16 - 8 = 8
```

所以整数部分是 8 位。

### 5.4 第 33 行

```python
return f"Q{int_bits}.{frac}"
```

返回字符串。

当前例子就会返回：

```text
Q8.8
```

### 5.5 这一段你应该记住什么

**`_dtype_tag()` 只是把 spec 里的定点格式，整理成人更容易看的 `Q8.8` 这种标签。**

它不改变数据。
它只是生成说明字段。

---

## 6. 第 36 到 47 行：`load_spec()` 读取并检查模型规格

对应源码：

```python
def load_spec(path: str | Path) -> dict[str, Any]:
    spec_path = Path(path)
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    if spec.get("model_type") != "mlp":
        raise ValueError(...)
    if "layers" not in spec or not spec["layers"]:
        raise ValueError("spec must contain at least one layer")
    if "hardware_target" not in spec:
        raise ValueError("spec must contain hardware_target")
    if "data_format" not in spec:
        raise ValueError("spec must contain data_format")
    return spec
```

### 6.1 第 37 行

```python
spec_path = Path(path)
```

把传进来的路径变成 `Path` 对象。

这样后面读文件更方便。

### 6.2 第 38 行

```python
spec = json.loads(spec_path.read_text(encoding="utf-8"))
```

这一行做了两件事：

1. 读文本文件
2. 把 JSON 文本转成 Python 字典

也就是说，模型规格从文件里进来了。

### 6.3 第 39 到 40 行

```python
if spec.get("model_type") != "mlp":
    raise ValueError(...)
```

这里只允许 `model_type` 是 `mlp`。

这说明当前 allocator 不是泛化支持 CNN、Transformer 等任意模型。
它就是服务当前 tiny-tpu 项目的 MLP 原型。

### 6.4 第 41 到 42 行

```python
if "layers" not in spec or not spec["layers"]:
    raise ValueError("spec must contain at least one layer")
```

必须有 `layers`，而且不能为空。

因为 allocator 要从 layers 里推导：
- 有几层
- 每层输出维度是多少
- 需要哪些 `W/B/H/dZ` tensor

没有 layers，后面就没法推导 tensor catalog。

### 6.5 第 43 到 44 行

```python
if "hardware_target" not in spec:
    raise ValueError("spec must contain hardware_target")
```

必须有硬件目标。

因为 allocator 要知道：
- UB 深度是多少
- 后面能不能放得下所有 tensor

### 6.6 第 45 到 46 行

```python
if "data_format" not in spec:
    raise ValueError("spec must contain data_format")
```

必须有数据格式。

因为每个 tensor 的 `dtype` 都要从这里推出来。

### 6.7 第 47 行

```python
return spec
```

检查通过后，把 spec 返回给后续函数。

### 6.8 这一段你应该记住什么

**`load_spec()` 不是只读文件，它还在确认这份模型规格至少包含 allocator 必需的字段。**

---

## 7. 第 50 到 158 行：`infer_tensor_catalog()` 是这个文件的核心

对应源码开头：

```python
def infer_tensor_catalog(spec: dict[str, Any]) -> list[TensorSpec]:
```

这个函数的任务是：

**根据模型规格，推导训练过程中会出现哪些 tensor。**

注意：

这里还没有真正分配地址。
这里只是在列清单。

你可以把它想成：

> 先列购物清单，再去仓库给每件东西安排货架位置。

这里的“购物清单”就是 tensor catalog。

---

## 8. 第 51 到 57 行：先从 spec 里拿基本信息

对应源码：

```python
layers = spec["layers"]
batch_size = int(spec["batch_size"])
input_dim = int(spec["input_dim"])
dtype = _dtype_tag(spec["data_format"])
training_enabled = bool(spec.get("training", {}).get("enabled", True))
persist_output_activation = bool(spec.get("persist_output_activation", False))
```

### 8.1 `layers`

```python
layers = spec["layers"]
```

取出模型层列表。

当前项目里是两层 MLP，所以大概可以理解成：
- 第一层：输入到隐藏层
- 第二层：隐藏层到输出层

### 8.2 `batch_size`

```python
batch_size = int(spec["batch_size"])
```

取 batch 大小。

当前输出里 `X` 是 `[4, 2]`，说明 batch 是 `4`。

### 8.3 `input_dim`

```python
input_dim = int(spec["input_dim"])
```

取输入维度。

当前项目里 `input_dim = 2`，所以 `X` 的 shape 是 `[4, 2]`。

### 8.4 `dtype`

```python
dtype = _dtype_tag(spec["data_format"])
```

把数据格式转成 `Q8.8` 这样的字符串。

### 8.5 `training_enabled`

```python
training_enabled = bool(spec.get("training", {}).get("enabled", True))
```

判断是否启用训练。

如果训练启用，后面就会生成梯度相关 tensor，比如：
- `dZ2`
- `dH1`
- `dZ1`

如果只是推理，这些梯度 tensor 就不一定需要。

### 8.6 `persist_output_activation`

```python
persist_output_activation = bool(spec.get("persist_output_activation", False))
```

这个字段决定最后一层 activation 要不要长期落到 UB 里。

当前默认是 `False`。

所以你会看到输出里：

```json
"name": "H2",
"storage": "ephemeral",
"addr": null
```

意思是：

**最后输出激活 `H2` 不作为长期 UB tensor 保存，它只是流水线里的临时值。**

### 8.7 这一段你应该记住什么

**`infer_tensor_catalog()` 一开始先拿模型尺寸、数据格式、训练开关和输出激活保存策略。后面所有 tensor 都是从这些信息推出来的。**

---

## 9. 第 58 到 60 行：准备 tensor 列表和最终输出维度

对应源码：

```python
tensors: list[TensorSpec] = []
output_dim = int(layers[-1]["out_dim"])
```

### 9.1 `tensors = []`

这是一个空列表。

后面每推导出一个 tensor，就 `append` 到这个列表里。

最后这个列表会包含：
- `X`
- `Y`
- `W1/B1/W2/B2`
- `H1/H2`
- `dZ2/dH1/dZ1`

### 9.2 `output_dim`

```python
output_dim = int(layers[-1]["out_dim"])
```

取最后一层的输出维度。

为什么用 `layers[-1]`？

因为 Python 里 `-1` 表示最后一个元素。

当前模型最后一层输出维度是 `1`，所以：

```text
output_dim = 1
```

这会影响 `Y` 的 shape。

### 9.3 这一段你应该记住什么

**这两行是在准备容器和最终输出维度。后面开始真正往 tensor 清单里加东西。**

---

## 10. 第 61 到 82 行：先加入输入 `X` 和标签 `Y`

对应源码：

```python
tensors.append(
    TensorSpec(
        name="X",
        role="input",
        shape=[batch_size, input_dim],
        words=batch_size * input_dim,
        storage="ub",
        addr=None,
        dtype=dtype,
    )
)
tensors.append(
    TensorSpec(
        name="Y",
        role="label",
        shape=[batch_size, output_dim],
        words=batch_size * output_dim,
        storage="ub",
        addr=None,
        dtype=dtype,
    )
)
```

### 10.1 为什么先加 `X`

`X` 是输入数据。

当前项目里：
- batch 是 `4`
- input_dim 是 `2`

所以：

```python
shape=[batch_size, input_dim]
```

就变成：

```text
[4, 2]
```

`words` 就是：

```text
4 * 2 = 8
```

这和 `ub_map.json` 对得上：

```json
"name": "X",
"shape": [4, 2],
"words": 8,
"storage": "ub",
"addr": 0
```

### 10.2 为什么 `X` 是 `storage="ub"`

因为输入 `X` 是 host 一开始要写进 UB 的数据。
后面 scheduler 也要从 UB 里读 `X`。

所以它必须长期落到 UB。

### 10.3 为什么 `addr=None`

这里还没有分配真实地址。

所以先写：

```python
addr=None
```

后面 `allocate_from_spec()` 才会把它改成具体地址，比如 `0`。

### 10.4 为什么再加 `Y`

`Y` 是标签。

训练时要算 loss 和梯度，所以硬件后面需要知道标签是什么。

当前项目里：
- batch 是 `4`
- output_dim 是 `1`

所以 `Y` 的 shape 是：

```text
[4, 1]
```

`words` 是：

```text
4 * 1 = 4
```

对应 `ub_map.json`：

```json
"name": "Y",
"shape": [4, 1],
"words": 4,
"storage": "ub",
"addr": 8
```

### 10.5 这一段你应该记住什么

**`X` 和 `Y` 是 host 一开始就要放进 UB 的基础数据，所以它们都标成 `storage="ub"`。**

---

## 11. 第 84 到 113 行：遍历每一层，生成 `W` 和 `B`

对应源码：

```python
prev_dim = input_dim
layer_out_dims: list[int] = []
for index, layer in enumerate(layers, start=1):
    if layer.get("type") != "linear":
        raise ValueError(f"layer {index} must be type=linear for the current allocator")
    out_dim = int(layer["out_dim"])
    layer_out_dims.append(out_dim)
    tensors.append(TensorSpec(name=f"W{index}", ...))
    tensors.append(TensorSpec(name=f"B{index}", ...))
    prev_dim = out_dim
```

### 11.1 第 84 行：`prev_dim = input_dim`

一开始，第一层的输入维度就是模型输入维度。

当前例子里：

```text
prev_dim = 2
```

### 11.2 第 85 行：`layer_out_dims`

```python
layer_out_dims: list[int] = []
```

这个列表用来记录每一层的输出维度。

后面生成 activation 和 gradient 时还要用。

当前两层模型大概会得到：

```python
layer_out_dims = [2, 1]
```

### 11.3 第 86 行：遍历每一层

```python
for index, layer in enumerate(layers, start=1):
```

这里 `start=1` 很重要。

它让第一层编号是 `1`，不是 Python 默认的 `0`。

所以后面命名就是：
- `W1`
- `B1`
- `W2`
- `B2`

而不是 `W0/B0`。

### 11.4 第 87 到 88 行：当前只支持 linear

```python
if layer.get("type") != "linear":
    raise ValueError(...)
```

这表示当前 allocator 只支持线性层。

它不是通用深度学习框架。
它服务的是当前项目的两层 MLP。

### 11.5 第 89 到 90 行：取这一层输出维度

```python
out_dim = int(layer["out_dim"])
layer_out_dims.append(out_dim)
```

比如：
- 第一层 `out_dim = 2`
- 第二层 `out_dim = 1`

记录下来是为了后面生成：
- `H1/H2`
- `dZ2/dZ1`
- `dH1`

### 11.6 第 91 到 101 行：生成权重 `W{index}`

对应逻辑：

```python
TensorSpec(
    name=f"W{index}",
    role="weight",
    shape=[out_dim, prev_dim],
    words=out_dim * prev_dim,
    storage="ub",
    addr=None,
    dtype=dtype,
)
```

如果是第一层：
- `index = 1`
- `out_dim = 2`
- `prev_dim = 2`

所以生成：

```text
W1 shape = [2, 2]
words = 4
```

如果是第二层：
- `index = 2`
- `out_dim = 1`
- `prev_dim = 2`

所以生成：

```text
W2 shape = [1, 2]
words = 2
```

为什么 `storage="ub"`？

因为权重必须由 host 初始装载到 UB，后面还要被硬件读出来参与计算和更新。

### 11.7 第 102 到 112 行：生成 bias `B{index}`

对应逻辑：

```python
TensorSpec(
    name=f"B{index}",
    role="bias",
    shape=[out_dim],
    words=out_dim,
    storage="ub",
    addr=None,
    dtype=dtype,
)
```

如果是第一层：

```text
B1 shape = [2]
words = 2
```

如果是第二层：

```text
B2 shape = [1]
words = 1
```

bias 也放 UB，因为：
- host 初始要装载
- VPU 前向要读
- 训练时还可能在 UB 内原地更新

### 11.8 第 113 行：更新 `prev_dim`

```python
prev_dim = out_dim
```

这一行很关键。

它的意思是：

**当前层的输出维度，会成为下一层的输入维度。**

第一层结束后：

```text
prev_dim = hidden_dim = 2
```

所以第二层权重 `W2` 的 shape 才会是 `[1, 2]`。

### 11.9 这一段你应该记住什么

**这一段根据每一层的输入输出维度，生成每层的权重 `W` 和 bias `B`，并且都标成 UB 常驻数据。**

---

## 12. 第 115 到 128 行：生成 activation `H1/H2`

对应源码：

```python
for index, out_dim in enumerate(layer_out_dims, start=1):
    is_last = index == len(layer_out_dims)
    storage = "ub" if (not is_last or persist_output_activation) else "ephemeral"
    tensors.append(
        TensorSpec(
            name=f"H{index}",
            role="activation",
            shape=[batch_size, out_dim],
            words=batch_size * out_dim,
            storage=storage,
            addr=None,
            dtype=dtype,
        )
    )
```

### 12.1 这段在生成什么

它生成每一层的 activation：

- 第一层输出：`H1`
- 第二层输出：`H2`

### 12.2 第 116 行：判断是不是最后一层

```python
is_last = index == len(layer_out_dims)
```

如果当前层编号等于最后一层编号，那就是最后一层。

当前模型有两层：
- `H1` 不是最后一层输出
- `H2` 是最后一层输出

### 12.3 第 117 行：决定 `storage`

```python
storage = "ub" if (not is_last or persist_output_activation) else "ephemeral"
```

这行是这段最重要的逻辑。

翻译成人话：

如果不是最后一层，就放 UB。
如果是最后一层，默认不放 UB，除非配置要求保存它。

所以当前默认情况下：

```text
H1 -> ub
H2 -> ephemeral
```

### 12.4 为什么 `H1` 要放 UB

因为 `H1` 后面还会被用到。

比如：
- 第二层前向要读 `H1`
- 更新 `W2` 时也要用 `H1`

所以 `H1` 必须长期放在 UB 里。

### 12.5 为什么 `H2` 可以是 `ephemeral`

`H2` 是最后一层前向输出。

在当前设计里，它可以在 VPU/loss 管线里直接被消费，不一定需要长期写回 UB。

所以默认：

```json
"name": "H2",
"storage": "ephemeral",
"addr": null
```

这不是丢数据，而是工程选择：

**只把后面还要再读的中间结果长期落 UB。**

### 12.6 这一段你应该记住什么

**activation 不一定都要存 UB。`H1` 因为后面还要用，所以存；`H2` 默认只是临时经过，所以可以不存。**

---

## 13. 第 130 到 157 行：如果训练打开，就生成梯度 tensor

对应源码：

```python
if training_enabled:
    for index in range(len(layer_out_dims), 0, -1):
        out_dim = layer_out_dims[index - 1]
        tensors.append(
            TensorSpec(
                name=f"dZ{index}",
                role="gradient_activation",
                shape=[batch_size, out_dim],
                words=batch_size * out_dim,
                storage="ub",
                addr=None,
                dtype=dtype,
            )
        )
        if index > 1:
            prev_out_dim = layer_out_dims[index - 2]
            tensors.append(
                TensorSpec(
                    name=f"dH{index - 1}",
                    role="gradient_hidden",
                    shape=[batch_size, prev_out_dim],
                    words=batch_size * prev_out_dim,
                    storage="ephemeral",
                    addr=None,
                    dtype=dtype,
                )
            )
```

### 13.1 第 130 行：只有训练才需要这段

```python
if training_enabled:
```

如果只是推理，不需要反向传播和参数更新。

但当前项目的重点是训练闭环，所以这里会进入。

### 13.2 第 131 行：为什么倒着遍历

```python
for index in range(len(layer_out_dims), 0, -1):
```

反向传播是从最后一层往前走。

当前两层模型会先处理：
- 第 2 层
- 再处理第 1 层

所以这里是倒序遍历。

### 13.3 第 132 行：拿这一层输出维度

```python
out_dim = layer_out_dims[index - 1]
```

Python list 从 0 开始，层号从 1 开始。

所以要用 `index - 1` 去取列表。

比如：
- `index = 2`，取 `layer_out_dims[1]`，得到 `1`
- `index = 1`，取 `layer_out_dims[0]`，得到 `2`

### 13.4 第 133 到 143 行：生成 `dZ{index}`

`dZ` 可以粗理解成这一层输出激活对应的梯度。

当前模型会生成：

```text
dZ2 shape = [4, 1]
dZ1 shape = [4, 2]
```

为什么 `dZ` 是 `storage="ub"`？

因为后面会再次读它们。

比如：
- `dZ2` 用于反传到第一层，也用于更新 `W2`
- `dZ1` 用于更新 `W1`

所以它们不能只是临时值，必须放 UB。

### 13.5 第 144 行：如果不是第一层，还会生成 `dH`

```python
if index > 1:
```

这表示：

当前不是第一层时，还会有一个往前传的隐藏梯度 `dH`。

对于两层模型，`index = 2` 时会生成：

```text
dH1
```

### 13.6 第 145 到 156 行：生成 `dH{index - 1}`

```python
name=f"dH{index - 1}"
role="gradient_hidden"
storage="ephemeral"
```

`dH1` 是隐藏层梯度的中间态。

为什么它是 `ephemeral`？

因为当前系统更关心最终要落地的 `dZ1`。
`dH1` 可以在 VPU/导数路径里短暂存在，不一定长期保存到 UB。

所以你会在 `ub_map.json` 里看到：

```json
"name": "dH1",
"storage": "ephemeral",
"addr": null
```

### 13.7 第 158 行：返回 tensor catalog

```python
return tensors
```

到这里，tensor 清单已经推导完了。

但注意：

**这个清单里很多 UB tensor 的 `addr` 还都是 `None`。**

真正分配地址是在下一个函数。

### 13.8 这一段你应该记住什么

**训练打开后，allocator 会额外生成梯度相关 tensor；其中后面还要再读的 `dZ` 放 UB，只是中间过渡的 `dH` 可以是 ephemeral。**

---

## 14. 先用当前 `ub_map.json` 对一下结果

当前例子最终 tensor 大概是：

```text
X    input                ub         addr 0   words 8
Y    label                ub         addr 8   words 4
W1   weight               ub         addr 12  words 4
B1   bias                 ub         addr 16  words 2
W2   weight               ub         addr 18  words 2
B2   bias                 ub         addr 20  words 1
H1   activation           ub         addr 21  words 8
H2   activation           ephemeral  addr null
dZ2  gradient_activation  ub         addr 29  words 4
dH1  gradient_hidden      ephemeral  addr null
dZ1  gradient_activation  ub         addr 33  words 8
```

这个表很重要。

你现在先不用背全部地址。
但你要看懂两个规律：

1. `ub` 的 tensor 有地址
2. `ephemeral` 的 tensor 没地址

并且地址是连续往后排的。

---

## 15. 第 161 到 188 行：`allocate_from_spec()` 真正分配 UB 地址

对应源码：

```python
def allocate_from_spec(spec: dict[str, Any]) -> dict[str, Any]:
    ub_depth_words = int(spec["hardware_target"]["ub_depth_words"])
    catalog = infer_tensor_catalog(spec)

    cursor = 0
    allocated: list[TensorSpec] = []
    for tensor in catalog:
        entry = replace(tensor)
        if entry.storage == "ub":
            entry.addr = cursor
            cursor += entry.words
        allocated.append(entry)

    if cursor > ub_depth_words:
        raise ValueError(...)

    return {...}
```

这个函数是 allocator 真正“分地址”的地方。

---

## 16. 第 162 到 163 行：先拿 UB 深度，再生成 catalog

对应源码：

```python
ub_depth_words = int(spec["hardware_target"]["ub_depth_words"])
catalog = infer_tensor_catalog(spec)
```

### 16.1 `ub_depth_words`

这表示 UB 总共有多少 word。

当前例子里：

```json
"ub_depth_words": 128
```

所以 allocator 最多只能分配 128 个 word。

### 16.2 `catalog`

```python
catalog = infer_tensor_catalog(spec)
```

先调用前面讲过的函数，把 tensor 清单推出来。

这时清单已经知道：
- 有哪些 tensor
- 每个 tensor 多大
- 哪些要放 UB
- 哪些是 ephemeral

但还没正式给 UB tensor 填地址。

### 16.3 这一段你应该记住什么

**分地址之前，先知道 UB 总容量，再拿到 tensor 清单。**

---

## 17. 第 165 到 172 行：用 `cursor` 连续分配地址

对应源码：

```python
cursor = 0
allocated: list[TensorSpec] = []
for tensor in catalog:
    entry = replace(tensor)
    if entry.storage == "ub":
        entry.addr = cursor
        cursor += entry.words
    allocated.append(entry)
```

### 17.1 `cursor = 0`

`cursor` 可以理解成：

**当前 UB 已经用到哪里了。**

一开始什么都没放，所以从地址 `0` 开始。

### 17.2 `allocated = []`

这里准备一个新的列表。

后面每处理一个 tensor，就把处理后的结果放进去。

### 17.3 `for tensor in catalog`

按 tensor catalog 的顺序一个一个处理。

当前顺序大概是：

```text
X -> Y -> W1 -> B1 -> W2 -> B2 -> H1 -> H2 -> dZ2 -> dH1 -> dZ1
```

### 17.4 `entry = replace(tensor)`

这行表示复制一个 tensor 记录。

为什么不直接改原来的 `tensor`？

因为这样更安全。
它避免在原始 catalog 对象上直接修改。

你可以粗理解成：

**复制一份出来，然后在复制品上填地址。**

### 17.5 如果 `storage == "ub"`

```python
if entry.storage == "ub":
    entry.addr = cursor
    cursor += entry.words
```

这是最关键的分配逻辑。

翻成人话：

如果这个 tensor 要放 UB：

1. 它的起始地址就是当前 `cursor`
2. 然后 `cursor` 往后移动它占用的 `words`

举例：

一开始：

```text
cursor = 0
```

处理 `X`：

```text
X words = 8
X addr = 0
cursor = 0 + 8 = 8
```

处理 `Y`：

```text
Y words = 4
Y addr = 8
cursor = 8 + 4 = 12
```

处理 `W1`：

```text
W1 words = 4
W1 addr = 12
cursor = 12 + 4 = 16
```

处理 `B1`：

```text
B1 words = 2
B1 addr = 16
cursor = 16 + 2 = 18
```

一直这样往后排。

### 17.6 如果是 `ephemeral`

如果 `entry.storage` 不是 `ub`，就不会进入 `if`。

也就是说：

- 不分配地址
- `addr` 继续保持 `None`
- `cursor` 不变

所以 `H2` 和 `dH1` 不占 UB 长期地址空间。

### 17.7 `allocated.append(entry)`

不管这个 tensor 是 `ub` 还是 `ephemeral`，最后都会放进 `allocated`。

为什么 ephemeral 也要放进去？

因为输出报告要完整描述它存在过。

只是它没有 UB 地址。

### 17.8 这一段你应该记住什么

**UB 地址分配就是一个 cursor 从 0 开始往后走。遇到 UB tensor 就占一段空间，遇到 ephemeral tensor 就跳过地址分配。**

---

## 18. 第 174 到 177 行：检查 UB 会不会溢出

对应源码：

```python
if cursor > ub_depth_words:
    raise ValueError(
        f"UB allocation overflow: need {cursor} words but target depth is {ub_depth_words}"
    )
```

### 18.1 这里在检查什么

所有 UB tensor 分完后，`cursor` 就代表总共用了多少 word。

如果：

```text
cursor > ub_depth_words
```

就说明放不下。

### 18.2 当前例子放得下吗

当前 `ub_map.json` 里写：

```json
"allocated_words": 41,
"free_words": 87
```

硬件目标是：

```json
"ub_depth_words": 128
```

所以：

```text
41 <= 128
```

放得下。

### 18.3 这一段你应该记住什么

**allocator 不只是分地址，它还负责提前发现 UB 空间不够的问题。**

---

## 19. 第 179 到 188 行：返回 UB map 报告

对应源码：

```python
return {
    "allocator_version": "0.1",
    "spec_name": spec["name"],
    "model_type": spec["model_type"],
    "data_format": spec["data_format"],
    "hardware_target": spec["hardware_target"],
    "allocated_words": cursor,
    "free_words": ub_depth_words - cursor,
    "tensors": [asdict(tensor) for tensor in allocated],
}
```

### 19.1 `allocator_version`

当前 allocator 版本号。

### 19.2 `spec_name`

这份 UB map 对应哪个模型规格。

当前例子里是：

```text
mlp_2_2_1_q8_8_xor
```

### 19.3 `model_type`

模型类型。

当前是：

```text
mlp
```

### 19.4 `data_format`

原样带出数据格式。

这样后面看 UB map 时，不需要再去 spec 里查数据格式。

### 19.5 `hardware_target`

原样带出硬件目标。

比如：
- array width
- lanes
- UB depth

### 19.6 `allocated_words`

已经分配了多少 UB word。

当前例子是：

```text
41
```

### 19.7 `free_words`

还剩多少 UB word。

当前例子：

```text
128 - 41 = 87
```

### 19.8 `tensors`

```python
"tensors": [asdict(tensor) for tensor in allocated]
```

这里把每个 `TensorSpec` 转成普通 dict。

为什么要转？

因为 JSON 不能直接输出 dataclass 对象。
要转成普通字典，才能 `json.dumps()`。

### 19.9 这一段你应该记住什么

**`allocate_from_spec()` 最后输出的就是 `ub_map.json` 的主体内容。它不仅有每个 tensor 的地址，还有容量统计和硬件目标信息。**

---

## 20. 第 191 到 222 行：命令行入口

对应源码：

```python
def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Infer tensor layout and allocate UB addresses.")
    parser.add_argument("spec", help="Path to a model spec JSON file")
    parser.add_argument(
        "-o",
        "--output",
        help="Optional output JSON path. If omitted, the allocation is printed to stdout.",
    )
    return parser


def main() -> int:
    parser = _build_arg_parser()
    args = parser.parse_args()

    spec = load_spec(args.spec)
    report = allocate_from_spec(spec)
    payload = json.dumps(report, indent=2, ensure_ascii=False)

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(payload + "\n", encoding="utf-8")
        print(output_path)
    else:
        print(payload)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

### 20.1 `_build_arg_parser()`

它定义这个脚本怎么从命令行使用。

需要一个参数：

```text
spec
```

也就是模型规格 JSON 文件路径。

可选一个参数：

```text
-o / --output
```

表示把结果写到哪个文件。

### 20.2 `main()` 的执行流程

`main()` 做这几步：

1. 解析命令行参数
2. 用 `load_spec()` 读模型规格
3. 用 `allocate_from_spec()` 生成 UB map 报告
4. 用 `json.dumps()` 转成 JSON 文本
5. 如果指定了输出路径，就写文件
6. 如果没指定输出路径，就直接打印

### 20.3 最后两行

```python
if __name__ == "__main__":
    raise SystemExit(main())
```

意思是：

如果你直接运行这个文件，就执行 `main()`。

### 20.4 这一段你应该记住什么

**这部分只是脚本入口，让 allocator 可以独立运行并输出 JSON。核心逻辑还是前面的 `infer_tensor_catalog()` 和 `allocate_from_spec()`。**

---

## 21. 把整个文件连起来再说一遍

`ub_allocator.py` 的完整流程是：

1. 读取模型 spec
2. 检查 spec 至少有 MLP、layers、hardware_target、data_format
3. 根据 spec 推导训练需要哪些 tensor
4. 标记哪些 tensor 要放 UB，哪些只是 ephemeral
5. 对 UB tensor 用 cursor 连续分配地址
6. 检查 UB 容量够不够
7. 输出 `ub_map.json`

一句话：

**它把模型里的“张量世界”，落成了硬件 UB 里的“地址世界”。**

---

## 22. 和 `scheduler.py` 怎么接上

你刚看过 `scheduler.py` 的小白版。
现在应该把两者关系记成：

- `ub_allocator.py`
  - 决定 `X/W1/H1/dZ2` 这些 tensor 放在哪里

- `scheduler.py`
  - 用这些地址生成读命令
  - 比如 `tensors["W1"]["addr"]`

举一个最直接的例子：

`ub_map.json` 里：

```json
"W1": "addr 12"
```

`scheduler.py` 后面会生成：

```python
tensors["W1"]["addr"]
```

然后这个地址会进入 schedule 命令里的：

```text
ub_rd_addr_in
```

所以：

**allocator 是地址来源，scheduler 是地址使用者。**

---

## 23. 小白最容易搞混的 4 个点

### 23.1 `TensorSpec` 不是 tensor 数据本身

`TensorSpec` 只是描述信息。

它不是 `X` 的具体数值，也不是 `W1` 的具体权重值。

它只是说：

```text
X 叫什么、是什么角色、什么形状、占几个 word、放不放 UB、地址是多少、数据格式是什么
```

### 23.2 `addr=None` 不代表 tensor 不存在

在 `infer_tensor_catalog()` 阶段，所有 tensor 初始都是 `addr=None`。

这只是因为还没分配地址。

到了 `allocate_from_spec()`，UB tensor 才会被填上地址。

### 23.3 `ephemeral` 也不是没用

`ephemeral` 表示不长期落 UB。

但它仍然可能在流水线中短暂出现。

例如：
- `H2`
- `dH1`

它们不是“没意义”，只是“不需要长期分配 UB 地址”。

### 23.4 地址连续不等于最优

当前 allocator 是简单连续分配。

它的优点是：
- 简单
- 稳定
- 好调试
- 和 schedule 容易对上

但它不是最优内存规划。
后续可以优化成：
- 生命周期复用
- 多 bank 感知布局
- 更复杂的 packing

---

## 24. 最后一页总结

如果你只记 6 件事：

1. `ub_allocator.py` 是地址起点。
2. `TensorSpec` 是每个 tensor 的说明卡。
3. `infer_tensor_catalog()` 负责推导有哪些 tensor。
4. `storage="ub"` 才会分配地址。
5. `storage="ephemeral"` 不分配长期 UB 地址。
6. `allocate_from_spec()` 用 cursor 从 0 开始连续分配地址。

最终一句话：

**先有 `ub_map.json`，后面的 `scheduler.py` 才知道该从 UB 的哪个地址读 `X/W/B/H/dZ`。**

---

## 25. 你看完这份后，下一步看什么

建议下一步看：

- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/04_encode_instrs.py_guide_zh.md`

原因是：

你现在已经知道：
- allocator 怎么定地址
- scheduler 怎么用地址生成阶段命令

下一步就该看：

**这些阶段命令怎么继续变成 IMEM/指令字段。**

如果你继续，我下一份就给你做：

**`04_encode_instrs.py` 的同风格小白逐段细讲版。**
