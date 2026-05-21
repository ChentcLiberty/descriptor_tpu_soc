/************************************************************************************************************************
TPU descriptor / fixed-table 定义(接口头文件)
@brief  CPU+TPU 异构 SoC 的 descriptor、固定表、共享内存地址定义
@date   2026/04/17
************************************************************************************************************************/

#include <stdint.h>

#ifndef __TPU_DESC_H
#define __TPU_DESC_H

// TPU 子网络编号
#define NET_ID_MLP_KEY           0u
#define NET_ID_MLP_OTHER         1u
#define NET_ID_CLASSIFIER        2u
#define NET_ID_CNN1D_RESERVED    3u

// TPU 网络家族
#define TPU_FAMILY_MLP           0u
#define TPU_FAMILY_HEAD          1u
#define TPU_FAMILY_CNN1D         2u

// descriptor flags
#define TPU_DESC_F_RELU          (1u << 0)
#define TPU_DESC_F_BUFSEL        (1u << 1)
#define TPU_DESC_F_LAST_STAGE    (1u << 2)
#define TPU_DESC_F_DEBUG_DUMP    (1u << 3)
#define TPU_DESC_F_TILE2X2_Q8_8  (1u << 16)

// shared SRAM 参数区
#define TPU_PARAM_POOL_MLP_KEY_BASE        0x60000000u
#define TPU_PARAM_POOL_MLP_KEY_L1_BASE     0x60000400u
#define TPU_PARAM_POOL_MLP_KEY_L2_BASE     0x60002000u
#define TPU_PARAM_POOL_MLP_KEY_L3_BASE     0x60007000u
#define TPU_PARAM_POOL_MLP_KEY_L4_BASE     0x6000C000u
#define TPU_PARAM_POOL_MLP_OTHER_BASE      0x6000E000u
#define TPU_PARAM_POOL_MLP_OTHER_L1_BASE   0x6000E400u
#define TPU_PARAM_POOL_CLASSIFIER_BASE     0x60020000u
#define TPU_PARAM_POOL_CLASSIFIER_L0_BASE  0x60020000u
#define TPU_PARAM_POOL_CLASSIFIER_L1_BASE  0x60050000u
#define TPU_PARAM_POOL_CLASSIFIER_L2_BASE  0x60064000u
#define TPU_PARAM_POOL_CLASSIFIER_L3_BASE  0x60069000u
#define TPU_PARAM_POOL_CNN1D_RSVD_BASE     0x60070000u

#define TPU_PARAM_POOL_CLASSIFIER_L0_STRIDE_BYTES 0x00006000u
#define TPU_PARAM_POOL_CLASSIFIER_L1_STRIDE_BYTES 0x00005000u

// 当前 demo / DMA stub 使用的参数字数
#define TPU_PARAM_POOL_MLP_KEY_WORDS       48u
#define TPU_PARAM_POOL_MLP_KEY_L1_WORDS    1056u
#define TPU_PARAM_POOL_MLP_KEY_L2_WORDS    4160u
#define TPU_PARAM_POOL_MLP_KEY_L3_WORDS    4128u
#define TPU_PARAM_POOL_MLP_KEY_L4_WORDS    1040u
#define TPU_PARAM_POOL_MLP_OTHER_WORDS     112u
#define TPU_PARAM_POOL_MLP_OTHER_L1_WORDS  528u
#define TPU_PARAM_POOL_CLASSIFIER_WORDS    5168u
#define TPU_PARAM_POOL_CLASSIFIER_L0_WORDS 5168u
#define TPU_PARAM_POOL_CLASSIFIER_L1_WORDS 4112u
#define TPU_PARAM_POOL_CLASSIFIER_L2_WORDS 4128u
#define TPU_PARAM_POOL_CLASSIFIER_L3_WORDS 130u
#define TPU_PARAM_POOL_CNN1D_RSVD_WORDS    71168u

