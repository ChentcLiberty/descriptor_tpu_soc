#include <stdint.h>

#include "../../include/tpu_desc.h"
#include "breath_cpu_frontend.h"

#ifndef BREATH_TPU_SOC_USE_CPU_FRONTEND
#define BREATH_TPU_SOC_USE_CPU_FRONTEND 0
#endif

#ifndef BREATH_CPU_FRONTEND_USE_SW_CNN
#define BREATH_CPU_FRONTEND_USE_SW_CNN 0
#endif

#ifndef BREATH_CPU_FRONTEND_PREPROCESS_RAW
#define BREATH_CPU_FRONTEND_PREPROCESS_RAW 0
#endif

#if BREATH_TPU_SOC_USE_CPU_FRONTEND
#include "../../generated/breath_cpu_frontend_q8_8_layout.h"
#if !BREATH_CPU_FRONTEND_USE_SW_CNN
#include "../../generated/breath_cpu_frontend_fixture.h"
#endif
#endif

static volatile uint32_t* frontend_word_ptr(uint32_t addr){
    return (volatile uint32_t*)(uintptr_t)addr;
}

static void frontend_copy_words(uint32_t dst_addr, const uint32_t* src_words, uint32_t word_count){
    for(uint32_t i = 0u;i < word_count;i++){
        frontend_word_ptr(dst_addr)[i] = src_words[i];
    }
}

static void frontend_copy_shared_words(uint32_t dst_addr, uint32_t src_addr, uint32_t word_count){
    for(uint32_t i = 0u;i < word_count;i++){
        frontend_word_ptr(dst_addr)[i] = frontend_word_ptr(src_addr)[i];
    }
}

#if BREATH_TPU_SOC_USE_CPU_FRONTEND
static uint32_t g_frontend_hw_cnn_ready;
#endif

#if BREATH_TPU_SOC_USE_CPU_FRONTEND && (BREATH_CPU_FRONTEND_USE_SW_CNN || BREATH_CPU_FRONTEND_PREPROCESS_RAW)
#if BREATH_CPU_FRONTEND_USE_SW_CNN
static uint32_t g_frontend_cnn_ready;
#endif
#if BREATH_CPU_FRONTEND_PREPROCESS_RAW
static uint32_t g_frontend_preprocess_ready;
#endif

static int16_t frontend_read_q16(uint32_t base_addr, uint32_t value_index){
    uint32_t word = frontend_word_ptr(base_addr)[value_index >> 1];
    uint32_t raw = (value_index & 1u) ? (word >> 16) : (word & 0xFFFFu);
    return (int16_t)(uint16_t)raw;
}

static void frontend_write_q16(uint32_t base_addr, uint32_t value_index, int16_t value){
    volatile uint32_t* word_ptr = frontend_word_ptr(base_addr) + (value_index >> 1);
    uint32_t word = *word_ptr;
    uint32_t raw = (uint16_t)value;

    if(value_index & 1u){
        word = (word & 0x0000FFFFu) | (raw << 16);
    }
    else{
        word = (word & 0xFFFF0000u) | raw;
    }
    *word_ptr = word;
}

static int32_t frontend_read_s32(uint32_t base_addr, uint32_t word_index){
    return (int32_t)frontend_word_ptr(base_addr)[word_index];
}

static int64_t frontend_round_shift_s64(int64_t value, uint32_t shift){
    int64_t add;

    if(shift == 0u){
        return value;
    }
    add = (int64_t)1 << (shift - 1u);
    if(value >= 0){
        return (value + add) >> shift;
    }
    return -(((-value) + add) >> shift);
}

static int16_t frontend_sat_q16(int32_t value){
    if(value > 32767){
        return (int16_t)32767;
    }
    if(value < -32768){
        return (int16_t)-32768;
    }
    return (int16_t)value;
}

