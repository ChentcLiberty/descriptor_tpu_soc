#!/usr/bin/env python3
"""Export BreathClassifier Linear/MLP weights to packed Q8.8 TPU param blobs.

The current stage2 hardware accelerates Linear-style subgraphs only. This script
exports these parts from the PyTorch checkpoint:

- perceptron_subnet: 2 -> 32 -> 64 -> 128 -> 64 -> 32
- other_encoder:     6 -> 32 -> 32
- classifier:        322 -> 256 -> 128 -> 64 -> 4

BatchNorm1d after a Linear layer is folded into that Linear layer so the C/RTL
Q8.8 path matches PyTorch eval semantics better. CNN/FiLM/Pool stays on CPU for
this project boundary and is not exported here.
"""

import argparse
import io
import json
import math
import pickle
import sys
import zipfile
from collections import OrderedDict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CHECKPOINT = Path('/home/jjt/soc/算法/Breathrecognitionbest/checkpoints/best_model.pth')
DEFAULT_OUT_DIR = ROOT / 'work/600_competition_5stage/software/generated'

# name, linear prefix, batchnorm prefix or None, input dim, output dim, chunk output words
LAYER_SPECS = [
    ('mlp_key_l0', 'perceptron_subnet.layers.0', 'perceptron_subnet.layers.1', 2, 32, None),
    ('mlp_key_l1', 'perceptron_subnet.layers.4', 'perceptron_subnet.layers.5', 32, 64, None),
    ('mlp_key_l2', 'perceptron_subnet.layers.8', 'perceptron_subnet.layers.9', 64, 128, None),
    ('mlp_key_l3', 'perceptron_subnet.layers.12', 'perceptron_subnet.layers.13', 128, 64, None),
    ('mlp_key_l4', 'perceptron_subnet.layers.16', 'perceptron_subnet.layers.17', 64, 32, None),
    ('mlp_other_l0', 'other_encoder.encoder.0', 'other_encoder.encoder.1', 6, 32, None),
    ('mlp_other_l1', 'other_encoder.encoder.4', 'other_encoder.encoder.5', 32, 32, None),
    ('classifier_l0', 'classifier.0', 'classifier.1', 322, 256, 16),
    ('classifier_l1', 'classifier.4', 'classifier.5', 256, 128, 16),
    ('classifier_l2', 'classifier.8', 'classifier.9', 128, 64, None),
    ('classifier_l3', 'classifier.12', None, 64, 4, None),
]

_STORAGE_DTYPES = {
    'ByteStorage': np.uint8,
    'CharStorage': np.int8,
    'ShortStorage': np.int16,
    'IntStorage': np.int32,
    'LongStorage': np.int64,
    'HalfStorage': np.float16,
    'FloatStorage': np.float32,
    'DoubleStorage': np.float64,
    'BoolStorage': np.bool_,
}


class StorageType(object):
    def __init__(self, storage_name):
        self.storage_name = storage_name
        self.dtype = _STORAGE_DTYPES.get(storage_name)
        if self.dtype is None:
            raise pickle.UnpicklingError('unsupported torch storage type: %s' % storage_name)


class StorageRef(object):
    def __init__(self, storage_type, key, location, size):
        self.storage_type = storage_type
        self.key = str(key)
        self.location = location
        self.size = int(size)


class TensorRef(object):
    def __init__(self, storage, storage_offset, size, stride):
        self.storage = storage
        self.storage_offset = int(storage_offset)
        self.size = tuple(int(x) for x in size)
        self.stride = tuple(int(x) for x in stride)


class TorchZipUnpickler(pickle.Unpickler):
    def persistent_load(self, pid):
        if not isinstance(pid, tuple) or len(pid) < 5 or pid[0] != 'storage':
            raise pickle.UnpicklingError('unsupported persistent id: %r' % (pid,))
        _, storage_type, key, location, size = pid[:5]
        return StorageRef(storage_type, key, location, size)

    def find_class(self, module, name):
        if module == 'torch._utils' and name in ('_rebuild_tensor', '_rebuild_tensor_v2'):
            return _rebuild_tensor
        if module == 'torch._utils' and name == '_rebuild_parameter':
            return _rebuild_parameter
        if module == 'torch' and name.endswith('Storage'):
            return StorageType(name)
        if module == 'collections' and name == 'OrderedDict':
            return OrderedDict
        return super(TorchZipUnpickler, self).find_class(module, name)


