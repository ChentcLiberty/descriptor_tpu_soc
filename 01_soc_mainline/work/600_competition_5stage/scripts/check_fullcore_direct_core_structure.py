#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    rtl_dir = script_dir.parent / 'fpga' / 'panda_soc_eva' / 'rtl'

    scan_files = [
        rtl_dir / 'tpu_stage2_real_wrapper.v',
        rtl_dir / 'tpu_stage2_fullcore_wrapper.v',
        rtl_dir / 'tpu_frontend_local.v',
        rtl_dir / 'tpu_stage2_fullcore_bridge.v',
    ]

    forbidden_tokens = {
        'tpu_soc': 'active path must not structurally depend on tpu_soc',
        'tpu_frontend_axil': 'active path must not structurally depend on tpu_frontend_axil',
        'control_unit': 'active path must not structurally depend on control_unit',
        'step_exec': 'active path must not use the old generic step_exec interface',
        'ST_FE_IMEM_': 'bridge state machine must not retain old IMEM load states',
        'ST_FE_STATUS_REQ': 'bridge state machine must not retain the old frontend status request state',
        'ST_FE_RB_STEP': 'bridge state machine must not retain the old readback step state',
        'imem_instr_by_idx': 'bridge must not retain the old IMEM micro-sequence helper',
    }

    required_tokens = {
        'tpu_stage2_real_wrapper.v': ['tpu_stage2_fullcore_wrapper'],
        'tpu_stage2_fullcore_wrapper.v': ['tpu_frontend_local', 'ub_rd_y_data_out_0', 'vpu_data_out_1'],
        'tpu_frontend_local.v': ['readback_exec_valid', 'tile_exec_valid'],
        'tpu_stage2_fullcore_bridge.v': ['readback_exec_valid', 'TPU_FE_REG_UB_PUSH'],
    }

    errors = []
    for file_path in scan_files:
        if not file_path.exists():
            errors.append(f'missing file: {file_path}')
            continue
        text = file_path.read_text()
        for token, reason in forbidden_tokens.items():
            if token in text:
                errors.append(f'{file_path.name}: found forbidden token `{token}` ({reason})')
        for token in required_tokens.get(file_path.name, []):
            if token not in text:
                errors.append(f'{file_path.name}: missing required token `{token}`')

    if errors:
        print('[FAIL] fullcore direct-core structure check failed')
        for err in errors:
            print(f' - {err}')
        return 1

    print('[PASS] fullcore direct-core structure check passed')
    for file_path in scan_files:
        print(f' - scanned {file_path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
