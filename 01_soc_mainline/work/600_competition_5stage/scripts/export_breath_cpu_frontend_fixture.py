#!/usr/bin/env python3
"""Export one real breath test window as a CPU front-end Q8.8 fixture.

The fixture is intentionally small enough to live in the CPU image. It gives the
bare-metal CPU code a real algorithm-derived input path without embedding the
large CNN/FiLM weights in IMEM:

- MLP_KEY input: normalized dominant frequency + std from a test window
- MLP_OTHER input: normalized remaining six statistical features
- CLASSIFIER raw-key slot: same normalized key features
- CLASSIFIER CNN slot: CNN/FiLM branch output computed from best_model.pth

The CNN/FiLM output is fixture-backed in this first CPU plan step. The C runtime
owns the front-end plumbing and can later replace this fixture with an in-CPU
fixed-point CNN/FiLM implementation or a hardware CNN/VPU block.
"""

import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from export_breath_linear_q8_8_params import load_state_dict, q8_8, pack_i16, require_key

DEFAULT_CHECKPOINT = Path('/home/jjt/soc/算法/Breathrecognitionbest/checkpoints/best_model.pth')
DEFAULT_CSV_DIR = Path('/home/jjt/soc/算法/Breathrecognitionbest/csv')
DEFAULT_OUT_DIR = ROOT / 'work/600_competition_5stage/software/generated'

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


def linear(state, prefix, x):
    weight = require_key(state, prefix + '.weight').astype(np.float32)
    bias_key = prefix + '.bias'
    if bias_key in state:
        bias = state[bias_key].astype(np.float32)
    else:
        bias = np.zeros((weight.shape[0],), dtype=np.float32)
    return weight.dot(x) + bias


def conv1d_same(state, prefix, x, padding):
    weight = require_key(state, prefix + '.weight').astype(np.float32)
    bias = require_key(state, prefix + '.bias').astype(np.float32)
    out_channels, in_channels, kernel = weight.shape
    if x.shape[0] != in_channels:
        raise SystemExit('%s input channel mismatch: %d vs %d' % (prefix, x.shape[0], in_channels))
    padded = np.pad(x, ((0, 0), (padding, padding)), mode='constant')
    length = x.shape[1]
    y = np.zeros((out_channels, length), dtype=np.float32)
    for oc in range(out_channels):
        acc = np.full((length,), bias[oc], dtype=np.float32)
        for ic in range(in_channels):
            for k in range(kernel):
                acc += weight[oc, ic, k] * padded[ic, k:k + length]
        y[oc] = acc
    return y


def batch_norm_1d(state, prefix, x):
    gamma = require_key(state, prefix + '.weight').astype(np.float32)
    beta = require_key(state, prefix + '.bias').astype(np.float32)
    running_mean = require_key(state, prefix + '.running_mean').astype(np.float32)
    running_var = require_key(state, prefix + '.running_var').astype(np.float32)
    eps_value = state.get(prefix + '.eps', None)
    eps = float(eps_value) if eps_value is not None else 1.0e-5
    scale = gamma / np.sqrt(running_var + eps)
    return x * scale.reshape((-1, 1)) + (beta - running_mean * scale).reshape((-1, 1))


def relu(x):
    return np.maximum(x, 0.0).astype(np.float32)


