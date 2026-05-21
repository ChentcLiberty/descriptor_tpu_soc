#!/usr/bin/env python3
"""Compare fixed-point CPU+TPU golden against a numpy float eval path.

This script avoids importing torch. It materializes the checkpoint with the
existing torchzip loader and runs a numpy version of the eval graph for a small
number of samples. It is intentionally slower than the fixed-point golden check
because it uses straightforward Python/Numpy convolution loops.
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
import check_breath_cpu_frontend_q8_8_samples as fixed_check
from export_breath_linear_q8_8_params import load_state_dict, fold_linear_bn

DEFAULT_OUT = frontend.ROOT / 'work/600_competition_5stage/software/generated/breath_cpu_frontend_float_compare.json'


def relu(x):
    return np.maximum(x, 0.0)


def linear(x, weight, bias):
    return x @ weight.T + bias


def conv1d_same(x, weight, bias, pad):
    in_ch, in_len = x.shape
    out_ch, weight_in_ch, kernel = weight.shape
    if in_ch != weight_in_ch:
        raise SystemExit('conv input channel mismatch: %d vs %d' % (in_ch, weight_in_ch))
    out = np.zeros((out_ch, in_len), dtype=np.float32)
    for oc in range(out_ch):
        acc = np.full((in_len,), bias[oc], dtype=np.float32)
        for ic in range(in_ch):
            padded = np.pad(x[ic], (pad, pad), mode='constant')
            for pos in range(in_len):
                acc[pos] += np.sum(padded[pos:pos + kernel] * weight[oc, ic])
        out[oc] = acc
    return out


def maxpool2(x):
    length = x.shape[1]
    return np.maximum(x[:, 0:length:2], x[:, 1:length:2])


def run_float_eval(state, features_norm, signal_norm):
    key_features = features_norm[:2].astype(np.float32)
    other_features = features_norm[2:].astype(np.float32)

    x = key_features
    for linear_prefix, bn_prefix in [
        ('perceptron_subnet.layers.0', 'perceptron_subnet.layers.1'),
        ('perceptron_subnet.layers.4', 'perceptron_subnet.layers.5'),
        ('perceptron_subnet.layers.8', 'perceptron_subnet.layers.9'),
        ('perceptron_subnet.layers.12', 'perceptron_subnet.layers.13'),
        ('perceptron_subnet.layers.16', 'perceptron_subnet.layers.17'),
    ]:
        weight, bias = fold_linear_bn(state, linear_prefix, bn_prefix)
        x = relu(linear(x, weight, bias))
    perceptron_out = x

    x = signal_norm.astype(np.float32).reshape(1, -1)
    weight, bias = frontend.fold_conv_bn(state, 'cnn_extractor.conv1', 'cnn_extractor.bn1')
    x = maxpool2(relu(conv1d_same(x, weight, bias, 3)))

    weight, bias = frontend.fold_conv_bn(state, 'cnn_extractor.conv2', 'cnn_extractor.bn2')
    x = conv1d_same(x, weight, bias, 2)

    film = key_features
    weight, bias = frontend.linear_params(state, 'cnn_extractor.film_generator.0')
    film = relu(linear(film, weight, bias))
    weight, bias = frontend.linear_params(state, 'cnn_extractor.film_generator.2')
    film = linear(film, weight, bias)
    gamma = film[:64].reshape(64, 1)
    beta = film[64:].reshape(64, 1)
    x = maxpool2(relu((1.0 + gamma) * x + beta))

    weight, bias = frontend.fold_conv_bn(state, 'cnn_extractor.conv3', 'cnn_extractor.bn3')
    x = maxpool2(relu(conv1d_same(x, weight, bias, 1)))

    weight, bias = frontend.fold_conv_bn(state, 'cnn_extractor.conv4', 'cnn_extractor.bn4')
    cnn_out = relu(conv1d_same(x, weight, bias, 1)).mean(axis=1)

    x = other_features
    for linear_prefix, bn_prefix in [
        ('other_encoder.encoder.0', 'other_encoder.encoder.1'),
        ('other_encoder.encoder.4', 'other_encoder.encoder.5'),
    ]:
        weight, bias = fold_linear_bn(state, linear_prefix, bn_prefix)
        x = relu(linear(x, weight, bias))
    other_out = x

    fused = np.concatenate([perceptron_out, key_features, cnn_out, other_out]).astype(np.float32)
    x = fused
    for linear_prefix, bn_prefix in [
        ('classifier.0', 'classifier.1'),
        ('classifier.4', 'classifier.5'),
        ('classifier.8', 'classifier.9'),
    ]:
        weight, bias = fold_linear_bn(state, linear_prefix, bn_prefix)
        x = relu(linear(x, weight, bias))
    weight, bias = fold_linear_bn(state, 'classifier.12', None)
    return linear(x, weight, bias)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, default=frontend.DEFAULT_CHECKPOINT)
    parser.add_argument('--csv-dir', type=Path, default=frontend.DEFAULT_CSV_DIR)
    parser.add_argument('--tpu-header', type=Path, default=frontend.DEFAULT_TPU_HEADER)
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT)
    parser.add_argument('--sample-indices', help='comma list or inclusive ranges, e.g. 0,1,4-7')
    parser.add_argument('--max-samples', type=int, default=4)
    parser.add_argument('--scale', type=int, default=frontend.Q_SCALE)
    parser.add_argument('--loader', choices=('auto', 'torch', 'torchzip'), default='auto')
    args = parser.parse_args()

    state, loader_used = load_state_dict(args.checkpoint, args.loader)
    all_features, all_signals = frontend.load_all_splits(args.csv_dir)
    feature_mean = all_features.mean(axis=0)
    feature_std = all_features.std(axis=0)
    signal_mean = all_signals.reshape((-1, 1000)).mean(axis=0)
    signal_std = all_signals.reshape((-1, 1000)).std(axis=0)
    test_rows = frontend.read_windows(args.csv_dir / 'breath_test_windows.csv')
    sample_indices = fixed_check.parse_indices(args.sample_indices, args.max_samples, len(test_rows))

    cpu_params, param_clip_counts = fixed_check.build_cpu_params(state, args.scale)
    tpu_arrays = frontend.tpu_pool.parse_arrays(args.tpu_header)

    samples = []
    for idx in sample_indices:
        features, signal, label = test_rows[idx]
        fixed = fixed_check.check_sample(idx, test_rows[idx], feature_mean, feature_std, signal_mean, signal_std, cpu_params, tpu_arrays)
        features_norm = frontend.standardize(features, feature_mean, feature_std).astype(np.float32)
        signal_norm = frontend.standardize(signal, signal_mean, signal_std).astype(np.float32)
        float_logits = run_float_eval(state, features_norm, signal_norm)
        float_pred = int(np.argmax(float_logits))
        samples.append({
            'sample_index': int(idx),
            'label': int(label),
            'float_pred_argmax': float_pred,
            'float_logits': [float(x) for x in float_logits],
            'fixed_pred_argmax': fixed['pred_argmax'],
            'fixed_logits_q8_8': fixed['logits_q8_8'],
            'fixed_classifier_final_out_words': fixed['classifier_final_out_words'],
            'fixed_matches_float_argmax': bool(fixed['pred_argmax'] == float_pred),
            'float_matches_label': bool(float_pred == int(label)),
            'fixed_matches_label': bool(fixed['pred_argmax'] == int(label)),
            'raw_feature_max_abs_diff_vs_csv': fixed['raw_feature_max_abs_diff_vs_csv'],
            'feature_clip_count': fixed['feature_clip_count'],
            'signal_clip_count': fixed['signal_clip_count'],
        })

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
    print('samples compared:', len(samples))
    for item in samples:
        print('sample %d label=%d float_pred=%d fixed_pred=%d match_float=%s fixed_final=%s' % (
            item['sample_index'],
            item['label'],
            item['float_pred_argmax'],
            item['fixed_pred_argmax'],
            'yes' if item['fixed_matches_float_argmax'] else 'no',
            ' '.join(item['fixed_classifier_final_out_words']),
        ))
    mismatches = [item for item in samples if not item['fixed_matches_float_argmax']]
    if mismatches:
        print('fixed/float argmax mismatches:', ','.join(str(item['sample_index']) for item in mismatches))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
