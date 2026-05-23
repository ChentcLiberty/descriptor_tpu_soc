# Software Overview

This file is the shortest useful software-side summary for the current
`01_soc_mainline` path.

If:

- `ARCHITECTURE_OVERVIEW.md` explains the system shape
- `VERIFICATION_OVERVIEW.md` explains how the repo validates it

then this file explains **what the CPU/runtime side is responsible for**.

## 1. Software role in the current mainline

The current system is not “CPU disappears once RTL exists”.

The CPU side is still responsible for:

- raw preprocess
- feature / signal preparation
- descriptor construction
- launch sequencing
- result polling
- chaining multiple TPU stages together

This is especially important because the current system is **not** raw
end-to-end full hardware.

## 2. Key software files

Start with these files:

- `software/include/tpu_desc.h`
- `software/lib/tpu_runtime.c`
- `software/test/breath_tpu_soc_demo/main.c`
- `software/test/breath_tpu_soc_demo/breath_cpu_frontend.c`

They correspond roughly to:

- memory contract
- runtime/launch helpers
- demo sequencing
- CPU-side frontend and raw preprocess

## 3. Descriptor contract

The software/hardware contract is centered on an 8-word descriptor:

```c
TPUDesc {
    net_id,
    input_addr,
    output_addr,
    param_addr,
    scratch_addr,
    input_words,
    output_words,
    flags
}
```

This descriptor is defined in:

- `software/include/tpu_desc.h`

The important software meaning is:

- software chooses the addresses
- software chooses the task type through `net_id`
- hardware consumes the descriptor as the execution contract

## 4. Main software-visible task split

Current `net_id` mapping:

- `NET_ID_MLP_KEY = 0`
- `NET_ID_MLP_OTHER = 1`
- `NET_ID_CLASSIFIER = 2`
- `NET_ID_CNN1D_RESERVED = 3`

The naming still preserves history, but current behavior is:

- `NET_ID=3` is the hardware CNN frontend path
- `NET_ID=0/1/2` are the fullcore TPU/classifier-side paths

This means the software side is responsible for sequencing different task types
across one shared descriptor-launch mechanism.

## 5. Shared-SRAM software layout

The software-visible SRAM map is also defined in `tpu_desc.h`.

Important regions include:

- descriptor buffers
- input buffers
- output buffers
- scratch buffers
- classifier fusion buffers
- CNN frontend signal / feature / output regions

The software side decides which buffers are active and where each stage will
read and write.

This is why the CPU runtime remains central even though computation has moved
into hardware.

## 6. Runtime helpers

Main runtime file:

- `software/lib/tpu_runtime.c`

This layer is the software glue between the CPU program and the hardware MMIO +
shared-SRAM contract.

Typical responsibilities include:

- selecting the active buffer set
- building descriptors
- writing descriptors into shared SRAM
- programming TPU control registers
- waiting for completion
- synchronizing CPU-visible and device-visible memory state

Important design point:

the runtime is not just a thin `start()` call wrapper.
It also manages:

- buffer layout
- parameter-base selection
- memory synchronization / cache-evict behavior
- task metadata

## 7. CPU frontend role

Main frontend file:

- `software/test/breath_tpu_soc_demo/breath_cpu_frontend.c`

This file matters because the current system boundary is still:

```text
CPU raw preprocess
-> signal / feature preparation
-> descriptor launch
-> hardware CNN frontend / classifier path
```

The CPU frontend side still performs work such as:

- preparing fixture-driven input paths
- preparing raw preprocess paths
- producing software-side signal / feature blobs
- preparing classifier fusion input
- marking CNN output readiness for later stages

So even after the `NET_ID=3` hardware frontend integration, the software
frontend layer remains meaningful.

## 8. Demo sequencing

Main demo file:

- `software/test/breath_tpu_soc_demo/main.c`

This file is the most useful “how does the whole thing get launched” entry on
the software side.

The demo code shows:

- how descriptors are created
- how stages are launched
- how buffers are alternated
- how `NET_ID=3` is inserted into the stage sequence
- how classifier continuation is chained after the frontend result

This is the easiest way to understand the current software-visible execution
story without reading every helper first.

## 9. Current software boundary

Important boundary:

- raw preprocess is still on the CPU side
- the software side still owns orchestration
- the hardware side owns descriptor-driven execution once launched

So the system is **not**:

```text
raw signal -> fully autonomous hardware-only graph
```

It is closer to:

```text
CPU preprocess / software orchestration
-> descriptor-driven hardware tasks
-> software observes / chains stages
```

## 10. Recommended software reading order

1. `SOFTWARE_OVERVIEW.md`
2. `software/include/tpu_desc.h`
3. `software/lib/tpu_runtime.c`
4. `software/test/breath_tpu_soc_demo/main.c`
5. `software/test/breath_tpu_soc_demo/breath_cpu_frontend.c`

## 11. Related docs

- `ARCHITECTURE_OVERVIEW.md`
- `VERIFICATION_OVERVIEW.md`
- `stage2_net3_cnn_frontend_status_20260518.md`
- `CPU_TPU_呼吸识别_算法拆分_CPU发送TPU_讲解稿_20260419.md`