static int16_t frontend_sat_q16_s64(int64_t value){
    if(value > 32767){
        return (int16_t)32767;
    }
    if(value < -32768){
        return (int16_t)-32768;
    }
    return (int16_t)value;
}

static int16_t frontend_relu_q16(int16_t value){
    return (value < 0) ? (int16_t)0 : value;
}

#if BREATH_CPU_FRONTEND_PREPROCESS_RAW
static uint64_t frontend_isqrt_u64(uint64_t value){
    uint64_t rem = value;
    uint64_t root = 0u;
    uint64_t bit = (uint64_t)1 << 62;

    while(bit > rem){
        bit >>= 2;
    }

    while(bit != 0u){
        if(rem >= root + bit){
            rem -= root + bit;
            root = (root >> 1) + bit;
        }
        else{
            root >>= 1;
        }
        bit >>= 2;
    }

    return root;
}

static int32_t frontend_signed_lshift_div(int64_t value, uint32_t shift, uint64_t divisor){
    uint64_t numerator;
    uint64_t quotient;

    if(divisor == 0u){
        return 0;
    }

    if(value < 0){
        numerator = ((uint64_t)(-value)) << shift;
        quotient = numerator / divisor;
        if(quotient > 2147483648ull){
            return (int32_t)0x80000000u;
        }
        return -(int32_t)quotient;
    }

    numerator = ((uint64_t)value) << shift;
    quotient = numerator / divisor;
    if(quotient > 2147483647ull){
        return (int32_t)0x7FFFFFFF;
    }
    return (int32_t)quotient;
}

static int16_t frontend_normalize_q8_8(int32_t raw_value, int32_t mean_value, int32_t inv_std_value, uint32_t shift){
    int64_t centered = (int64_t)raw_value - (int64_t)mean_value;
    int64_t scaled = centered * (int64_t)inv_std_value;
    return frontend_sat_q16_s64(frontend_round_shift_s64(scaled, shift));
}

static int32_t frontend_extract_dominant_freq_q28(void){
    uint64_t best_score = 0u;
    uint32_t best_bin = 0u;

    for(uint32_t bin = 0u;bin < BREATH_CPU_FRONTEND_WELCH_BINS;bin++){
        uint64_t score = 0u;
        uint32_t table_base = bin * BREATH_CPU_FRONTEND_WELCH_NPERSEG;

        for(uint32_t start = 0u;
            start + BREATH_CPU_FRONTEND_WELCH_NPERSEG <= BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES;
            start += BREATH_CPU_FRONTEND_WELCH_STEP){
            int64_t seg_sum = 0;
            int64_t real_acc = 0;
            int64_t imag_acc = 0;
            int32_t seg_mean;

            for(uint32_t i = 0u;i < BREATH_CPU_FRONTEND_WELCH_NPERSEG;i++){
                seg_sum += frontend_read_s32(BREATH_CPU_FRONTEND_RAW_SIGNAL_BASE, start + i);
            }
            seg_mean = (int32_t)(seg_sum / (int64_t)BREATH_CPU_FRONTEND_WELCH_NPERSEG);

            for(uint32_t i = 0u;i < BREATH_CPU_FRONTEND_WELCH_NPERSEG;i++){
                int32_t sample_q30 = frontend_read_s32(BREATH_CPU_FRONTEND_RAW_SIGNAL_BASE, start + i);
                int32_t x_q20 = (sample_q30 - seg_mean) >> 10;
                int32_t win_q15 = frontend_read_q16(BREATH_CPU_FRONTEND_WELCH_WINDOW_BASE, i);
                int32_t cos_q15 = frontend_read_q16(BREATH_CPU_FRONTEND_WELCH_COS_BASE, table_base + i);
                int32_t sin_q15 = frontend_read_q16(BREATH_CPU_FRONTEND_WELCH_SIN_BASE, table_base + i);
                int32_t xw_q20 = (int32_t)frontend_round_shift_s64((int64_t)x_q20 * win_q15, 15u);

                real_acc += frontend_round_shift_s64((int64_t)xw_q20 * cos_q15, 15u);
                imag_acc -= frontend_round_shift_s64((int64_t)xw_q20 * sin_q15, 15u);
            }

            score += (uint64_t)(real_acc * real_acc) + (uint64_t)(imag_acc * imag_acc);
        }

        if((bin == 0u) || (score > best_score)){
            best_score = score;
            best_bin = bin;
        }
    }

    return (int32_t)((uint64_t)best_bin * BREATH_CPU_FRONTEND_WELCH_FS_HZ * BREATH_CPU_FRONTEND_RAW_FEATURE_SCALE / BREATH_CPU_FRONTEND_WELCH_NPERSEG);
}

