"""Export the included MNISTCNN3 checkpoint as INT16 weights / activations.

The activation codes use a calibrated, layer-specific range stored in a uint16
container. Limits are selected from the INT32 worst-case MAC bound, with half
the accumulator range reserved for bias and rounding headroom.
"""
import json
import os
import struct
import sys
import time

import numpy as np
import torch
import torch.nn.functional as F

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from cnn3_model import MNISTCNN3

DATA = os.path.join(ROOT, "data", "MNIST", "raw")
CKPT = os.path.join(HERE, "mnist_cnn3_fp32.pth")
OUT = os.path.join(ROOT, "weights", "int16")
TB_DATA = os.path.join(ROOT, "tb", "data")
MAX_ACC = (1 << 31) - 1
torch.set_num_threads(1)


def read_idx(images_path, labels_path=None):
    with open(images_path, "rb") as f:
        magic, count, rows, cols = struct.unpack(">IIII", f.read(16))
        if magic != 2051:
            raise ValueError(f"Unexpected MNIST image magic {magic}: {images_path}")
        images = np.frombuffer(f.read(), dtype=np.uint8).reshape(count, rows, cols).copy()
    if labels_path is None:
        return images
    with open(labels_path, "rb") as f:
        magic, n = struct.unpack(">II", f.read(8))
        if magic != 2049 or n != len(images):
            raise ValueError(f"Unexpected MNIST label header: {labels_path}")
        labels = np.frombuffer(f.read(), dtype=np.uint8).copy()
    return images, labels


train_x = read_idx(os.path.join(DATA, "train-images-idx3-ubyte"))
test_x, test_y = read_idx(os.path.join(DATA, "t10k-images-idx3-ubyte"),
                          os.path.join(DATA, "t10k-labels-idx1-ubyte"))
EVAL_COUNT = min(int(os.environ.get("MNIST_EVAL_COUNT", str(len(test_y)))), len(test_y))
test_x, test_y = test_x[:EVAL_COUNT], test_y[:EVAL_COUNT]
model = MNISTCNN3().eval()
checkpoint = torch.load(CKPT, map_location="cpu", weights_only=True)
model.load_state_dict(checkpoint["model_state_dict"])

