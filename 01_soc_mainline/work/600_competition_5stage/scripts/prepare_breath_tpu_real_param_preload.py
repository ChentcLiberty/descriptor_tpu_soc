#!/usr/bin/env python3
"""Prepare real-Q8.8 parameter preload artifacts for the breath TPU SoC demo.

This script makes the real-parameter CPU boot path reproducible:

1. export Linear/MLP checkpoint weights to software/generated/*.h/json
2. convert that header into a sparse shared-SRAM param_pool $readmemh file
3. build the demo with TPU_RUNTIME_PARAM_POOL_PRELOADED=1
4. generate the separate real-params IMEM files used by the real-params TB
5. optionally rebuild the default deterministic demo and IMEM baseline
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
PRELOAD_IMEM_PREFIX = WORK / 'fpga/stage2_programs/breath_tpu_soc_demo_preload_params/breath_tpu_soc_demo_preload_params_imem'


def run(cmd, cwd=ROOT):
    print('+ ' + ' '.join(str(x) for x in cmd))
    subprocess.run([str(x) for x in cmd], cwd=str(cwd), check=True)


def build_demo(preloaded):
    run([
        'make', '-C', DEMO_DIR, '-B',
        'TPU_RUNTIME_USE_MMIO=1',
        'TPU_RUNTIME_USE_EXPORTED_PARAMS_Q8_8=0',
        'TPU_RUNTIME_PARAM_POOL_PRELOADED=%d' % (1 if preloaded else 0),
        'BREATH_TPU_SOC_DEMO_USE_UART=0',
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
    parser.add_argument('--skip-export', action='store_true', help='reuse existing software/generated parameter header')
    parser.add_argument('--skip-param-pool', action='store_true', help='reuse existing sparse param_pool mem/json')
    parser.add_argument('--no-restore-default', action='store_true', help='leave demo build products in preloaded mode')
    parser.add_argument('--loader', choices=('auto', 'torch', 'torchzip'), default='auto', help='checkpoint loader passed to export script')
    args = parser.parse_args()

    if not args.skip_export:
        run([
            sys.executable,
            SCRIPTS / 'export_breath_linear_q8_8_params.py',
            '--loader', args.loader,
        ])

    if not args.skip_param_pool:
        run([
            sys.executable,
            SCRIPTS / 'gen_breath_tpu_param_pool_init.py',
        ])

    build_demo(preloaded=True)
    gen_imem(PRELOAD_IMEM_PREFIX)

    if not args.no_restore_default:
        build_demo(preloaded=False)
        gen_imem(DEFAULT_IMEM_PREFIX)

    print('prepared real-param preload IMEM:', PRELOAD_IMEM_PREFIX)
    if not args.no_restore_default:
        print('restored deterministic baseline IMEM:', DEFAULT_IMEM_PREFIX)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
