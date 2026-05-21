#!/usr/bin/env python3
"""Prepare CPU-front-end CNN/FiLM preload artifacts for the breath TPU SoC demo.

The generated boot image runs the remaining CNN/FiLM branch on the RISC-V CPU
with Q8.8 fixed-point loops. Large CNN weights and the sample input live in
shared SRAM; TPU still accelerates the Linear/MLP/classifier stages.
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / 'work/600_competition_5stage'
SCRIPTS = WORK / 'scripts'
DEMO_DIR = WORK / 'software/test/breath_tpu_soc_demo'
DEMO_BIN = DEMO_DIR / 'breath_tpu_soc_demo.bin'
DEFAULT_IMEM_PREFIX = WORK / 'fpga/stage2_programs/breath_tpu_soc_demo/breath_tpu_soc_demo_imem'
CPU_FRONTEND_IMEM_PREFIX = WORK / 'fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend/breath_tpu_soc_demo_cpu_frontend_imem'
RAW_BUILD_DIR = WORK / 'fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_raw_build'
RAW_DEMO_ELF = RAW_BUILD_DIR / 'breath_tpu_soc_demo_cpu_frontend_raw.elf'
RAW_DEMO_BIN = RAW_BUILD_DIR / 'breath_tpu_soc_demo_cpu_frontend_raw.bin'
RAW_DEMO_DUMP = RAW_BUILD_DIR / 'breath_tpu_soc_demo_cpu_frontend_raw.dump'


def run(cmd, cwd=ROOT):
    print('+ ' + ' '.join(str(x) for x in cmd))
    subprocess.run([str(x) for x in cmd], cwd=str(cwd), check=True)


def build_demo(cpu_frontend, sw_cnn, preloaded, mmio, uart):
    run([
        'make', '-C', DEMO_DIR, '-B',
        'TPU_RUNTIME_USE_MMIO=%d' % (1 if mmio else 0),
        'TPU_RUNTIME_USE_EXPORTED_PARAMS_Q8_8=0',
        'TPU_RUNTIME_PARAM_POOL_PRELOADED=%d' % (1 if preloaded else 0),
        'BREATH_TPU_SOC_DEMO_USE_UART=%d' % (1 if uart else 0),
        'BREATH_TPU_SOC_USE_CPU_FRONTEND=%d' % (1 if cpu_frontend else 0),
        'BREATH_CPU_FRONTEND_USE_SW_CNN=%d' % (1 if sw_cnn else 0),
        'BREATH_CPU_FRONTEND_PREPROCESS_RAW=%d' % (1 if sw_cnn else 0),
    ])


def gen_imem(out_prefix):
    run([
        sys.executable,
        SCRIPTS / 'gen_imem_init_roms.py',
        '--bin', DEMO_BIN,
        '--out-prefix', out_prefix,
        '--start-addr', '0x800',
    ])


def snapshot_raw_build():
    RAW_BUILD_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(DEMO_DIR / 'breath_tpu_soc_demo', RAW_DEMO_ELF)
    shutil.copy2(DEMO_DIR / 'breath_tpu_soc_demo.bin', RAW_DEMO_BIN)
    shutil.copy2(DEMO_DIR / 'breath_tpu_soc_demo.dump', RAW_DEMO_DUMP)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-linear-export', action='store_true', help='reuse existing Linear/MLP/classifier Q8.8 header')
    parser.add_argument('--skip-cpu-export', action='store_true', help='reuse existing CPU CNN shared-SRAM mem/layout')
    parser.add_argument('--no-restore-default', action='store_true', help='leave demo build products in CPU-front-end mode')
    parser.add_argument('--loader', choices=('auto', 'torch', 'torchzip'), default='auto')
    parser.add_argument('--sample-index', type=int, default=0)
    args = parser.parse_args()

    if not args.skip_linear_export:
        run([
            sys.executable,
            SCRIPTS / 'export_breath_linear_q8_8_params.py',
            '--loader', args.loader,
        ])

    if not args.skip_cpu_export:
        run([
            sys.executable,
            SCRIPTS / 'export_breath_cpu_frontend_q8_8.py',
            '--loader', args.loader,
            '--sample-index', str(args.sample_index),
        ])

    build_demo(cpu_frontend=True, sw_cnn=True, preloaded=True, mmio=True, uart=False)
    gen_imem(CPU_FRONTEND_IMEM_PREFIX)
    snapshot_raw_build()

    if not args.no_restore_default:
        build_demo(cpu_frontend=False, sw_cnn=False, preloaded=False, mmio=True, uart=False)
        gen_imem(DEFAULT_IMEM_PREFIX)

    print('prepared CPU-front-end IMEM:', CPU_FRONTEND_IMEM_PREFIX)
    print('prepared CPU-front-end shared SRAM mem:', WORK / 'fpga/stage2_programs/breath_cpu_frontend_q8_8/breath_cpu_frontend_q8_8.mem')
    print('snapshotted raw CPU-front-end ELF:', RAW_DEMO_ELF)
    print('snapshotted raw CPU-front-end BIN:', RAW_DEMO_BIN)
    print('snapshotted raw CPU-front-end dump:', RAW_DEMO_DUMP)
    if not args.no_restore_default:
        print('restored deterministic baseline IMEM:', DEFAULT_IMEM_PREFIX)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
