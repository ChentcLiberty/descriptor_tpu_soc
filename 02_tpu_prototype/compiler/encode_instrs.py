#!/usr/bin/env python3
"""Encode a schedule.json command list into 32-bit opcode TPU instructions.

Instruction format (32-bit):
  opcode=3'b000  NOP
  opcode=3'b001  SWITCH  (sys_switch)
  opcode=3'b010  UB_RD
    [2:0]   opcode = 3'b010
    [8:3]   addr[5:0]       UB address (0-63)
    [12:9]  row_size[3:0]   row count (1-15)
    [14:13] col_size[1:0]   column count
    [15]    transpose
    [18:16] ptr_sel[2:0]    0=input,1=weight,2=bias,3=Y,4=H,5=grad_bias,6=grad_weight
    [22:19] vpu_pathway[3:0]
    [31:23] reserved
  opcode=3'b011  UB_WR_HOST
    [2:0]   opcode = 3'b011
    [18:3]  data[15:0]
    [31:19] reserved

Outputs:
  - imem.hex  : one 32-bit instruction per line (8 hex chars)
  - imem.txt  : human-readable annotation
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

OPCODE_NOP    = 0b000
OPCODE_SWITCH = 0b001
OPCODE_UB_RD  = 0b010
OPCODE_UB_WR  = 0b011


def encode_command(cmd: dict) -> int:
    """Encode one scheduler command into a 32-bit opcode instruction."""
    kind    = cmd.get("kind", "nop")
    signals = cmd.get("signals", {})

    if kind == "wait":
        return None  # not encoded, handled by sequencer hardware

    if kind == "control" and signals.get("sys_switch_in"):
        return OPCODE_SWITCH  # 32'h00000001

    if kind == "ub_read":
        instr = OPCODE_UB_RD
        addr      = int(signals.get("ub_rd_addr_in",  0)) & 0x3F
        row       = int(signals.get("ub_rd_row_size", 0)) & 0xF
        col       = int(signals.get("ub_rd_col_size", 0)) & 0x3
        transpose = int(signals.get("ub_rd_transpose", 0)) & 0x1
        ptr_sel   = int(signals.get("ub_ptr_select",  0)) & 0x7
        vpu_path  = signals.get("vpu_data_pathway", 0)
        if isinstance(vpu_path, str):
            vpu_path = int(vpu_path, 2)
        vpu_path = int(vpu_path) & 0xF
        wait_after = int(cmd.get("wait_after", 0)) & 0x1

        instr |= addr     << 3
        instr |= row      << 9
        instr |= col      << 13
        instr |= transpose << 15
        instr |= ptr_sel  << 16
        instr |= vpu_path << 19
        instr |= wait_after << 23
        return instr

    # NOP for unknown / unhandled
    return OPCODE_NOP


def encode_schedule(schedule_path: str | Path, out_dir: str | Path) -> int:
    schedule = json.loads(Path(schedule_path).read_text(encoding="utf-8"))
    commands = schedule["commands"]

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    hex_lines = []
    txt_lines = [f"# TinyTPU IMEM (32-bit opcode) from {Path(schedule_path).name}\n"]

    slot = 0
    for cmd in commands:
        instr = encode_command(cmd)
        if instr is None:
            txt_lines.append(f"# [wait] {cmd['stage']}.{cmd['name']} — skipped (handled by sequencer)\n")
            continue
        hex_str = f"{instr:08x}"
        hex_lines.append(hex_str)
        txt_lines.append(f"[{slot:02d}] {hex_str}  {cmd['stage']}.{cmd['name']}  ({cmd['kind']})\n")
        if cmd.get("note"):
            txt_lines.append(f"       note: {cmd['note']}\n")
        slot += 1

    txt_lines.insert(1, f"# {slot} instructions (wait commands excluded)\n\n")

    (out_dir / "imem.hex").write_text("\n".join(hex_lines) + "\n", encoding="utf-8")
    (out_dir / "imem.txt").write_text("".join(txt_lines), encoding="utf-8")

    print(f"Encoded {slot} instructions -> {out_dir}/imem.hex")
    print(f"Annotation                  -> {out_dir}/imem.txt")
    return slot


def main() -> int:
    parser = argparse.ArgumentParser(description="Encode schedule.json to 32-bit opcode IMEM hex.")
    parser.add_argument("schedule", help="Path to schedule.json")
    parser.add_argument("-o", "--output", default="compiler/out", help="Output directory")
    args = parser.parse_args()
    encode_schedule(args.schedule, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
