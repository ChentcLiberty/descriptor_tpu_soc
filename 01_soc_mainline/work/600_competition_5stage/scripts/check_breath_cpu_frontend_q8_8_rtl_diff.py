#!/usr/bin/env python3
"""Validate the allowed raw NET_ID=3 RTL diff set against generated baselines."""

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import export_breath_cpu_frontend_q8_8 as frontend

WATCHED_ARRAYS = [
    'param_key_words',
    'mlp_key_out_words',
    'mlp_other_out_words',
    'cnn_words',
    'classifier_l2_out_words',
    'classifier_final_out_words',
]

RAW_NET3_BASELINE_POLICY = 'staged_dual_baseline_rtl_signoff'


def load_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def build_actual_diffs(expected, rtl_expected):
    diffs = {}
    for array_name in WATCHED_ARRAYS:
        lhs = expected[array_name]
        rhs = rtl_expected[array_name]
        if len(lhs) != len(rhs):
            raise SystemExit('length mismatch for %s: %d vs %d' % (array_name, len(lhs), len(rhs)))
        rows = {}
        for word_idx, (lhs_word, rhs_word) in enumerate(zip(lhs, rhs)):
            if lhs_word != rhs_word:
                rows[word_idx] = {
                    'expected': lhs_word,
                    'rtl_expected': rhs_word,
                }
        if rows:
            diffs[array_name] = rows
    return diffs


def verify_allowed_diffs(expected, rtl_expected):
    actual_diffs = build_actual_diffs(expected, rtl_expected)
    allowed = frontend.RAW_NET3_FULLCORE_WATCHPOINT_OVERRIDES

    failures = []

    extra_arrays = sorted(set(actual_diffs) - set(allowed))
    for array_name in extra_arrays:
        failures.append('unexpected differing array: %s' % array_name)

    missing_arrays = sorted(set(allowed) - set(actual_diffs))
    for array_name in missing_arrays:
        failures.append('expected differing array missing from generated baselines: %s' % array_name)

    for array_name, overrides in sorted(allowed.items()):
        lhs = expected[array_name]
        rhs = rtl_expected[array_name]
        actual_rows = actual_diffs.get(array_name, {})

        extra_indices = sorted(set(actual_rows) - set(overrides))
        for word_idx in extra_indices:
            failures.append('%s[%d] differs unexpectedly: %s vs %s' % (
                array_name, word_idx, lhs[word_idx], rhs[word_idx]))

        for word_idx, word_value in sorted(overrides.items()):
            if word_idx >= len(rhs):
                failures.append('%s[%d] out of range for rtl_expected length %d' % (
                    array_name, word_idx, len(rhs)))
                continue
            actual_word = int(rhs[word_idx], 16)
            if actual_word != int(word_value):
                failures.append('%s[%d] rtl_expected=%s but override expects 0x%08X' % (
                    array_name, word_idx, rhs[word_idx], int(word_value)))
            if (word_idx not in actual_rows) and (int(lhs[word_idx], 16) != int(word_value)):
                failures.append('%s[%d] should differ to 0x%08X but generated baselines still match at %s' % (
                    array_name, word_idx, int(word_value), lhs[word_idx]))

        for word_idx, rhs_word in enumerate(rhs):
            if word_idx in overrides:
                continue
            if lhs[word_idx] != rhs_word:
                failures.append('%s[%d] changed outside allowed override set: %s vs %s' % (
                    array_name, word_idx, lhs[word_idx], rhs_word))

    return actual_diffs, failures


def emit_summary(actual_diffs):
    print('baseline policy: %s' % RAW_NET3_BASELINE_POLICY)
    print('validated arrays:')
    for array_name in WATCHED_ARRAYS:
        diff_rows = actual_diffs.get(array_name, {})
        if diff_rows:
            indices = ','.join(str(word_idx) for word_idx in sorted(diff_rows))
            print('  %s: diff indices [%s]' % (array_name, indices))
        else:
            print('  %s: no diffs' % array_name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-json', type=Path,
                        default=frontend.DEFAULT_OUT_DIR / 'breath_cpu_frontend_q8_8_expected.json')
    parser.add_argument('--rtl-expected-json', type=Path,
                        default=frontend.DEFAULT_OUT_DIR / frontend.DEFAULT_RTL_EXPECTED_JSON.name)
    args = parser.parse_args()

    expected = load_json(args.expected_json)
    rtl_expected = load_json(args.rtl_expected_json)
    actual_diffs, failures = verify_allowed_diffs(expected, rtl_expected)
    emit_summary(actual_diffs)

    if failures:
        print('validation failures:')
        for item in failures:
            print('  - %s' % item)
        raise SystemExit(1)

    print('raw NET_ID=3 RTL diff check passed')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