static void frontend_compute_raw_features_q28(int32_t* features_q28){
    int64_t sum_q30 = 0;
    int32_t min_q30 = frontend_read_s32(BREATH_CPU_FRONTEND_RAW_SIGNAL_BASE, 0u);
    int32_t max_q30 = min_q30;
    int32_t mean_q30;
    uint64_t m2_q60 = 0u;
    uint64_t energy_q60 = 0u;
    uint64_t m2_q36 = 0u;
    int64_t m3_q54 = 0;
    uint64_t m2_q32 = 0u;
    uint64_t m4_q64 = 0u;
    uint32_t zero_cross = 0u;
    int32_t prev_sign;

    for(uint32_t i = 0u;i < BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES;i++){
        int32_t sample = frontend_read_s32(BREATH_CPU_FRONTEND_RAW_SIGNAL_BASE, i);
        sum_q30 += sample;
        if(sample < min_q30){
            min_q30 = sample;
        }
        if(sample > max_q30){
            max_q30 = sample;
        }
        energy_q60 += (uint64_t)((int64_t)sample * (int64_t)sample);
    }

    mean_q30 = (int32_t)(sum_q30 / (int64_t)BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES);
    prev_sign = (frontend_read_s32(BREATH_CPU_FRONTEND_RAW_SIGNAL_BASE, 0u) > 0) ? 1 :
        ((frontend_read_s32(BREATH_CPU_FRONTEND_RAW_SIGNAL_BASE, 0u) < 0) ? -1 : 0);

    for(uint32_t i = 0u;i < BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES;i++){
        int32_t sample = frontend_read_s32(BREATH_CPU_FRONTEND_RAW_SIGNAL_BASE, i);
        int64_t diff_q30 = (int64_t)sample - (int64_t)mean_q30;
        int64_t diff_q18 = diff_q30 >> 12;
        int64_t diff_q16 = diff_q30 >> 14;
        int32_t sign = (sample > 0) ? 1 : ((sample < 0) ? -1 : 0);

        m2_q60 += (uint64_t)(diff_q30 * diff_q30);
        m2_q36 += (uint64_t)(diff_q18 * diff_q18);
        m3_q54 += diff_q18 * diff_q18 * diff_q18;
        m2_q32 += (uint64_t)(diff_q16 * diff_q16);
        m4_q64 += (uint64_t)(diff_q16 * diff_q16 * diff_q16 * diff_q16);

        if(i != 0u && sign != prev_sign){
            zero_cross++;
        }
        prev_sign = sign;
    }

    m2_q60 /= BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES;
    m2_q36 /= BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES;
    m3_q54 /= (int64_t)BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES;
    m2_q32 /= BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES;
    m4_q64 /= BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES;

    features_q28[0] = frontend_extract_dominant_freq_q28();
    features_q28[1] = (int32_t)(frontend_isqrt_u64(m2_q60) >> 2);
    features_q28[2] = mean_q30 >> 2;
    features_q28[3] = (max_q30 - min_q30) >> 2;

    {
        uint64_t sqrt_m2_q18 = frontend_isqrt_u64(m2_q36);
        uint64_t skew_denom_q54 = m2_q36 * sqrt_m2_q18;
        features_q28[4] = frontend_signed_lshift_div(m3_q54, 28u, skew_denom_q54);
    }

    {
        uint64_t kurt_denom_q64 = m2_q32 * m2_q32;
        int32_t kurt = frontend_signed_lshift_div((int64_t)m4_q64, 28u, kurt_denom_q64);
        features_q28[5] = kurt - (int32_t)(3u * BREATH_CPU_FRONTEND_RAW_FEATURE_SCALE);
    }

    features_q28[6] = (int32_t)(energy_q60 >> 32);
    features_q28[7] = (int32_t)(zero_cross * BREATH_CPU_FRONTEND_RAW_FEATURE_SCALE);
}

