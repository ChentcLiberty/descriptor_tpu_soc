#!/usr/bin/env python3
"""Multi-sample fixed-point golden check for the breath CPU front-end path.

This check does not emit RTL preload files. It reuses the fixed-point CPU
front-end and TPU Linear golden functions to summarize multiple rows from the
breath test CSV split.
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import export_breath_cpu_frontend_q8_8 as frontend
from export_breath_linear_q8_8_params import load_state_dict


DEFAULT_OUT = frontend.ROOT / 'work/600_competition_5stage/software/generated/breath_cpu_frontend_q8_8_samples_expected.json'


def parse_indices(spec, max_samples, total):
    if spec is None:
        return list(range(min(max_samples, total)))

    indices = []
    for token in spec.split(','):
        token = token.strip()
        if not token:
            continue
        if '-' in token:
            left, right = token.split('-', 1)
            start = int(left, 10)
            stop = int(right, 10)
            if stop < start:
                raise SystemExit('descending sample range is not supported: %s' % token)
            indices.extend(range(start, stop + 1))
        else:
            indices.append(int(token, 10))

    deduped = []
    seen = set()
    for idx in indices:
        if idx < 0 or idx >= total:
            raise SystemExit('sample index %d out of range 0..%d' % (idx, total - 1))
        if idx not in seen:
            deduped.append(idx)
            seen.add(idx)
    return deduped


def build_cpu_params(state, scale):
    params = {}
    clip_counts = {}

    for layer_name, conv_prefix, bn_prefix in [
        ('conv1', 'cnn_extractor.conv1', 'cnn_extractor.bn1'),
        ('conv2', 'cnn_extractor.conv2', 'cnn_extractor.bn2'),
        ('conv3', 'cnn_extractor.conv3', 'cnn_extractor.bn3'),
        ('conv4', 'cnn_extractor.conv4', 'cnn_extractor.bn4'),
    ]:
        weight, bias = frontend.fold_conv_bn(state, conv_prefix, bn_prefix)
        wq, wc = frontend.quantize_vector(weight.reshape(-1), scale)
        bq, bc = frontend.quantize_vector(bias.reshape(-1), scale)
        params[layer_name + '_w'] = wq
        params[layer_name + '_b'] = bq
        clip_counts[layer_name + '_w'] = wc
        clip_counts[layer_name + '_b'] = bc

    for layer_name, prefix in [
        ('film_l0', 'cnn_extractor.film_generator.0'),
        ('film_l2', 'cnn_extractor.film_generator.2'),
    ]:
        weight, bias = frontend.linear_params(state, prefix)
        wq, wc = frontend.quantize_vector(weight.reshape(-1), scale)
        bq, bc = frontend.quantize_vector(bias.reshape(-1), scale)
        params[layer_name + '_w'] = wq
        params[layer_name + '_b'] = bq
        clip_counts[layer_name + '_w'] = wc
        clip_counts[layer_name + '_b'] = bc

    return params, clip_counts


def s16(value):
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def unpack_logits(words):
    logits = []
    for item in words:
        word = int(item, 16) if isinstance(item, str) else int(item)
        logits.append(s16(word))
        logits.append(s16(word >> 16))
    return logits


def argmax(values):
    best_idx = 0
    best_value = values[0]
    for idx, value in enumerate(values[1:], 1):
        if value > best_value:
            best_idx = idx
            best_value = value
    return best_idx


def check_sample(sample_index, row, feature_mean, feature_std, signal_mean, signal_std, cpu_params, tpu_arrays):
    features, signal, label = row
    pre = frontend.cpu_preprocess_q8_8(signal, feature_mean, feature_std, signal_mean, signal_std)
    feature_q = pre['feature_q8']
    signal_q = pre['signal_q8']
    feature_words = frontend.pack_qvals(feature_q)

    cnn_q = frontend.run_cpu_cnn_q8(signal_q, feature_q, cpu_params)
    cnn_words = frontend.pack_qvals(cnn_q)
    expected = frontend.run_classifier_expected(tpu_arrays, feature_words, cnn_words)

    final_words = expected['classifier_final_out_words']
    logits_q8_8 = unpack_logits(final_words)
    raw_features_float = np.asarray([float(w) / frontend.RAW_FEATURE_SCALE for w in pre['raw_features_q28']], dtype=np.float64)
    csv_features = np.asarray(features, dtype=np.float64)
    feature_abs_diff = np.abs(raw_features_float - csv_features)

    return {
        'sample_index': int(sample_index),
        'label': int(label),
        'pred_argmax': int(argmax(logits_q8_8)),
        'classifier_final_out_words': final_words,
        'logits_q8_8': [int(x) for x in logits_q8_8],
        'feature_words': ['0x%08X' % w for w in feature_words],
        'cpu_cnn_first_words': ['0x%08X' % w for w in cnn_words[:8]],
        'raw_feature_max_abs_diff_vs_csv': float(feature_abs_diff.max()),
        'raw_feature_mean_abs_diff_vs_csv': float(feature_abs_diff.mean()),
        'feature_clip_count': int(sum(1 for value in feature_q if value in (-32768, 32767))),
        'signal_clip_count': int(sum(1 for value in signal_q if value in (-32768, 32767))),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, default=frontend.DEFAULT_CHECKPOINT)
    parser.add_argument('--csv-dir', type=Path, default=frontend.DEFAULT_CSV_DIR)
    parser.add_argument('--tpu-header', type=Path, default=frontend.DEFAULT_TPU_HEADER)
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT)
    parser.add_argument('--sample-indices', help='comma list or inclusive ranges, e.g. 0,1,4-7')
    parser.add_argument('--max-samples', type=int, default=4, help='used when --sample-indices is omitted')
    parser.add_argument('--scale', type=int, default=frontend.Q_SCALE)
    parser.add_argument('--loader', choices=('auto', 'torch', 'torchzip'), default='auto')
    parser.add_argument('--require-no-clip', action='store_true')
    args = parser.parse_args()

    state, loader_used = load_state_dict(args.checkpoint, args.loader)
    all_features, all_signals = frontend.load_all_splits(args.csv_dir)
    feature_mean = all_features.mean(axis=0)
    feature_std = all_features.std(axis=0)
    signal_mean = all_signals.reshape((-1, 1000)).mean(axis=0)
    signal_std = all_signals.reshape((-1, 1000)).std(axis=0)
    test_rows = frontend.read_windows(args.csv_dir / 'breath_test_windows.csv')
    sample_indices = parse_indices(args.sample_indices, args.max_samples, len(test_rows))

    cpu_params, param_clip_counts = build_cpu_params(state, args.scale)
    tpu_arrays = frontend.tpu_pool.parse_arrays(args.tpu_header)

    samples = [check_sample(idx, test_rows[idx], feature_mean, feature_std, signal_mean, signal_std, cpu_params, tpu_arrays)
               for idx in sample_indices]

    if args.require_no_clip:
        clipped = [item for item in samples if item['feature_clip_count'] or item['signal_clip_count']]
        if clipped:
            raise SystemExit('normalized feature/signal clipping observed in samples: %s' %
                             ','.join(str(item['sample_index']) for item in clipped))

    payload = {
        'checkpoint': str(args.checkpoint),
        'csv_dir': str(args.csv_dir),
        'loader': loader_used,
        'scale': args.scale,
        'sample_indices': sample_indices,
        'param_clip_counts': param_clip_counts,
        'samples': samples,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='ascii')

    print('generated:', args.out)
    print('samples checked:', len(samples))
    for item in samples:
        print('sample %d label=%d pred=%d final=%s feature_diff_max=%.6g clips(feature/signal)=%d/%d' % (
            item['sample_index'],
            item['label'],
            item['pred_argmax'],
            ' '.join(item['classifier_final_out_words']),
            item['raw_feature_max_abs_diff_vs_csv'],
            item['feature_clip_count'],
            item['signal_clip_count'],
        ))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
