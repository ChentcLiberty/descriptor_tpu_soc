#!/usr/bin/env python3
"""Software golden check for the stage2 CPU+TPU breath SoC demo.

This mirrors the current deterministic Q8.8 runtime schedule. It does not
require torch and intentionally does not model the real trained network weights
yet. Its job is to keep descriptor addresses, param_pool layout, tile chunking,
and the RTL compute stub semantics aligned before real weight export is added.
"""

import argparse
import re
from collections import namedtuple
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TPU_DESC_H = ROOT / "work/600_competition_5stage/software/include/tpu_desc.h"
SHARED_BASE = 0x60000000

Launch = namedtuple(
    "Launch",
    "idx name net_id desc_addr input_addr output_addr param_addr input_words output_words flags",
)


class SharedMemory(object):
    def __init__(self):
        self._words = {}

    def read(self, addr):
        check_word_addr(addr)
        return self._words.get(addr, 0)

    def write(self, addr, value):
        check_word_addr(addr)
        self._words[addr] = value & 0xFFFFFFFF

    def zero_words(self, base_addr, word_count):
        for i in range(word_count):
            self.write(base_addr + (i << 2), 0)

    def write_words(self, base_addr, words):
        for i, word in enumerate(words):
            self.write(base_addr + (i << 2), word)

    def read_words(self, base_addr, word_count):
        return [self.read(base_addr + (i << 2)) for i in range(word_count)]


def parse_macros(path):
    define_re = re.compile(r"^\s*#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.+?)\s*$")
    pending = []

    for line in path.read_text(encoding="utf-8").splitlines():
        match = define_re.match(line)
        if not match:
            continue

        name, expr = match.groups()
        expr = expr.split("//", 1)[0].strip()
        if not expr:
            continue

        expr = re.sub(r"(?i)(0x[0-9a-f]+)[uUlL]*", r"\1", expr)
        expr = re.sub(r"\b(\d+)[uUlL]*\b", r"\1", expr)
        pending.append((name, expr))

    values = {}
    progressed = True
    while pending and progressed:
        progressed = False
        next_pending = []
        for name, expr in pending:
            try:
                value = eval(expr, {"__builtins__": {}}, values)
            except Exception:
                next_pending.append((name, expr))
                continue
            if isinstance(value, int):
                values[name] = value
                progressed = True
            else:
                next_pending.append((name, expr))
        pending = next_pending

    return values


def check_word_addr(addr):
    if (addr & 0x3) != 0:
        raise ValueError("unaligned word address 0x%08x" % addr)
    if addr < SHARED_BASE:
        raise ValueError("address below shared SRAM base 0x%08x" % addr)


def u16(value):
    return value & 0xFFFF


def s16(value):
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def q8_8_mul_to_32(a, b):
    return (s16(a) * s16(b)) >> 8


def round_shift_signed(value, shift):
    value = int(value)
    if shift <= 0:
        return value << (-shift)
    add = 1 << (shift - 1)
    if value >= 0:
        return (value + add) >> shift
    return -(((-value) + add) >> shift)


def q8_8_saturate(value):
    if value > 32767:
        return 0x7FFF
    if value < -32768:
        return 0x8000
    return u16(value)


def pack_q8_8(y0, y1):
    return (u16(y1) << 16) | u16(y0)


def run_linear(mem, launch):
    input_words = mem.read_words(launch.input_addr, launch.input_words)
    stride_words = (launch.input_words << 1) + 1
    relu = (launch.flags & 0x1) != 0

    for out_idx in range(launch.output_words):
        param_base = launch.param_addr + ((out_idx * stride_words) << 2)
        acc0 = 0
        acc1 = 0
        for in_idx, in_word in enumerate(input_words):
            p0 = mem.read(param_base + ((in_idx << 1) << 2))
            p1 = mem.read(param_base + (((in_idx << 1) + 1) << 2))
            x0 = s16(in_word)
            x1 = s16(in_word >> 16)
            acc0 += x0 * s16(p0)
            acc0 += x1 * s16(p0 >> 16)
            acc1 += x0 * s16(p1)
            acc1 += x1 * s16(p1 >> 16)

        bias_word = mem.read(param_base + ((launch.input_words << 1) << 2))
        acc0 += s16(bias_word) << 8
        acc1 += s16(bias_word >> 16) << 8
        acc0 = round_shift_signed(acc0, 8)
        acc1 = round_shift_signed(acc1, 8)

        y0 = 0 if relu and acc0 < 0 else q8_8_saturate(acc0)
        y1 = 0 if relu and acc1 < 0 else q8_8_saturate(acc1)
        mem.write(launch.output_addr + (out_idx << 2), pack_q8_8(y0, y1))