def _rebuild_tensor(storage, storage_offset, size, stride, *unused):
    return TensorRef(storage, storage_offset, size, stride)


def _rebuild_parameter(data, requires_grad, backward_hooks):
    return data


def import_torch():
    try:
        import torch
    except Exception as exc:
        raise RuntimeError('PyTorch import failed: %s' % exc)
    return torch


def to_numpy(value):
    if isinstance(value, np.ndarray):
        return value
    if isinstance(value, np.generic):
        return np.asarray(value)
    if hasattr(value, 'detach'):
        return value.detach().cpu().numpy()
    if hasattr(value, 'cpu') and hasattr(value.cpu(), 'numpy'):
        return value.cpu().numpy()
    return np.asarray(value)


def normalize_state_dict(ckpt):
    if isinstance(ckpt, dict):
        for key in ('model_state_dict', 'state_dict', 'model'):
            value = ckpt.get(key)
            if isinstance(value, dict):
                ckpt = value
                break

    if not isinstance(ckpt, dict):
        raise SystemExit('checkpoint does not contain a state_dict-like object')

    state = {}
    for key, value in ckpt.items():
        clean_key = key[7:] if key.startswith('module.') else key
        state[clean_key] = to_numpy(value)
    return state


def load_state_dict_torch(checkpoint_path):
    torch = import_torch()
    ckpt = torch.load(str(checkpoint_path), map_location='cpu')
    return normalize_state_dict(ckpt)


def _zip_prefix(names):
    for name in names:
        if name.endswith('/data.pkl'):
            return name[:-len('data.pkl')]
    raise SystemExit('checkpoint zip does not contain data.pkl')


def _materialize_tensor(zip_file, prefix, tensor_ref, storage_cache):
    storage = tensor_ref.storage
    dtype = storage.storage_type.dtype
    itemsize = np.dtype(dtype).itemsize
    if storage.key not in storage_cache:
        raw = zip_file.read(prefix + 'data/' + storage.key)
        expected_bytes = storage.size * itemsize
        if len(raw) < expected_bytes:
            raise SystemExit('storage %s too small: %d bytes, expected at least %d' % (storage.key, len(raw), expected_bytes))
        storage_cache[storage.key] = np.frombuffer(raw[:expected_bytes], dtype=dtype)

    base = storage_cache[storage.key]
    if not tensor_ref.size:
        return np.asarray(base[tensor_ref.storage_offset]).copy()

    byte_strides = tuple(stride * itemsize for stride in tensor_ref.stride)
    view = np.lib.stride_tricks.as_strided(
        base[tensor_ref.storage_offset:],
        shape=tensor_ref.size,
        strides=byte_strides,
    )
    return np.asarray(view).copy()


def _materialize(obj, zip_file, prefix, storage_cache):
    if isinstance(obj, TensorRef):
        return _materialize_tensor(zip_file, prefix, obj, storage_cache)
    if isinstance(obj, OrderedDict):
        return OrderedDict((key, _materialize(value, zip_file, prefix, storage_cache)) for key, value in obj.items())
    if isinstance(obj, dict):
        return {key: _materialize(value, zip_file, prefix, storage_cache) for key, value in obj.items()}
    if isinstance(obj, list):
        return [_materialize(value, zip_file, prefix, storage_cache) for value in obj]
    if isinstance(obj, tuple):
        return tuple(_materialize(value, zip_file, prefix, storage_cache) for value in obj)
    return obj


def load_state_dict_torchzip(checkpoint_path):
    with zipfile.ZipFile(checkpoint_path) as zip_file:
        names = zip_file.namelist()
        prefix = _zip_prefix(names)
        payload = zip_file.read(prefix + 'data.pkl')
        unpickler = TorchZipUnpickler(io.BytesIO(payload))
        ckpt = unpickler.load()
        ckpt = _materialize(ckpt, zip_file, prefix, {})
    return normalize_state_dict(ckpt)


