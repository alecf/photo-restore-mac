#!/usr/bin/env python3
"""Rewrite the GFPGAN Core ML model so it runs on the Apple Neural Engine.

The adopted GFPGAN.mlmodel (john-rocky/CoreML-Models) has two problems on the Neural Engine,
both in its StyleGAN2 decoder's 15 modulated convs and 8 to-RGB convs:

1. fp16 overflow. Each modulated conv "demodulates" its weights:
       demod = rsqrt( sum_{i,kh,kw} (W * s)^2 + eps )
   That sum reaches ~2.6e6 on real faces. The Neural Engine computes in fp16 (max 65504), so
   it becomes inf, demod becomes 0, and the decoder outputs a flat brown square.
2. Runtime conv weights. The model builds each conv's weights per face (W * s * demod). The
   Neural Engine only runs convs with constant weights, so these 23 fell back to the CPU.

The fix rewrites each one into StyleGAN2's equivalent "non-fused" form, where every conv has
constant weights:
       y = conv(x * s, W) * demod,     demod = rsqrt( W2 @ s^2 + eps ),   W2[o,i] = sum_k W[o,i]^2
with power-of-two factors that cancel exactly but keep every intermediate value in fp16 range:
       y = conv(x * (c*s), W * k/c) * rsqrt( k^2 * (W2 @ s^2) + k^2 * eps )
k is chosen per layer from calibration faces (tools/models/calibration/) so the scaled sum stays
near TARGET; c is a fixed 1/8 that keeps x*s small.

Result: every layer is placed on the Neural Engine, ~20x faster than the GPU path, and the
output matches the original model on CPU at >50 dB PSNR. Weights are stored as fp16 (half the
download; the Neural Engine computes in fp16 anyway), which costs no measurable accuracy.

Run (needs the original model, from download.py):
    uv run --python 3.12 --with coremltools --with numpy --with pillow \
        python tools/models/rewrite_gfpgan_ane.py

Writes tools/models/cache/GFPGAN-ANE.mlmodel, then verifies it on the Neural Engine against
the original on the CPU. The output is deterministic: the same input gives the same bytes.
"""
from __future__ import annotations

import argparse
import copy
import glob
import hashlib
import math
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
from coremltools.proto import FeatureTypes_pb2 as ft
from coremltools.proto import NeuralNetwork_pb2 as nnp
from PIL import Image

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
CALIBRATION = sorted(glob.glob(str(HERE / "calibration" / "*.jpg")))
FIXTURE = REPO / "RestoreEngine/Tests/RestoreEngineTests/Fixtures/input_sample.jpg"

TARGET = 256.0     # aim for scaled demod sums near this (fp16 max is 65504)
C = 1.0 / 8        # scale on x*s; undone in the conv weights
FP16_MAX = 65504.0
MIN_PSNR_DB = 45.0


def load_rgb(path) -> Image.Image:
    return Image.open(path).convert("RGB").resize((512, 512), Image.BICUBIC)


def with_outputs(spec, names):
    """A copy of `spec` that also exposes the named intermediate blobs as outputs."""
    s = copy.deepcopy(spec)
    for n in names:
        o = s.description.output.add()
        o.name = n
        o.type.multiArrayType.dataType = ft.ArrayFeatureType.FLOAT32
    return s


def calibrate(spec, layers):
    """Max of each demod sum (the reduceSum outputs) over the calibration faces, in fp32."""
    sums = [l.output[0] for l in layers if l.WhichOneof("layer") == "reduceSum"]
    model = ct.models.MLModel(with_outputs(spec, sums), compute_units=ct.ComputeUnit.CPU_ONLY)
    mx = dict.fromkeys(sums, 0.0)
    for path in CALIBRATION:
        out = model.predict({"x_1": load_rgb(path)})
        for n in sums:
            mx[n] = max(mx[n], float(np.asarray(out[n]).max()))
    return mx


def new_layer(name, kind, inputs):
    layer = nnp.NeuralNetworkLayer(name=name, input=inputs, output=[name])
    getattr(layer, kind).SetInParent()
    return layer


