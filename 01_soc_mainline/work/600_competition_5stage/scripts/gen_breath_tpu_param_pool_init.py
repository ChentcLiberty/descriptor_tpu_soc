#!/usr/bin/env python3
"""Generate shared-SRAM param_pool init files for the breath TPU demo.

This script consumes the generated packed Q8.8 C header and emits a sparse
Verilog $readmemh file with @word-address directives. The addresses are word
offsets relative to shared SRAM base 0x6000_0000, matching axi_ram.mem[]. It
also computes the current deterministic demo input outputs using the exported
real parameters, so a preload TB can compare against a software golden.
"""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_HEADER = ROOT / "work/600_competition_5stage/software/generated/breath_tpu_params_q8_8.h"
DEFAULT_OUT_DIR = ROOT / "work/600_competition_5stage/fpga/stage2_programs/breath_tpu_params_q8_8"
SHARED_BASE = 0x60000000

ADDR = {
    "g_tpu_param_mlp_key_l0": 0x60000000,
    "g_tpu_param_mlp_key_l1": 0x60000400,
    "g_tpu_param_mlp_key_l2": 0x60002000,
    "g_tpu_param_mlp_key_l3": 0x60007000,
    "g_tpu_param_mlp_key_l4": 0x6000C000,
    "g_tpu_param_mlp_other_l0": 0x6000E000,
    "g_tpu_param_mlp_other_l1": 0x6000E400,
    "g_tpu_param_classifier_l2": 0x60064000,
    "g_tpu_param_classifier_l3": 0x60069000,
}
for i in range(8):
    ADDR["g_tpu_param_classifier_l0_chunk%d" % i] = 0x60020000 + i * 0x6000
for i in range(4):
    ADDR["g_tpu_param_classifier_l1_chunk%d" % i] = 0x60050000 + i * 0x5000

TPU_IN_BUF0_BASE = 0x60010100
TPU_IN_BUF1_BASE = 0x60011100
TPU_OUT_BUF0_BASE = 0x60010400
TPU_OUT_BUF1_BASE = 0x60011400
TPU_SCRATCH0_BASE = 0x60010800
TPU_SCRATCH1_BASE = 0x60011800
TPU_CLASSIFIER_IN_BASE = 0x60012000
TPU_CLASSIFIER_L0_OUT_BASE = 0x60012400
TPU_CLASSIFIER_L1_OUT_BASE = 0x60012800
TPU_CLASSIFIER_L2_OUT_BASE = 0x60012C00
TPU_CLASSIFIER_OUT_BASE = 0x60013000


def parse_arrays(header_path):
    text = header_path.read_text(encoding="utf-8")
    array_re = re.compile(r"static\s+const\s+uint32_t\s+(\w+)\s*\[[^\]]+\]\s*=\s*\{(.*?)\};", re.S)
    arrays = {}
    for name, body in array_re.findall(text):
        words = [int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]+)u?", body)]
        arrays[name] = words
    return arrays


def check_regions(arrays):
    regions = []
    for name, words in arrays.items():
        if name not in ADDR:
            continue
        base = ADDR[name]
        regions.append((base, base + len(words) * 4, name))
    regions.sort()
    for left, right in zip(regions, regions[1:]):
        if left[1] > right[0]:
            raise SystemExit("param region overlap: %s vs %s" % (left[2], right[2]))
    return regions


def write_sparse_mem(arrays, out_path):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="ascii") as f:
        f.write("// Auto-generated sparse shared SRAM param_pool init.\n")
        f.write("// Addresses are word offsets from 0x6000_0000 for axi_ram.mem[].\n")
        for name in sorted(ADDR, key=lambda item: ADDR[item]):
            words = arrays.get(name)
            if words is None:
                raise SystemExit("missing array in header: %s" % name)
            word_index = (ADDR[name] - SHARED_BASE) // 4
            f.write("\n// %s @ 0x%08X words=%d\n" % (name, ADDR[name], len(words)))
            f.write("@%08X\n" % word_index)
            for i in range(0, len(words), 8):
                f.write(" ".join("%08X" % word for word in words[i:i + 8]) + "\n")


def s16(value):
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def u16(value):
    return value & 0xFFFF


def qmul(a, b):
    return (s16(a) * s16(b)) >> 8


def round_shift_signed(value, shift):
    value = int(value)
    if shift <= 0:
        return value << (-shift)
    add = 1 << (shift - 1)
    if value >= 0:
        return (value + add) >> shift
    return -(((-value) + add) >> shift)


def sat(value):
    if value > 32767:
        return 0x7FFF
    if value < -32768:
        return 0x8000
    return u16(value)


def pack(y0, y1):
    return (u16(y1) << 16) | u16(y0)


class Mem:
    def __init__(self):
        self.words = {}

    def read(self, addr):
        return self.words.get(addr, 0)

    def write(self, addr, value):
        self.words[addr] = value & 0xFFFFFFFF

    def load(self, addr, words):
        for i, word in enumerate(words):
            self.write(addr + i * 4, word)

    def copy(self, dst, src, count):
        for i in range(count):
            self.write(dst + i * 4, self.read(src + i * 4))

    def read_words(self, addr, count):
        return [self.read(addr + i * 4) for i in range(count)]