def load_state_dict(checkpoint_path, loader):
    if loader == 'torch':
        return load_state_dict_torch(checkpoint_path), 'torch'
    if loader == 'torchzip':
        return load_state_dict_torchzip(checkpoint_path), 'torchzip'

    try:
        return load_state_dict_torch(checkpoint_path), 'torch'
    except Exception as exc:
        print('torch checkpoint loader unavailable, falling back to torchzip: %s' % exc, file=sys.stderr)
        return load_state_dict_torchzip(checkpoint_path), 'torchzip'


def require_key(state, key):
    if key not in state:
        raise SystemExit('checkpoint missing key: %s' % key)
    return state[key]


def fold_linear_bn(state, linear_prefix, bn_prefix):
    weight = require_key(state, linear_prefix + '.weight').astype(np.float32)
    bias_key = linear_prefix + '.bias'
    if bias_key in state:
        bias = state[bias_key].astype(np.float32)
    else:
        bias = np.zeros((weight.shape[0],), dtype=np.float32)

    if bn_prefix is None:
        return weight, bias

    gamma = require_key(state, bn_prefix + '.weight').astype(np.float32)
    beta = require_key(state, bn_prefix + '.bias').astype(np.float32)
    running_mean = require_key(state, bn_prefix + '.running_mean').astype(np.float32)
    running_var = require_key(state, bn_prefix + '.running_var').astype(np.float32)
    eps_value = state.get(bn_prefix + '.eps', None)
    eps = float(eps_value) if eps_value is not None else 1.0e-5

    scale = gamma / np.sqrt(running_var + eps)
    folded_weight = weight * scale.reshape((-1, 1))
    folded_bias = (bias - running_mean) * scale + beta
    return folded_weight, folded_bias


def q8_8(value, scale):
    raw = int(round(float(value) * scale))
    clipped = False
    if raw > 32767:
        raw = 32767
        clipped = True
    elif raw < -32768:
        raw = -32768
        clipped = True
    return raw & 0xFFFF, clipped


def pack_i16(lo, hi):
    return ((hi & 0xFFFF) << 16) | (lo & 0xFFFF)


def pack_linear_q8_8(weight_rows, bias_values, input_dim, output_dim, scale, output_word_start=0, output_words=None):
    if input_dim % 2 != 0 or output_dim % 2 != 0:
        raise SystemExit('current packed Q8.8 layout requires even input/output dims')

    input_words = input_dim // 2
    total_output_words = output_dim // 2
    if output_words is None:
        output_words = total_output_words

    words = []
    clipped = 0
    for local_out_word in range(output_words):
        global_out_word = output_word_start + local_out_word
        out0 = global_out_word * 2
        out1 = out0 + 1
        if out1 >= output_dim:
            raise SystemExit('output chunk exceeds layer output dim')

        for in_word in range(input_words):
            in0 = in_word * 2
            in1 = in0 + 1
            w00, c0 = q8_8(weight_rows[out0][in0], scale)
            w01, c1 = q8_8(weight_rows[out0][in1], scale)
            w10, c2 = q8_8(weight_rows[out1][in0], scale)
            w11, c3 = q8_8(weight_rows[out1][in1], scale)
            words.append(pack_i16(w00, w01))
            words.append(pack_i16(w10, w11))
            clipped += int(c0) + int(c1) + int(c2) + int(c3)

        b0, c0 = q8_8(bias_values[out0], scale)
        b1, c1 = q8_8(bias_values[out1], scale)
        words.append(pack_i16(b0, b1))
        clipped += int(c0) + int(c1)

    return words, clipped


def c_array(name, words):
    lines = []
    lines.append('static const uint32_t %s[%d] = {' % (name, len(words)))
    for i in range(0, len(words), 4):
        chunk = words[i:i + 4]
        lines.append('    ' + ', '.join('0x%08Xu' % word for word in chunk) + (',' if i + 4 < len(words) else ''))
    lines.append('};')
    return '\n'.join(lines)


