#include <stdint.h>

#include "../../include/utils.h"
#include "../../include/tpu_runtime.h"

#ifndef BREATH_TPU_SOC_DEMO_USE_UART
#define BREATH_TPU_SOC_DEMO_USE_UART 1
#endif

#ifndef BREATH_TPU_SOC_USE_CPU_FRONTEND
#define BREATH_TPU_SOC_USE_CPU_FRONTEND 0
#endif

#ifndef BREATH_TPU_SOC_USE_HW_CNN_FRONTEND
#define BREATH_TPU_SOC_USE_HW_CNN_FRONTEND 0
#endif

#if BREATH_TPU_SOC_USE_CPU_FRONTEND
#include "breath_cpu_frontend.h"
#endif

#if BREATH_TPU_SOC_DEMO_USE_UART
#include "../../include/apb_uart.h"
#include "../../include/xprintf.h"
#define UART0_BASEADDE 0x40003000u
#define DEMO_LOG(...) xprintf(__VA_ARGS__)

static ApbUART uart0;

static void uart_putc(uint8_t c){
    while(apb_uart_send_byte(&uart0, c));
}

static void demo_log_init(void){
    apb_uart_init(&uart0, UART0_BASEADDE);
    xdev_out(uart_putc);
}
#else
#define DEMO_LOG(...) do {} while(0)
static void demo_log_init(void){}
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define TPU_WAIT_TIMEOUT_DEFAULT 500000u
#define TPU_WAIT_TIMEOUT_CNN1D   30000000u

static volatile uint32_t* shared_word_ptr(uint32_t addr){
    return (volatile uint32_t*)(uintptr_t)addr;
}

static void print_desc(const TPUDesc* desc){
    DEMO_LOG("desc.net_id      = %d\r\n", desc->net_id);
    DEMO_LOG("desc.input_addr  = 0x%08x\r\n", desc->input_addr);
    DEMO_LOG("desc.output_addr = 0x%08x\r\n", desc->output_addr);
    DEMO_LOG("desc.param_addr  = 0x%08x\r\n", desc->param_addr);
    DEMO_LOG("desc.scratch_addr= 0x%08x\r\n", desc->scratch_addr);
    DEMO_LOG("desc.input_words = %d\r\n", desc->input_words);
    DEMO_LOG("desc.output_words= %d\r\n", desc->output_words);
    DEMO_LOG("desc.flags       = 0x%08x\r\n", desc->flags);
}

static int submit_and_dump_stage_timeout(const TPUDesc* desc, const char* stage_name, uint32_t timeout_cycles){
    uint32_t output_dump[TPU_DEMO_OUTPUT_DUMP_WORDS] = {0u};
    int wait_rc;

    DEMO_LOG("\r\n[%s]\r\n", stage_name);
    DEMO_LOG("active_buf_id    = %d\r\n", g_tpu_runtime.active_buf_id);
    DEMO_LOG("active_desc_addr = 0x%08x\r\n", g_tpu_runtime.active_desc_addr);
    print_desc(desc);

    tpu_submit_desc(&g_tpu_runtime, desc);

#if TPU_RUNTIME_USE_MMIO
    wait_rc = tpu_wait_done(&g_tpu_runtime, timeout_cycles);
    DEMO_LOG("wait_done rc     = %d\r\n", wait_rc);
#else
    wait_rc = 0;
    DEMO_LOG("wait_done skipped (MMIO disabled)\r\n");
#endif

    tpu_read_output_words(desc, output_dump, TPU_DEMO_OUTPUT_DUMP_WORDS);
    DEMO_LOG("out[0..3]        = %08x %08x %08x %08x\r\n",
        output_dump[0], output_dump[1], output_dump[2], output_dump[3]);

    return wait_rc;
}

static int submit_and_dump_stage(const TPUDesc* desc, const char* stage_name){
    return submit_and_dump_stage_timeout(desc, stage_name, TPU_WAIT_TIMEOUT_DEFAULT);
}

