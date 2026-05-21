# CPU+TPU 呼吸识别 SoC 实现清单（2026-04-16）

本文档是在 `cpu_tpu_breath_soc_plan_20260416.md` 基础上的落地清单版，目标是把后续实现拆成可以直接开工的文件、接口和执行步骤。

## 1. 当前工程里建议复用的目录

当前 CPU 工程已有软件目录：

- `/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/software/include`
- `/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/software/lib`
- `/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/software/test`

因此后续建议直接在这套目录下新增 CPU 侧 runtime 和 demo，不再另起一套软件工程。

## 2. net_id 最终划分

当前先锁 4 个 `net_id`：

```c
enum {
    NET_ID_MLP_KEY        = 0,
    NET_ID_MLP_OTHER      = 1,
    NET_ID_CLASSIFIER     = 2,
    NET_ID_CNN1D_RESERVED = 3
};
```

语义：

- `NET_ID_MLP_KEY`
  - 对应关键特征分支
  - 网络：`2 -> 32 -> 64 -> 128 -> 64 -> 32`
- `NET_ID_MLP_OTHER`
  - 对应其余特征分支
  - 网络：`6 -> 32 -> 32`
- `NET_ID_CLASSIFIER`
  - 对应分类头
  - 网络：`322 -> 256 -> 128 -> 64 -> 4`
- `NET_ID_CNN1D_RESERVED`
  - 当前只保留编号占位
  - 以后如果真的做卷积硬件或简化卷积块，再接入该 `net_id`

## 3. fixed table 建议内容

CPU 固件里维护一张静态表：

```c
typedef struct {
    uint32_t net_id;
    uint32_t family;        // MLP / HEAD / CNN1D
    uint32_t imem_slot;     // TinyTPU 对应哪套程序
    uint32_t input_words;
    uint32_t output_words;
    uint32_t param_words;
    uint32_t need_scratch;
} tpu_net_meta_t;
```

建议表内容按下面填：

```c
static const tpu_net_meta_t g_tpu_net_meta[] = {
    { NET_ID_MLP_KEY,    TPU_FAMILY_MLP,  0,  /*input*/ 1,   /*output*/ 16, /*param*/ TBD, /*scratch*/ 1 },
    { NET_ID_MLP_OTHER,  TPU_FAMILY_MLP,  1,  /*input*/ 3,   /*output*/ 16, /*param*/ TBD, /*scratch*/ 1 },
    { NET_ID_CLASSIFIER, TPU_FAMILY_HEAD, 2,  /*input*/ 161, /*output*/ 2,  /*param*/ TBD, /*scratch*/ 1 },
    { NET_ID_CNN1D_RESERVED, TPU_FAMILY_CNN1D, 3, 0, 0, 0, 0 },
};
```

说明：

- 这里 `input_words/output_words` 默认按 `32bit word` 计数。
- 因为 TPU 当前内部主数据是 `Q8.8 / 16-bit`，建议两个 16-bit 数据打成一个 32-bit word。
- `TBD` 的 `param_words` 后面根据离线导出的量化权重精确填。
- 当前 RTL 已支持 `TPU_DESC_F_TILE2X2_Q8_8` 的 packed Q8.8 linear 模式：`param_words = output_words * (2 * input_words + 1)`。当前 demo 已覆盖 `2 -> 32 -> 64 -> 128 -> 64 -> 32`，对应 `48/1056/4160/4128/1040` 个参数 word。
- 当前已经支持单层 linear 的跨 input word 累加和 ReLU；`MLP_KEY` 由 CPU 软件显式 layer schedule 串起，尚未做通用自动 layer graph。

## 4. 输入输出打包建议

### 4.1 16-bit packing 规则

统一采用：

```c
word[15:0]   = lane0
word[31:16]  = lane1
```

这样可以直接适配当前 TinyTPU 的双 lane host/DMA 装载思路。

### 4.2 各子网络输入输出建议

- `MLP_KEY`
  - 输入：`2` 个特征
  - 打成 `1` 个 32-bit word
  - 输出：`32` 维，可打成 `16` 个 word

- `MLP_OTHER`
  - 输入：`6` 个特征
  - 打成 `3` 个 32-bit word
  - 输出：`32` 维，可打成 `16` 个 word

- `CLASSIFIER`
  - 输入理论上是 `322` 维
  - 当前打包时建议：
    - `32` 维 `mlp_key` 输出 -> `16` word
    - `2` 维原始关键特征 -> `1` word
    - `256` 维 CNN 输出 -> `128` word
    - `32` 维 `mlp_other` 输出 -> `16` word
    - 总计 `161` word
  - 输出 `4` 维 -> `2` word