static void breath_cpu_frontend_preprocess_raw(void){
    int32_t raw_features_q28[BREATH_CPU_FRONTEND_FEATURE_VALUES];

    if(g_frontend_preprocess_ready){
        return;
    }

    frontend_compute_raw_features_q28(raw_features_q28);

    for(uint32_t i = 0u;i < BREATH_CPU_FRONTEND_FEATURE_VALUES;i++){
        int16_t normalized = frontend_normalize_q8_8(raw_features_q28[i],
            frontend_read_s32(BREATH_CPU_FRONTEND_FEATURE_MEAN_BASE, i),
            frontend_read_s32(BREATH_CPU_FRONTEND_FEATURE_INV_STD_BASE, i),
            BREATH_CPU_FRONTEND_FEATURE_NORM_SHIFT);
        frontend_write_q16(BREATH_CPU_FRONTEND_FEATURE_BASE, i, normalized);
    }

    for(uint32_t i = 0u;i < BREATH_CPU_FRONTEND_SIGNAL_VALUES;i++){
        int16_t normalized = frontend_normalize_q8_8(frontend_read_s32(BREATH_CPU_FRONTEND_RAW_SIGNAL_BASE, i),
            frontend_read_s32(BREATH_CPU_FRONTEND_SIGNAL_MEAN_BASE, i),
            frontend_read_s32(BREATH_CPU_FRONTEND_SIGNAL_INV_STD_BASE, i),
            BREATH_CPU_FRONTEND_SIGNAL_NORM_SHIFT);
        frontend_write_q16(BREATH_CPU_FRONTEND_SIGNAL_BASE, i, normalized);
    }

    g_frontend_preprocess_ready = 1u;
}
#endif

#if BREATH_CPU_FRONTEND_USE_SW_CNN
static int16_t frontend_conv_at(uint32_t input_base,
                                uint32_t weight_base,
                                uint32_t bias_base,
                                uint32_t in_ch,
                                uint32_t in_len,
                                uint32_t kernel,
                                uint32_t pad,
                                uint32_t out_ch_idx,
                                uint32_t out_pos){
    int64_t acc = ((int64_t)frontend_read_q16(bias_base, out_ch_idx)) << 8;

    for(uint32_t ic = 0u;ic < in_ch;ic++){
        uint32_t input_base_idx = ic * in_len;
        uint32_t weight_base_idx = ((out_ch_idx * in_ch) + ic) * kernel;
        for(uint32_t k = 0u;k < kernel;k++){
            int32_t input_pos = (int32_t)out_pos + (int32_t)k - (int32_t)pad;
            if((input_pos >= 0) && ((uint32_t)input_pos < in_len)){
                int16_t x = frontend_read_q16(input_base, input_base_idx + (uint32_t)input_pos);
                int16_t w = frontend_read_q16(weight_base, weight_base_idx + k);
                acc += (int64_t)x * (int64_t)w;
            }
        }
    }

    return frontend_sat_q16_s64(frontend_round_shift_s64(acc, 8u));
}