def mlp_key_l0_blob():
    words = []
    for i in range(1, 17):
        words.extend([i << 8, i << 24, 0])
    return words


def load_identity_linear_params(mem, base_addr, input_words, output_words, param_words):
    stride_words = (input_words << 1) + 1
    mem.zero_words(base_addr, param_words)
    for out_word in range(output_words):
        src_word = out_word % input_words if input_words else 0
        out_base = base_addr + ((out_word * stride_words) << 2)
        mem.write(out_base + ((src_word * 2) << 2), 0x00000100)
        mem.write(out_base + (((src_word * 2) + 1) << 2), 0x01000000)


def load_sparse_identity_linear_params(mem, base_addr, input_words, output_start, output_words):
    stride_words = (input_words << 1) + 1
    mem.zero_words(base_addr, output_words * stride_words)
    for out_word in range(output_words):
        global_out_word = output_start + out_word
        src_word = global_out_word % input_words if input_words else 0
        out_base = base_addr + ((out_word * stride_words) << 2)
        mem.write(out_base + ((src_word * 2) << 2), 0x00000100)
        mem.write(out_base + (((src_word * 2) + 1) << 2), 0x01000000)


def load_param_pool(mem, c):
    mem.write_words(c["TPU_PARAM_POOL_MLP_KEY_BASE"], mlp_key_l0_blob())
    load_identity_linear_params(mem, c["TPU_PARAM_POOL_MLP_KEY_L1_BASE"], 16, 32, c["TPU_PARAM_POOL_MLP_KEY_L1_WORDS"])
    load_identity_linear_params(mem, c["TPU_PARAM_POOL_MLP_KEY_L2_BASE"], 32, 64, c["TPU_PARAM_POOL_MLP_KEY_L2_WORDS"])
    load_identity_linear_params(mem, c["TPU_PARAM_POOL_MLP_KEY_L3_BASE"], 64, 32, c["TPU_PARAM_POOL_MLP_KEY_L3_WORDS"])
    load_identity_linear_params(mem, c["TPU_PARAM_POOL_MLP_KEY_L4_BASE"], 32, 16, c["TPU_PARAM_POOL_MLP_KEY_L4_WORDS"])
    load_identity_linear_params(mem, c["TPU_PARAM_POOL_MLP_OTHER_BASE"], 3, 16, c["TPU_PARAM_POOL_MLP_OTHER_WORDS"])
    load_identity_linear_params(mem, c["TPU_PARAM_POOL_MLP_OTHER_L1_BASE"], 16, 16, c["TPU_PARAM_POOL_MLP_OTHER_L1_WORDS"])

    for chunk in range(c["TPU_CLASSIFIER_L0_CHUNKS"]):
        base = c["TPU_PARAM_POOL_CLASSIFIER_L0_BASE"] + chunk * c["TPU_PARAM_POOL_CLASSIFIER_L0_STRIDE_BYTES"]
        start = chunk * c["TPU_CLASSIFIER_L0_CHUNK_WORDS"]
        load_sparse_identity_linear_params(mem, base, c["TPU_CLASSIFIER_L0_INPUT_WORDS"], start, c["TPU_CLASSIFIER_L0_CHUNK_WORDS"])

    for chunk in range(c["TPU_CLASSIFIER_L1_CHUNKS"]):
        base = c["TPU_PARAM_POOL_CLASSIFIER_L1_BASE"] + chunk * c["TPU_PARAM_POOL_CLASSIFIER_L1_STRIDE_BYTES"]
        start = chunk * c["TPU_CLASSIFIER_L1_CHUNK_WORDS"]
        load_sparse_identity_linear_params(mem, base, c["TPU_CLASSIFIER_L1_INPUT_WORDS"], start, c["TPU_CLASSIFIER_L1_CHUNK_WORDS"])

    load_identity_linear_params(
        mem,
        c["TPU_PARAM_POOL_CLASSIFIER_L2_BASE"],
        c["TPU_CLASSIFIER_L2_INPUT_WORDS"],
        c["TPU_CLASSIFIER_L2_OUTPUT_WORDS"],
        c["TPU_PARAM_POOL_CLASSIFIER_L2_WORDS"],
    )
    load_identity_linear_params(
        mem,
        c["TPU_PARAM_POOL_CLASSIFIER_L3_BASE"],
        c["TPU_CLASSIFIER_L3_INPUT_WORDS"],
        c["TPU_CLASSIFIER_L3_OUTPUT_WORDS"],
        c["TPU_PARAM_POOL_CLASSIFIER_L3_WORDS"],
    )