## 5. param_pool 推荐布局

建议 shared SRAM 参数区固定如下：

```text
0x6000_0000  param_pool.mlp_key_l0      // 2 -> 32
0x6000_0400  param_pool.mlp_key_l1      // 32 -> 64
0x6000_2000  param_pool.mlp_key_l2      // 64 -> 128
0x6000_7000  param_pool.mlp_key_l3      // 128 -> 64
0x6000_C000  param_pool.mlp_key_l4      // 64 -> 32
0x6000_E000  param_pool.mlp_other_l0    // 6 -> 32
0x6000_E400  param_pool.mlp_other_l1    // 32 -> 32
0x6002_0000  param_pool.classifier_l0_chunk0 // 322 -> 256, 8 chunks, stride 0x6000
0x6005_0000  param_pool.classifier_l1_chunk0 // 256 -> 128, 4 chunks, stride 0x5000
0x6006_4000  param_pool.classifier_l2        // 128 -> 64
0x6006_9000  param_pool.classifier_l3        // 64 -> 4
0x6007_0000  param_pool.cnn1d_reserved
```

### 5.1 为什么这样分

- 每个子网络独立一段，便于 debug。
- CPU boot 阶段一次性装入。
- descriptor 只需要切换 `param_addr`。
- 后续如果重导权重，不影响其他子网布局。

### 5.2 参数加载策略

boot 阶段：

1. CPU 从编译进程序的数组或 ROM blob 中读出参数
2. 写入 shared SRAM 固定参数区
3. 后续每次推理不再重写参数区

## 6. 双缓冲任务区推荐布局

```text
0x6001_0000  desc0
0x6001_0100  in_buf0
0x6001_0400  out_buf0
0x6001_0800  scratch0

0x6001_1000  desc1
0x6001_1100  in_buf1
0x6001_1400  out_buf1
0x6001_1800  scratch1
```

### 6.1 设计意图

- `desc0/1`：双缓冲任务描述
- `in_buf0/1`：双缓冲输入
- `out_buf0/1`：双缓冲输出
- `scratch0/1`：给分类头和后续 tile 中间数据留空间

### 6.2 运行节奏

- TPU 用 `buf0` 运行当前任务时
- CPU 准备 `buf1` 的下一任务
- 然后轮换

## 7. descriptor 最终建议

```c
typedef struct {
    uint32_t net_id;
    uint32_t input_addr;
    uint32_t output_addr;
    uint32_t param_addr;
    uint32_t scratch_addr;
    uint32_t input_words;
    uint32_t output_words;
    uint32_t flags;
} tpu_desc_t;
```

### 7.1 flags 建议位定义

```c
#define TPU_DESC_F_RELU          (1u << 0)
#define TPU_DESC_F_BUFSEL        (1u << 1)
#define TPU_DESC_F_LAST_STAGE    (1u << 2)
#define TPU_DESC_F_DEBUG_DUMP    (1u << 3)
#define TPU_DESC_F_TILE2X2_Q8_8  (1u << 16)
```

说明：

- 第一版不要把 flags 做太花。
- 先给少量控制位，足够调试和双缓冲就行。
- `TPU_DESC_F_TILE2X2_Q8_8` 当前已经在 RTL 中落地为 packed Q8.8 linear 模式：每个 output word 生成两个 Q8.8 lane，每个 output word 对应 `2 * input_words + 1` 个 param word。
- `MLP_KEY` 当前由 5 个 descriptor 顺序完成：`2 -> 32`、`32 -> 64`、`64 -> 128`、`128 -> 64`、`64 -> 32`。
- `MLP_OTHER` 当前由 2 个 descriptor 顺序完成：`6 -> 32`、`32 -> 32`。
- 每层 descriptor 只描述本层的 `input_addr/output_addr/param_addr/input_words/output_words/flags`，CPU 负责把上一层输出地址接成下一层输入地址。

## 8. CPU 软件文件规划

这些文件当前已经有最小骨架，后续继续扩展：

### 8.1 头文件

- `software/include/tpu_desc.h`
  - 放 `tpu_desc_t`
  - 放 `tpu_net_meta_t`
  - 放 `NET_ID_*`
  - 放 shared SRAM 地址宏