def maxpool1d_2(x):
    length = (x.shape[1] // 2) * 2
    return x[:, :length].reshape((x.shape[0], length // 2, 2)).max(axis=2).astype(np.float32)


def cnn_film_forward(state, raw_signal_norm, key_features_norm):
    x = raw_signal_norm.reshape((1, -1)).astype(np.float32)

    x = relu(batch_norm_1d(state, 'cnn_extractor.bn1', conv1d_same(state, 'cnn_extractor.conv1', x, 3)))
    x = maxpool1d_2(x)

    x = batch_norm_1d(state, 'cnn_extractor.bn2', conv1d_same(state, 'cnn_extractor.conv2', x, 2))
    film = linear(state, 'cnn_extractor.film_generator.0', key_features_norm.astype(np.float32))
    film = relu(film)
    film = linear(state, 'cnn_extractor.film_generator.2', film)
    gamma = film[:64].reshape((64, 1))
    beta = film[64:].reshape((64, 1))
    x = (1.0 + gamma) * x + beta
    x = relu(x)
    x = maxpool1d_2(x)

    x = relu(batch_norm_1d(state, 'cnn_extractor.bn3', conv1d_same(state, 'cnn_extractor.conv3', x, 1)))
    x = maxpool1d_2(x)

    x = relu(batch_norm_1d(state, 'cnn_extractor.bn4', conv1d_same(state, 'cnn_extractor.conv4', x, 1)))
    return x.mean(axis=1).astype(np.float32)


def pack_vector_q8_8(values, scale):
    if len(values) % 2 != 0:
        raise SystemExit('packed vector length must be even')
    words = []
    clipped = 0
    for i in range(0, len(values), 2):
        lo, c0 = q8_8(values[i], scale)
        hi, c1 = q8_8(values[i + 1], scale)
        words.append(pack_i16(lo, hi))
        clipped += int(c0) + int(c1)
    return words, clipped


def c_words(name, words):
    lines = ['static const uint32_t %s[%d] = {' % (name, len(words))]
    for i in range(0, len(words), 4):
        chunk = words[i:i + 4]
        suffix = ',' if i + 4 < len(words) else ''
        lines.append('    ' + ', '.join('0x%08Xu' % word for word in chunk) + suffix)
    lines.append('};')
    return '\n'.join(lines)


def export_fixture(args):
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

    cnn_out = cnn_film_forward(state, signal_norm, features_norm[:2])
    mlp_key_words, clip_key = pack_vector_q8_8(features_norm[:2], args.scale)
    mlp_other_words, clip_other = pack_vector_q8_8(features_norm[2:], args.scale)
    raw_key_words, clip_raw = pack_vector_q8_8(features_norm[:2], args.scale)
    cnn_words, clip_cnn = pack_vector_q8_8(cnn_out, args.scale)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    header_path = args.out_dir / 'breath_cpu_frontend_fixture.h'
    manifest_path = args.out_dir / 'breath_cpu_frontend_fixture_manifest.json'

    header = []
    header.append('/* Auto-generated by export_breath_cpu_frontend_fixture.py. */')
    header.append('#ifndef BREATH_CPU_FRONTEND_FIXTURE_H')
    header.append('#define BREATH_CPU_FRONTEND_FIXTURE_H')
    header.append('')
    header.append('#include <stdint.h>')
    header.append('')
    header.append('#define BREATH_CPU_FRONTEND_SAMPLE_INDEX %du' % args.sample_index)
    header.append('#define BREATH_CPU_FRONTEND_EXPECTED_LABEL %du' % label)
    header.append('#define BREATH_CPU_FRONTEND_Q8_8_SCALE %du' % int(args.scale))
    header.append('#define BREATH_CPU_FRONTEND_MLP_KEY_WORDS %du' % len(mlp_key_words))
    header.append('#define BREATH_CPU_FRONTEND_MLP_OTHER_WORDS %du' % len(mlp_other_words))
    header.append('#define BREATH_CPU_FRONTEND_RAW_KEY_WORDS %du' % len(raw_key_words))
    header.append('#define BREATH_CPU_FRONTEND_CNN_WORDS %du' % len(cnn_words))
    header.append('')
    header.append(c_words('g_breath_cpu_frontend_mlp_key_words', mlp_key_words))
    header.append('')
    header.append(c_words('g_breath_cpu_frontend_mlp_other_words', mlp_other_words))
    header.append('')
    header.append(c_words('g_breath_cpu_frontend_raw_key_words', raw_key_words))
    header.append('')
    header.append(c_words('g_breath_cpu_frontend_cnn_words', cnn_words))
    header.append('')
    header.append('#endif')
    header.append('')
    header_path.write_text('\n'.join(header), encoding='ascii')

    manifest = {
        'checkpoint': str(args.checkpoint),
        'csv_dir': str(args.csv_dir),
        'loader': loader_used,
        'sample_index': args.sample_index,
        'expected_label': label,
        'q_format': 'Q8.8 packed two int16 lanes per uint32 word',
        'scale': args.scale,
        'clipped_values': {
            'mlp_key': clip_key,
            'mlp_other': clip_other,
            'raw_key': clip_raw,
            'cnn': clip_cnn,
        },
        'raw_features': [float(x) for x in features],
        'normalized_features': [float(x) for x in features_norm],
        'packed_words': {
            'mlp_key': ['0x%08X' % x for x in mlp_key_words],
            'mlp_other': ['0x%08X' % x for x in mlp_other_words],
            'raw_key': ['0x%08X' % x for x in raw_key_words],
            'cnn_first4': ['0x%08X' % x for x in cnn_words[:4]],
            'cnn_last4': ['0x%08X' % x for x in cnn_words[-4:]],
        },
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='ascii')

    print('loader  :', loader_used)
    print('exported:', header_path)
    print('manifest:', manifest_path)
    print('sample  : index=%d label=%d' % (args.sample_index, label))
    print('mlp_key :', ' '.join('0x%08X' % x for x in mlp_key_words))
    print('mlp_other:', ' '.join('0x%08X' % x for x in mlp_other_words))
    print('cnn first4:', ' '.join('0x%08X' % x for x in cnn_words[:4]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, default=DEFAULT_CHECKPOINT)
    parser.add_argument('--csv-dir', type=Path, default=DEFAULT_CSV_DIR)
    parser.add_argument('--out-dir', type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument('--sample-index', type=int, default=0)
    parser.add_argument('--scale', type=float, default=256.0)
    parser.add_argument('--loader', choices=('auto', 'torch', 'torchzip'), default='auto')
    args = parser.parse_args()
    export_fixture(args)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
