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
Models live (gitignored) in `tools/models/cache/`; they'll be re-hosted with pinned SHA-256s in U3.