static void frontend_conv_relu_pool(uint32_t input_base,
                                    uint32_t output_base,
                                    uint32_t weight_base,
                                    uint32_t bias_base,
                                    uint32_t in_ch,
                                    uint32_t in_len,
                                    uint32_t out_ch,
                                    uint32_t kernel,
                                    uint32_t pad){
    uint32_t pooled_len = in_len >> 1;

    for(uint32_t oc = 0u;oc < out_ch;oc++){
        for(uint32_t p = 0u;p < pooled_len;p++){
            int16_t y0 = frontend_relu_q16(frontend_conv_at(input_base,
                weight_base,
                bias_base,
                in_ch,
                in_len,
                kernel,
                pad,
                oc,
                p << 1));
            int16_t y1 = frontend_relu_q16(frontend_conv_at(input_base,
                weight_base,
                bias_base,
                in_ch,
                in_len,
                kernel,
                pad,
                oc,
                (p << 1) + 1u));
            frontend_write_q16(output_base, oc * pooled_len + p, (y0 >= y1) ? y0 : y1);
        }
    }
}

static void frontend_linear_q8(uint32_t weight_base,
                               uint32_t bias_base,
                               const int16_t* input,
                               int16_t* output,
                               uint32_t in_count,
                               uint32_t out_count,
                               uint32_t relu){
    for(uint32_t oc = 0u;oc < out_count;oc++){
        int64_t acc = ((int64_t)frontend_read_q16(bias_base, oc)) << 8;
        uint32_t weight_base_idx = oc * in_count;
        for(uint32_t i = 0u;i < in_count;i++){
            acc += (int64_t)input[i] * (int64_t)frontend_read_q16(weight_base, weight_base_idx + i);
        }
        output[oc] = frontend_sat_q16_s64(frontend_round_shift_s64(acc, 8u));
        if(relu && (output[oc] < 0)){
            output[oc] = 0;
        }
    }
}

static void frontend_compute_film(int16_t* film_out){
    int16_t film_in[2];
    int16_t film_hidden[BREATH_CPU_FRONTEND_FILM_HIDDEN_VALUES];

    film_in[0] = frontend_read_q16(BREATH_CPU_FRONTEND_FEATURE_BASE, 0u);
    film_in[1] = frontend_read_q16(BREATH_CPU_FRONTEND_FEATURE_BASE, 1u);

    frontend_linear_q8(BREATH_CPU_FRONTEND_FILM_L0_W_BASE,
        BREATH_CPU_FRONTEND_FILM_L0_B_BASE,
        film_in,
        film_hidden,
        2u,
        BREATH_CPU_FRONTEND_FILM_HIDDEN_VALUES,
        1u);

    frontend_linear_q8(BREATH_CPU_FRONTEND_FILM_L2_W_BASE,
        BREATH_CPU_FRONTEND_FILM_L2_B_BASE,
        film_hidden,
        film_out,
        BREATH_CPU_FRONTEND_FILM_HIDDEN_VALUES,
        BREATH_CPU_FRONTEND_FILM_OUT_VALUES,
        0u);
}

static int16_t frontend_apply_film(int16_t value, int16_t gamma, int16_t beta){
    int64_t product = (int64_t)(BREATH_CPU_FRONTEND_Q8_8_SCALE + (int32_t)gamma) * (int64_t)value;
    int64_t modulated = frontend_round_shift_s64(product, 8u) + (int64_t)beta;
    int16_t clipped = frontend_sat_q16_s64(modulated);
    return frontend_relu_q16(clipped);
}