def prepare_demo_inputs(mem, c):
    mem.write(c["TPU_IN_BUF0_BASE"], 0x02000100)
    mem.write(c["TPU_IN_BUF1_BASE"], 0x00010002)
    mem.write(c["TPU_IN_BUF1_BASE"] + 4, 0x00030004)
    mem.write(c["TPU_IN_BUF1_BASE"] + 8, 0x00050006)


def copy_words(mem, dst_addr, src_addr, word_count):
    for i in range(word_count):
        mem.write(dst_addr + (i << 2), mem.read(src_addr + (i << 2)))


def prepare_classifier_fusion_input(mem, c):
    copy_words(
        mem,
        c["TPU_CLASSIFIER_IN_BASE"] + (c["TPU_CLASSIFIER_FUSION_MLP_KEY_OFS_WORDS"] << 2),
        c["TPU_OUT_BUF0_BASE"],
        c["TPU_CLASSIFIER_FUSION_MLP_KEY_WORDS"],
    )
    mem.write(
        c["TPU_CLASSIFIER_IN_BASE"] + (c["TPU_CLASSIFIER_FUSION_RAW_KEY_OFS_WORDS"] << 2),
        0x02000100,
    )
    for i in range(c["TPU_CLASSIFIER_FUSION_CNN_WORDS"]):
        mem.write(
            c["TPU_CLASSIFIER_IN_BASE"] + ((c["TPU_CLASSIFIER_FUSION_CNN_OFS_WORDS"] + i) << 2),
            0x00000200 + i,
        )
    copy_words(
        mem,
        c["TPU_CLASSIFIER_IN_BASE"] + (c["TPU_CLASSIFIER_FUSION_MLP_OTHER_OFS_WORDS"] << 2),
        c["TPU_SCRATCH1_BASE"],
        c["TPU_CLASSIFIER_FUSION_MLP_OTHER_WORDS"],
    )


