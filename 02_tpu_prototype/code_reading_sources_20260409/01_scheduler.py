#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from compiler.ub_allocator import allocate_from_spec, load_spec  # noqa: E402


def _tensor_map(allocation: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {tensor["name"]: tensor for tensor in allocation["tensors"]}


def _tile_ranges(total_rows: int, tile_rows: int) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for start in range(0, total_rows, tile_rows):
        ranges.append((start, min(tile_rows, total_rows - start)))
    return ranges


def _ub_read(
    stage: str,
    name: str,
    tensor: str,
    ptr_sel: int,
    addr: int,
    row: int,
    col: int,
    transpose: bool,
    *,
    vpu_path: str | None = None,
    note: str = "",
    wait_after: bool = False,
) -> dict[str, Any]:
    command: dict[str, Any] = {
        "stage": stage,
        "name": name,
        "kind": "ub_read",
        "tensor": tensor,
        "signals": {
            "ub_rd_start_in": 1,
            "ub_ptr_select": ptr_sel,
            "ub_rd_addr_in": addr,
            "ub_rd_row_size": row,
            "ub_rd_col_size": col,
            "ub_rd_transpose": int(transpose),
        },
        "wait_after": int(wait_after),
    }
    if vpu_path is not None:
        command["signals"]["vpu_data_pathway"] = vpu_path
    if note:
        command["note"] = note
    return command


def _switch(stage: str, name: str, note: str = "") -> dict[str, Any]:
    command: dict[str, Any] = {
        "stage": stage,
        "name": name,
        "kind": "control",
        "signals": {"sys_switch_in": 1},
    }
    if note:
        command["note"] = note
    return command


def _wait(stage: str, name: str, event: str, note: str = "") -> dict[str, Any]:
    command: dict[str, Any] = {
        "stage": stage,
        "name": name,
        "kind": "wait",
        "event": event,
    }
    if note:
        command["note"] = note
    return command


def _validate_current_target(spec: dict[str, Any]) -> None:
    layers = spec["layers"]
    hw = spec["hardware_target"]

    if spec.get("model_type") != "mlp":
        raise ValueError("scheduler currently supports model_type=mlp only")
    if len(layers) != 2:
        raise ValueError("scheduler currently supports exactly two linear layers")
    if hw.get("array_width") != 2 or hw.get("lanes") != 2:
        raise ValueError("scheduler currently targets the 2x2 / 2-lane tiny-tpu prototype")
    if int(spec["input_dim"]) > 2:
        raise ValueError("current scheduler assumes input_dim <= 2")
    if int(layers[0]["out_dim"]) > 2:
        raise ValueError("current scheduler assumes hidden_dim <= 2")
    if int(layers[1]["out_dim"]) > 2:
        raise ValueError("current scheduler assumes output_dim <= 2")
    if not bool(spec.get("training", {}).get("enabled", True)):
        raise ValueError("current scheduler is aimed at training flow generation")


def _nop(stage: str, name: str) -> dict[str, Any]:
    return {"stage": stage, "name": name, "kind": "nop", "signals": {}}


def build_schedule(spec: dict[str, Any]) -> dict[str, Any]:
    _validate_current_target(spec)
    allocation = allocate_from_spec(spec)
    tensors = _tensor_map(allocation)

    batch_size = int(spec["batch_size"])
    input_dim = int(spec["input_dim"])
    hidden_dim = int(spec["layers"][0]["out_dim"])
    output_dim = int(spec["layers"][1]["out_dim"])
    tile_width = int(spec["hardware_target"]["array_width"])

    commands: list[dict[str, Any]] = []

    # Forward layer 1: H1 = act(X @ W1^T + B1)
    commands.append(
        _ub_read(
            "forward_layer1",
            "load_w1_shadow",
            "W1",
            1,
            tensors["W1"]["addr"],
            hidden_dim,
            input_dim,
            True,
            note="Load W1^T through the top boundary into the PE shadow weight path.",
        )
    )
    for i in range(4):
        commands.append(_nop("forward_layer1", f"nop_w1_load_{i}"))
    commands.append(_switch("forward_layer1", "activate_w1"))
    commands.append(
        _ub_read(
            "forward_layer1",
            "stream_x",
            "X",
            0,
            tensors["X"]["addr"],
            batch_size,
            input_dim,
            False,
            vpu_path="1100",
            note="Run the first layer forward path: systolic -> bias -> leaky_relu.",
        )
    )
    commands.append(
        _ub_read(
            "forward_layer1",
            "stream_b1",
            "B1",
            2,
            tensors["B1"]["addr"],
            batch_size,
            hidden_dim,
            False,
            vpu_path="1100",
            wait_after=True,
            note="Bias stream for layer 1. VPU writeback is expected to append H1 to UB.",
        )
    )
    commands.append(
        _wait(
            "forward_layer1",
            "wait_h1_writeback",
            "vpu_drain",
            note="H1 should now be available in the UB activation region.",
        )
    )

    # Layer 2 forward + transition: dZ2 comes out directly from the 1111 path.
    commands.append(
        _ub_read(
            "transition_layer2",
            "load_w2_shadow",
            "W2",
            1,
            tensors["W2"]["addr"],
            output_dim,
            hidden_dim,
            True,
            note="Load W2^T for the second layer forward pass.",
        )
    )
    for i in range(4):
        commands.append(_nop("transition_layer2", f"nop_w2_load_{i}"))
    commands.append(_switch("transition_layer2", "activate_w2"))
    commands.append(
        _ub_read(
            "transition_layer2",
            "stream_h1",
            "H1",
            0,
            tensors["H1"]["addr"],
            batch_size,
            hidden_dim,
            False,
            vpu_path="1111",
            note="Run layer 2 forward + loss gradient + activation derivative.",
        )
    )
    commands.append(
        _ub_read(
            "transition_layer2",
            "stream_b2",
            "B2",
            2,
            tensors["B2"]["addr"],
            batch_size,
            output_dim,
            False,
            vpu_path="1111",
        )
    )
    commands.append(
        _ub_read(
            "transition_layer2",
            "stream_y",
            "Y",
            3,
            tensors["Y"]["addr"],
            batch_size,
            output_dim,
            False,
            vpu_path="1111",
            note="Loss module consumes Y while H2 stays transient in the VPU pipeline.",
        )
    )
    commands.append(
        _ub_read(
            "transition_layer2",
            "load_old_b2",
            "B2",
            5,
            tensors["B2"]["addr"],
            batch_size,
            output_dim,
            False,
            vpu_path="1111",
            wait_after=True,
            note="Enable in-UB bias update while dZ2 streams out of the VPU.",
        )
    )
    commands.append(
        _wait(
            "transition_layer2",
            "wait_dz2_writeback",
            "vpu_drain",
            note="dZ2 should now be appended in UB and B2 should be updated in place.",
        )
    )

    # Backward layer 1: dZ1 = act'(dZ2 @ W2, H1)
    commands.append(
        _ub_read(
            "backward_layer1",
            "load_w2_backward",
            "W2",
            1,
            tensors["W2"]["addr"],
            output_dim,
            hidden_dim,
            False,
            note="Backward uses W2 without transpose.",
        )
    )
    for i in range(4):
        commands.append(_nop("backward_layer1", f"nop_w2bwd_load_{i}"))
    commands.append(_switch("backward_layer1", "activate_w2_backward"))
    commands.append(
        _ub_read(
            "backward_layer1",
            "load_old_b1",
            "B1",
            5,
            tensors["B1"]["addr"],
            batch_size,
            hidden_dim,
            False,
            vpu_path="0001",
            note="Prime the in-UB B1 update path before the derivative stream starts.",
        )
    )
    commands.append(
        _ub_read(
            "backward_layer1",
            "stream_dz2",
            "dZ2",
            0,
            tensors["dZ2"]["addr"],
            batch_size,
            output_dim,
            False,
            vpu_path="0001",
            note="Run the derivative-only VPU path for layer 1 backward propagation.",
        )
    )
    commands.append(
        _ub_read(
            "backward_layer1",
            "stream_h1_for_derivative",
            "H1",
            4,
            tensors["H1"]["addr"],
            batch_size,
            hidden_dim,
            False,
            vpu_path="0001",
            wait_after=True,
            note="Start the H1 sign stream immediately after dH1 so the derivative stage sees aligned activations while B1 is already armed.",
        )
    )
    commands.append(
        _wait(
            "backward_layer1",
            "wait_dz1_writeback",
            "vpu_drain",
            note="dZ1 should now be appended in UB and B1 should be updated in place.",
        )
    )

    # Weight update for W1: dW1 = dZ1^T @ X
    for tile_index, (tile_start, tile_rows) in enumerate(_tile_ranges(batch_size, tile_width)):
        x_addr = tensors["X"]["addr"] + tile_start * input_dim
        dz1_addr = tensors["dZ1"]["addr"] + tile_start * hidden_dim
        stage = f"update_w1_tile_{tile_index}"
        commands.append(
            _ub_read(
                stage,
                "load_x_tile_to_top",
                "X",
                1,
                x_addr,
                tile_rows,
                input_dim,
                False,
                note="Use the top boundary as one side of the outer-product update tile.",
            )
        )
        for i in range(4):
            commands.append(_nop(stage, f"nop_x_load_{i}"))
        commands.append(_switch(stage, "activate_x_tile"))
        commands.append(
            _ub_read(
                stage,
                "load_dz1_tile_transposed",
                "dZ1",
                0,
                dz1_addr,
                tile_rows,
                hidden_dim,
                True,
                vpu_path="0000",
                note="Pure systolic outer-product tile for dW1.",
            )
        )
        commands.append(
            _ub_read(
                stage,
                "load_old_w1",
                "W1",
                6,
                tensors["W1"]["addr"],
                hidden_dim,
                input_dim,
                False,
                vpu_path="0000",
                wait_after=True,
                note="Consume old W1 so the in-UB gradient_descent block can update in place.",
            )
        )
        commands.append(_wait(stage, "wait_w1_update", "vpu_drain"))

    # Weight update for W2: dW2 = dZ2^T @ H1
    for tile_index, (tile_start, tile_rows) in enumerate(_tile_ranges(batch_size, tile_width)):
        h1_addr = tensors["H1"]["addr"] + tile_start * hidden_dim
        dz2_addr = tensors["dZ2"]["addr"] + tile_start * output_dim
        stage = f"update_w2_tile_{tile_index}"
        commands.append(
            _ub_read(
                stage,
                "load_h1_tile_to_top",
                "H1",
                1,
                h1_addr,
                tile_rows,
                hidden_dim,
                False,
                note="Use H1 tiles on the top boundary for the W2 outer product.",
            )
        )
        for i in range(4):
            commands.append(_nop(stage, f"nop_h1_load_{i}"))
        commands.append(_switch(stage, "activate_h1_tile"))
        commands.append(
            _ub_read(
                stage,
                "load_dz2_tile_transposed",
                "dZ2",
                0,
                dz2_addr,
                tile_rows,
                output_dim,
                True,
                vpu_path="0000",
                note="Pure systolic outer-product tile for dW2.",
            )
        )
        commands.append(
            _ub_read(
                stage,
                "load_old_w2",
                "W2",
                6,
                tensors["W2"]["addr"],
                output_dim,
                hidden_dim,
                False,
                vpu_path="0000",
                wait_after=True,
                note="Consume old W2 so the in-UB gradient_descent block can update in place.",
            )
        )
        commands.append(_wait(stage, "wait_w2_update", "vpu_drain"))

    host_load_plan = [
        {
            "tensor": tensor["name"],
            "addr": tensor["addr"],
            "shape": tensor["shape"],
            "words": tensor["words"],
        }
        for tensor in allocation["tensors"]
        if tensor["storage"] == "ub" and tensor["role"] in {"input", "label", "weight", "bias"}
    ]

    return {
        "scheduler_version": "0.1",
        "spec_name": spec["name"],
        "target": "tiny-tpu-2x2-stage-schedule",
        "assumptions": [
            "current RTL is still testbench-driven at the top level",
            "command list is stage-level and not a cycle-accurate waveform program yet",
            "current implementation targets a 2-layer MLP under the 2x2 / 2-lane prototype limits",
        ],
        "host_load_plan": host_load_plan,
        "ub_allocation": allocation,
        "commands": commands,
    }


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Emit a stage-level schedule for the current tiny-tpu prototype.")
    parser.add_argument("spec", help="Path to a model spec JSON file")
    parser.add_argument(
        "-o",
        "--output",
        help="Optional output JSON path. If omitted, the schedule is printed to stdout.",
    )
    return parser


def main() -> int:
    parser = _build_arg_parser()
    args = parser.parse_args()

    spec = load_spec(args.spec)
    schedule = build_schedule(spec)
    payload = json.dumps(schedule, indent=2, ensure_ascii=False)

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(payload + "\n", encoding="utf-8")
        print(output_path)
    else:
        print(payload)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