def rewrite(spec):
    layers = list(spec.neuralNetwork.layers)
    by_out = {l.output[0]: l for l in layers}
    sum_max = calibrate(spec, layers)

    def const(name):
        l = by_out[name]
        assert l.WhichOneof("layer") == "loadConstantND", l.name
        return np.array(l.loadConstantND.data.floatValue, np.float32).reshape(list(l.loadConstantND.shape))

    out_layers = []
    for l in layers:
        # Runtime-weight convs are the ones with two inputs: (activations, weights).
        if not (l.WhichOneof("layer") == "convolution" and len(l.input) == 2):
            out_layers.append(l)
            continue
        x, weight = l.input
        flat = by_out[by_out[weight].input[0]]            # reshape -> (O,I,kh,kw) multiply
        first = by_out[flat.input[0]]
        if first.WhichOneof("layer") == "multiplyBroadcastable":
            # Modulated conv: flat = (W * s) * reshape(rsqrt(sum + eps)).
            modulate = first
            add_eps = by_out[by_out[by_out[flat.input[1]].input[0]].input[0]]
            demod_sum = add_eps.input[0]
        else:
            # to-RGB conv: flat = W * s, no demodulation.
            modulate, demod_sum = flat, None
        W = const(modulate.input[0])[0]                   # (O, I, kh, kw)
        style = by_out[modulate.input[1]].input[0]        # (1, I) style vector
        O, I = W.shape[:2]
        k = 1.0
        if demod_sum:
            k = 2.0 ** -max(0, math.ceil(math.log2(math.sqrt(sum_max[demod_sum] / TARGET))))

        p = l.name
        scaled = new_layer(p + "_sc", "multiply", [style])
        scaled.multiply.alpha = C
        s4 = new_layer(p + "_s4", "reshapeStatic", [p + "_sc"])
        s4.reshapeStatic.targetShape.extend([1, I, 1, 1])
        xs = new_layer(p + "_xs", "multiplyBroadcastable", [x, p + "_s4"])
        conv = copy.deepcopy(l)
        del conv.input[:]
        conv.input.append(p + "_xs")
        conv.convolution.hasBias = False
        conv.convolution.weights.floatValue.extend((W * (k / C)).ravel().tolist())
        out_layers += [scaled, s4, xs, conv]

        if demod_sum:
            final = l.output[0]
            conv.output[0] = p + "_raw"
            sq = new_layer(p + "_sq", "unary", [style])
            sq.unary.type = nnp.UnaryFunctionLayerParams.POWER
            sq.unary.alpha = 2.0
            sq.unary.scale = k                            # (k*s)^2
            dsum = new_layer(p + "_dsum", "innerProduct", [p + "_sq"])
            dsum.innerProduct.inputChannels = I
            dsum.innerProduct.outputChannels = O
            dsum.innerProduct.hasBias = False
            dsum.innerProduct.weights.floatValue.extend((W.astype(np.float64) ** 2).sum(axis=(2, 3)).astype(np.float32).ravel().tolist())
            eps = new_layer(p + "_eps", "add", [p + "_dsum"])
            eps.add.alpha = 1e-8 * k * k
            rs = new_layer(p + "_d", "unary", [p + "_eps"])
            rs.unary.type = nnp.UnaryFunctionLayerParams.RSQRT
            rs.unary.alpha = 1.0
            d4 = new_layer(p + "_d4", "reshapeStatic", [p + "_d"])
            d4.reshapeStatic.targetShape.extend([1, O, 1, 1])
            mul = nnp.NeuralNetworkLayer(name=p + "_demod", input=[p + "_raw", p + "_d4"], output=[final])
            mul.multiplyBroadcastable.SetInParent()
            out_layers += [sq, dsum, eps, rs, d4, mul]
            print(f"  {p:22s} {O:3d}x{I:3d}x{W.shape[2]}x{W.shape[3]}  demod sum max {sum_max[demod_sum]:9.3g}  k=1/{int(1 / k)}")
        else:
            print(f"  {p:22s} {O:3d}x{I:3d}x{W.shape[2]}x{W.shape[3]}  to-RGB")

    # Drop the old runtime-weight chains, which nothing reads any more.
    keep = {o.name for o in spec.description.output}
    while True:
        used = {i for l in out_layers for i in l.input} | keep
        pruned = [l for l in out_layers if any(o in used for o in l.output)]
        if len(pruned) == len(out_layers):
            break
        out_layers = pruned
    del spec.neuralNetwork.layers[:]
    spec.neuralNetwork.layers.extend(out_layers)
    spec.description.metadata.shortDescription += (
        " Rewritten for the Apple Neural Engine (non-fused modulated convs, fp16-safe demodulation)"
        " by photo-restore-mac tools/models/rewrite_gfpgan_ane.py."
    )
    print(f"rewrote convs: {len(layers)} -> {len(out_layers)} layers")
    return spec