static void run_demo_stage(uint32_t net_id, uint8_t buf_id, uint32_t flags, const char* stage_name){
    TPUDesc desc;

    tpu_select_desc_buffer(&g_tpu_runtime, buf_id);
#if BREATH_TPU_SOC_USE_CPU_FRONTEND
    if(net_id == NET_ID_MLP_KEY){
        breath_cpu_frontend_prepare_mlp_key_input(g_tpu_runtime.active_input_addr);
    }
    else if(net_id == NET_ID_MLP_OTHER){
        breath_cpu_frontend_prepare_mlp_other_input(g_tpu_runtime.active_input_addr);
    }
    else{
        tpu_prepare_demo_input(&g_tpu_runtime, net_id);
    }
#else
    tpu_prepare_demo_input(&g_tpu_runtime, net_id);
#endif
    tpu_build_desc(&desc,
        net_id,
        g_tpu_runtime.active_input_addr,
        g_tpu_runtime.active_output_addr,
        g_tpu_runtime.active_scratch_addr,
        flags);

    (void)submit_and_dump_stage(&desc, stage_name);
}

#if BREATH_TPU_SOC_USE_CPU_FRONTEND && BREATH_TPU_SOC_USE_HW_CNN_FRONTEND
static void run_cnn_frontend_stage(uint8_t buf_id, const char* stage_name){
    TPUDesc desc;

    tpu_select_desc_buffer(&g_tpu_runtime, buf_id);
    breath_cpu_frontend_prepare_cnn_frontend();
    tpu_build_cnn1d_desc(&desc,
        breath_cpu_frontend_cnn_output_addr(),
        TPU_CNN1D_SCRATCH_BASE,
        0u);

    DEMO_LOG("cnn.signal_addr  = 0x%08x\r\n", breath_cpu_frontend_cnn_signal_addr());
    DEMO_LOG("cnn.output_addr  = 0x%08x\r\n", breath_cpu_frontend_cnn_output_addr());
    DEMO_LOG("cnn.scratch_addr = 0x%08x\r\n", TPU_CNN1D_SCRATCH_BASE);

    if(submit_and_dump_stage_timeout(&desc, stage_name, TPU_WAIT_TIMEOUT_CNN1D) == 0){
        breath_cpu_frontend_mark_cnn_output_ready();
    }
}
#endif

static void run_linear_stage_flags(uint32_t net_id,
                                   uint8_t buf_id,
                                   uint32_t input_addr,
                                   uint32_t output_addr,
                                   uint32_t param_addr,
                                   uint32_t scratch_addr,
                                   uint32_t input_words,
                                   uint32_t output_words,
                                   uint32_t flags,
                                   const char* stage_name){
    TPUDesc desc;

    tpu_select_desc_buffer(&g_tpu_runtime, buf_id);

    desc.net_id = net_id;
    desc.input_addr = input_addr;
    desc.output_addr = output_addr;
    desc.param_addr = param_addr;
    desc.scratch_addr = scratch_addr;
    desc.input_words = input_words;
    desc.output_words = output_words;
    desc.flags = flags;

    (void)submit_and_dump_stage(&desc, stage_name);
}

static void run_linear_stage(uint32_t net_id,
                             uint8_t buf_id,
                             uint32_t input_addr,
                             uint32_t output_addr,
                             uint32_t param_addr,
                             uint32_t scratch_addr,
                             uint32_t input_words,
                             uint32_t output_words,
                             const char* stage_name){
    run_linear_stage_flags(net_id,
        buf_id,
        input_addr,
        output_addr,
        param_addr,
        scratch_addr,
        input_words,
        output_words,
        TPU_DESC_F_RELU | TPU_DESC_F_TILE2X2_Q8_8,
        stage_name);
}

static void copy_shared_words(uint32_t dst_addr, uint32_t src_addr, uint32_t word_count){
    for(uint32_t i = 0u;i < word_count;i++){
        shared_word_ptr(dst_addr)[i] = shared_word_ptr(src_addr)[i];
    }
}