static void frontend_conv2_film_relu_pool(const int16_t* film_values){
    uint32_t pooled_len = BREATH_CPU_FRONTEND_CONV2_IN_LEN >> 1;

    for(uint32_t oc = 0u;oc < BREATH_CPU_FRONTEND_CONV2_OUT_CH;oc++){
        int16_t gamma = film_values[oc];
        int16_t beta = film_values[BREATH_CPU_FRONTEND_CONV2_OUT_CH + oc];
        for(uint32_t p = 0u;p < pooled_len;p++){
            int16_t y0 = frontend_conv_at(BREATH_CPU_FRONTEND_BUF0_BASE,
                BREATH_CPU_FRONTEND_CONV2_W_BASE,
                BREATH_CPU_FRONTEND_CONV2_B_BASE,
                BREATH_CPU_FRONTEND_CONV2_IN_CH,
                BREATH_CPU_FRONTEND_CONV2_IN_LEN,
                BREATH_CPU_FRONTEND_CONV2_KERNEL,
                BREATH_CPU_FRONTEND_CONV2_PAD,
                oc,
                p << 1);
            int16_t y1 = frontend_conv_at(BREATH_CPU_FRONTEND_BUF0_BASE,
                BREATH_CPU_FRONTEND_CONV2_W_BASE,
                BREATH_CPU_FRONTEND_CONV2_B_BASE,
                BREATH_CPU_FRONTEND_CONV2_IN_CH,
                BREATH_CPU_FRONTEND_CONV2_IN_LEN,
                BREATH_CPU_FRONTEND_CONV2_KERNEL,
                BREATH_CPU_FRONTEND_CONV2_PAD,
                oc,
                (p << 1) + 1u);
            y0 = frontend_apply_film(y0, gamma, beta);
            y1 = frontend_apply_film(y1, gamma, beta);
            frontend_write_q16(BREATH_CPU_FRONTEND_BUF1_BASE, oc * pooled_len + p, (y0 >= y1) ? y0 : y1);
        }
    }
}

static void frontend_conv4_relu_mean(void){
    for(uint32_t oc = 0u;oc < BREATH_CPU_FRONTEND_CONV4_OUT_CH;oc++){
        int32_t sum = 0;
        for(uint32_t pos = 0u;pos < BREATH_CPU_FRONTEND_CONV4_IN_LEN;pos++){
            int16_t y = frontend_relu_q16(frontend_conv_at(BREATH_CPU_FRONTEND_BUF0_BASE,
                BREATH_CPU_FRONTEND_CONV4_W_BASE,
                BREATH_CPU_FRONTEND_CONV4_B_BASE,
                BREATH_CPU_FRONTEND_CONV4_IN_CH,
                BREATH_CPU_FRONTEND_CONV4_IN_LEN,
                BREATH_CPU_FRONTEND_CONV4_KERNEL,
                BREATH_CPU_FRONTEND_CONV4_PAD,
                oc,
                pos));
            sum += y;
        }
        frontend_write_q16(BREATH_CPU_FRONTEND_CNN_OUT_BASE,
            oc,
            frontend_sat_q16(sum / (int32_t)BREATH_CPU_FRONTEND_CONV4_IN_LEN));
    }
}

static void breath_cpu_frontend_compute_cnn(void){
    int16_t film_values[BREATH_CPU_FRONTEND_FILM_OUT_VALUES];

    if(g_frontend_cnn_ready){
        return;
    }

#if BREATH_CPU_FRONTEND_PREPROCESS_RAW
    breath_cpu_frontend_preprocess_raw();
#endif

    frontend_conv_relu_pool(BREATH_CPU_FRONTEND_SIGNAL_BASE,
        BREATH_CPU_FRONTEND_BUF0_BASE,
        BREATH_CPU_FRONTEND_CONV1_W_BASE,
        BREATH_CPU_FRONTEND_CONV1_B_BASE,
        BREATH_CPU_FRONTEND_CONV1_IN_CH,
        BREATH_CPU_FRONTEND_CONV1_IN_LEN,
        BREATH_CPU_FRONTEND_CONV1_OUT_CH,
        BREATH_CPU_FRONTEND_CONV1_KERNEL,
        BREATH_CPU_FRONTEND_CONV1_PAD);

    frontend_compute_film(film_values);
    frontend_conv2_film_relu_pool(film_values);

    frontend_conv_relu_pool(BREATH_CPU_FRONTEND_BUF1_BASE,
        BREATH_CPU_FRONTEND_BUF0_BASE,
        BREATH_CPU_FRONTEND_CONV3_W_BASE,
        BREATH_CPU_FRONTEND_CONV3_B_BASE,
        BREATH_CPU_FRONTEND_CONV3_IN_CH,
        BREATH_CPU_FRONTEND_CONV3_IN_LEN,
        BREATH_CPU_FRONTEND_CONV3_OUT_CH,
        BREATH_CPU_FRONTEND_CONV3_KERNEL,
        BREATH_CPU_FRONTEND_CONV3_PAD);

    frontend_conv4_relu_mean();
    g_frontend_cnn_ready = 1u;
}
#endif
#endif