def build_launches(c):
    relu_tile = c["TPU_DESC_F_RELU"] | c["TPU_DESC_F_TILE2X2_Q8_8"]
    tile_last = c["TPU_DESC_F_TILE2X2_Q8_8"] | c["TPU_DESC_F_LAST_STAGE"]
    launches = [
        Launch(1, "MLP_KEY_L0_2_TO_32", c["NET_ID_MLP_KEY"], c["TPU_DESC0_BASE"], c["TPU_IN_BUF0_BASE"], c["TPU_OUT_BUF0_BASE"], c["TPU_PARAM_POOL_MLP_KEY_BASE"], 1, 16, relu_tile),
        Launch(2, "MLP_KEY_L1_32_TO_64", c["NET_ID_MLP_KEY"], c["TPU_DESC1_BASE"], c["TPU_OUT_BUF0_BASE"], c["TPU_SCRATCH0_BASE"], c["TPU_PARAM_POOL_MLP_KEY_L1_BASE"], 16, 32, relu_tile),
        Launch(3, "MLP_KEY_L2_64_TO_128", c["NET_ID_MLP_KEY"], c["TPU_DESC0_BASE"], c["TPU_SCRATCH0_BASE"], c["TPU_OUT_BUF1_BASE"], c["TPU_PARAM_POOL_MLP_KEY_L2_BASE"], 32, 64, relu_tile),
        Launch(4, "MLP_KEY_L3_128_TO_64", c["NET_ID_MLP_KEY"], c["TPU_DESC1_BASE"], c["TPU_OUT_BUF1_BASE"], c["TPU_SCRATCH1_BASE"], c["TPU_PARAM_POOL_MLP_KEY_L3_BASE"], 64, 32, relu_tile),
        Launch(5, "MLP_KEY_L4_64_TO_32", c["NET_ID_MLP_KEY"], c["TPU_DESC0_BASE"], c["TPU_SCRATCH1_BASE"], c["TPU_OUT_BUF0_BASE"], c["TPU_PARAM_POOL_MLP_KEY_L4_BASE"], 32, 16, relu_tile),
        Launch(6, "MLP_OTHER_L0_6_TO_32", c["NET_ID_MLP_OTHER"], c["TPU_DESC1_BASE"], c["TPU_IN_BUF1_BASE"], c["TPU_OUT_BUF1_BASE"], c["TPU_PARAM_POOL_MLP_OTHER_BASE"], 3, 16, relu_tile),
        Launch(7, "MLP_OTHER_L1_32_TO_32", c["NET_ID_MLP_OTHER"], c["TPU_DESC0_BASE"], c["TPU_OUT_BUF1_BASE"], c["TPU_SCRATCH1_BASE"], c["TPU_PARAM_POOL_MLP_OTHER_L1_BASE"], 16, 16, relu_tile),
    ]

    idx = 8
    buf_desc = [c["TPU_DESC0_BASE"], c["TPU_DESC1_BASE"]]
    for chunk in range(c["TPU_CLASSIFIER_L0_CHUNKS"]):
        launches.append(
            Launch(
                idx,
                "CLASSIFIER_L0_322_TO_256_CHUNK%d" % chunk,
                c["NET_ID_CLASSIFIER"],
                buf_desc[chunk & 1],
                c["TPU_CLASSIFIER_IN_BASE"],
                c["TPU_CLASSIFIER_L0_OUT_BASE"] + ((chunk * c["TPU_CLASSIFIER_L0_CHUNK_WORDS"]) << 2),
                c["TPU_PARAM_POOL_CLASSIFIER_L0_BASE"] + chunk * c["TPU_PARAM_POOL_CLASSIFIER_L0_STRIDE_BYTES"],
                c["TPU_CLASSIFIER_L0_INPUT_WORDS"],
                c["TPU_CLASSIFIER_L0_CHUNK_WORDS"],
                relu_tile,
            )
        )
        idx += 1

    for chunk in range(c["TPU_CLASSIFIER_L1_CHUNKS"]):
        launches.append(
            Launch(
                idx,
                "CLASSIFIER_L1_256_TO_128_CHUNK%d" % chunk,
                c["NET_ID_CLASSIFIER"],
                buf_desc[(chunk + c["TPU_CLASSIFIER_L0_CHUNKS"]) & 1],
                c["TPU_CLASSIFIER_L0_OUT_BASE"],
                c["TPU_CLASSIFIER_L1_OUT_BASE"] + ((chunk * c["TPU_CLASSIFIER_L1_CHUNK_WORDS"]) << 2),
                c["TPU_PARAM_POOL_CLASSIFIER_L1_BASE"] + chunk * c["TPU_PARAM_POOL_CLASSIFIER_L1_STRIDE_BYTES"],
                c["TPU_CLASSIFIER_L1_INPUT_WORDS"],
                c["TPU_CLASSIFIER_L1_CHUNK_WORDS"],
                relu_tile,
            )
        )
        idx += 1

    launches.append(
        Launch(
            idx,
            "CLASSIFIER_L2_128_TO_64",
            c["NET_ID_CLASSIFIER"],
            c["TPU_DESC0_BASE"],
            c["TPU_CLASSIFIER_L1_OUT_BASE"],
            c["TPU_CLASSIFIER_L2_OUT_BASE"],
            c["TPU_PARAM_POOL_CLASSIFIER_L2_BASE"],
            c["TPU_CLASSIFIER_L2_INPUT_WORDS"],
            c["TPU_CLASSIFIER_L2_OUTPUT_WORDS"],
            relu_tile,
        )
    )
    idx += 1
    launches.append(
        Launch(
            idx,
            "CLASSIFIER_L3_64_TO_4",
            c["NET_ID_CLASSIFIER"],
            c["TPU_DESC1_BASE"],
            c["TPU_CLASSIFIER_L2_OUT_BASE"],
            c["TPU_CLASSIFIER_OUT_BASE"],
            c["TPU_PARAM_POOL_CLASSIFIER_L3_BASE"],
            c["TPU_CLASSIFIER_L3_INPUT_WORDS"],
            c["TPU_CLASSIFIER_L3_OUTPUT_WORDS"],
            tile_last,
        )
    )
    return launches