static void prepare_classifier_demo_input(void){
#if BREATH_TPU_SOC_USE_CPU_FRONTEND
    breath_cpu_frontend_prepare_classifier_input(TPU_CLASSIFIER_IN_BASE,
        TPU_OUT_BUF0_BASE,
        TPU_SCRATCH1_BASE);
#else
    copy_shared_words(TPU_CLASSIFIER_IN_BASE + (TPU_CLASSIFIER_FUSION_MLP_KEY_OFS_WORDS << 2),
        TPU_OUT_BUF0_BASE,
        TPU_CLASSIFIER_FUSION_MLP_KEY_WORDS);

    shared_word_ptr(TPU_CLASSIFIER_IN_BASE)[TPU_CLASSIFIER_FUSION_RAW_KEY_OFS_WORDS] = 0x02000100u;

    for(uint32_t i = 0u;i < TPU_CLASSIFIER_FUSION_CNN_WORDS;i++){
        shared_word_ptr(TPU_CLASSIFIER_IN_BASE)[TPU_CLASSIFIER_FUSION_CNN_OFS_WORDS + i] = 0x00000200u + i;
    }

    copy_shared_words(TPU_CLASSIFIER_IN_BASE + (TPU_CLASSIFIER_FUSION_MLP_OTHER_OFS_WORDS << 2),
        TPU_SCRATCH1_BASE,
        TPU_CLASSIFIER_FUSION_MLP_OTHER_WORDS);
#endif
}

