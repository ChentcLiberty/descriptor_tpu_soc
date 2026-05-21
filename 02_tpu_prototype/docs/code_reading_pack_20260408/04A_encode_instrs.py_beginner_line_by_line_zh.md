# `encode_instrs.py` 小白版逐段细讲

对应源码：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/03_encode_instrs.py`

原版讲解：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408/04_encode_instrs.py_guide_zh.md`

配套输入和输出：
- `/home/jjt/tpu-soc/code_reading_sources_20260409/13_mlp_2_2_1_q8_8.schedule.json`
- `/home/jjt/tpu-soc/code_reading_sources_20260409/15_imem.hex`
- `/home/jjt/tpu-soc/code_reading_sources_20260409/16_imem.txt`

这份文档是给小白看的。
目标是让你明白：

**`encode_instrs.py` 怎么把 `schedule.json` 里的阶段命令，压成硬件 IMEM 里能读的 32-bit 指令。**

---

## 0. 先记住 5 句话

1. `scheduler.py` 生成的是阶段命令。
2. `encode_instrs.py` 把阶段命令编码成 32-bit 指令。
3. `imem.hex` 是给硬件 IMEM 用的机器可读版本。
4. `imem.txt` 是给人调试看的注释版本。
5. `control_unit.sv` 后面会按相同位段把这条 32-bit 指令拆回来。

如果你只记一句话，就记：

**encoder 是软件 schedule 到硬件 IMEM 的最后一跳。**

---

## 1. 你应该怎么打开这几个文件

建议左边打开源码：

```text
/home/jjt/tpu-soc/code_reading_sources_20260409/03_encode_instrs.py
```

右边打开这篇文档：

```text
/home/jjt/tpu-soc/docs/code_reading_pack_20260408/04A_encode_instrs.py_beginner_line_by_line_zh.md
```

再准备两个对照文件：

```text
/home/jjt/tpu-soc/code_reading_sources_20260409/13_mlp_2_2_1_q8_8.schedule.json
/home/jjt/tpu-soc/code_reading_sources_20260409/16_imem.txt
```

第一轮只看一个问题：

**schedule 里的一条命令，最后变成了 imem 里的哪一行。**

---

## 2. 第 1 到 24 行：文件开头的长注释就是指令格式说明

对应源码：

```python
1  #!/usr/bin/env python3
2  """Encode a schedule.json command list into 32-bit opcode TPU instructions.
4  Instruction format (32-bit):
5    opcode=3'b000  NOP
6    opcode=3'b001  SWITCH  (sys_switch)
7    opcode=3'b010  UB_RD
8      [2:0]   opcode = 3'b010
9      [8:3]   addr[5:0]       UB address (0-63)
10     [12:9]  row_size[3:0]   row count (1-15)
11     [14:13] col_size[1:0]   column count
12     [15]    transpose
13     [18:16] ptr_sel[2:0]
14     [22:19] vpu_pathway[3:0]
15     [31:23] reserved
16   opcode=3'b011  UB_WR_HOST
17     [2:0]   opcode = 3'b011
18     [18:3]  data[15:0]
21 Outputs:
22   - imem.hex  : one 32-bit instruction per line (8 hex chars)
23   - imem.txt  : human-readable annotation
24 """
```

### 2.1 第 2 行在说什么

```python
Encode a schedule.json command list into 32-bit opcode TPU instructions.
```

这句话就是整个文件的任务。

翻成人话：

**把 `schedule.json` 里的命令列表，变成 32 位 TPU 指令。**

### 2.2 第 5 行：`NOP`

```text
opcode=3'b000  NOP
```

`NOP` 就是什么都不做的空指令。

在 `imem.hex` 里你会看到很多：

```text
00000000
```

这就是 `NOP`。

### 2.3 第 6 行：`SWITCH`

```text
opcode=3'b001  SWITCH  (sys_switch)
```

`SWITCH` 是系统切换指令。

在 schedule 里它来自：

```text
kind = control
signals.sys_switch_in = 1
```

在 `imem.txt` 里你会看到：

```text
[05] 00000001  forward_layer1.activate_w1  (control)
```

这就是 `SWITCH`。

### 2.4 第 7 到 15 行：`UB_RD` 是最重要的指令