void breath_cpu_frontend_prepare_cnn_frontend(void){
#if BREATH_TPU_SOC_USE_CPU_FRONTEND && BREATH_CPU_FRONTEND_PREPROCESS_RAW
    breath_cpu_frontend_preprocess_raw();
#elif BREATH_TPU_SOC_USE_CPU_FRONTEND && BREATH_CPU_FRONTEND_USE_SW_CNN
#if BREATH_CPU_FRONTEND_PREPROCESS_RAW
    breath_cpu_frontend_preprocess_raw();
#endif
#endif
}

void breath_cpu_frontend_mark_cnn_output_ready(void){
#if BREATH_TPU_SOC_USE_CPU_FRONTEND
    g_frontend_hw_cnn_ready = 1u;
#endif
}

uint32_t breath_cpu_frontend_cnn_signal_addr(void){
#if BREATH_TPU_SOC_USE_CPU_FRONTEND
    return BREATH_CPU_FRONTEND_SIGNAL_BASE;
#else
    return 0u;
#endif
}

uint32_t breath_cpu_frontend_cnn_output_addr(void){
#if BREATH_TPU_SOC_USE_CPU_FRONTEND
    return BREATH_CPU_FRONTEND_CNN_OUT_BASE;
#else
    return 0u;
#endif
}

void breath_cpu_frontend_prepare_mlp_key_input(uint32_t dst_addr){
#if BREATH_TPU_SOC_USE_CPU_FRONTEND && BREATH_CPU_FRONTEND_PREPROCESS_RAW
    breath_cpu_frontend_preprocess_raw();
    frontend_copy_shared_words(dst_addr, BREATH_CPU_FRONTEND_FEATURE_BASE, TPU_CLASSIFIER_FUSION_RAW_KEY_WORDS);
#elif BREATH_TPU_SOC_USE_CPU_FRONTEND && BREATH_CPU_FRONTEND_USE_SW_CNN
    frontend_copy_shared_words(dst_addr, BREATH_CPU_FRONTEND_FEATURE_BASE, TPU_CLASSIFIER_FUSION_RAW_KEY_WORDS);
#elif BREATH_TPU_SOC_USE_CPU_FRONTEND
    frontend_copy_words(dst_addr, g_breath_cpu_frontend_mlp_key_words, BREATH_CPU_FRONTEND_MLP_KEY_WORDS);
#else
    (void)dst_addr;
#endif
}

void breath_cpu_frontend_prepare_mlp_other_input(uint32_t dst_addr){
#if BREATH_TPU_SOC_USE_CPU_FRONTEND && BREATH_CPU_FRONTEND_PREPROCESS_RAW
    breath_cpu_frontend_preprocess_raw();
    frontend_copy_shared_words(dst_addr,
        BREATH_CPU_FRONTEND_FEATURE_BASE + 4u,
        BREATH_CPU_FRONTEND_FEATURE_WORDS - 1u);
#elif BREATH_TPU_SOC_USE_CPU_FRONTEND && BREATH_CPU_FRONTEND_USE_SW_CNN
    frontend_copy_shared_words(dst_addr,
        BREATH_CPU_FRONTEND_FEATURE_BASE + 4u,
        BREATH_CPU_FRONTEND_FEATURE_WORDS - 1u);
#elif BREATH_TPU_SOC_USE_CPU_FRONTEND
    frontend_copy_words(dst_addr, g_breath_cpu_frontend_mlp_other_words, BREATH_CPU_FRONTEND_MLP_OTHER_WORDS);
#else
    (void)dst_addr;
#endif
}