# Preserve more INT16 activation range for smaller fan-ins while bounding every
# worst-case signed-weight MAC sum to half the signed INT32 range.
fanins = {"input": 9, "conv1": 72, "conv2": 144, "conv3": 32, "fc1": 16}
act_limit = {name: MAX_ACC // (2 * 32768 * fanin) for name, fanin in fanins.items()}

# Calibrate float activations on the first 1,000 training examples.
cal = torch.from_numpy(train_x[:1000]).float().unsqueeze(1) / 255.0
with torch.no_grad():
    a1 = F.relu(model.conv1(cal))
    p1 = F.max_pool2d(a1, 2, 2)
    a2 = F.relu(model.conv2(p1))
    p2 = F.max_pool2d(a2, 2, 2)
    a3 = F.relu(model.conv3(p2))
    p3 = F.max_pool2d(a3, 2, 2)
    h1 = F.relu(model.fc1(p3.flatten(1)))
    maxima = {"conv1": a1.max().item(), "conv2": a2.max().item(),
              "conv3": a3.max().item(), "fc1": h1.max().item()}
    pool_maxima = {"conv1": p1.max().item(), "conv2": p2.max().item(),
                   "conv3": p3.max().item()}

# The source tensor is ToTensor() normalized to [0,1], while IDX pixels are [0,255].
activation_scale = {"input": 1.0 / act_limit["input"]}
for name in ("conv1", "conv2", "conv3", "fc1"):
    qmax = act_limit[name]
    activation_scale[name] = (maxima[name] / qmax) if maxima[name] else 1.0
layers = {"conv1": model.conv1, "conv2": model.conv2, "conv3": model.conv3,
          "fc1": model.fc1, "fc2": model.fc2}
quantized = {}
metadata = {
    "scheme": "symmetric signed INT16 weights; unsigned calibrated INT16 activation codes",
    "activation_calibration_images": 1000,
    "activation_limits": act_limit,
    "activation_scales_float_per_integer_code": activation_scale,
    "weight_limit": 32767,
    "accumulator": "signed INT32; worst-case MAC bound reserves half range for bias",
    "layers": {},
}

for name, layer in layers.items():
    wf = layer.weight.detach().cpu().numpy()
    ws = float(np.max(np.abs(wf)) / 32767.0) or 1.0
    qw = np.clip(np.rint(wf / ws), -32767, 32767).astype(np.int16)
    src = "input" if name == "conv1" else {
        "conv2": "conv1", "conv3": "conv2", "fc1": "conv3", "fc2": "fc1"
    }[name]
    dst = None if name == "fc2" else name
    si = activation_scale[src]
    so = 1.0 if dst is None else activation_scale[dst]
    bias = np.rint(layer.bias.detach().cpu().numpy() / (si * ws)).astype(np.int64)
    if np.any(bias < -(1 << 31)) or np.any(bias > MAX_ACC):
        raise OverflowError(f"INT32 bias overflow in {name}")
    multiplier = int(np.rint((si * ws / so) * (1 << 31)))
    quantized[name] = (qw, bias.astype(np.int32), multiplier)
    np.savetxt(os.path.join(OUT, name + "_weight.mem"), qw.reshape(-1).view(np.uint16), fmt="%04x")
    np.savetxt(os.path.join(OUT, name + "_bias.mem"), bias & 0xffffffff, fmt="%08x")
    if name != "fc2":
        np.savetxt(os.path.join(OUT, name + "_multiplier.mem"), [multiplier], fmt="%016x")
    metadata["layers"][name] = {
        "weight_shape": list(qw.shape), "weight_scale": ws,
        "input_scale": si, "output_scale": so,
        "requant_multiplier_q31": multiplier,
        "bias_scale": si * ws,
        "max_abs_quantized_bias": int(np.max(np.abs(bias))),
        "theoretical_mac_bound_without_bias": int(act_limit[src] * 32768 * fanins[src]),
    }

with open(os.path.join(OUT, "quantization_metadata.json"), "w", encoding="utf-8") as f:
    json.dump(metadata, f, indent=2)


def round_q31(acc, mult):
    product = acc.astype(np.int64) * np.int64(mult)
    den = 1 << 31
    lo = np.floor_divide(product, den)
    rem = np.mod(product, den)
    half = den // 2
    return lo + ((rem > half) | ((rem == half) & ((lo & 1) != 0))).astype(np.int64)


observed_max = {name: 0 for name in layers}


def checked_int32(acc, name):
    observed_max[name] = max(observed_max[name], int(np.max(np.abs(acc))))
    if np.any(acc < -(1 << 31)) or np.any(acc > MAX_ACC):
        raise OverflowError(f"INT32 accumulator overflow in {name}: observed max abs {observed_max[name]}")
    return acc.astype(np.int32)


def conv(x, name, activate=True):
    w, b, mult = quantized[name]
    n, ci, h, width = x.shape
    co, _, kh, kw = w.shape
    oh, ow = h - kh + 1, width - kw + 1
    out = np.empty((n, co, oh, ow), dtype=np.uint16 if activate else np.int32)
    wm = w.reshape(co, -1).astype(np.int64)
    for yy in range(oh):
        for xx in range(ow):
            patch = x[:, :, yy:yy+kh, xx:xx+kw].reshape(n, -1).astype(np.int64)
            acc = checked_int32(patch @ wm.T + b.astype(np.int64), name)
            if activate:
                z = np.clip(round_q31(acc, mult), 0, act_limit[name]).astype(np.uint16)
                out[:, :, yy, xx] = z
            else:
                out[:, :, yy, xx] = acc
    return out


def fc(x, name, activate=True):
    w, b, mult = quantized[name]
    acc = checked_int32(x.astype(np.int64) @ w.astype(np.int64).T + b.astype(np.int64), name)
    if not activate:
        return acc
    return np.clip(round_q31(acc, mult), 0, act_limit[name]).astype(np.uint16)


def infer_batch(images):
    q_input = np.rint(images.astype(np.float64) * (act_limit["input"] / 255.0)).astype(np.uint16)
    x = conv(q_input[:, None, :, :], "conv1")
    x = x[:, :, :26, :26].reshape(len(x), 8, 13, 2, 13, 2).max(axis=(3, 5))
    x = conv(x, "conv2")
    x = x[:, :, :10, :10].reshape(len(x), 16, 5, 2, 5, 2).max(axis=(3, 5))
    x = conv(x, "conv3")
    x = x[:, :, :2, :2].reshape(len(x), 32, 1, 2, 1, 2).max(axis=(3, 5))
    x = fc(x.reshape(len(x), 32), "fc1")
    scores = fc(x, "fc2", activate=False)
    return scores.argmax(axis=1).astype(np.uint8)


os.makedirs(OUT, exist_ok=True)
os.makedirs(TB_DATA, exist_ok=True)
start = time.perf_counter()
predictions = []
for start_i in range(0, len(test_x), 128):
    predictions.extend(infer_batch(test_x[start_i:start_i+128]).tolist())
predictions = np.asarray(predictions, dtype=np.uint8)
int16_correct = int(np.count_nonzero(predictions == test_y))
elapsed = time.perf_counter() - start

# FP32 software baseline from the same trained checkpoint.
fp32_correct = 0
with torch.no_grad():
    for i in range(0, len(test_x), 128):
        batch = torch.from_numpy(test_x[i:i+128]).float().unsqueeze(1) / 255.0
        labels = torch.from_numpy(test_y[i:i+128]).long()
        fp32_correct += int((model(batch).argmax(1) == labels).sum().item())

# Emit the same first 100 test cases consumed by the RTL testbench.
first100 = test_x[:100].astype(np.uint32) * act_limit["input"]
first100 = np.rint(first100 / 255.0).astype(np.uint16)
np.savetxt(os.path.join(TB_DATA, "mnist100_pixels_int16.mem"), first100.reshape(-1), fmt="%04x")
np.savetxt(os.path.join(TB_DATA, "mnist100_expected_int16.mem"), predictions[:100], fmt="%x")
np.savetxt(os.path.join(TB_DATA, "mnist100_labels.mem"), test_y[:100], fmt="%x")

for name in layers:
    metadata["layers"][name]["observed_max_abs_accumulator_test_set"] = observed_max[name]
metadata["fp32_correct"] = fp32_correct
metadata["int16_correct"] = int16_correct
metadata["test_images"] = len(test_y)
metadata["rtl_vectors"] = 100
with open(os.path.join(OUT, "quantization_metadata.json"), "w", encoding="utf-8") as f:
    json.dump(metadata, f, indent=2)

report = {
    "architecture": "MNISTCNN3",
    "checkpoint": os.path.relpath(CKPT, ROOT),
    "fp32": {"correct": fp32_correct, "total": len(test_y),
             "accuracy_percent": 100.0 * fp32_correct / len(test_y)},
    "int16_reference": {"correct": int16_correct, "total": len(test_y),
                         "accuracy_percent": 100.0 * int16_correct / len(test_y),
                         "cpu_ms_per_image": 1000.0 * elapsed / len(test_y)},
    "int16_vs_python_vectors": {"count": 100, "predictions": predictions[:100].astype(int).tolist()},
    "accumulator_observed_max_abs": observed_max,
}
with open(os.path.join(ROOT, "reports", "accuracy_int16.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
print(f"FP32:  {fp32_correct}/{len(test_y)} = {100*fp32_correct/len(test_y):.2f}%")
print(f"INT16: {int16_correct}/{len(test_y)} = {100*int16_correct/len(test_y):.2f}%")
print(f"INT16 reference CPU time: {1000*elapsed/len(test_y):.3f} ms/image")
print("INT32 observed maximum absolute accumulators:", observed_max)
print("Weights:", OUT)
print("Test vectors:", TB_DATA)