`UB_RD` 是这个项目里最核心的指令类型。

因为训练过程里大量动作都是：

- 从 UB 读 `X`
- 从 UB 读 `W1`
- 从 UB 读 `B1`
- 从 UB 读 `H1`
- 从 UB 读 `dZ2`
- 从 UB 读旧权重做更新

这些都会落成 `UB_RD`。

### 2.5 `UB_RD` 每个位段是什么意思

以注释为准：

```text
[2:0]   opcode
[8:3]   addr
[12:9]  row_size
[14:13] col_size
[15]    transpose
[18:16] ptr_sel
[22:19] vpu_pathway
[31:23] reserved
```

小白先不用背二进制。
你只要知道：

**32-bit 指令不是一整个数字随便用，而是被切成很多小字段，每个字段控制一件事。**

例如一条 UB 读指令里同时装了：

- 从 UB 哪个地址读
- 读多少行
- 读多少列
- 要不要转置
- 用哪种 UB 指针语义
- VPU 走哪条 pathway

### 2.6 第 16 到 19 行：`UB_WR_HOST`

这里定义了 host 写 UB 的一种 opcode。

但你在当前主 schedule 编码里，重点先不用放在它上面。
当前这份代码的核心实际是 `NOP`、`SWITCH`、`UB_RD`。

### 2.7 第 21 到 23 行：两个输出文件

```text
imem.hex
imem.txt
```

区别是：

- `imem.hex`
  - 给硬件或仿真加载
  - 每行就是 8 个 hex 字符
  - 人读起来不直观

- `imem.txt`
  - 给人看
  - 会写出 slot、hex、stage、name、kind、note
  - 适合你调试和面试讲解

### 2.8 这一段你应该记住什么

**文件开头的 docstring 已经定义了软件和 RTL 对齐的指令格式。encoder 只是按这个格式把字段塞进 32-bit 数字里。**

---

## 3. 第 25 到 33 行：导入工具和定义 opcode 常量

对应源码：

```python
25 from __future__ import annotations
26 import argparse
27 import json
28 from pathlib import Path

30 OPCODE_NOP    = 0b000
31 OPCODE_SWITCH = 0b001
32 OPCODE_UB_RD  = 0b010
33 OPCODE_UB_WR  = 0b011
```

### 3.1 第 25 到 28 行

这些是 Python 工具。

- `argparse` 用来解析命令行参数
- `json` 用来读取 `schedule.json`
- `Path` 用来处理路径

它们不是编码规则本身。

### 3.2 第 30 到 33 行

```python
OPCODE_NOP    = 0b000
OPCODE_SWITCH = 0b001
OPCODE_UB_RD  = 0b010
OPCODE_UB_WR  = 0b011
```

这里把 opcode 写成常量。

为什么要这样？

因为后面写代码时，用名字比直接写数字更清楚。

比如：

```python
instr = OPCODE_UB_RD
```

比：

```python
instr = 2
```

更容易看懂。

### 3.3 小白该记住什么

**opcode 是指令最底部的类型字段。硬件先看 opcode，才知道这条指令是 NOP、SWITCH 还是 UB_RD。**

---

## 4. 第 36 到 70 行：`encode_command()` 是核心函数

对应源码：

```python
def encode_command(cmd: dict) -> int:
    """Encode one scheduler command into a 32-bit opcode instruction."""
    kind    = cmd.get("kind", "nop")
    signals = cmd.get("signals", {})

    if kind == "wait":
        return None

    if kind == "control" and signals.get("sys_switch_in"):
        return OPCODE_SWITCH

    if kind == "ub_read":
        instr = OPCODE_UB_RD
        ...
        return instr

    return OPCODE_NOP
```

这整个函数做一件事：

**把 schedule 里的一条 command，编码成一条 32-bit 指令。**

---

## 5. 第 38 到 39 行：先拿 `kind` 和 `signals`

对应源码：

```python
kind    = cmd.get("kind", "nop")
signals = cmd.get("signals", {})
```

### 5.1 `kind`

`kind` 是命令类型。

在 `schedule.json` 里常见几种：

- `ub_read`
- `control`
- `nop`
- `wait`

