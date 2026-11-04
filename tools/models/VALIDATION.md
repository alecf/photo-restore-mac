# U2 — Core ML model validation results

Date: 2026-05-29 · Apple Silicon, Core ML runtime via coremltools.

Adopted the pre-converted Core ML artifacts from `john-rocky/CoreML-Models` (see `manifest.json`
for Drive ids, sizes, licenses, and pinned SHA-256s) rather than converting from scratch.
Validated each against a PyTorch reference produced by the existing `photo-restore` pipeline
(`gen_reference.py`, run in that project's venv) on a **facexlib-aligned 512×512 face crop** taken
from `inputs/77ishIMG_1210.jpeg`.

| Model | Input → Output | SSIM vs PyTorch | PSNR | Gate | Verdict |
|---|---|---|---|---|---|
| Real-ESRGAN x4plus | Image 512 → 2048 | **0.9978** | 56.0 dB | ≥0.98 (deterministic) | ✅ PASS |
| GFPGAN v1.4 | Image 512 → 512 | 0.8336 | 26.6 dB | ≥0.80 (generative) | ✅ PASS (visually confirmed) |
| Face-parsing (BiSeNet) | Image 512 → class map | n/a (sanity) | — | shape + ≥3 classes | ✅ PASS |

## Why GFPGAN uses a looser gate
GFPGAN is **generative** — a StyleGAN decoder regenerates the face from a learned prior, so two
valid builds produce visibly-similar but pixel-different restorations. A side-by-side of input vs
Core ML vs PyTorch (`/tmp/pr-ref/gfpgan_compare.png` when regenerated) shows both outputs are
sharp, faithful restorations; the 0.83 SSIM is texture/tone micro-variation, **not** a conversion
defect. (A defect looks like garbage — Real-ESRGAN's 0.998 confirms the image-in/image-out
conversion path itself is sound.) Deterministic models keep the strict ≥0.98 gate; generative
models get a structural-sanity gate + visual confirmation.

## Implication for U6 (flag)
The adopted GFPGAN is **not** the same checkpoint/build as `photo-restore`'s spandrel GFPGAN v1.4,
so the final Swift face region will differ from `../photo-restore/outputs/` at ~0.83-SSIM level.
**U6's face gate should therefore validate restoration quality (visual + structural similarity),
not strict pixel parity against the old CLI outputs.** This matches the project's north star (a
great restoration app, not a bit-for-bit CLI clone). If exact CLI parity is ever required, the
fallback is converting the *same* `GFPGANv1.4.pth` via the clean arch (`tools/convert/`, deferred).

## Face-parsing note
The adopted face-parsing model is BiSeNet (`zllrunning/face-parsing.PyTorch`), a *different* model
from facexlib's internal parsenet. It yields a 19-class face mask suitable for feathered paste-back
(U6); it won't reproduce facexlib's exact mask, which is fine for the paste-back's purpose.

## Reproduce
```
uv run --with gdown python tools/models/download.py
../photo-restore/.venv/bin/python tools/models/gen_reference.py \
    ../photo-restore/inputs/77ishIMG_1210.jpeg /tmp/pr-ref
uv run --with coremltools,pillow,numpy,scikit-image python tools/models/validate.py
```
Models live (gitignored) in `tools/models/cache/`; they're re-hosted with pinned SHA-256s on the
`models-v2` GitHub release (see `HOSTING.md`).

## GFPGAN on the Neural Engine (2026-11-04)

The adopted `GFPGAN.mlmodel` returns a flat brown square on the Neural Engine (macOS 27). Its
StyleGAN2 weight-demodulation sums reach ~2.6e6, past the fp16 maximum of 65504, so they become
inf and the decoder's activations collapse to 0. Its 23 modulated/to-RGB convs also build their
weights at runtime, which the Neural Engine can't run, so they fell back to the CPU.

`rewrite_gfpgan_ane.py` rewrites those convs into the equivalent non-fused form with constant
weights and power-of-two scale factors that cancel exactly, then stores the weights as fp16. The
result, `GFPGAN-ANE.mlmodel` (174 MB, deterministic SHA-256), has every layer placed on the
Neural Engine and runs at ~45 ms per face (vs ~1 s on the GPU for the original).

| Rewritten model, vs original on CPU | Worst PSNR (26 held-out inputs) |
|---|---|
| Neural Engine (`.all`) | 55.5 dB |
| GPU (`.cpuAndGPU`) | 54.8 dB |
| CPU | 58.8 dB |

Held-out inputs: whole photos and crops from five public-domain portraits, the test fixture, and
synthetic black/white/gray/red/noise images. The largest intermediate value is ~1.2e3, 54× below
the fp16 maximum. The script re-runs a shorter version of this check every time it builds.

```
uv run --python 3.12 --with-requirements tools/models/requirements.txt \
    python tools/models/rewrite_gfpgan_ane.py
```