static void run_classifier_schedule(void){
    uint8_t buf_id = 0u;

    prepare_classifier_demo_input();

    for(uint32_t chunk = 0u;chunk < TPU_CLASSIFIER_L0_CHUNKS;chunk++){
        uint32_t param_addr = TPU_PARAM_POOL_CLASSIFIER_L0_BASE + (chunk * TPU_PARAM_POOL_CLASSIFIER_L0_STRIDE_BYTES);
        uint32_t output_addr = TPU_CLASSIFIER_L0_OUT_BASE + ((chunk * TPU_CLASSIFIER_L0_CHUNK_WORDS) << 2);
        run_linear_stage(NET_ID_CLASSIFIER,
            buf_id,
            TPU_CLASSIFIER_IN_BASE,
            output_addr,
            param_addr,
            TPU_CLASSIFIER_SCRATCH_BASE,
            TPU_CLASSIFIER_L0_INPUT_WORDS,
            TPU_CLASSIFIER_L0_CHUNK_WORDS,
            "CLASSIFIER_L0_322_TO_256_CHUNK");
        buf_id ^= 0x1u;
    }

    for(uint32_t chunk = 0u;chunk < TPU_CLASSIFIER_L1_CHUNKS;chunk++){
        uint32_t param_addr = TPU_PARAM_POOL_CLASSIFIER_L1_BASE + (chunk * TPU_PARAM_POOL_CLASSIFIER_L1_STRIDE_BYTES);
        uint32_t output_addr = TPU_CLASSIFIER_L1_OUT_BASE + ((chunk * TPU_CLASSIFIER_L1_CHUNK_WORDS) << 2);
        run_linear_stage(NET_ID_CLASSIFIER,
            buf_id,
            TPU_CLASSIFIER_L0_OUT_BASE,
            output_addr,
            param_addr,
            TPU_CLASSIFIER_SCRATCH_BASE,
            TPU_CLASSIFIER_L1_INPUT_WORDS,
            TPU_CLASSIFIER_L1_CHUNK_WORDS,
            "CLASSIFIER_L1_256_TO_128_CHUNK");
        buf_id ^= 0x1u;
    }

    run_linear_stage(NET_ID_CLASSIFIER,
        buf_id,
        TPU_CLASSIFIER_L1_OUT_BASE,
        TPU_CLASSIFIER_L2_OUT_BASE,
        TPU_PARAM_POOL_CLASSIFIER_L2_BASE,
        TPU_CLASSIFIER_SCRATCH_BASE,
        TPU_CLASSIFIER_L2_INPUT_WORDS,
        TPU_CLASSIFIER_L2_OUTPUT_WORDS,
        "CLASSIFIER_L2_128_TO_64");
    buf_id ^= 0x1u;

    run_linear_stage_flags(NET_ID_CLASSIFIER,
        buf_id,
        TPU_CLASSIFIER_L2_OUT_BASE,
        TPU_CLASSIFIER_OUT_BASE,
        TPU_PARAM_POOL_CLASSIFIER_L3_BASE,
        TPU_CLASSIFIER_SCRATCH_BASE,
        TPU_CLASSIFIER_L3_INPUT_WORDS,
        TPU_CLASSIFIER_L3_OUTPUT_WORDS,
        TPU_DESC_F_TILE2X2_Q8_8 | TPU_DESC_F_LAST_STAGE,
        "CLASSIFIER_L3_64_TO_4");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
    demo_log_init();

    tpu_runtime_init(&g_tpu_runtime, TPU_CTRL_BASEADDR);
    tpu_load_param_pool();

    DEMO_LOG("breath_tpu_soc_demo start\r\n");
    DEMO_LOG("TPU runtime regs_base = 0x%08x\r\n", g_tpu_runtime.regs_baseaddr);
    DEMO_LOG("param_pool loaded: key=0x%08x other=0x%08x classifier=0x%08x\r\n",
        TPU_PARAM_POOL_MLP_KEY_BASE,
        TPU_PARAM_POOL_MLP_OTHER_BASE,
        TPU_PARAM_POOL_CLASSIFIER_BASE);
#if BREATH_TPU_SOC_USE_CPU_FRONTEND
    DEMO_LOG("cpu_frontend sample label = %d\r\n", breath_cpu_frontend_expected_label());
#if BREATH_TPU_SOC_USE_HW_CNN_FRONTEND
    DEMO_LOG("cpu_frontend hw cnn path = enabled\r\n");
#else
    DEMO_LOG("cpu_frontend hw cnn path = disabled\r\n");
#endif
#endif

    run_demo_stage(NET_ID_MLP_KEY, 0u, TPU_DESC_F_RELU | TPU_DESC_F_TILE2X2_Q8_8, "MLP_KEY_L0_2_TO_32");
    run_linear_stage(NET_ID_MLP_KEY, 1u, TPU_OUT_BUF0_BASE, TPU_SCRATCH0_BASE, TPU_PARAM_POOL_MLP_KEY_L1_BASE, TPU_SCRATCH0_BASE + 0x400u, 16u, 32u, "MLP_KEY_L1_32_TO_64");
    run_linear_stage(NET_ID_MLP_KEY, 0u, TPU_SCRATCH0_BASE, TPU_OUT_BUF1_BASE, TPU_PARAM_POOL_MLP_KEY_L2_BASE, TPU_OUT_BUF1_BASE + 0x400u, 32u, 64u, "MLP_KEY_L2_64_TO_128");
    run_linear_stage(NET_ID_MLP_KEY, 1u, TPU_OUT_BUF1_BASE, TPU_SCRATCH1_BASE, TPU_PARAM_POOL_MLP_KEY_L3_BASE, TPU_SCRATCH1_BASE + 0x400u, 64u, 32u, "MLP_KEY_L3_128_TO_64");
    run_linear_stage(NET_ID_MLP_KEY, 0u, TPU_SCRATCH1_BASE, TPU_OUT_BUF0_BASE, TPU_PARAM_POOL_MLP_KEY_L4_BASE, TPU_SCRATCH0_BASE + 0x400u, 32u, 16u, "MLP_KEY_L4_64_TO_32");
    run_demo_stage(NET_ID_MLP_OTHER, 1u, TPU_DESC_F_RELU | TPU_DESC_F_TILE2X2_Q8_8, "MLP_OTHER_L0_6_TO_32");
    run_linear_stage(NET_ID_MLP_OTHER, 0u, TPU_OUT_BUF1_BASE, TPU_SCRATCH1_BASE, TPU_PARAM_POOL_MLP_OTHER_L1_BASE, TPU_SCRATCH1_BASE + 0x400u, 16u, 16u, "MLP_OTHER_L1_32_TO_32");
#if BREATH_TPU_SOC_USE_CPU_FRONTEND && BREATH_TPU_SOC_USE_HW_CNN_FRONTEND
    run_cnn_frontend_stage(0u, "CNN_FRONTEND_NET3");
#endif
    run_classifier_schedule();

    DEMO_LOG("breath_tpu_soc_demo end\r\n");

    while(1){
    }
}