如果这个 command 没写 `kind`，默认当成 `nop`。

### 5.2 `signals`

`signals` 是这条命令携带的控制字段。

例如 `stream_b1` 的 signals 里有：

```json
"ub_ptr_select": 2,
"ub_rd_addr_in": 16,
"ub_rd_row_size": 4,
"ub_rd_col_size": 2,
"ub_rd_transpose": 0,
"vpu_data_pathway": "1100"
```

这些字段后面会被塞到 32-bit 指令的不同 bit 位置。

### 5.3 这一段你应该记住什么

**encoder 先看命令类型 `kind`，再看命令携带的 `signals`。**

---

## 6. 第 41 到 42 行：为什么 `wait` 不编码

对应源码：

```python
if kind == "wait":
    return None  # not encoded, handled by sequencer hardware
```

这段非常重要。

如果 command 是：

```json
{
  "kind": "wait",
  "event": "vpu_drain"
}
```

encoder 不会把它变成一条 IMEM 指令。

而是返回：

```python
None
```

### 6.1 为什么不编码 `wait`

因为当前设计里，真正让 Frontend 等待的不是一条单独 `WAIT` 指令。

它的逻辑是：

1. 某条 `UB_RD` 指令带 `wait_after = 1`
2. Frontend dispatch 这条指令
3. Frontend 看到 bit23 是 1
4. Frontend 进入等待状态
5. 等 `vpu_drain` 后再继续

所以 `wait` 命令更多是 schedule 里的人类可读阶段边界，不直接占用 IMEM slot。

### 6.2 在 `imem.txt` 里会怎么看到它

虽然 `wait` 不进 `imem.hex`，但 `imem.txt` 会记录：

```text
# [wait] forward_layer1.wait_h1_writeback skipped (handled by sequencer)
```

意思是：

**它不占机器指令 slot，但人能看到这里有一个等待语义。**

### 6.3 这一段你应该记住什么

**`wait` 不编码，不代表系统不等。真正触发等待的是前一条 UB_RD 里的 `wait_after` bit。**

---

## 7. 第 44 到 45 行：`control + sys_switch_in` 编成 `SWITCH`

对应源码：

```python
if kind == "control" and signals.get("sys_switch_in"):
    return OPCODE_SWITCH  # 32'h00000001
```

如果 command 类型是 `control`，并且 signals 里有：

```python
sys_switch_in = 1
```

那它就编码成 `SWITCH`。

当前 `SWITCH` 的 opcode 是：

```text
0b001
```

所以整条指令就是：

```text
00000001
```

在 `imem.txt` 里你会看到：

```text
[05] 00000001  forward_layer1.activate_w1  (control)
```

### 7.1 这一段你应该记住什么

**`activate_w1` 这种 control 命令，最后会变成一条 `SWITCH` 指令，让硬件做 shadow/active 切换。**

---

## 8. 第 47 到 67 行：`ub_read` 怎么编码成 `UB_RD`

这是整个文件最重要的一段。

对应源码：

```python
if kind == "ub_read":
    instr = OPCODE_UB_RD
    addr      = int(signals.get("ub_rd_addr_in",  0)) & 0x3F
    row       = int(signals.get("ub_rd_row_size", 0)) & 0xF
    col       = int(signals.get("ub_rd_col_size", 0)) & 0x3
    transpose = int(signals.get("ub_rd_transpose", 0)) & 0x1
    ptr_sel   = int(signals.get("ub_ptr_select",  0)) & 0x7
    vpu_path  = signals.get("vpu_data_pathway", 0)
    if isinstance(vpu_path, str):
        vpu_path = int(vpu_path, 2)
    vpu_path = int(vpu_path) & 0xF
    wait_after = int(cmd.get("wait_after", 0)) & 0x1

    instr |= addr     << 3
    instr |= row      << 9
    instr |= col      << 13
    instr |= transpose << 15
    instr |= ptr_sel  << 16
    instr |= vpu_path << 19
    instr |= wait_after << 23
    return instr
```

---

## 9. 第 48 行：先放 opcode

```python
instr = OPCODE_UB_RD
```

这表示先创建一条 UB_RD 指令。

此时它还只有 opcode，没有地址、行列、转置、路径等字段。

