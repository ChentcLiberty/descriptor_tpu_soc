#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Any


@dataclass
class TensorSpec:
    name: str
    role: str
    shape: list[int]
    words: int
    storage: str
    addr: int | None
    dtype: str


def _product(shape: list[int]) -> int:
    total = 1
    for dim in shape:
        total *= dim
    return total


def _dtype_tag(data_format: dict[str, Any]) -> str:
    width = int(data_format["width_bits"])
    frac = int(data_format["frac_bits"])
    int_bits = width - frac
    return f"Q{int_bits}.{frac}"


def load_spec(path: str | Path) -> dict[str, Any]:
    spec_path = Path(path)
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    if spec.get("model_type") != "mlp":
        raise ValueError(f"unsupported model_type: {spec.get('model_type')!r}")
    if "layers" not in spec or not spec["layers"]:
        raise ValueError("spec must contain at least one layer")
    if "hardware_target" not in spec:
        raise ValueError("spec must contain hardware_target")
    if "data_format" not in spec:
        raise ValueError("spec must contain data_format")
    return spec


def infer_tensor_catalog(spec: dict[str, Any]) -> list[TensorSpec]:
    layers = spec["layers"]
    batch_size = int(spec["batch_size"])
    input_dim = int(spec["input_dim"])
    dtype = _dtype_tag(spec["data_format"])
    training_enabled = bool(spec.get("training", {}).get("enabled", True))
    persist_output_activation = bool(spec.get("persist_output_activation", False))

    tensors: list[TensorSpec] = []
    output_dim = int(layers[-1]["out_dim"])

    tensors.append(
        TensorSpec(
            name="X",
            role="input",
            shape=[batch_size, input_dim],
            words=batch_size * input_dim,
            storage="ub",
            addr=None,
            dtype=dtype,
        )
    )
    tensors.append(
        TensorSpec(
            name="Y",
            role="label",
            shape=[batch_size, output_dim],
            words=batch_size * output_dim,
            storage="ub",
            addr=None,
            dtype=dtype,
        )
    )

    prev_dim = input_dim
    layer_out_dims: list[int] = []
    for index, layer in enumerate(layers, start=1):
        if layer.get("type") != "linear":
            raise ValueError(f"layer {index} must be type=linear for the current allocator")
        out_dim = int(layer["out_dim"])
        layer_out_dims.append(out_dim)
        tensors.append(
            TensorSpec(
                name=f"W{index}",
                role="weight",
                shape=[out_dim, prev_dim],
                words=out_dim * prev_dim,
                storage="ub",
                addr=None,
                dtype=dtype,
            )
        )
        tensors.append(
            TensorSpec(
                name=f"B{index}",
                role="bias",
                shape=[out_dim],
                words=out_dim,
                storage="ub",
                addr=None,
                dtype=dtype,
            )
        )
        prev_dim = out_dim

    for index, out_dim in enumerate(layer_out_dims, start=1):
        is_last = index == len(layer_out_dims)
        storage = "ub" if (not is_last or persist_output_activation) else "ephemeral"
        tensors.append(
            TensorSpec(
                name=f"H{index}",
                role="activation",
                shape=[batch_size, out_dim],
                words=batch_size * out_dim,
                storage=storage,
                addr=None,
                dtype=dtype,
            )
        )

    if training_enabled:
        for index in range(len(layer_out_dims), 0, -1):
            out_dim = layer_out_dims[index - 1]
            tensors.append(
                TensorSpec(
                    name=f"dZ{index}",
                    role="gradient_activation",
                    shape=[batch_size, out_dim],
                    words=batch_size * out_dim,
                    storage="ub",
                    addr=None,
                    dtype=dtype,
                )
            )
            if index > 1:
                prev_out_dim = layer_out_dims[index - 2]
                tensors.append(
                    TensorSpec(
                        name=f"dH{index - 1}",
                        role="gradient_hidden",
                        shape=[batch_size, prev_out_dim],
                        words=batch_size * prev_out_dim,
                        storage="ephemeral",
                        addr=None,
                        dtype=dtype,
                    )
                )

    return tensors


def allocate_from_spec(spec: dict[str, Any]) -> dict[str, Any]:
    ub_depth_words = int(spec["hardware_target"]["ub_depth_words"])
    catalog = infer_tensor_catalog(spec)

    cursor = 0
    allocated: list[TensorSpec] = []
    for tensor in catalog:
        entry = replace(tensor)
        if entry.storage == "ub":
            entry.addr = cursor
            cursor += entry.words
        allocated.append(entry)

    if cursor > ub_depth_words:
        raise ValueError(
            f"UB allocation overflow: need {cursor} words but target depth is {ub_depth_words}"
        )

    return {
        "allocator_version": "0.1",
        "spec_name": spec["name"],
        "model_type": spec["model_type"],
        "data_format": spec["data_format"],
        "hardware_target": spec["hardware_target"],
        "allocated_words": cursor,
        "free_words": ub_depth_words - cursor,
        "tensors": [asdict(tensor) for tensor in allocated],
    }


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Infer tensor layout and allocate UB addresses.")
    parser.add_argument("spec", help="Path to a model spec JSON file")
    parser.add_argument(
        "-o",
        "--output",
        help="Optional output JSON path. If omitted, the allocation is printed to stdout.",
    )
    return parser


def main() -> int:
    parser = _build_arg_parser()
    args = parser.parse_args()

    spec = load_spec(args.spec)
    report = allocate_from_spec(spec)
    payload = json.dumps(report, indent=2, ensure_ascii=False)

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
