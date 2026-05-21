# Directory Map

## Root Roles

- `src/`: 原始 TPU 核 RTL。
- `src_axi/`: AXI-Lite SoC 封装版 RTL。
- `compiler/`: Python 调度器、UB 分配器、指令编码与输出产物。
- `test/`: cocotb、directed testbench、dump tb。
- `docs/`: 项目说明、图示、综合与面试文档。
- `career/`: 求职相关材料，与工程主干分离。
- `archive/`: 历史备份、保留版本。

## Career Layout

- `career/resume/`: 简历版本、投递说明。
- `career/interview_prep/`: 面试复习资料、项目口述稿、证据映射。

## Archive Layout

- `archive/backup_before_bias_fix_20260331/`: 修复前 unified_buffer_v3 相关备份。

## Generated Outputs

这些目录和文件仍保留在根目录，避免打断现有回归流程：

- `sim_build/`
- `waveforms/`
- `results.xml`

## Cleanup Rule

新增文件时优先按下面规则放置：

- 工程代码放 `src/`、`src_axi/`、`compiler/`、`test/`
- 项目文档放 `docs/`
- 简历/面试材料放 `career/`
- 一次性备份放 `archive/`
- 构建输出不要长期留在源码目录中，优先复用现有生成目录