你可以理解成：

**先说明这条指令的类型是 UB 读，再往里面塞各种参数。**

---

## 10. 第 49 到 54 行：从 signals 里取字段

对应源码：

```python
addr      = int(signals.get("ub_rd_addr_in",  0)) & 0x3F
row       = int(signals.get("ub_rd_row_size", 0)) & 0xF
col       = int(signals.get("ub_rd_col_size", 0)) & 0x3
transpose = int(signals.get("ub_rd_transpose", 0)) & 0x1
ptr_sel   = int(signals.get("ub_ptr_select",  0)) & 0x7
vpu_path  = signals.get("vpu_data_pathway", 0)
```

### 10.1 `addr`

`addr` 是 UB 起始地址。

`& 0x3F` 表示只保留 6 bit。

因为前面指令格式说了：

```text
[8:3] addr[5:0]
```

6 bit 最多能表示 `0-63`。

### 10.2 `row`

`row` 是读多少行。

`& 0xF` 表示只保留 4 bit。

因为位段是：

```text
[12:9] row_size[3:0]
```

### 10.3 `col`

`col` 是读多少列。

`& 0x3` 表示只保留 2 bit。

因为位段是：

```text
[14:13] col_size[1:0]
```

### 10.4 `transpose`

`transpose` 表示要不要转置。

`& 0x1` 表示只保留 1 bit。

0 表示不转置，1 表示转置。

### 10.5 `ptr_sel`

`ptr_sel` 是 UB 读语义选择。

`& 0x7` 表示只保留 3 bit。

因为位段是：

```text
[18:16] ptr_sel[2:0]
```

### 10.6 `vpu_path`

`vpu_path` 是 VPU pathway。

例如 schedule 里可能写：

```json
"vpu_data_pathway": "1100"
```

这还是字符串，后面要转成整数。

### 10.7 这一段你应该记住什么

**这一步是在从 schedule 的 `signals` 里取字段，并且用 bit mask 限制每个字段的宽度。**

---

## 11. 第 55 到 57 行：把字符串 pathway 转成数字

对应源码：

```python
if isinstance(vpu_path, str):
    vpu_path = int(vpu_path, 2)
vpu_path = int(vpu_path) & 0xF
```

如果 `vpu_path` 是字符串，比如：

```text
1100
```

那么：

```python
int("1100", 2)
```

结果是十进制 `12`。

然后：

```python
& 0xF
```

只保留 4 bit。

### 11.1 为什么要这么做

因为 `schedule.json` 里为了人好看，可能写成字符串 `1100`。

但真正编码到指令里时，它必须是数字。

### 11.2 这一段你应该记住什么

**人看的 pathway 字符串，要先转成整数，才能塞进 32-bit 指令。**

---

## 12. 第 58 行：`wait_after` 是关键阶段边界 bit

对应源码：

```python
wait_after = int(cmd.get("wait_after", 0)) & 0x1
```

`wait_after` 来自 schedule command 本身，不在 `signals` 里面。

比如 `stream_b1` 这条命令里有：

```json
"wait_after": 1
```

它表示：

**这条 UB_RD 发完以后，Frontend 不应该马上 advance，而要等后级流水收尾。**

### 12.1 为什么它重要

因为它后面会编码进 bit23：

```python
instr |= wait_after << 23
```

然后 RTL Frontend 会读这个 bit。

所以这一个 bit 是软件和硬件对“阶段边界”的直接约定。

### 12.2 这一段你应该记住什么

**`wait_after` 不是额外的一条 wait 指令，而是当前 UB_RD 指令里的一个标志位。**

---

## 13. 第 60 到 66 行：把字段塞进不同 bit 位置

对应源码：

```python
instr |= addr     << 3
instr |= row      << 9
instr |= col      << 13
instr |= transpose << 15
instr |= ptr_sel  << 16
instr |= vpu_path << 19
instr |= wait_after << 23
```

这几行是 bit-level 编码。

小白可以先这样理解：

**把每个字段移动到它该待的位置，然后用 OR 拼到同一个 32-bit 数字里。**

逐行看：

- `addr << 3`
  - 放到 `[8:3]`

- `row << 9`
  - 放到 `[12:9]`

