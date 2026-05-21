#!/usr/bin/env python3
"""Prepare fixture-backed CPU-front-end IMEM artifacts for the breath TPU SoC demo.

This variant keeps CPU-front-end plumbing enabled but uses the compact exported
fixture vectors in IMEM while still preloading the real Q8.8 parameter pool and
shared-SRAM sample data from the external mem image.
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / 'work/600_competition_5stage'
SCRIPTS = WORK / 'scripts'
DEMO_DIR = WORK / 'software/test/breath_tpu_soc_demo'
DEMO_BIN = DEMO_DIR / 'breath_tpu_soc_demo.bin'
DEFAULT_IMEM_PREFIX = WORK / 'fpga/stage2_programs/breath_tpu_soc_demo/breath_tpu_soc_demo_imem'
FIXTURE_IMEM_PREFIX = WORK / 'fpga/stage2_programs/breath_tpu_soc_demo_cpu_frontend_fixture/breath_tpu_soc_demo_cpu_frontend_fixture_imem'


def run(cmd, cwd=ROOT):
    print('+ ' + ' '.join(str(x) for x in cmd))
    subprocess.run([str(x) for x in cmd], cwd=str(cwd), check=True)


def build_demo(cpu_frontend, sw_cnn, exported, preloaded, mmio, uart):
    run([
        'make', '-C', DEMO_DIR, '-B',
        'TPU_RUNTIME_USE_MMIO=%d' % (1 if mmio else 0),
        'TPU_RUNTIME_USE_EXPORTED_PARAMS_Q8_8=%d' % (1 if exported else 0),
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-linear-export', action='store_true', help='reuse existing Linear/MLP/classifier Q8.8 header')
    parser.add_argument('--skip-cpu-export', action='store_true', help='reuse existing shared-SRAM preload mem/layout')
    parser.add_argument('--skip-fixture-export', action='store_true', help='reuse existing CPU-front-end fixture header')
    parser.add_argument('--skip-fixture-check', action='store_true', help='reuse existing CPU-front-end fixture expected json/svh')
    parser.add_argument('--no-restore-default', action='store_true', help='leave demo build products in CPU-front-end fixture mode')
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

    if not args.skip_fixture_export:
        run([
            sys.executable,
            SCRIPTS / 'export_breath_cpu_frontend_fixture.py',
            '--loader', args.loader,
            '--sample-index', str(args.sample_index),
        ])

    if not args.skip_fixture_check:
        run([
            sys.executable,
            SCRIPTS / 'check_breath_cpu_frontend_fixture.py',
        ])

    build_demo(cpu_frontend=True, sw_cnn=False, exported=False, preloaded=True, mmio=True, uart=False)
    gen_imem(FIXTURE_IMEM_PREFIX)

    if not args.no_restore_default:
        build_demo(cpu_frontend=False, sw_cnn=False, exported=False, preloaded=False, mmio=True, uart=False)
        gen_imem(DEFAULT_IMEM_PREFIX)

    print('prepared CPU-front-end fixture IMEM:', FIXTURE_IMEM_PREFIX)
    print('prepared CPU-front-end shared SRAM mem:', WORK / 'fpga/stage2_programs/breath_cpu_frontend_q8_8/breath_cpu_frontend_q8_8.mem')
    print('prepared CPU-front-end fixture expected include:', WORK / 'software/generated/breath_cpu_frontend_fixture_expected.svh')
    if not args.no_restore_default:
        print('restored deterministic baseline IMEM:', DEFAULT_IMEM_PREFIX)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