- `software/include/tpu_regs.h`
  - 放 TPU 控制寄存器偏移
  - 放 `CTRL/STATUS/DESC_LO/DESC_HI/PERF`

- `software/include/tpu_runtime.h`
  - 放 CPU 侧对外 API

### 8.2 源文件

- `software/lib/tpu_runtime.c`
  - `tpu_runtime_init()`
  - `tpu_load_param_pool()`
  - `tpu_submit_desc()`
  - `tpu_wait_done()`
  - `tpu_run_net()`
  - 当前已能编译成 `breath_tpu_soc_demo` 并通过 CPU boot 顶层仿真发起 21 次 TPU launch
  - `NET_ID_MLP_KEY` 已接入 `TILE2X2_Q8_8` 软件用例：CPU 连续驱动 `2 -> 32 -> 64 -> 128 -> 64 -> 32`，中间结果在 `out0/out1/scratch0/scratch1` 间轮转
  - `NET_ID_MLP_OTHER` 已接入 `TILE2X2_Q8_8` 软件用例：CPU 连续驱动 `6 -> 32 -> 32`，当前使用 deterministic identity-style 参数验证 tile 调度和 DMA 写回
  - `NET_ID_CLASSIFIER` 已接入 `TILE2X2_Q8_8` 分块软件用例：CPU 连续驱动 `322 -> 256 -> 128 -> 64 -> 4`，其中前两层按 output chunk 分块

- `software/lib/tpu_pack.c`
  - 特征和向量打包工具
  - `q8.8` 打包/拆包
  - `322` 维融合向量打包

- `software/lib/breath_pipeline.c`
  - CPU 侧算法管线编排
  - 先跑特征提取和 CNN
  - 再调用多个 TPU 子任务

### 8.3 demo 目录

建议新增：

- `software/test/breath_tpu_soc_demo/Makefile`
- `software/test/breath_tpu_soc_demo/main.c`

这个 demo 的职责是：

- 准备一组固定输入
- 调 `tpu_runtime_init()`
- 加载参数区
- 依次触发：
  - `NET_ID_MLP_KEY`
  - `NET_ID_MLP_OTHER`
  - `NET_ID_CLASSIFIER`
- 最后打印或写 signature

## 9. CPU 侧 API 建议

```c
void tpu_runtime_init(void);
void tpu_load_param_pool(void);
int  tpu_submit_desc(const tpu_desc_t *desc);
int  tpu_wait_done(uint32_t timeout);
int  tpu_run_net(uint32_t net_id,
                 uint32_t input_addr,
                 uint32_t output_addr,
                 uint32_t scratch_addr,
                 uint32_t flags);
```

### 9.1 上层 pipeline API 建议

```c
int breath_run_window(const int16_t *raw_1000,
                      const int16_t *features_8,
                      uint32_t *result_class);
```

职责：

1. CPU 本地执行 `CNN1D`
2. CPU 触发 `MLP_KEY`
3. CPU 触发 `MLP_OTHER`
4. CPU 组织 322 维融合向量
5. CPU 触发 `CLASSIFIER`
6. CPU 回收最终 4 类结果

## 10. 最小 demo 的执行顺序

### 10.1 上电初始化

1. `init.c / start.S` 进入 C 环境
2. 初始化 UART（如果保留）
3. `tpu_runtime_init()`
4. `tpu_load_param_pool()`

### 10.2 单窗口推理

1. CPU 取 `1000` 点窗口
2. CPU 计算 `8` 个统计特征
3. CPU 执行 `CNN1D` 分支
4. CPU 组织 `MLP_KEY` 输入并触发 TPU
5. CPU 组织 `MLP_OTHER` 输入并触发 TPU
6. CPU 拼 `322` 维融合向量
7. CPU 触发 `CLASSIFIER`
8. CPU 读分类输出
9. CPU 打印或写 signature

### 10.3 连续窗口版

- 当前窗口跑 `buf0`
- CPU 同时准备下一窗口 `buf1`
- 让 `CPU data master` 和 `TPU DMA master` 同时碰 shared SRAM
- 作为仲裁真实生效的 directed test

## 11. 验证建议

最少做 3 级验证：

1. `driver/unit` 级
- descriptor 填写和地址打包对不对
- `q8.8` pack/unpack 对不对

2. `soc/e2e` 级
- CPU 写 descriptor
- TPU DMA 取数
- TPU 跑一个 `net_id`
- CPU 读结果

3. `concurrency` 级
- TPU DMA 跑 `buf0`
- CPU 同时往 `buf1` 写下一任务输入
- 波形里看到两个 master 真实争用 shared SRAM