- `col << 13`
  - 放到 `[14:13]`

- `transpose << 15`
  - 放到 `[15]`

- `ptr_sel << 16`
  - 放到 `[18:16]`

- `vpu_path << 19`
  - 放到 `[22:19]`

- `wait_after << 23`
  - 放到 `[23]`

### 13.1 为什么用 `|=`

`|=` 是按位 OR 后赋值。

你可以理解成：

**原来 instr 里已经有 opcode，现在再把 addr、row、col 等字段一个一个合进去。**

### 13.2 这一段你应该记住什么

**encoder 的核心不是复杂算法，而是按约定把每个字段移到固定 bit 位置。**

---

## 14. 第 67 行：返回最终指令

```python
return instr
```

到这里，一条 `ub_read` 命令已经变成一个 Python 整数。

后面会再格式化成 8 位 hex 字符串。

例如：

```text
00e24882
```

---

## 15. 第 69 到 70 行：未知命令默认当 NOP

对应源码：

```python
# NOP for unknown / unhandled
return OPCODE_NOP
```

如果 command 不是上面支持的几类，就返回 `NOP`。

这是一种保守处理方式。

意思是：

**不认识的命令不要乱编码成危险动作，默认让它什么都不做。**

---

## 16. 用 `stream_b1` 做一个完整例子

在 `schedule.json` 里，`stream_b1` 大概是：

```json
{
  "stage": "forward_layer1",
  "name": "stream_b1",
  "kind": "ub_read",
  "tensor": "B1",
  "signals": {
    "ub_ptr_select": 2,
    "ub_rd_addr_in": 16,
    "ub_rd_row_size": 4,
    "ub_rd_col_size": 2,
    "ub_rd_transpose": 0,
    "vpu_data_pathway": "1100"
  },
  "wait_after": 1
}
```

encoder 做的事情是：

1. 看到 `kind = ub_read`
2. 先放 `OPCODE_UB_RD`
3. 把 `addr = 16` 放到 `[8:3]`
4. 把 `row = 4` 放到 `[12:9]`
5. 把 `col = 2` 放到 `[14:13]`
6. 把 `transpose = 0` 放到 `[15]`
7. 把 `ptr_sel = 2` 放到 `[18:16]`
8. 把 `vpu_path = 1100` 转成数字 12，放到 `[22:19]`
9. 把 `wait_after = 1` 放到 `[23]`

最后在 `imem.txt` 里你会看到：

```text
[07] 00e24882  forward_layer1.stream_b1  (ub_read)
```

这说明它最后变成了：

```text
00e24882
```

你不用手算这个 hex。
你只要知道：

**这个 hex 里面已经打包了 UB 地址、行列大小、ptr_sel、VPU pathway 和 wait_after。**

---

## 17. 第 73 到 103 行：`encode_schedule()` 处理整份 schedule

对应源码：

```python
def encode_schedule(schedule_path: str | Path, out_dir: str | Path) -> int:
    schedule = json.loads(Path(schedule_path).read_text(encoding="utf-8"))
    commands = schedule["commands"]

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    hex_lines = []
    txt_lines = [f"# TinyTPU IMEM (32-bit opcode) from {Path(schedule_path).name}\n"]

    slot = 0
    for cmd in commands:
        instr = encode_command(cmd)
        if instr is None:
            txt_lines.append(...)
            continue
        hex_str = f"{instr:08x}"
        hex_lines.append(hex_str)
        txt_lines.append(...)
        if cmd.get("note"):
            txt_lines.append(...)
        slot += 1

    txt_lines.insert(1, f"# {slot} instructions (wait commands excluded)\n\n")

    (out_dir / "imem.hex").write_text(...)
    (out_dir / "imem.txt").write_text(...)

    print(...)
    return slot
```

这个函数不是编码一条命令，而是编码整份 schedule。

---

## 18. 第 74 到 75 行：读入 schedule

对应源码：

```python
schedule = json.loads(Path(schedule_path).read_text(encoding="utf-8"))
commands = schedule["commands"]
```

第一行读取 JSON 文件。
第二行拿出核心命令列表。

也就是说，encoder 真正关心的是：

```text
schedule["commands"]
```

---

