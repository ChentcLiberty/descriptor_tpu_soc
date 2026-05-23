# Presentation Assets Guide

This file explains the presentation-oriented assets related to the current
mainline documentation.

## What is kept in the public repo

The public repo keeps the **source scripts** and the **refreshed Markdown
talk-track docs**:

- `render_breath_soc_rtl_arch_ppt.py`
- `render_breath_soc_rtl_arch_explained_ppt.py`
- `render_breath_soc_algo_to_tpu_flow_ppt.py`
- `CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`
- `CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`

The two Markdown guides were refreshed to the `2026-05-22` mainline wording.

## Expected generated standalone outputs

When regenerated in a workspace that has the required Python dependency
(`python-pptx`) and the local doc scripts available, the main standalone assets
are:

- `19_CPU_TPU_呼吸识别SoC_RTL架构图_4p_可编辑.pptx`
- `20_CPU_TPU_呼吸识别SoC_RTL架构图_6p_含讲解.pptx`
- `21_CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_3p.pptx`
- `22_CPU_TPU_呼吸识别_算法到RTL_9p_讲解顺序版.pptx`

## Appended deck variants

Some scripts can also produce appended deck variants such as:

- `陈韦东tinytpusoc_呼吸识别SoC更新版_v2_RTL架构图.pptx`
- `陈韦东tinytpusoc_呼吸识别SoC更新版_v3_RTL架构图_含讲解.pptx`
- `陈韦东tinytpusoc_呼吸识别SoC更新版_v4_算法到CPU发送TPU.pptx`

These appended outputs depend on local base-deck files being present. They are
therefore treated as workspace/share-delivery assets rather than guaranteed
public-repo artifacts.

## Why the binaries are not committed here

The public repository intentionally avoids bundling large binary presentation
files by default because:

- they significantly increase repo weight
- they are derived artifacts from the scripts
- some appended variants depend on local base decks not guaranteed in public
  export

## Best reading path in the public repo

If you only need the content and not the binary slides:

1. `stage2_net3_cnn_frontend_status_20260518.md`
2. `CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
3. `CPU_TPU_呼吸识别SoC_RTL架构图_讲解稿_20260419.md`

If you need the slide binaries for delivery or presentation, use the shared
bundle or regenerate them in a local workspace.