// classifier 分块 tile schedule
#define TPU_CLASSIFIER_INPUT_WORDS         161u
#define TPU_CLASSIFIER_L0_INPUT_WORDS      161u
#define TPU_CLASSIFIER_L0_OUTPUT_WORDS     128u
#define TPU_CLASSIFIER_L0_CHUNK_WORDS      16u
#define TPU_CLASSIFIER_L0_CHUNKS           8u
#define TPU_CLASSIFIER_L1_INPUT_WORDS      128u
#define TPU_CLASSIFIER_L1_OUTPUT_WORDS     64u
#define TPU_CLASSIFIER_L1_CHUNK_WORDS      16u
#define TPU_CLASSIFIER_L1_CHUNKS           4u
#define TPU_CLASSIFIER_L2_INPUT_WORDS      64u
#define TPU_CLASSIFIER_L2_OUTPUT_WORDS     32u
#define TPU_CLASSIFIER_L3_INPUT_WORDS      32u
#define TPU_CLASSIFIER_L3_OUTPUT_WORDS     2u

// shared SRAM 双缓冲任务区
#define TPU_DESC0_BASE                     0x60010000u
#define TPU_IN_BUF0_BASE                   0x60010100u
#define TPU_OUT_BUF0_BASE                  0x60010400u
#define TPU_SCRATCH0_BASE                  0x60010800u

#define TPU_DESC1_BASE                     0x60011000u
#define TPU_IN_BUF1_BASE                   0x60011100u
#define TPU_OUT_BUF1_BASE                  0x60011400u
#define TPU_SCRATCH1_BASE                  0x60011800u

// classifier 激活/中间结果区
#define TPU_CLASSIFIER_IN_BASE             0x60012000u
#define TPU_CLASSIFIER_L0_OUT_BASE         0x60012400u
#define TPU_CLASSIFIER_L1_OUT_BASE         0x60012800u
#define TPU_CLASSIFIER_L2_OUT_BASE         0x60012C00u
#define TPU_CLASSIFIER_OUT_BASE            0x60013000u
#define TPU_CLASSIFIER_SCRATCH_BASE        0x60013400u

// classifier 融合输入布局：16 + 1 + 128 + 16 = 161 word
#define TPU_CLASSIFIER_FUSION_MLP_KEY_OFS_WORDS    0u
#define TPU_CLASSIFIER_FUSION_MLP_KEY_WORDS        16u
#define TPU_CLASSIFIER_FUSION_RAW_KEY_OFS_WORDS    16u
#define TPU_CLASSIFIER_FUSION_RAW_KEY_WORDS        1u
#define TPU_CLASSIFIER_FUSION_CNN_OFS_WORDS        17u
#define TPU_CLASSIFIER_FUSION_CNN_WORDS            128u
#define TPU_CLASSIFIER_FUSION_MLP_OTHER_OFS_WORDS  145u
#define TPU_CLASSIFIER_FUSION_MLP_OTHER_WORDS      16u

// CNN1D front-end 共享区
#define TPU_CNN1D_SIGNAL_BASE               0x60120000u
#define TPU_CNN1D_SIGNAL_WORDS             500u
#define TPU_CNN1D_FEATURE_BASE             0x60121000u
#define TPU_CNN1D_FEATURE_WORDS            4u
#define TPU_CNN1D_SCRATCH_BASE             0x60100000u
#define TPU_CNN1D_OUT_BASE                 0x60122000u
#define TPU_CNN1D_OUT_WORDS                128u

// software-only dcache eviction 区
#define TPU_CACHE_EVICT_REGION0_BASE       0x60700000u
#define TPU_CACHE_EVICT_REGION1_BASE       0x60702000u
#define TPU_DCACHE_LINE_BYTES              16u
#define TPU_DCACHE_SET_COUNT               128u
#define TPU_DCACHE_SET_STRIDE              (TPU_DCACHE_LINE_BYTES * TPU_DCACHE_SET_COUNT)
#define TPU_DCACHE_EVICT_TAGS              3u

#define TPU_BUF_COUNT                      2u
#define TPU_DESC_WORDS                     8u
#define TPU_DEMO_OUTPUT_DUMP_WORDS         4u

typedef struct{
    uint32_t net_id;
    uint32_t input_addr;
    uint32_t output_addr;
    uint32_t param_addr;
    uint32_t scratch_addr;
    uint32_t input_words;
    uint32_t output_words;
    uint32_t flags;
}TPUDesc;

typedef struct{
    uint32_t net_id;
    uint32_t family;
    uint32_t imem_slot;
    uint32_t input_words;
    uint32_t output_words;
    uint32_t param_words;
    uint32_t need_scratch;
}TPUNetMeta;

typedef struct{
    uint32_t desc_addr;
    uint32_t input_addr;
    uint32_t output_addr;
    uint32_t scratch_addr;
}TPUBufferLayout;

#endif