## 19. 第 77 到 81 行：准备输出目录和输出列表

对应源码：

```python
out_dir = Path(out_dir)
out_dir.mkdir(parents=True, exist_ok=True)

hex_lines = []
txt_lines = [f"# TinyTPU IMEM (32-bit opcode) from {Path(schedule_path).name}\n"]
```

### 19.1 `out_dir.mkdir(...)`

如果输出目录不存在，就创建它。

### 19.2 `hex_lines`

`hex_lines` 用来保存机器可读的 hex 指令。

最后会写到：

```text
imem.hex
```

### 19.3 `txt_lines`

`txt_lines` 用来保存人类可读的注释。

最后会写到：

```text
imem.txt
```

---

## 20. 第 83 到 95 行：逐条命令编码

对应源码：

```python
slot = 0
for cmd in commands:
    instr = encode_command(cmd)
    if instr is None:
        txt_lines.append(f"# [wait] {cmd['stage']}.{cmd['name']} ...")
        continue
    hex_str = f"{instr:08x}"
    hex_lines.append(hex_str)
    txt_lines.append(f"[{slot:02d}] {hex_str}  {cmd['stage']}.{cmd['name']}  ({cmd['kind']})\n")
    if cmd.get("note"):
        txt_lines.append(f"       note: {cmd['note']}\n")
    slot += 1
```

### 20.1 `slot = 0`

`slot` 是 IMEM 指令编号。

注意：

**只有真正进入 IMEM 的指令才占 slot。**

`wait` 不占 slot。

### 20.2 `instr = encode_command(cmd)`

对当前 command 编码。

可能返回：

- 一个整数
  - 表示真实指令

- `None`
  - 表示这是 wait，不进入 IMEM

### 20.3 如果 `instr is None`

```python
if instr is None:
    txt_lines.append(...)
    continue
```

这种情况就是 wait command。

它不会进入 `hex_lines`。
也不会让 `slot += 1`。

但它会写进 `imem.txt` 作为注释，方便你知道这里有等待语义。

### 20.4 `hex_str = f"{instr:08x}"`

这行把整数格式化成 8 位十六进制字符串。

例如：

```text
1 -> 00000001
0 -> 00000000
```

### 20.5 `hex_lines.append(hex_str)`

把机器指令写进列表。

最后 `hex_lines` 就会变成 `imem.hex`。

### 20.6 `txt_lines.append(...)`

把可读注释写进去。

所以你在 `imem.txt` 里能看到：

```text
[07] 00e24882  forward_layer1.stream_b1  (ub_read)
```

### 20.7 `note`

如果 command 自带 `note`，也写到 `imem.txt`。

这对调试很有用。

### 20.8 `slot += 1`

只有真实编码成 IMEM 指令时，slot 才往后走。

所以 `imem.txt` 里会写：

```text
# 59 instructions (wait commands excluded)
```

意思是：

**wait command 被排除后，真正进 IMEM 的有 59 条。**

---

## 21. 第 96 到 103 行：写出 `imem.hex` 和 `imem.txt`

对应源码：

```python
txt_lines.insert(1, f"# {slot} instructions (wait commands excluded)\n\n")

(out_dir / "imem.hex").write_text("\n".join(hex_lines) + "\n", encoding="utf-8")
(out_dir / "imem.txt").write_text("".join(txt_lines), encoding="utf-8")

print(f"Encoded {slot} instructions -> {out_dir}/imem.hex")
print(f"Annotation                  -> {out_dir}/imem.txt")
return slot
```

### 21.1 `txt_lines.insert(...)`

在 `imem.txt` 的第二行插入指令数量说明。

例如：

```text
# 59 instructions (wait commands excluded)
```

### 21.2 写 `imem.hex`

```python
imem.hex
```

每行一个 32-bit 指令。

例子：

```text
0001c462
00000000
00000000
00000001
```

这个文件更偏机器使用。

### 21.3 写 `imem.txt`

```python
imem.txt
```

这个文件更偏人使用。

它会告诉你：

- 第几条指令
- hex 是什么
- 对应哪个 stage
- 对应哪个 command name
- 原始 kind 是什么
- note 是什么
- wait 在哪里被跳过

### 21.4 这一段你应该记住什么