def verification_inputs():
    """Calibration faces, the test fixture, and synthetic inputs that push the style vectors."""
    rng = np.random.default_rng(0)
    synthetic = {
        "black": np.zeros((512, 512, 3)), "white": np.full((512, 512, 3), 255),
        "gray": np.full((512, 512, 3), 128), "red": np.tile([255, 0, 0], (512, 512, 1)),
        "noise": rng.integers(0, 256, (512, 512, 3)),
    }
    items = [(Path(p).stem, load_rgb(p)) for p in CALIBRATION]
    if FIXTURE.exists():
        items.append(("fixture", load_rgb(FIXTURE)))
    items += [(k, Image.fromarray(v.astype(np.uint8))) for k, v in synthetic.items()]
    return items


def verify(src_path, out_path):
    """The rewritten model on the Neural Engine must match the original on the CPU, and every
    watched intermediate value must stay far below the fp16 max."""
    ref = ct.models.MLModel(str(src_path), compute_units=ct.ComputeUnit.CPU_ONLY)
    ane = ct.models.MLModel(str(out_path), compute_units=ct.ComputeUnit.ALL)
    spec = ane.get_spec()
    watched = [l.output[0] for l in spec.neuralNetwork.layers if l.output[0].endswith(("_raw", "_eps", "_xs"))]
    probe = ct.models.MLModel(with_outputs(spec, watched), compute_units=ct.ComputeUnit.CPU_ONLY)

    worst_psnr, peak = math.inf, 0.0
    for name, img in verification_inputs():
        a = np.asarray(ref.predict({"x_1": img})["activation_out"].convert("RGB"), np.float64)
        b = np.asarray(ane.predict({"x_1": img})["activation_out"].convert("RGB"), np.float64)
        mse = np.mean((a - b) ** 2)
        psnr = math.inf if mse == 0 else 10 * math.log10(255 ** 2 / mse)
        worst_psnr = min(worst_psnr, psnr)
        r = probe.predict({"x_1": img})
        peak = max(peak, max(float(np.abs(np.asarray(r[n])).max()) for n in watched))
        print(f"  {name:20s} PSNR vs original-on-CPU {psnr:5.1f} dB")
    print(f"worst PSNR {worst_psnr:.1f} dB (gate {MIN_PSNR_DB}); largest intermediate {peak:.4g} "
          f"= fp16 headroom x{FP16_MAX / peak:.0f}")
    return worst_psnr >= MIN_PSNR_DB and peak < FP16_MAX / 8


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", default=str(HERE / "cache" / "GFPGAN.mlmodel"))
    ap.add_argument("--out", default=str(HERE / "cache" / "GFPGAN-ANE.mlmodel"))
    ap.add_argument("--fp32", action="store_true", help="keep fp32 weights (twice the file size)")
    ap.add_argument("--no-verify", action="store_true")
    args = ap.parse_args()
    if not CALIBRATION:
        print("no calibration images in tools/models/calibration/", file=sys.stderr)
        return 1

    spec = rewrite(ct.utils.load_spec(args.src))
    if not args.fp32:
        import contextlib, io
        from coremltools.models.neural_network import quantization_utils
        with contextlib.redirect_stdout(io.StringIO()):  # it prints a line per layer
            half = quantization_utils.quantize_weights(ct.models.MLModel(spec, skip_model_load=True), nbits=16)
        spec = half.get_spec()
    # Not ct.utils.save_spec: protobuf map order (the metadata) varies between runs unless
    # serialization is deterministic, and the pinned SHA-256 must be reproducible.
    data = spec.SerializeToString(deterministic=True)
    Path(args.out).write_bytes(data)
    print(f"saved {args.out}  size={len(data)}  sha256={hashlib.sha256(data).hexdigest()}")

    if not args.no_verify and not verify(args.src, args.out):
        print("VERIFICATION FAILED", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
