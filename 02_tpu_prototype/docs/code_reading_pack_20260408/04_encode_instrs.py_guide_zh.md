# `encode_instrs.py` 逐段精讲

文件：
- `/home/jjt/TitanTPU/_vendor/tiny-tpu/compiler/encode_instrs.py`

这份文档只讲 `encode_instrs.py`。
它解决的问题非常直接：
**`schedule.json` 里的阶段命令，最后怎么变成 IMEM 里的 32-bit 指令。**

---

## 1. 这个文件的定位

如果说：
- `scheduler.py` 负责生成“阶段命令”
- `control_unit.sv` 负责 RTL 侧“拆字段”

那 `encode_instrs.py` 正好夹在中间。

它做的是：
- 把软件语义对象编码成 bit-level 指令
- 把这些指令写成 `imem.hex`
- 再给一份 `imem.txt` 做可读注释

一句话说：
**它是软件 schedule 到硬件 IMEM 的最后一跳。**

---

## 2. 文件开头已经把 ISA 写明了

顶部注释最值得先看。
它把 32-bit 指令格式讲得很清楚：
- `NOP`
- `SWITCH`
- `UB_RD`
- `UB_WR_HOST`

其中最关键的是 `UB_RD` 的位段：
- `[8:3]` addr
- `[12:9]` row_size
- `[14:13]` col_size
- `[15]` transpose
- `[18:16]` ptr_sel
- `[22:19]` vpu_pathway
- `[23]` wait_after

这一步很关键，因为它把 scheduler 里的语义字段，第一次压成真正的 bit positions。

---

## 3. `encode_command()` 是核心

整个文件真正最重要的函数就是 `encode_command()`。

它按 `kind` 分几类处理：
- `wait` -> 不编码
- `control + sys_switch_in` -> 编成 `SWITCH`
- `ub_read` -> 编成 `UB_RD`
- 其他默认当 `NOP`

这里最值得注意的是：
**`wait` 不进入 IMEM。**

原因不是忘了，而是当前架构里：
- `wait` 由 Frontend sequencer 硬件处理
- `wait_after` 则作为 `UB_RD` 的一个 bit 被编码进去

这说明当前系统把“显式等待事件”和“指令后等待标记”分成了两层。

---

## 4. 为什么 `wait_after` 很有代表性

这一行很重要：

```python
wait_after = int(cmd.get("wait_after", 0)) & 0x1
instr |= wait_after << 23
```

它说明：
- `wait_after` 不是一个额外指令
- 而是附着在当前 `UB_RD` 指令上的一个阶段边界标记

然后在 Frontend 那边，`seq_instr[23]` 又会被读出来，决定 sequencer 是否进入 `SEQ_WAIT`。

所以这一个 bit 是软件和硬件对“阶段边界”的直接握手点。

---

## 5. 为什么这个文件对理解 `control_unit.sv` 很重要

因为你如果只看 `control_unit.sv`，会看到它在按位拆字段；
但如果你不先看 `encode_instrs.py`，就不知道这些位到底是谁在软件侧写进去的。

所以这两个文件要配套看：
- `encode_instrs.py` 负责“怎么打包”
- `control_unit.sv` 负责“怎么拆包”

这正是软件和 RTL bit-level 对齐最直接的证据。

---

## 6. 为什么它把 `imem.hex` 和 `imem.txt` 一起输出

`imem.hex` 的用途是：
- 真实给 IMEM 使用

`imem.txt` 的用途是：
- 人能读
- 调试时能知道第几条 slot 对应哪个 stage/name
- 对照波形和 schedule 时更方便

这其实是很典型的工程做法：
- 一个给机器
- 一个给人

---

## 7. 这个文件现在的限制也很清楚

当前它只支持：
- 现有这套 opcode
- 当前 tiny-tpu 的字段定义
- 当前 scheduler 产出的命令类型

也就是说，它是当前原型的 encoder，不是通用 ISA assembler。

但这并不是缺点，因为当前项目最重要的是：
**把现有原型的软件控制链打通。**

---

## 8. 如果后面升级，它会怎么变

后面如果系统更复杂，这个文件通常会往几个方向演进：
- 支持更多 opcode
- 支持更复杂的立即数字段
- 支持 patch / label / branch
- 支持更完整的指令注释和调试信息

但当前版本已经完成了它最核心的使命：
**把阶段级 schedule 落成硬件可执行的 IMEM 指令流。**

---

## 一页总结

如果你只记 `encode_instrs.py` 的 5 个点，就记：

1. 它是 `schedule.json -> IMEM` 的桥。
2. `wait` 不编码，交给 Frontend sequencer 处理。
3. `wait_after` 被编码到 bit23，是阶段边界的重要标志。
4. `UB_RD` 是最核心的编码类型，因为它承载大部分训练阶段语义。
5. 它和 `control_unit.sv` 必须配套看，一个打包，一个拆包。

最后一句话：
**`encode_instrs.py` 的价值，是把软件里的阶段命令第一次压成了 RTL 真正会读的 32-bit 指令格式。**
