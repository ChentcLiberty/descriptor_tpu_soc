#!/usr/bin/env python3
"""Export CPU-side CNN/FiLM front-end data for the breath TPU SoC demo.

This script keeps the CPU program small: the RISC-V CPU executes fixed-point
CNN/FiLM loops, while large weights, the normalized test signal, and normalized
features are preloaded into shared SRAM through a sparse $readmemh image. The
same image also contains the exported TPU Linear/MLP/classifier param pool.
"""

import argparse
import csv
import json
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from export_breath_linear_q8_8_params import load_state_dict, q8_8, pack_i16, require_key
import gen_breath_tpu_param_pool_init as tpu_pool

DEFAULT_CHECKPOINT = Path('/home/jjt/soc/算法/Breathrecognitionbest/checkpoints/best_model.pth')
DEFAULT_CSV_DIR = Path('/home/jjt/soc/算法/Breathrecognitionbest/csv')
DEFAULT_TPU_HEADER = ROOT / 'work/600_competition_5stage/software/generated/breath_tpu_params_q8_8.h'
DEFAULT_OUT_DIR = ROOT / 'work/600_competition_5stage/software/generated'
DEFAULT_MEM_DIR = ROOT / 'work/600_competition_5stage/fpga/stage2_programs/breath_cpu_frontend_q8_8'
DEFAULT_TB_OUT = ROOT / 'work/600_competition_5stage/software/generated/breath_cpu_frontend_q8_8_expected.svh'
DEFAULT_RTL_EXPECTED_JSON = ROOT / 'work/600_competition_5stage/software/generated/breath_cpu_frontend_q8_8_rtl_expected.json'
DEFAULT_RTL_TB_OUT = ROOT / 'work/600_competition_5stage/software/generated/breath_cpu_frontend_q8_8_rtl_expected.svh'
DEFAULT_RTL_DIFF_MD = ROOT / 'work/600_competition_5stage/software/generated/breath_cpu_frontend_q8_8_rtl_diff.md'

SHARED_BASE = 0x60000000
CPU_WEIGHT_BASE = 0x60070000
CPU_BUF0_BASE = 0x60100000
CPU_BUF1_BASE = 0x60110000
CPU_SIGNAL_BASE = 0x60120000
CPU_FEATURE_BASE = 0x60121000
CPU_CNN_OUT_BASE = 0x60122000
CPU_RAW_SIGNAL_BASE = 0x60123000
CPU_FEATURE_MEAN_BASE = 0x60124000
CPU_FEATURE_INV_STD_BASE = 0x60124100
CPU_SIGNAL_MEAN_BASE = 0x60125000
CPU_SIGNAL_INV_STD_BASE = 0x60126000
CPU_WELCH_WINDOW_BASE = 0x60127000
CPU_WELCH_COS_BASE = 0x60128000
CPU_WELCH_SIN_BASE = 0x60139000
CPU_REGION_LIMIT = 0x60700000

Q_SCALE = 256
RAW_SIGNAL_SCALE = 1 << 30
RAW_FEATURE_SCALE = 1 << 28
INV_STD_SCALE = 1 << 20
WELCH_TRIG_SCALE = 1 << 15
WELCH_NPERSEG = 256
WELCH_STEP = 128
WELCH_BINS = WELCH_NPERSEG // 2 + 1
WELCH_FS_HZ = 50

FEATURE_COLS = [
    'dominant_freq',
    'std',
    'mean',
    'peak_to_peak',
    'skewness',
    'kurtosis',
    'energy',
    'zero_crossing_rate',
]
SIGNAL_COLS = ['signal_%d' % i for i in range(1000)]
SPLIT_FILES = [
    'breath_train_windows.csv',
    'breath_val_windows.csv',
    'breath_test_windows.csv',
]

# Raw preprocess + NET_ID=3 uses the hardware CNN front-end but still reuses the
# verified fullcore classifier path. Keep the algorithmic export as-is, and pin
# a separate RTL baseline for the end-to-end classifier outputs that have been
# validated in the long SoC regression.
RAW_NET3_FULLCORE_WATCHPOINT_OVERRIDES = {
    'mlp_key_out_words': {
        0: 0x001700B6,
        15: 0x0000008B,
    },
    'mlp_other_out_words': {
        0: 0x00AC0000,
        15: 0x004A0018,
    },
    'classifier_l2_out_words': {
        0: 0x00000029,
        31: 0x0000002E,
    },
    'classifier_final_out_words': {
        0: 0xFE4A01CF,
        1: 0xFECB01F2,
    },
}