def run_linear(mem, input_addr, output_addr, param_addr, input_words, output_words, relu):
    inputs = mem.read_words(input_addr, input_words)
    stride_words = input_words * 2 + 1
    for out_idx in range(output_words):
        param_base = param_addr + out_idx * stride_words * 4
        acc0 = 0
        acc1 = 0
        for in_idx, in_word in enumerate(inputs):
            p0 = mem.read(param_base + (in_idx * 2) * 4)
            p1 = mem.read(param_base + (in_idx * 2 + 1) * 4)
            x0 = s16(in_word)
            x1 = s16(in_word >> 16)
            acc0 += x0 * s16(p0)
            acc0 += x1 * s16(p0 >> 16)
            acc1 += x0 * s16(p1)
            acc1 += x1 * s16(p1 >> 16)
        bias = mem.read(param_base + (input_words * 2) * 4)
        acc0 += s16(bias) << 8
        acc1 += s16(bias >> 16) << 8
        acc0 = round_shift_signed(acc0, 8)
        acc1 = round_shift_signed(acc1, 8)
        y0 = 0 if relu and acc0 < 0 else sat(acc0)
        y1 = 0 if relu and acc1 < 0 else sat(acc1)
        mem.write(output_addr + out_idx * 4, pack(y0, y1))


def compute_demo_expected(arrays):
    mem = Mem()
    for name, words in arrays.items():
        if name in ADDR:
            mem.load(ADDR[name], words)

    mem.write(TPU_IN_BUF0_BASE, 0x02000100)
    mem.write(TPU_IN_BUF1_BASE + 0, 0x00010002)
    mem.write(TPU_IN_BUF1_BASE + 4, 0x00030004)
    mem.write(TPU_IN_BUF1_BASE + 8, 0x00050006)

    run_linear(mem, TPU_IN_BUF0_BASE, TPU_OUT_BUF0_BASE, ADDR["g_tpu_param_mlp_key_l0"], 1, 16, True)
    run_linear(mem, TPU_OUT_BUF0_BASE, TPU_SCRATCH0_BASE, ADDR["g_tpu_param_mlp_key_l1"], 16, 32, True)
    run_linear(mem, TPU_SCRATCH0_BASE, TPU_OUT_BUF1_BASE, ADDR["g_tpu_param_mlp_key_l2"], 32, 64, True)
    run_linear(mem, TPU_OUT_BUF1_BASE, TPU_SCRATCH1_BASE, ADDR["g_tpu_param_mlp_key_l3"], 64, 32, True)
    run_linear(mem, TPU_SCRATCH1_BASE, TPU_OUT_BUF0_BASE, ADDR["g_tpu_param_mlp_key_l4"], 32, 16, True)

    run_linear(mem, TPU_IN_BUF1_BASE, TPU_OUT_BUF1_BASE, ADDR["g_tpu_param_mlp_other_l0"], 3, 16, True)
    run_linear(mem, TPU_OUT_BUF1_BASE, TPU_SCRATCH1_BASE, ADDR["g_tpu_param_mlp_other_l1"], 16, 16, True)

    mem.copy(TPU_CLASSIFIER_IN_BASE + 0 * 4, TPU_OUT_BUF0_BASE, 16)
    mem.write(TPU_CLASSIFIER_IN_BASE + 16 * 4, 0x02000100)
    for i in range(128):
        mem.write(TPU_CLASSIFIER_IN_BASE + (17 + i) * 4, 0x00000200 + i)
    mem.copy(TPU_CLASSIFIER_IN_BASE + 145 * 4, TPU_SCRATCH1_BASE, 16)

    for chunk in range(8):
        run_linear(mem, TPU_CLASSIFIER_IN_BASE, TPU_CLASSIFIER_L0_OUT_BASE + chunk * 16 * 4, ADDR["g_tpu_param_classifier_l0_chunk%d" % chunk], 161, 16, True)
    for chunk in range(4):
        run_linear(mem, TPU_CLASSIFIER_L0_OUT_BASE, TPU_CLASSIFIER_L1_OUT_BASE + chunk * 16 * 4, ADDR["g_tpu_param_classifier_l1_chunk%d" % chunk], 128, 16, True)
    run_linear(mem, TPU_CLASSIFIER_L1_OUT_BASE, TPU_CLASSIFIER_L2_OUT_BASE, ADDR["g_tpu_param_classifier_l2"], 64, 32, True)
    run_linear(mem, TPU_CLASSIFIER_L2_OUT_BASE, TPU_CLASSIFIER_OUT_BASE, ADDR["g_tpu_param_classifier_l3"], 32, 2, False)

    return {
        "mlp_key_out_words": ["0x%08X" % w for w in mem.read_words(TPU_OUT_BUF0_BASE, 16)],
        "mlp_other_out_words": ["0x%08X" % w for w in mem.read_words(TPU_SCRATCH1_BASE, 16)],
        "classifier_l2_out_words": ["0x%08X" % w for w in mem.read_words(TPU_CLASSIFIER_L2_OUT_BASE, 32)],
        "classifier_final_out_words": ["0x%08X" % w for w in mem.read_words(TPU_CLASSIFIER_OUT_BASE, 2)],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--header", type=Path, default=DEFAULT_HEADER)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args()

    arrays = parse_arrays(args.header)
    regions = check_regions(arrays)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    mem_path = args.out_dir / "breath_tpu_param_pool_q8_8.mem"
    expected_path = args.out_dir / "breath_tpu_param_pool_q8_8_expected.json"
    write_sparse_mem(arrays, mem_path)
    expected = compute_demo_expected(arrays)
    expected["param_regions"] = [
        {"name": name, "base": "0x%08X" % base, "end": "0x%08X" % end, "words": (end - base) // 4}
        for base, end, name in regions
    ]
    expected_path.write_text(json.dumps(expected, indent=2, sort_keys=True) + "\n", encoding="ascii")
    print("generated:", mem_path)
    print("generated:", expected_path)
    print("param regions:", len(regions))
    print("classifier final out:", " ".join(expected["classifier_final_out_words"]))


if __name__ == "__main__":
    main()