当前已新增一个不依赖 `torch` 的 deterministic software golden：

```bash
python3 work/600_competition_5stage/scripts/check_breath_tpu_soc_golden.py
```

它覆盖当前 21 次 launch 的 descriptor 顺序、Q8.8 packed linear 计算、classifier 分块参数区和关键输出。它不是最终真实模型 accuracy golden，下一步仍要导入 `best_model.pth` 的量化权重后再做真实 golden 对比。

## 12. 当前最大的未决实现点

### 12.1 cache/coherency

当前第一版已经采用 shared SRAM uncached bypass：

- `panda_soc_stage2_base_top.v` 里把 `0x6000_0000` shared SRAM 段接成 `ext_mem_uncached="true"`。
- CPU 访问 shared SRAM 时不走 DCache 数据阵列，而是通过单拍 ICB/AXI 旁路进入 shared SRAM。
- 这比简单把 `EN_DCACHE=false` 更稳，因为 `EN_DCACHE=false` 会把原来的 `m_axi_dcache_*` 外存路径 tie-off。

当前边界：

- 第一版不做复杂 cache maintenance。
- shared SRAM 段按硬件约定为 uncached 区。
- 如果以后把 TPU DMA 指向普通可缓存内存，再需要 cache flush/invalidate 或一致性协议。

### 12.2 分类头输入很大

`322` 维分类头对 `2x2` TinyTPU 来说可以做，但一定是：

- tile 化
- 多次调用
- 时间换面积

这不是问题，反而正好是项目价值点。

## 13. 下一批最值得直接开工的文件

如果下一步开始写代码，优先顺序建议是：

1. 把当前 SoC 顶层 `shared_sram_init_file` 的 real-params 仿真初始化方式替换成板上可用的 bootloader/ROM/外部配置流。
2. 继续把 `tpu_desc_fetch_dma_stub.v` 的 input/param stream 接到真实 TinyTPU UB/load 或 systolic/PE datapath。
3. 保持 `NET_ID=0/1/2` 的 21 次 launch CPU boot 回归，同时把真实模型 golden 从当前固定 demo 输入扩展到更多样本。
4. 后补 `tb_panda_soc_stage2_smoke.sv` 的 top-level MMIO BFM 收口。

当前真实参数产物可重复生成，不再要求先找到可用 PyTorch 环境；`export_breath_linear_q8_8_params.py` 默认 `--loader auto`，会在 `torch.load()` 不可用时自动回退到不依赖 torch 的 `torchzip` checkpoint reader。

推荐重生产物命令：

```bash
python3 work/600_competition_5stage/scripts/prepare_breath_tpu_real_param_preload.py
cd work/600_competition_5stage/fpga/panda_soc_eva/tb
./run_vcs_stage2_cpu_boot_real_params.sh
./run_vcs_stage2_cpu_boot.sh
```

如果只想强制不用 torch 导出参数：

```bash
python3 work/600_competition_5stage/scripts/export_breath_linear_q8_8_params.py --loader torchzip
```

## 14. 2026-04-18 当前验证状态

已完成：

- 确定性参数路径：`TPU_RUNTIME_PARAM_POOL_PRELOADED=0`，CPU boot 顶层 VCS 通过，21 次 launch 全部完成。
- 真实 Q8.8 参数导出：生成 `software/generated/breath_tpu_params_q8_8.h` 和 manifest。
- 真实参数池预加载：生成 `fpga/stage2_programs/breath_tpu_params_q8_8/breath_tpu_param_pool_q8_8.mem` 和 expected JSON。
- 真实参数 CPU boot 路径：`TPU_RUNTIME_PARAM_POOL_PRELOADED=1`，使用独立 IMEM，并通过 SoC 顶层 `shared_sram_init_file` 预加载 shared SRAM，VCS 通过，最终输出 `0x001CFE5C 0xFE3D03B3`。

当前注意点：

- 真实参数 header 直接编入 CPU 镜像会导致 flash/stack 溢出，因此当前采用 shared SRAM 预加载；后续如果要上板，需要把这条路径替换成 bootloader/ROM/外部配置流加载。
- 当前 `$readmemh` 已收敛到 `panda_soc_shared_mem_subsys` 内部的可选仿真初始化路径，并用 `SHARED_SRAM_INIT_DELAY=1` 避开 `axi_ram` time-0 清零竞争；TB 只检查关键参数字后释放 CPU reset。