void breath_cpu_frontend_prepare_classifier_input(uint32_t fusion_base_addr,
                                                  uint32_t mlp_key_out_addr,
                                                  uint32_t mlp_other_out_addr){
#if BREATH_TPU_SOC_USE_CPU_FRONTEND
    if(g_frontend_hw_cnn_ready){
        frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_MLP_KEY_OFS_WORDS << 2),
            mlp_key_out_addr,
            TPU_CLASSIFIER_FUSION_MLP_KEY_WORDS);

        frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_RAW_KEY_OFS_WORDS << 2),
            BREATH_CPU_FRONTEND_FEATURE_BASE,
            TPU_CLASSIFIER_FUSION_RAW_KEY_WORDS);

        frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_CNN_OFS_WORDS << 2),
            BREATH_CPU_FRONTEND_CNN_OUT_BASE,
            TPU_CLASSIFIER_FUSION_CNN_WORDS);

        frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_MLP_OTHER_OFS_WORDS << 2),
            mlp_other_out_addr,
            TPU_CLASSIFIER_FUSION_MLP_OTHER_WORDS);
        return;
    }
#endif

#if BREATH_TPU_SOC_USE_CPU_FRONTEND && BREATH_CPU_FRONTEND_USE_SW_CNN
    breath_cpu_frontend_compute_cnn();

    frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_MLP_KEY_OFS_WORDS << 2),
        mlp_key_out_addr,
        TPU_CLASSIFIER_FUSION_MLP_KEY_WORDS);

    frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_RAW_KEY_OFS_WORDS << 2),
        BREATH_CPU_FRONTEND_FEATURE_BASE,
        TPU_CLASSIFIER_FUSION_RAW_KEY_WORDS);

    frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_CNN_OFS_WORDS << 2),
        BREATH_CPU_FRONTEND_CNN_OUT_BASE,
        TPU_CLASSIFIER_FUSION_CNN_WORDS);

    frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_MLP_OTHER_OFS_WORDS << 2),
        mlp_other_out_addr,
        TPU_CLASSIFIER_FUSION_MLP_OTHER_WORDS);
#elif BREATH_TPU_SOC_USE_CPU_FRONTEND
    frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_MLP_KEY_OFS_WORDS << 2),
        mlp_key_out_addr,
        TPU_CLASSIFIER_FUSION_MLP_KEY_WORDS);

    frontend_copy_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_RAW_KEY_OFS_WORDS << 2),
        g_breath_cpu_frontend_raw_key_words,
        BREATH_CPU_FRONTEND_RAW_KEY_WORDS);

    frontend_copy_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_CNN_OFS_WORDS << 2),
        g_breath_cpu_frontend_cnn_words,
        BREATH_CPU_FRONTEND_CNN_WORDS);

    frontend_copy_shared_words(fusion_base_addr + (TPU_CLASSIFIER_FUSION_MLP_OTHER_OFS_WORDS << 2),
        mlp_other_out_addr,
        TPU_CLASSIFIER_FUSION_MLP_OTHER_WORDS);
#else
    (void)fusion_base_addr;
    (void)mlp_key_out_addr;
    (void)mlp_other_out_addr;
#endif
}

uint32_t breath_cpu_frontend_expected_label(void){
#if BREATH_TPU_SOC_USE_CPU_FRONTEND
    return BREATH_CPU_FRONTEND_EXPECTED_LABEL;
#else
    return 0u;
#endif
}