def export_header(state, out_dir, scale):
    out_dir.mkdir(parents=True, exist_ok=True)
    arrays = []
    manifest = {
        'q_format': 'Q8.8 packed two int16 lanes per uint32 word',
        'scale': scale,
        'layers': [],
    }

    for name, linear_prefix, bn_prefix, input_dim, output_dim, chunk_words in LAYER_SPECS:
        folded_weight, folded_bias = fold_linear_bn(state, linear_prefix, bn_prefix)
        shape = tuple(int(x) for x in folded_weight.shape)
        expected_shape = (output_dim, input_dim)
        if shape != expected_shape:
            raise SystemExit('%s weight shape mismatch: actual %s expected %s' % (name, shape, expected_shape))

        weight_rows = folded_weight.tolist()
        bias_values = folded_bias.tolist()
        input_words = input_dim // 2
        output_words_total = output_dim // 2
        layer_info = {
            'name': name,
            'linear': linear_prefix,
            'batchnorm_folded': bn_prefix,
            'input_dim': input_dim,
            'output_dim': output_dim,
            'input_words': input_words,
            'output_words': output_words_total,
            'chunks': [],
        }

        if chunk_words is None:
            words, clipped = pack_linear_q8_8(weight_rows, bias_values, input_dim, output_dim, scale)
            array_name = 'g_tpu_param_%s' % name
            arrays.append(c_array(array_name, words))
            layer_info['chunks'].append({'array': array_name, 'output_word_start': 0, 'output_words': output_words_total, 'param_words': len(words), 'clipped_values': clipped})
        else:
            chunk_count = int(math.ceil(float(output_words_total) / float(chunk_words)))
            for chunk in range(chunk_count):
                start = chunk * chunk_words
                words_this = min(chunk_words, output_words_total - start)
                words, clipped = pack_linear_q8_8(weight_rows, bias_values, input_dim, output_dim, scale, start, words_this)
                array_name = 'g_tpu_param_%s_chunk%d' % (name, chunk)
                arrays.append(c_array(array_name, words))
                layer_info['chunks'].append({'array': array_name, 'output_word_start': start, 'output_words': words_this, 'param_words': len(words), 'clipped_values': clipped})

        manifest['layers'].append(layer_info)

    header = []
    header.append('/* Auto-generated by export_breath_linear_q8_8_params.py. */')
    header.append('#ifndef BREATH_TPU_PARAMS_Q8_8_H')
    header.append('#define BREATH_TPU_PARAMS_Q8_8_H')
    header.append('')
    header.append('#include <stdint.h>')
    header.append('')
    header.extend(arrays)
    header.append('')
    header.append('#endif')
    header.append('')

    header_path = out_dir / 'breath_tpu_params_q8_8.h'
    manifest_path = out_dir / 'breath_tpu_params_q8_8_manifest.json'
    header_path.write_text('\n\n'.join(header), encoding='ascii')
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='ascii')
    return header_path, manifest_path, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, default=DEFAULT_CHECKPOINT)
    parser.add_argument('--out-dir', type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument('--scale', type=float, default=256.0, help='float-to-Q8.8 scale; default 256')
    parser.add_argument('--loader', choices=('auto', 'torch', 'torchzip'), default='auto', help='checkpoint loader; auto falls back to torchzip')
    args = parser.parse_args()

    state, loader_used = load_state_dict(args.checkpoint, args.loader)
    header_path, manifest_path, manifest = export_header(state, args.out_dir, args.scale)

    print('loader  :', loader_used)
    print('exported:', header_path)
    print('manifest:', manifest_path)
    for layer in manifest['layers']:
        total_words = sum(chunk['param_words'] for chunk in layer['chunks'])
        clipped = sum(chunk['clipped_values'] for chunk in layer['chunks'])
        print('%-16s chunks=%d param_words=%d clipped_values=%d' % (layer['name'], len(layer['chunks']), total_words, clipped))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