def check_no_overlap(regions):
    sorted_regions = sorted(regions, key=lambda item: item[1])
    for left, right in zip(sorted_regions, sorted_regions[1:]):
        name_a, base_a, words_a = left
        name_b, base_b, words_b = right
        end_a = base_a + (words_a << 2)
        end_b = base_b + (words_b << 2)
        if end_a > base_b:
            raise AssertionError(
                "region overlap: %s [0x%08x, 0x%08x) vs %s [0x%08x, 0x%08x)" %
                (name_a, base_a, end_a, name_b, base_b, end_b)
            )


def run_checks(c):
    mem = SharedMemory()
    load_param_pool(mem, c)
    prepare_demo_inputs(mem, c)

    launches = build_launches(c)
    if len(launches) != 21:
        raise AssertionError("expected 21 launches, got %d" % len(launches))

    expected_desc = [
        c["TPU_DESC0_BASE"], c["TPU_DESC1_BASE"], c["TPU_DESC0_BASE"],
        c["TPU_DESC1_BASE"], c["TPU_DESC0_BASE"], c["TPU_DESC1_BASE"],
        c["TPU_DESC0_BASE"], c["TPU_DESC0_BASE"], c["TPU_DESC1_BASE"],
        c["TPU_DESC0_BASE"], c["TPU_DESC1_BASE"], c["TPU_DESC0_BASE"],
        c["TPU_DESC1_BASE"], c["TPU_DESC0_BASE"], c["TPU_DESC1_BASE"],
        c["TPU_DESC0_BASE"], c["TPU_DESC1_BASE"], c["TPU_DESC0_BASE"],
        c["TPU_DESC1_BASE"], c["TPU_DESC0_BASE"], c["TPU_DESC1_BASE"],
    ]
    for launch, desc_addr in zip(launches, expected_desc):
        if launch.desc_addr != desc_addr:
            raise AssertionError(
                "launch #%d desc mismatch: actual 0x%08x expected 0x%08x" %
                (launch.idx, launch.desc_addr, desc_addr)
            )

    for launch in launches[:7]:
        run_linear(mem, launch)

    prepare_classifier_fusion_input(mem, c)

    for launch in launches[7:]:
        run_linear(mem, launch)

    expected = {
        c["TPU_OUT_BUF0_BASE"] + 0 * 4: 0x02000100,
        c["TPU_OUT_BUF0_BASE"] + 15 * 4: 0x20001000,
        c["TPU_SCRATCH0_BASE"] + 0 * 4: 0x02000100,
        c["TPU_SCRATCH0_BASE"] + 31 * 4: 0x20001000,
        c["TPU_OUT_BUF1_BASE"] + 0 * 4: 0x00010002,
        c["TPU_OUT_BUF1_BASE"] + 1 * 4: 0x00030004,
        c["TPU_OUT_BUF1_BASE"] + 2 * 4: 0x00050006,
        c["TPU_SCRATCH1_BASE"] + 0 * 4: 0x00010002,
        c["TPU_SCRATCH1_BASE"] + 15 * 4: 0x00010002,
        c["TPU_CLASSIFIER_L0_OUT_BASE"] + 0 * 4: 0x02000100,
        c["TPU_CLASSIFIER_L0_OUT_BASE"] + 15 * 4: 0x20001000,
        c["TPU_CLASSIFIER_L0_OUT_BASE"] + 112 * 4: 0x0000025F,
        c["TPU_CLASSIFIER_L0_OUT_BASE"] + 127 * 4: 0x0000026E,
        c["TPU_CLASSIFIER_L1_OUT_BASE"] + 0 * 4: 0x02000100,
        c["TPU_CLASSIFIER_L1_OUT_BASE"] + 15 * 4: 0x20001000,
        c["TPU_CLASSIFIER_L1_OUT_BASE"] + 63 * 4: 0x0000022E,
        c["TPU_CLASSIFIER_L2_OUT_BASE"] + 0 * 4: 0x02000100,
        c["TPU_CLASSIFIER_L2_OUT_BASE"] + 31 * 4: 0x0000020E,
        c["TPU_CLASSIFIER_OUT_BASE"] + 0 * 4: 0x02000100,
        c["TPU_CLASSIFIER_OUT_BASE"] + 1 * 4: 0x04000200,
    }

    for addr, expected_word in expected.items():
        actual = mem.read(addr)
        if actual != expected_word:
            raise AssertionError("0x%08x: actual 0x%08x, expected 0x%08x" % (addr, actual, expected_word))

    param_regions = [
        ("mlp_key_l0", c["TPU_PARAM_POOL_MLP_KEY_BASE"], c["TPU_PARAM_POOL_MLP_KEY_WORDS"]),
        ("mlp_key_l1", c["TPU_PARAM_POOL_MLP_KEY_L1_BASE"], c["TPU_PARAM_POOL_MLP_KEY_L1_WORDS"]),
        ("mlp_key_l2", c["TPU_PARAM_POOL_MLP_KEY_L2_BASE"], c["TPU_PARAM_POOL_MLP_KEY_L2_WORDS"]),
        ("mlp_key_l3", c["TPU_PARAM_POOL_MLP_KEY_L3_BASE"], c["TPU_PARAM_POOL_MLP_KEY_L3_WORDS"]),
        ("mlp_key_l4", c["TPU_PARAM_POOL_MLP_KEY_L4_BASE"], c["TPU_PARAM_POOL_MLP_KEY_L4_WORDS"]),
        ("mlp_other_l0", c["TPU_PARAM_POOL_MLP_OTHER_BASE"], c["TPU_PARAM_POOL_MLP_OTHER_WORDS"]),
        ("mlp_other_l1", c["TPU_PARAM_POOL_MLP_OTHER_L1_BASE"], c["TPU_PARAM_POOL_MLP_OTHER_L1_WORDS"]),
    ]
    for chunk in range(c["TPU_CLASSIFIER_L0_CHUNKS"]):
        param_regions.append(
            (
                "classifier_l0_chunk%d" % chunk,
                c["TPU_PARAM_POOL_CLASSIFIER_L0_BASE"] + chunk * c["TPU_PARAM_POOL_CLASSIFIER_L0_STRIDE_BYTES"],
                c["TPU_PARAM_POOL_CLASSIFIER_L0_WORDS"],
            )
        )
    for chunk in range(c["TPU_CLASSIFIER_L1_CHUNKS"]):
        param_regions.append(
            (
                "classifier_l1_chunk%d" % chunk,
                c["TPU_PARAM_POOL_CLASSIFIER_L1_BASE"] + chunk * c["TPU_PARAM_POOL_CLASSIFIER_L1_STRIDE_BYTES"],
                c["TPU_PARAM_POOL_CLASSIFIER_L1_WORDS"],
            )
        )
    param_regions.extend(
        [
            ("classifier_l2", c["TPU_PARAM_POOL_CLASSIFIER_L2_BASE"], c["TPU_PARAM_POOL_CLASSIFIER_L2_WORDS"]),
            ("classifier_l3", c["TPU_PARAM_POOL_CLASSIFIER_L3_BASE"], c["TPU_PARAM_POOL_CLASSIFIER_L3_WORDS"]),
        ]
    )
    check_no_overlap(param_regions)

    final_words = mem.read_words(c["TPU_CLASSIFIER_OUT_BASE"], c["TPU_CLASSIFIER_L3_OUTPUT_WORDS"])
    print("golden check passed")
    print("launches             : %d" % len(launches))
    print("classifier final out : %s" % " ".join("0x%08x" % word for word in final_words))
    print("param regions checked: %d" % len(param_regions))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--header", type=Path, default=TPU_DESC_H, help="Path to tpu_desc.h")
    args = parser.parse_args()

    constants = parse_macros(args.header)
    run_checks(constants)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