def read_windows(csv_path):
    rows = []
    with csv_path.open(newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            features = np.asarray([float(row[name]) for name in FEATURE_COLS], dtype=np.float32)
            signal = np.asarray([float(row[name]) for name in SIGNAL_COLS], dtype=np.float32)
            label = int(row['label'])
            rows.append((features, signal, label))
    return rows


def load_all_splits(csv_dir):
    all_rows = []
    for name in SPLIT_FILES:
        all_rows.extend(read_windows(csv_dir / name))
    if not all_rows:
        raise SystemExit('no rows loaded from %s' % csv_dir)
    features = np.stack([row[0] for row in all_rows], axis=0)
    signals = np.stack([row[1] for row in all_rows], axis=0)
    return features, signals


def standardize(values, mean, std):
    std = np.where(std == 0.0, 1.0, std)
    return (values - mean) / std


def fold_conv_bn(state, conv_prefix, bn_prefix):
    weight = require_key(state, conv_prefix + '.weight').astype(np.float32)
    bias = require_key(state, conv_prefix + '.bias').astype(np.float32)
    gamma = require_key(state, bn_prefix + '.weight').astype(np.float32)
    beta = require_key(state, bn_prefix + '.bias').astype(np.float32)
    running_mean = require_key(state, bn_prefix + '.running_mean').astype(np.float32)
    running_var = require_key(state, bn_prefix + '.running_var').astype(np.float32)
    eps_value = state.get(bn_prefix + '.eps', None)
    eps = float(eps_value) if eps_value is not None else 1.0e-5
    scale = gamma / np.sqrt(running_var + eps)
    return weight * scale.reshape((-1, 1, 1)), (bias - running_mean) * scale + beta


def linear_params(state, prefix):
    weight = require_key(state, prefix + '.weight').astype(np.float32)
    bias_key = prefix + '.bias'
    if bias_key in state:
        bias = state[bias_key].astype(np.float32)
    else:
        bias = np.zeros((weight.shape[0],), dtype=np.float32)
    return weight, bias


def quantize_vector(values, scale=Q_SCALE):
    qvals = []
    clipped = 0
    for value in np.asarray(values, dtype=np.float32).reshape(-1):
        q, did_clip = q8_8(value, scale)
        qvals.append(q if q < 0x8000 else q - 0x10000)
        clipped += int(did_clip)
    return qvals, clipped


def pack_qvals(qvals):
    if len(qvals) % 2 != 0:
        raise SystemExit('packed vector length must be even, got %d' % len(qvals))
    return [pack_i16(qvals[i], qvals[i + 1]) for i in range(0, len(qvals), 2)]


def quantize_s32(values, scale):
    words = []
    clipped = 0
    for value in np.asarray(values, dtype=np.float64).reshape(-1):
        raw = int(round(float(value) * scale))
        if raw > 2147483647:
            raw = 2147483647
            clipped += 1
        elif raw < -2147483648:
            raw = -2147483648
            clipped += 1
        words.append(raw & 0xFFFFFFFF)
    return words, clipped


def q_s32(value, scale):
    raw = int(round(float(value) * scale))
    if raw > 2147483647:
        return 2147483647
    if raw < -2147483648:
        return -2147483648
    return raw


def s32(word):
    word &= 0xFFFFFFFF
    return word - 0x100000000 if word & 0x80000000 else word


def isqrt_u64(value):
    if value <= 0:
        return 0
    return int(math.isqrt(int(value)))


def round_shift_signed(value, shift):
    value = int(value)
    if shift <= 0:
        return value << (-shift)
    add = 1 << (shift - 1)
    if value >= 0:
        return (value + add) >> shift
    return -(((-value) + add) >> shift)


def sat_i16(value):
    value = int(value)
    if value > 32767:
        return 32767
    if value < -32768:
        return -32768
    return value


def build_welch_tables():
    n = np.arange(WELCH_NPERSEG, dtype=np.float64)
    window = 0.5 - 0.5 * np.cos((2.0 * np.pi * n) / WELCH_NPERSEG)
    window_q = [q_s32(x, WELCH_TRIG_SCALE) for x in window]
    cos_q = []
    sin_q = []
    for k in range(WELCH_BINS):
        angle = (2.0 * np.pi * k * n) / WELCH_NPERSEG
        cos_q.extend(q_s32(x, WELCH_TRIG_SCALE) for x in np.cos(angle))
        sin_q.extend(q_s32(x, WELCH_TRIG_SCALE) for x in np.sin(angle))
    return window_q, cos_q, sin_q


def extract_dominant_freq_q28(raw_signal_q30, window_q15, cos_q15, sin_q15):
    best_bin = 0
    best_score = -1
    starts = range(0, len(raw_signal_q30) - WELCH_NPERSEG + 1, WELCH_STEP)
    for bin_idx in range(WELCH_BINS):
        score = 0
        table_base = bin_idx * WELCH_NPERSEG
        for start in starts:
            segment = raw_signal_q30[start:start + WELCH_NPERSEG]
            seg_mean = sum(segment) // WELCH_NPERSEG
            real_acc = 0
            imag_acc = 0
            for i, sample in enumerate(segment):
                x_q20 = (sample - seg_mean) >> 10
                xw_q20 = round_shift_signed(x_q20 * window_q15[i], 15)
                real_acc += round_shift_signed(xw_q20 * cos_q15[table_base + i], 15)
                imag_acc -= round_shift_signed(xw_q20 * sin_q15[table_base + i], 15)
            score += real_acc * real_acc + imag_acc * imag_acc
        if score > best_score:
            best_score = score
            best_bin = bin_idx
    return best_bin * WELCH_FS_HZ * RAW_FEATURE_SCALE // WELCH_NPERSEG


def extract_cpu_raw_features_q28(raw_signal_q30, window_q15, cos_q15, sin_q15):
    n = len(raw_signal_q30)
    mean_q30 = sum(raw_signal_q30) // n
    min_q30 = min(raw_signal_q30)
    max_q30 = max(raw_signal_q30)
    diffs_q30 = [x - mean_q30 for x in raw_signal_q30]

    m2_q60 = sum(d * d for d in diffs_q30) // n
    std_q30 = isqrt_u64(m2_q60)
    energy_q28 = sum(x * x for x in raw_signal_q30) >> 32

    diffs_q18 = [d >> 12 for d in diffs_q30]
    m2_q36 = sum(d * d for d in diffs_q18) // n
    m3_q54 = sum(d * d * d for d in diffs_q18) // n
    sqrt_m2_q18 = isqrt_u64(m2_q36)
    skew_denom_q54 = m2_q36 * sqrt_m2_q18
    skew_q28 = 0 if skew_denom_q54 == 0 else int((m3_q54 << 28) // skew_denom_q54)

    diffs_q16 = [d >> 14 for d in diffs_q30]
    m2_q32 = sum(d * d for d in diffs_q16) // n
    m4_q64 = sum(d * d * d * d for d in diffs_q16) // n
    kurt_denom_q64 = m2_q32 * m2_q32
    kurt_q28 = 0 if kurt_denom_q64 == 0 else int((m4_q64 << 28) // kurt_denom_q64) - (3 << 28)

    zero_cross = 0
    prev = 1 if raw_signal_q30[0] > 0 else (-1 if raw_signal_q30[0] < 0 else 0)
    for sample in raw_signal_q30[1:]:
        sign = 1 if sample > 0 else (-1 if sample < 0 else 0)
        if sign != prev:
            zero_cross += 1
        prev = sign

    return [
        extract_dominant_freq_q28(raw_signal_q30, window_q15, cos_q15, sin_q15),
        std_q30 >> 2,
        mean_q30 >> 2,
        (max_q30 - min_q30) >> 2,
        skew_q28,
        kurt_q28,
        energy_q28,
        zero_cross << 28,
    ]


def normalize_q8_8_from_raw(raw_q, mean_q, inv_std_q, shift):
    return sat_i16(round_shift_signed((int(raw_q) - int(mean_q)) * int(inv_std_q), shift))


def cpu_preprocess_q8_8(signal, feature_mean, feature_std, signal_mean, signal_std):
    raw_signal_q30 = [q_s32(x, RAW_SIGNAL_SCALE) for x in signal]
    feature_mean_q28 = [q_s32(x, RAW_FEATURE_SCALE) for x in feature_mean]
    feature_inv_std_q20 = [q_s32(1.0 / (x if x != 0.0 else 1.0), INV_STD_SCALE) for x in feature_std]
    signal_mean_q30 = [q_s32(x, RAW_SIGNAL_SCALE) for x in signal_mean]
    signal_inv_std_q20 = [q_s32(1.0 / (x if x != 0.0 else 1.0), INV_STD_SCALE) for x in signal_std]
    window_q15, cos_q15, sin_q15 = build_welch_tables()

    raw_features_q28 = extract_cpu_raw_features_q28(raw_signal_q30, window_q15, cos_q15, sin_q15)
    feature_q8 = [
        normalize_q8_8_from_raw(raw_features_q28[i], feature_mean_q28[i], feature_inv_std_q20[i], 40)
        for i in range(len(raw_features_q28))
    ]
    signal_q8 = [
        normalize_q8_8_from_raw(raw_signal_q30[i], signal_mean_q30[i], signal_inv_std_q20[i], 42)
        for i in range(len(raw_signal_q30))
    ]
    return {
        'raw_signal_q30': raw_signal_q30,
        'feature_mean_q28': feature_mean_q28,
        'feature_inv_std_q20': feature_inv_std_q20,
        'signal_mean_q30': signal_mean_q30,
        'signal_inv_std_q20': signal_inv_std_q20,
        'welch_window_q15': window_q15,
        'welch_cos_q15': cos_q15,
        'welch_sin_q15': sin_q15,
        'raw_features_q28': raw_features_q28,
        'feature_q8': feature_q8,
        'signal_q8': signal_q8,
    }


def qmul(a, b):
    return (int(a) * int(b)) >> 8


def sat(value):
    value = int(value)
    if value > 32767:
        return 32767
    if value < -32768:
        return -32768
    return value


def relu(value):
    return value if value > 0 else 0


def conv_at(inp, weights, bias, in_ch, in_len, kernel, pad, oc, pos):
    acc = int(bias[oc]) << 8
    for ic in range(in_ch):
        input_base = ic * in_len
        weight_base = ((oc * in_ch + ic) * kernel)
        for k in range(kernel):
            ipos = pos + k - pad
            if 0 <= ipos < in_len:
                acc += int(inp[input_base + ipos]) * int(weights[weight_base + k])
    return sat(round_shift_signed(acc, 8))


def conv_relu_pool(inp, weights, bias, in_ch, in_len, out_ch, kernel, pad):
    pooled_len = in_len // 2
    out = [0] * (out_ch * pooled_len)
    for oc in range(out_ch):
        for p in range(pooled_len):
            y0 = relu(conv_at(inp, weights, bias, in_ch, in_len, kernel, pad, oc, p * 2))
            y1 = relu(conv_at(inp, weights, bias, in_ch, in_len, kernel, pad, oc, p * 2 + 1))
            out[oc * pooled_len + p] = y0 if y0 >= y1 else y1
    return out, pooled_len


def linear_q8(inp, weights, bias, out_count, in_count, do_relu):
    out = []
    for oc in range(out_count):
        acc = int(bias[oc]) << 8
        base = oc * in_count
        for i in range(in_count):
            acc += int(inp[i]) * int(weights[base + i])
        value = sat(round_shift_signed(acc, 8))
        out.append(relu(value) if do_relu else value)
    return out


def conv2_film_relu_pool(inp, weights, bias, in_ch, in_len, out_ch, film):
    pooled_len = in_len // 2
    out = [0] * (out_ch * pooled_len)
    for oc in range(out_ch):
        gamma = int(film[oc])
        beta = int(film[out_ch + oc])
        for p in range(pooled_len):
            pooled = 0
            for lane in range(2):
                y = conv_at(inp, weights, bias, in_ch, in_len, 5, 2, oc, p * 2 + lane)
                mod = round_shift_signed((Q_SCALE + gamma) * int(y), 8) + beta
                mod = relu(sat(mod))
                if lane == 0 or mod > pooled:
                    pooled = mod
            out[oc * pooled_len + p] = pooled
    return out, pooled_len


def conv4_mean(inp, weights, bias, in_len):
    out = [0] * 256
    for oc in range(256):
        total = 0
        for pos in range(in_len):
            total += relu(conv_at(inp, weights, bias, 128, in_len, 3, 1, oc, pos))
        out[oc] = sat(total // in_len)
    return out


def run_cpu_cnn_q8(signal_q, feature_q, params):
    x, len1 = conv_relu_pool(signal_q,
        params['conv1_w'], params['conv1_b'], 1, 1000, 32, 7, 3)
    hidden = linear_q8(feature_q[:2], params['film_l0_w'], params['film_l0_b'], 64, 2, True)
    film = linear_q8(hidden, params['film_l2_w'], params['film_l2_b'], 128, 64, False)
    x, len2 = conv2_film_relu_pool(x, params['conv2_w'], params['conv2_b'], 32, len1, 64, film)
    x, len3 = conv_relu_pool(x,
        params['conv3_w'], params['conv3_b'], 64, len2, 128, 3, 1)
    return conv4_mean(x, params['conv4_w'], params['conv4_b'], len3)


def run_classifier_expected(tpu_arrays, feature_words, cnn_words):
    mem = tpu_pool.Mem()
    for name, words in tpu_arrays.items():
        if name in tpu_pool.ADDR:
            mem.load(tpu_pool.ADDR[name], words)

    mem.load(tpu_pool.TPU_IN_BUF0_BASE, feature_words[:1])
    mem.load(tpu_pool.TPU_IN_BUF1_BASE, feature_words[1:4])

    tpu_pool.run_linear(mem, tpu_pool.TPU_IN_BUF0_BASE, tpu_pool.TPU_OUT_BUF0_BASE, tpu_pool.ADDR['g_tpu_param_mlp_key_l0'], 1, 16, True)
    tpu_pool.run_linear(mem, tpu_pool.TPU_OUT_BUF0_BASE, tpu_pool.TPU_SCRATCH0_BASE, tpu_pool.ADDR['g_tpu_param_mlp_key_l1'], 16, 32, True)
    tpu_pool.run_linear(mem, tpu_pool.TPU_SCRATCH0_BASE, tpu_pool.TPU_OUT_BUF1_BASE, tpu_pool.ADDR['g_tpu_param_mlp_key_l2'], 32, 64, True)
    tpu_pool.run_linear(mem, tpu_pool.TPU_OUT_BUF1_BASE, tpu_pool.TPU_SCRATCH1_BASE, tpu_pool.ADDR['g_tpu_param_mlp_key_l3'], 64, 32, True)
    tpu_pool.run_linear(mem, tpu_pool.TPU_SCRATCH1_BASE, tpu_pool.TPU_OUT_BUF0_BASE, tpu_pool.ADDR['g_tpu_param_mlp_key_l4'], 32, 16, True)

    tpu_pool.run_linear(mem, tpu_pool.TPU_IN_BUF1_BASE, tpu_pool.TPU_OUT_BUF1_BASE, tpu_pool.ADDR['g_tpu_param_mlp_other_l0'], 3, 16, True)
    tpu_pool.run_linear(mem, tpu_pool.TPU_OUT_BUF1_BASE, tpu_pool.TPU_SCRATCH1_BASE, tpu_pool.ADDR['g_tpu_param_mlp_other_l1'], 16, 16, True)

    mem.copy(tpu_pool.TPU_CLASSIFIER_IN_BASE + 0 * 4, tpu_pool.TPU_OUT_BUF0_BASE, 16)
    mem.write(tpu_pool.TPU_CLASSIFIER_IN_BASE + 16 * 4, feature_words[0])
    mem.load(tpu_pool.TPU_CLASSIFIER_IN_BASE + 17 * 4, cnn_words)
    mem.copy(tpu_pool.TPU_CLASSIFIER_IN_BASE + 145 * 4, tpu_pool.TPU_SCRATCH1_BASE, 16)

    for chunk in range(8):
        tpu_pool.run_linear(mem,
            tpu_pool.TPU_CLASSIFIER_IN_BASE,
            tpu_pool.TPU_CLASSIFIER_L0_OUT_BASE + chunk * 16 * 4,
            tpu_pool.ADDR['g_tpu_param_classifier_l0_chunk%d' % chunk],
            161,
            16,
            True)
    for chunk in range(4):
        tpu_pool.run_linear(mem,
            tpu_pool.TPU_CLASSIFIER_L0_OUT_BASE,
            tpu_pool.TPU_CLASSIFIER_L1_OUT_BASE + chunk * 16 * 4,
            tpu_pool.ADDR['g_tpu_param_classifier_l1_chunk%d' % chunk],
            128,
            16,
            True)
    tpu_pool.run_linear(mem, tpu_pool.TPU_CLASSIFIER_L1_OUT_BASE, tpu_pool.TPU_CLASSIFIER_L2_OUT_BASE, tpu_pool.ADDR['g_tpu_param_classifier_l2'], 64, 32, True)
    tpu_pool.run_linear(mem, tpu_pool.TPU_CLASSIFIER_L2_OUT_BASE, tpu_pool.TPU_CLASSIFIER_OUT_BASE, tpu_pool.ADDR['g_tpu_param_classifier_l3'], 32, 2, False)

    return {
        'param_key_words': ['0x%08X' % w for w in mem.read_words(tpu_pool.ADDR['g_tpu_param_mlp_key_l0'], 2)],
        'mlp_key_out_words': ['0x%08X' % w for w in mem.read_words(tpu_pool.TPU_OUT_BUF0_BASE, 16)],
        'mlp_other_out_words': ['0x%08X' % w for w in mem.read_words(tpu_pool.TPU_SCRATCH1_BASE, 16)],
        'cnn_words': ['0x%08X' % w for w in cnn_words],
        'classifier_l2_out_words': ['0x%08X' % w for w in mem.read_words(tpu_pool.TPU_CLASSIFIER_L2_OUT_BASE, 32)],
        'classifier_final_out_words': ['0x%08X' % w for w in mem.read_words(tpu_pool.TPU_CLASSIFIER_OUT_BASE, 2)],
    }


def align(value, boundary):
    return (value + boundary - 1) & ~(boundary - 1)


def check_regions(regions):
    ordered = sorted(regions, key=lambda item: item['base'])
    for left, right in zip(ordered, ordered[1:]):
        left_end = left['base'] + len(left['words']) * 4
        if left_end > right['base']:
            raise SystemExit('shared SRAM region overlap: %s vs %s' % (left['name'], right['name']))
    for region in ordered:
        end = region['base'] + len(region['words']) * 4
        if region['base'] < SHARED_BASE or end > 0x60800000:
            raise SystemExit('shared SRAM region out of range: %s' % region['name'])
    return ordered


def write_sparse_mem(regions, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    ordered = check_regions(regions)
    with path.open('w', encoding='ascii') as f:
        f.write('// Auto-generated sparse shared SRAM init for CPU CNN front-end + TPU param_pool.\n')
        f.write('// Addresses are word offsets from 0x6000_0000 for axi_ram.mem[].\n')
        for region in ordered:
            word_index = (region['base'] - SHARED_BASE) // 4
            f.write('\n// %s @ 0x%08X words=%d\n' % (region['name'], region['base'], len(region['words'])))
            f.write('@%08X\n' % word_index)
            words = region['words']
            for i in range(0, len(words), 8):
                f.write(' '.join('%08X' % word for word in words[i:i + 8]) + '\n')


def add_cpu_region(regions, macros, cursor, name, macro_prefix, words):
    cursor = align(cursor, 0x100)
    if cursor + len(words) * 4 > CPU_REGION_LIMIT:
        raise SystemExit('CPU CNN weight/data region exceeds limit at %s' % name)
    regions.append({'name': name, 'base': cursor, 'words': words})
    macros[macro_prefix + '_BASE'] = cursor
    macros[macro_prefix + '_WORDS'] = len(words)
    return cursor + len(words) * 4


def export_layout_header(path, macros, expected):
    lines = []
    lines.append('/* Auto-generated by export_breath_cpu_frontend_q8_8.py. */')
    lines.append('#ifndef BREATH_CPU_FRONTEND_Q8_8_LAYOUT_H')
    lines.append('#define BREATH_CPU_FRONTEND_Q8_8_LAYOUT_H')
    lines.append('')
    for key in sorted(macros):
        value = macros[key]
        if isinstance(value, int):
            if key.endswith('_BASE'):
                lines.append('#define %s 0x%08Xu' % (key, value))
            else:
                lines.append('#define %s %du' % (key, value))
    final_words = expected['classifier_final_out_words']
    lines.append('#define BREATH_CPU_FRONTEND_EXPECT_CLASSIFIER_OUT0 %su' % final_words[0])
    lines.append('#define BREATH_CPU_FRONTEND_EXPECT_CLASSIFIER_OUT1 %su' % final_words[1])
    lines.append('')
    lines.append('#endif')
    path.write_text('\n'.join(lines) + '\n', encoding='ascii')




def sv_hex(word):
    value = int(str(word), 16) if isinstance(word, str) else int(word)
    return "32'h%08X" % (value & 0xFFFFFFFF)


def apply_watchpoint_overrides(expected, overrides):
    patched = dict(expected)
    for array_name, entries in overrides.items():
        words = list(patched[array_name])
        for word_idx, word_value in entries.items():
            words[word_idx] = '0x%08X' % (int(word_value) & 0xFFFFFFFF)
        patched[array_name] = words
    return patched


def emit_tb_svh(expected, macro_prefix='BREATH_CPU_FRONTEND_Q8_8_EXPECT'):
    guard = macro_prefix + '_SVH'
    lines = []
    lines.append('/* Auto-generated by export_breath_cpu_frontend_q8_8.py. */')
    lines.append('`ifndef %s' % guard)
    lines.append('`define %s' % guard)
    lines.append('')
    for key, value in [
        (macro_prefix + '_PARAM_KEY0', expected['param_key_words'][0]),
        (macro_prefix + '_PARAM_KEY1', expected['param_key_words'][1]),
        (macro_prefix + '_MLP_KEY_OUT0', expected['mlp_key_out_words'][0]),
        (macro_prefix + '_MLP_KEY_OUT15', expected['mlp_key_out_words'][15]),
        (macro_prefix + '_MLP_OTHER_OUT0', expected['mlp_other_out_words'][0]),
        (macro_prefix + '_MLP_OTHER_OUT15', expected['mlp_other_out_words'][15]),
        (macro_prefix + '_CNN_OUT0', expected['cnn_words'][0]),
        (macro_prefix + '_CNN_OUT7', expected['cnn_words'][7]),
        (macro_prefix + '_CNN_OUT31', expected['cnn_words'][31]),
        (macro_prefix + '_CNN_OUT63', expected['cnn_words'][63]),
        (macro_prefix + '_CNN_OUT95', expected['cnn_words'][95]),
        (macro_prefix + '_CNN_OUT127', expected['cnn_words'][127]),
        (macro_prefix + '_CLASSIFIER_L2_OUT0', expected['classifier_l2_out_words'][0]),
        (macro_prefix + '_CLASSIFIER_L2_OUT31', expected['classifier_l2_out_words'][31]),
        (macro_prefix + '_CLASSIFIER_OUT0', expected['classifier_final_out_words'][0]),
        (macro_prefix + '_CLASSIFIER_OUT1', expected['classifier_final_out_words'][1]),
    ]:
        lines.append('`define %s %s' % (key, sv_hex(value)))
    lines.append('')
    lines.append('`endif')
    return '\n'.join(lines) + '\n'


def emit_rtl_diff_md(expected, rtl_expected):
    watchpoint_labels = {
        'mlp_key_out_words': 'mlp_key_out_words',
        'mlp_other_out_words': 'mlp_other_out_words',
        'classifier_l2_out_words': 'classifier_l2_out_words',
        'classifier_final_out_words': 'classifier_final_out_words',
    }
    rows = []
    for array_name, label in watchpoint_labels.items():
        lhs = expected[array_name]
        rhs = rtl_expected[array_name]
        for word_idx, (lhs_word, rhs_word) in enumerate(zip(lhs, rhs)):
            if lhs_word != rhs_word:
                rows.append((label, word_idx, lhs_word, rhs_word))

    lines = []
    lines.append('# breath_cpu_frontend_q8_8 raw RTL diff')
    lines.append('')
    lines.append('Auto-generated by `export_breath_cpu_frontend_q8_8.py`.')
    lines.append('')
    lines.append('## Baselines')
    lines.append('')
    lines.append('- `breath_cpu_frontend_q8_8_expected.*`: algorithmic / software fixed-point reference')
    lines.append('- `breath_cpu_frontend_q8_8_rtl_expected.*`: verified raw `NET_ID=3` RTL baseline')
    lines.append('')
    lines.append('## Summary')
    lines.append('')
    lines.append('- sample_index: `%s`' % expected['sample_index'])
    lines.append('- label: `%s`' % expected['label'])
    lines.append('- differing watchpoints: `%d`' % len(rows))
    lines.append('')
    if rows:
        lines.append('## Differences')
        lines.append('')
        lines.append('| watchpoint | index | algorithmic expected | rtl expected |')
        lines.append('|---|---:|---:|---:|')
        for label, word_idx, lhs_word, rhs_word in rows:
            lines.append('| `%s` | `%d` | `%s` | `%s` |' % (label, word_idx, lhs_word, rhs_word))
        lines.append('')
    else:
        lines.append('## Differences')
        lines.append('')
        lines.append('No watchpoint differences detected.')
        lines.append('')

    unchanged = []
    for key in ['param_key_words', 'cnn_words']:
        if expected[key] == rtl_expected[key]:
            unchanged.append(key)
    if unchanged:
        lines.append('## Unchanged Arrays')
        lines.append('')
        for key in unchanged:
            lines.append('- `%s`' % key)
        lines.append('')

    return '\n'.join(lines)

def export_cpu_frontend(args):
    state, loader_used = load_state_dict(args.checkpoint, args.loader)
    all_features, all_signals = load_all_splits(args.csv_dir)
    feature_mean = all_features.mean(axis=0)
    feature_std = all_features.std(axis=0)
    signal_mean = all_signals.reshape((-1, 1000)).mean(axis=0)
    signal_std = all_signals.reshape((-1, 1000)).std(axis=0)

    test_rows = read_windows(args.csv_dir / 'breath_test_windows.csv')
    if args.sample_index < 0 or args.sample_index >= len(test_rows):
        raise SystemExit('sample index %d out of range 0..%d' % (args.sample_index, len(test_rows) - 1))
    features, signal, label = test_rows[args.sample_index]
    features_norm = standardize(features, feature_mean, feature_std).astype(np.float32)
    signal_norm = standardize(signal, signal_mean, signal_std).astype(np.float32)

    params = {}
    clip_counts = {}
    region_words = {}

    for layer_name, conv_prefix, bn_prefix in [
        ('conv1', 'cnn_extractor.conv1', 'cnn_extractor.bn1'),
        ('conv2', 'cnn_extractor.conv2', 'cnn_extractor.bn2'),
        ('conv3', 'cnn_extractor.conv3', 'cnn_extractor.bn3'),
        ('conv4', 'cnn_extractor.conv4', 'cnn_extractor.bn4'),
    ]:
        weight, bias = fold_conv_bn(state, conv_prefix, bn_prefix)
        wq, wc = quantize_vector(weight.reshape(-1), args.scale)
        bq, bc = quantize_vector(bias.reshape(-1), args.scale)
        params[layer_name + '_w'] = wq
        params[layer_name + '_b'] = bq
        region_words[layer_name + '_w'] = pack_qvals(wq)
        region_words[layer_name + '_b'] = pack_qvals(bq)
        clip_counts[layer_name + '_w'] = wc
        clip_counts[layer_name + '_b'] = bc

    for layer_name, prefix in [
        ('film_l0', 'cnn_extractor.film_generator.0'),
        ('film_l2', 'cnn_extractor.film_generator.2'),
    ]:
        weight, bias = linear_params(state, prefix)
        wq, wc = quantize_vector(weight.reshape(-1), args.scale)
        bq, bc = quantize_vector(bias.reshape(-1), args.scale)
        params[layer_name + '_w'] = wq
        params[layer_name + '_b'] = bq
        region_words[layer_name + '_w'] = pack_qvals(wq)
        region_words[layer_name + '_b'] = pack_qvals(bq)
        clip_counts[layer_name + '_w'] = wc
        clip_counts[layer_name + '_b'] = bc

    pre = cpu_preprocess_q8_8(signal, feature_mean, feature_std, signal_mean, signal_std)
    feature_q = pre['feature_q8']
    signal_q = pre['signal_q8']
    feature_words = pack_qvals(feature_q)
    signal_words = pack_qvals(signal_q)
    raw_signal_words = [word & 0xFFFFFFFF for word in pre['raw_signal_q30']]
    feature_mean_words = [word & 0xFFFFFFFF for word in pre['feature_mean_q28']]
    feature_inv_std_words = [word & 0xFFFFFFFF for word in pre['feature_inv_std_q20']]
    signal_mean_words = [word & 0xFFFFFFFF for word in pre['signal_mean_q30']]
    signal_inv_std_words = [word & 0xFFFFFFFF for word in pre['signal_inv_std_q20']]
    welch_window_words = pack_qvals(pre['welch_window_q15'])
    welch_cos_words = pack_qvals(pre['welch_cos_q15'])
    welch_sin_words = pack_qvals(pre['welch_sin_q15'])
    clip_counts['feature'] = sum(1 for value in feature_q if value in (-32768, 32767))
    clip_counts['signal'] = sum(1 for value in signal_q if value in (-32768, 32767))

    cnn_q = run_cpu_cnn_q8(signal_q, feature_q, params)
    cnn_words = pack_qvals(cnn_q)

    tpu_arrays = tpu_pool.parse_arrays(args.tpu_header)
    expected = run_classifier_expected(tpu_arrays, feature_words, cnn_words)

    regions = []
    for name in sorted(tpu_pool.ADDR, key=lambda item: tpu_pool.ADDR[item]):
        words = tpu_arrays.get(name)
        if words is None:
            raise SystemExit('missing TPU param array in header: %s' % name)
        regions.append({'name': name, 'base': tpu_pool.ADDR[name], 'words': words})

    macros = {
        'BREATH_CPU_FRONTEND_Q8_8_SCALE': int(args.scale),
        'BREATH_CPU_FRONTEND_SAMPLE_INDEX': int(args.sample_index),
        'BREATH_CPU_FRONTEND_EXPECTED_LABEL': int(label),
        'BREATH_CPU_FRONTEND_BUF0_BASE': CPU_BUF0_BASE,
        'BREATH_CPU_FRONTEND_BUF1_BASE': CPU_BUF1_BASE,
        'BREATH_CPU_FRONTEND_SIGNAL_BASE': CPU_SIGNAL_BASE,
        'BREATH_CPU_FRONTEND_SIGNAL_WORDS': len(signal_words),
        'BREATH_CPU_FRONTEND_SIGNAL_VALUES': len(signal_q),
        'BREATH_CPU_FRONTEND_FEATURE_BASE': CPU_FEATURE_BASE,
        'BREATH_CPU_FRONTEND_FEATURE_WORDS': len(feature_words),
        'BREATH_CPU_FRONTEND_FEATURE_VALUES': len(feature_q),
        'BREATH_CPU_FRONTEND_CNN_OUT_BASE': CPU_CNN_OUT_BASE,
        'BREATH_CPU_FRONTEND_CNN_OUT_WORDS': len(cnn_words),
        'BREATH_CPU_FRONTEND_CNN_OUT_VALUES': len(cnn_q),
        'BREATH_CPU_FRONTEND_RAW_SIGNAL_BASE': CPU_RAW_SIGNAL_BASE,
        'BREATH_CPU_FRONTEND_RAW_SIGNAL_WORDS': len(raw_signal_words),
        'BREATH_CPU_FRONTEND_RAW_SIGNAL_VALUES': len(raw_signal_words),
        'BREATH_CPU_FRONTEND_RAW_SIGNAL_SCALE': RAW_SIGNAL_SCALE,
        'BREATH_CPU_FRONTEND_RAW_FEATURE_SCALE': RAW_FEATURE_SCALE,
        'BREATH_CPU_FRONTEND_INV_STD_SCALE': INV_STD_SCALE,
        'BREATH_CPU_FRONTEND_FEATURE_MEAN_BASE': CPU_FEATURE_MEAN_BASE,
        'BREATH_CPU_FRONTEND_FEATURE_MEAN_WORDS': len(feature_mean_words),
        'BREATH_CPU_FRONTEND_FEATURE_INV_STD_BASE': CPU_FEATURE_INV_STD_BASE,
        'BREATH_CPU_FRONTEND_FEATURE_INV_STD_WORDS': len(feature_inv_std_words),
        'BREATH_CPU_FRONTEND_SIGNAL_MEAN_BASE': CPU_SIGNAL_MEAN_BASE,
        'BREATH_CPU_FRONTEND_SIGNAL_MEAN_WORDS': len(signal_mean_words),
        'BREATH_CPU_FRONTEND_SIGNAL_INV_STD_BASE': CPU_SIGNAL_INV_STD_BASE,
        'BREATH_CPU_FRONTEND_SIGNAL_INV_STD_WORDS': len(signal_inv_std_words),
        'BREATH_CPU_FRONTEND_FEATURE_NORM_SHIFT': 40,
        'BREATH_CPU_FRONTEND_SIGNAL_NORM_SHIFT': 42,
        'BREATH_CPU_FRONTEND_WELCH_WINDOW_BASE': CPU_WELCH_WINDOW_BASE,
        'BREATH_CPU_FRONTEND_WELCH_WINDOW_WORDS': len(welch_window_words),
        'BREATH_CPU_FRONTEND_WELCH_COS_BASE': CPU_WELCH_COS_BASE,
        'BREATH_CPU_FRONTEND_WELCH_COS_WORDS': len(welch_cos_words),
        'BREATH_CPU_FRONTEND_WELCH_SIN_BASE': CPU_WELCH_SIN_BASE,
        'BREATH_CPU_FRONTEND_WELCH_SIN_WORDS': len(welch_sin_words),
        'BREATH_CPU_FRONTEND_WELCH_NPERSEG': WELCH_NPERSEG,
        'BREATH_CPU_FRONTEND_WELCH_STEP': WELCH_STEP,
        'BREATH_CPU_FRONTEND_WELCH_BINS': WELCH_BINS,
        'BREATH_CPU_FRONTEND_WELCH_FS_HZ': WELCH_FS_HZ,
        'BREATH_CPU_FRONTEND_CONV1_IN_CH': 1,
        'BREATH_CPU_FRONTEND_CONV1_OUT_CH': 32,
        'BREATH_CPU_FRONTEND_CONV1_IN_LEN': 1000,
        'BREATH_CPU_FRONTEND_CONV1_OUT_LEN': 500,
        'BREATH_CPU_FRONTEND_CONV1_KERNEL': 7,
        'BREATH_CPU_FRONTEND_CONV1_PAD': 3,
        'BREATH_CPU_FRONTEND_CONV2_IN_CH': 32,
        'BREATH_CPU_FRONTEND_CONV2_OUT_CH': 64,
        'BREATH_CPU_FRONTEND_CONV2_IN_LEN': 500,
        'BREATH_CPU_FRONTEND_CONV2_OUT_LEN': 250,
        'BREATH_CPU_FRONTEND_CONV2_KERNEL': 5,
        'BREATH_CPU_FRONTEND_CONV2_PAD': 2,
        'BREATH_CPU_FRONTEND_CONV3_IN_CH': 64,
        'BREATH_CPU_FRONTEND_CONV3_OUT_CH': 128,
        'BREATH_CPU_FRONTEND_CONV3_IN_LEN': 250,
        'BREATH_CPU_FRONTEND_CONV3_OUT_LEN': 125,
        'BREATH_CPU_FRONTEND_CONV3_KERNEL': 3,
        'BREATH_CPU_FRONTEND_CONV3_PAD': 1,
        'BREATH_CPU_FRONTEND_CONV4_IN_CH': 128,
        'BREATH_CPU_FRONTEND_CONV4_OUT_CH': 256,
        'BREATH_CPU_FRONTEND_CONV4_IN_LEN': 125,
        'BREATH_CPU_FRONTEND_CONV4_KERNEL': 3,
        'BREATH_CPU_FRONTEND_CONV4_PAD': 1,
        'BREATH_CPU_FRONTEND_FILM_HIDDEN_VALUES': 64,
        'BREATH_CPU_FRONTEND_FILM_OUT_VALUES': 128,
    }

    cursor = CPU_WEIGHT_BASE
    for key, macro in [
        ('conv1_w', 'BREATH_CPU_FRONTEND_CONV1_W'),
        ('conv1_b', 'BREATH_CPU_FRONTEND_CONV1_B'),
        ('conv2_w', 'BREATH_CPU_FRONTEND_CONV2_W'),
        ('conv2_b', 'BREATH_CPU_FRONTEND_CONV2_B'),
        ('conv3_w', 'BREATH_CPU_FRONTEND_CONV3_W'),
        ('conv3_b', 'BREATH_CPU_FRONTEND_CONV3_B'),
        ('conv4_w', 'BREATH_CPU_FRONTEND_CONV4_W'),
        ('conv4_b', 'BREATH_CPU_FRONTEND_CONV4_B'),
        ('film_l0_w', 'BREATH_CPU_FRONTEND_FILM_L0_W'),
        ('film_l0_b', 'BREATH_CPU_FRONTEND_FILM_L0_B'),
        ('film_l2_w', 'BREATH_CPU_FRONTEND_FILM_L2_W'),
        ('film_l2_b', 'BREATH_CPU_FRONTEND_FILM_L2_B'),
    ]:
        cursor = add_cpu_region(regions, macros, cursor, 'g_breath_cpu_frontend_' + key, macro, region_words[key])

    regions.append({'name': 'g_breath_cpu_frontend_signal', 'base': CPU_SIGNAL_BASE, 'words': signal_words})
    regions.append({'name': 'g_breath_cpu_frontend_features', 'base': CPU_FEATURE_BASE, 'words': feature_words})
    regions.append({'name': 'g_breath_cpu_frontend_raw_signal_q30', 'base': CPU_RAW_SIGNAL_BASE, 'words': raw_signal_words})
    regions.append({'name': 'g_breath_cpu_frontend_feature_mean_q28', 'base': CPU_FEATURE_MEAN_BASE, 'words': feature_mean_words})
    regions.append({'name': 'g_breath_cpu_frontend_feature_inv_std_q20', 'base': CPU_FEATURE_INV_STD_BASE, 'words': feature_inv_std_words})
    regions.append({'name': 'g_breath_cpu_frontend_signal_mean_q30', 'base': CPU_SIGNAL_MEAN_BASE, 'words': signal_mean_words})
    regions.append({'name': 'g_breath_cpu_frontend_signal_inv_std_q20', 'base': CPU_SIGNAL_INV_STD_BASE, 'words': signal_inv_std_words})
    regions.append({'name': 'g_breath_cpu_frontend_welch_window_q15', 'base': CPU_WELCH_WINDOW_BASE, 'words': welch_window_words})
    regions.append({'name': 'g_breath_cpu_frontend_welch_cos_q15', 'base': CPU_WELCH_COS_BASE, 'words': welch_cos_words})
    regions.append({'name': 'g_breath_cpu_frontend_welch_sin_q15', 'base': CPU_WELCH_SIN_BASE, 'words': welch_sin_words})

    args.out_dir.mkdir(parents=True, exist_ok=True)
    args.mem_dir.mkdir(parents=True, exist_ok=True)
    layout_path = args.out_dir / 'breath_cpu_frontend_q8_8_layout.h'
    expected_path = args.out_dir / 'breath_cpu_frontend_q8_8_expected.json'
    tb_expected_path = args.out_dir / 'breath_cpu_frontend_q8_8_expected.svh'
    rtl_expected_path = args.out_dir / DEFAULT_RTL_EXPECTED_JSON.name
    rtl_tb_expected_path = args.out_dir / DEFAULT_RTL_TB_OUT.name
    rtl_diff_md_path = args.out_dir / DEFAULT_RTL_DIFF_MD.name
    manifest_path = args.out_dir / 'breath_cpu_frontend_q8_8_manifest.json'
    mem_path = args.mem_dir / 'breath_cpu_frontend_q8_8.mem'

    write_sparse_mem(regions, mem_path)
    export_layout_header(layout_path, macros, expected)

    expected_payload = dict(expected)
    expected_payload['sample_index'] = args.sample_index
    expected_payload['label'] = label
    expected_payload['feature_words'] = ['0x%08X' % w for w in feature_words]
    expected_payload['signal_first_words'] = ['0x%08X' % w for w in signal_words[:8]]
    expected_payload['raw_features_q28'] = ['0x%08X' % (w & 0xFFFFFFFF) for w in pre['raw_features_q28']]
    expected_payload['raw_features_cpu_float'] = [float(w) / RAW_FEATURE_SCALE for w in pre['raw_features_q28']]
    expected_payload['csv_raw_features_float'] = [float(x) for x in features]
    expected_payload['cpu_cnn_first_words'] = ['0x%08X' % w for w in cnn_words[:8]]
    expected_path.write_text(json.dumps(expected_payload, indent=2, sort_keys=True) + '\n', encoding='ascii')
    tb_expected_path.write_text(emit_tb_svh(expected_payload), encoding='ascii')
    rtl_expected_payload = apply_watchpoint_overrides(expected_payload, RAW_NET3_FULLCORE_WATCHPOINT_OVERRIDES)
    rtl_expected_path.write_text(json.dumps(rtl_expected_payload, indent=2, sort_keys=True) + '\n', encoding='ascii')
    rtl_tb_expected_path.write_text(
        emit_tb_svh(rtl_expected_payload, macro_prefix='BREATH_CPU_FRONTEND_Q8_8_RTL_EXPECT'),
        encoding='ascii')
    rtl_diff_md_path.write_text(emit_rtl_diff_md(expected_payload, rtl_expected_payload) + '\n', encoding='ascii')

    region_summary = []
    for region in check_regions(regions):
        region_summary.append({
            'name': region['name'],
            'base': '0x%08X' % region['base'],
            'end': '0x%08X' % (region['base'] + len(region['words']) * 4),
            'words': len(region['words']),
        })
    manifest = {
        'checkpoint': str(args.checkpoint),
        'loader': loader_used,
        'csv_dir': str(args.csv_dir),
        'sample_index': args.sample_index,
        'label': label,
        'scale': args.scale,
        'feature_columns': FEATURE_COLS,
        'normalized_features': [float(x) for x in features_norm],
        'cpu_preprocessed_features_q8_8': [int(x) for x in feature_q],
        'cpu_preprocessed_signal_first_q8_8': [int(x) for x in signal_q[:16]],
        'raw_features_cpu_float': [float(w) / RAW_FEATURE_SCALE for w in pre['raw_features_q28']],
        'csv_raw_features_float': [float(x) for x in features],
        'clip_counts': clip_counts,
        'regions': region_summary,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='ascii')

    print('generated:', layout_path)
    print('generated:', expected_path)
    print('generated:', tb_expected_path)
    print('generated:', rtl_expected_path)
    print('generated:', rtl_tb_expected_path)
    print('generated:', rtl_diff_md_path)
    print('generated:', manifest_path)
    print('generated:', mem_path)
    print('sample index:', args.sample_index, 'label:', label)
    print('cpu cnn first4:', ' '.join('0x%08X' % w for w in cnn_words[:4]))
    print('classifier final out:', ' '.join(expected['classifier_final_out_words']))
    print('rtl baseline classifier final out:', ' '.join(rtl_expected_payload['classifier_final_out_words']))
    print('clip counts:', ', '.join('%s=%d' % (k, clip_counts[k]) for k in sorted(clip_counts)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, default=DEFAULT_CHECKPOINT)
    parser.add_argument('--csv-dir', type=Path, default=DEFAULT_CSV_DIR)
    parser.add_argument('--tpu-header', type=Path, default=DEFAULT_TPU_HEADER)
    parser.add_argument('--out-dir', type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument('--mem-dir', type=Path, default=DEFAULT_MEM_DIR)
    parser.add_argument('--sample-index', type=int, default=0)
    parser.add_argument('--scale', type=int, default=Q_SCALE)
    parser.add_argument('--loader', choices=('auto', 'torch', 'torchzip'), default='auto')
    args = parser.parse_args()
    export_cpu_frontend(args)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