**encoder 同时输出机器文件和人类调试文件。`imem.hex` 给硬件，`imem.txt` 给你看。**

---

## 22. 第 106 到 116 行：命令行入口

对应源码：

```python
def main() -> int:
    parser = argparse.ArgumentParser(description="Encode schedule.json to 32-bit opcode IMEM hex.")
    parser.add_argument("schedule", help="Path to schedule.json")
    parser.add_argument("-o", "--output", default="compiler/out", help="Output directory")
    args = parser.parse_args()
    encode_schedule(args.schedule, args.output)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

这部分只是让这个文件可以直接作为脚本运行。

你传入：

```text
schedule.json 路径
```

它输出到：

```text
compiler/out
```

或者你用 `-o` 指定的目录。

---

## 23. 把整个文件连起来再说一遍

`encode_instrs.py` 的完整流程是：

1. 读取 `schedule.json`
2. 遍历 `commands`
3. 每条 command 调用 `encode_command()`
4. `wait` 返回 `None`，不进 IMEM
5. `control + sys_switch_in` 编成 `SWITCH`
6. `ub_read` 编成 `UB_RD`
7. 其他未知命令默认 `NOP`
8. 真正编码的指令写进 `imem.hex`
9. 调试说明写进 `imem.txt`

一句话：

**它把软件侧的阶段命令，压缩成 RTL 能按位拆解的 32-bit 指令。**

---

## 24. 和前后文件怎么接上

前面：

- `ub_allocator.py`
  - 负责 tensor 地址

- `scheduler.py`
  - 用这些地址生成阶段命令

当前：

- `encode_instrs.py`
  - 把阶段命令编码成 `imem.hex`

后面：

- `control_unit.sv`
  - 在 RTL 里按相同 bit 位段拆指令

所以这条链是：

```text
ub_map.json -> schedule.json -> imem.hex -> control_unit.sv decode
```

### 24.1 最关键的对齐点

`encode_instrs.py` 里：

```python
instr |= ptr_sel << 16
instr |= vpu_path << 19
instr |= wait_after << 23
```

后面的 `control_unit.sv` 必须按同样的 bit 位置去拆。

这就是软件和 RTL 的 bit-level 对齐。

---

## 25. 小白最容易搞混的 5 个点

### 25.1 `wait` 不进 IMEM，不代表没等待

等待语义是靠前一条 `UB_RD` 的 `wait_after` bit 触发的。

### 25.2 `imem.hex` 不是给人读的

它是机器文件。
你想理解每条指令，优先看 `imem.txt`。

### 25.3 `vpu_data_pathway = "1100"` 不是十进制一千一百

它是二进制字符串。

encoder 会用：

```python
int(vpu_path, 2)
```

把它转成数字。

### 25.4 `& 0x3F` 不是随便写的

这是为了限制字段宽度。

例如 addr 只有 6 bit，就用 `0x3F` 截断。

### 25.5 `slot` 和 schedule command 下标不一定一样

因为 `wait` command 会被跳过。

所以 `imem.txt` 的 `[07]` 不是原始 schedule 的第 7 个 command，而是真正进入 IMEM 的第 7 个 slot。

---

## 26. 最后一页总结

如果你只记 6 件事：

1. `encode_instrs.py` 是 `schedule.json -> imem.hex` 的桥。
2. 它的核心函数是 `encode_command()`。
3. `UB_RD` 是最重要的编码类型。
4. `wait` 不编码成单独指令。
5. `wait_after` 编进 bit23。
6. `imem.hex` 给硬件，`imem.txt` 给人看。

最终一句话：

**`encode_instrs.py` 的价值，是把软件里的训练阶段命令第一次压成 RTL 真正会读的 32-bit 指令格式。**

---

## 27. 你看完这份后，下一步看什么

下一步建议看：

```text
/home/jjt/tpu-soc/docs/code_reading_pack_20260408/05_control_unit.sv_guide_zh.md
```

原因是：

你刚看完“软件怎么打包指令”。
下一步就该看：

**RTL 怎么把这条 32-bit 指令拆回来。**

如果你继续，我下一份就做：

**`05_control_unit.sv` 的同风格小白逐段细讲版。**
