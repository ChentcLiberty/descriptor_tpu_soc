#ifndef BREATH_CPU_FRONTEND_H
#define BREATH_CPU_FRONTEND_H

#include <stdint.h>

void breath_cpu_frontend_prepare_mlp_key_input(uint32_t dst_addr);
void breath_cpu_frontend_prepare_mlp_other_input(uint32_t dst_addr);
void breath_cpu_frontend_prepare_cnn_frontend(void);
void breath_cpu_frontend_mark_cnn_output_ready(void);
void breath_cpu_frontend_prepare_classifier_input(uint32_t fusion_base_addr,
                                                  uint32_t mlp_key_out_addr,
                                                  uint32_t mlp_other_out_addr);
uint32_t breath_cpu_frontend_cnn_signal_addr(void);
uint32_t breath_cpu_frontend_cnn_output_addr(void);
uint32_t breath_cpu_frontend_expected_label(void);

#endif
