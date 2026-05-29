---
title: "feat: Photo Restore — native macOS app"
type: feat
status: active
date: 2026-05-29
deepened: 2026-05-29
---

# Photo Restore — native macOS app

**Deepened:** 2026-05-29 (interactive: architecture, performance, UX-flows, distribution)

## Context

There's a working Python CLI at `../photo-restore/` that restores old family-photo
scans: luminance-preserving auto-contrast, Real-ESRGAN x4 upscaling, and GFPGAN/CodeFormer
face restoration composited back over the upscaled background. All models run **locally** on
Apple Silicon (PyTorch MPS) — there are no cloud APIs and no API keys.

The goal is a **dirt-simple, polished, shareable macOS app**: open it, drag a folder or image
in, optionally pick an output folder, and watch the photo(s) restore. Confirmed decisions:

- **Pure Swift + Core ML** — fully native, no bundled Python runtime. The v1 models already exist
  as maintained, **pre-converted Core ML artifacts** (adopt + validate against our reference
  outputs, don't convert from scratch); the classical image stages are reimplemented in Swift.
- **Polished, shareable .app** — **non-sandboxed** Developer-ID build, Hardened Runtime,
  notarized + stapled (launches offline on a clean Mac). Models download on first launch.
- **Open source, MIT.** This removes the *legal* concern about CodeFormer's non-commercial
  license — non-commercial OSS use is permitted. CodeFormer is still deferred for v1 on
  **technical** grounds only (see Deferred).
- **Live stage-by-stage preview** — each stage publishes a downsampled intermediate to the UI,
  so the photo visibly improves (contrast → upscale → faces).
- **HEIC/RAW supported** — decoded via macOS ImageIO before the pipeline, so iPhone photos
  "just work" (the Mac app does what the CLI couldn't). Only truly undecodable files are skipped.
- **Conservative strength only (GFPGAN) for v1** — lowest conversion risk; clean seam for balanced.

### Reference pipeline (what we're porting), all in `../photo-restore/src/photo_restore/`
- `pipeline.py` — `restore_image(loaded, config)`: contrast → `_build_background` (upscale + Lanczos) → `faces.restore_onto`. Faces are restored at native res and composited onto the *already-upscaled* background (never pass through SR). `needs_enlargement` gate skips SR when target ≤ source.
- `stages/contrast.py` — luminance auto-levels (`0.299/0.587/0.114`, clip 0.5/99.5 percentile, one shared stretch curve).
- `stages/upscale.py` — Real-ESRGAN x4plus once at native factor; `_load_model` is `@lru_cache`; OOM caught → actionable error.
- `stages/faces.py` — facexlib detect + 5-point align to 512, run model, `_match_color` (YCrCb chroma swap), `_blend` (α 0.8), `_match_grain` (**unseeded**), parse-mask inverse-affine paste-back, size-gate (≤500 src px). `_load_model` `@lru_cache(maxsize=2)`.
- `resolution.py` — pure target math (port 1:1). `imageio.py` — load/save, EXIF + orientation, grayscale detect (channel spread ≤6), output collapsed to mode `L` for grayscale ("never colorize"). `models.py` — weight registry (URL + min_bytes + sha256, currently `sha256=None`).

**Parity reality:** `_match_grain` is unseeded, so reference outputs are non-deterministic in the
grain region. Bit-exact parity is impossible by construction — gate on **SSIM/PSNR with grain
disabled**, then visually review with grain on.

---

## Summary

Build a native SwiftUI Mac app whose restoration engine reimplements the Python pipeline in
Swift, runs the (offline-converted) Core ML models, and exposes a `Sendable` progress stream the
UI renders as a live before/after preview. Ship it as a notarized, non-sandboxed, MIT app that
downloads its models on first launch.

---

## Requirements

- **R1.** Drag-drop a single image or a folder (recursing subfolders); batch-process 100+ images without OOM or UI stalls.
- **R2.** Reproduce the Python pipeline's visual output within parity tolerance (SSIM/PSNR, grain off) for conservative/GFPGAN strength.
- **R3.** Show one before/after image at a time (split-slider wipe) plus a filmstrip of all queued images with status; live stage-by-stage preview for the in-flight image.
- **R4.** Active status + determinate progress (current stage, per-image and overall batch).
- **R5.** Mac-native settings (size, face intensity, advanced) — not a CLI-flag dump; defaults match the CLI.
- **R6.** Ship as a notarized, stapled, non-sandboxed .app that launches on a clean Mac and downloads models on first launch.
- **R7.** Never lose or silently drop user data: no in-place overwrite of originals; nothing the user dropped vanishes without a visible status.
- **R8.** Preserve the engine's invariants: "B&W stays gray," EXIF/orientation carried, "no faces" = success pass-through.

---

## Scope Boundaries

- **Conservative/GFPGAN strength only** for v1.
- **No colorization** (the engine explicitly never colorizes; preserve that).
- Not a general photo editor — restoration only (the existing pipeline's stages).

### Deferred to Follow-Up Work
- **CodeFormer / "balanced" strength.** Deferred on *technical* grounds: its fidelity-weight input
  folds to a constant during Core ML conversion (CodeFormer #252). When revisited: bake a fixed
  fidelity (0.8) or do graph surgery / ONNX-Runtime escape hatch. MIT/open-source means the
  non-commercial license is **no longer a blocker**. The Swift strength enum + settings seam are
  in place from v1.
- **Mac App Store distribution** (would require sandboxing + bookmarks — see Key Technical Decisions).

---

## Key Technical Decisions

- **Inference runtime: Core ML** (`.mlmodelc`), FP16 with FP32/GPU fallback. *Rationale:* native
  Swift `MLModel`, ANE/GPU, nothing extra to sign, cleanest notarization; the inference loop is
  ~50 lines of glue. *Flip trigger:* if a model shows FP16 artifacts, run that net FP32 (parity gate).
- **Reuse pre-converted models; don't build a conversion toolchain for v1.** Maintained Core ML
  artifacts exist for all three v1 models — Real-ESRGAN x4plus and GFPGAN v1.4 and BiSeNet
  face-parsing (`john-rocky/CoreML-Models`; BSD-3 / Apache-2 / MIT). Adopt them and validate against
  `../photo-restore/outputs/`; the from-scratch coremltools conversion (with the documented
  `clamp(x*127.5+127.5)` output wrapper + normalization) is the **fallback** only if a parity gate
  fails. The same author's Medium write-ups document the exact pre/post gotchas. *Note:* `john-rocky`
  artifacts download via Google Drive — we re-host verified copies (SHA-256 pinned) for U3.
- **Runtime alternatives evaluated and rejected for v1** (research 2026-05): **Rust (candle/burn)**
  and **MLX-Swift** have no model loader for these checkpoints → they'd require hand-porting RRDBNet
  and the GFPGAN StyleGAN decoder in their tensor ops (weeks, no fidelity guarantee) — *more* work,
  not less. **ggml / TF-Metal** ruled out (no image-convnet path / needs Python). **ONNX Runtime +
  Core ML EP** (Microsoft Swift SPM package, ~18 MB, still hits ANE/GPU) is viable but adds a
  framework for no v1 benefit — its one real win is **CodeFormer's fidelity-weight input**, which
  ONNX export handles more cleanly than the Core ML tracer (which folds it to a constant). So ONNX-RT
  is the documented seam for the deferred "balanced" strength, not a v1 dependency. The Rust `ort`
  crate (ORT + Core ML EP via C ABI) is the only non-Swift option that isn't a trap, but it offers
  nothing over the Swift package here.
- **Face detection/alignment: Apple Vision**, not a converted RetinaFace. Derive facexlib's 5
  template points (eye centers from pupils, nose, mouth corners from lips), fit a similarity
  transform (Umeyama) to facexlib's fixed 512 template. *Rationale:* avoids shipping a detector,
  ANE-accelerated, notarization-clean. *Flip trigger:* if Vision landmarks don't reproduce the
  template within tolerance on tilted/profile faces (Phase 3 gate), convert RetinaFace.
- **Real-ESRGAN tiling, size chosen by benchmark.** Convert at a fixed input shape; **tile large
  images** (overlap ~1/8 of tile, feathered seams). An early spike measures 512 vs 768 vs 1024
  latency + peak memory on min-spec (8 GB) hardware and locks the largest tile that fits.
  *Rationale:* fixed-512 ≈ 70 tiles/12 MP (~8–10 s SR); 1024 ≈ 20 tiles (1.5–3× faster); ANE
  prefers fixed shapes. **Cap SR input** so output ≤ ~1.5× target (removes 50–90% of tiles on big
  scans), preserving the engine's `needs_enlargement` skip.
- **Concurrency: single serial `InferenceEngine` actor** owning resident `MLModel`s (mirrors the
  Python `lru_cache` — load once per batch, warm up at launch, cache compiled `.mlmodelc`). A
  `BatchCoordinator` actor owns the queue with **backpressure (1–2 images in flight; concurrency 1
  on 8 GB)**, decode-on-demand, `autoreleasepool` per image/tile. *Rationale:* ANE serializes
  anyway; parallelism only inflates memory (100×12 MP eager-decoded ≈ 4.8 GB + a 4× intermediate
  ≈ 768 MB → OOM).
- **Engine has zero SwiftUI/AppKit imports.** It takes a `Sendable Config` in and emits a
  `Sendable` progress-event `AsyncStream` out (`.stageStarted` / `.preview(stage, downsampledFrame)`
  / `.faceRestored(i,n)` / `.completed(result)`). *Rationale:* this single boundary makes live
  preview, cancellation, error isolation, and the ONNX escape hatch all tractable. Previews are
  **always downsampled and coalesced** (≤2–4/sec; progress-fraction, not an image, during tiling).
- **Cancellation** via structured-concurrency `Task` cancellation honored at stage/tile/face
  boundaries (an in-flight `prediction` can't abort mid-call → finest granularity is one tile/face).
- **Per-image error isolation:** each queue item carries a status; a single item's throw never
  propagates to the batch. "No faces" is **success** (pass-through), not an error.
- **Distribution: non-sandboxed Developer ID**, Hardened Runtime, notarized + stapled. *Rationale:*
  a recursive folder-batch tool fights the sandbox (per-path security-scoped bookmarks); non-sandbox
  removes that friction and is standard for direct-download tools. *Tradeoff:* no App Store path
  without later adding sandbox + bookmarks.
- **Model storage: compiled `.mlmodelc` in Application Support** (not Caches — OS purges → surprise
  700 MB re-download), keyed by model version. *Rationale:* loading raw `.mlpackage` recompiles for
  minutes every launch. Download via resumable background `URLSessionDownloadTask` + **SHA-256
  verification** (pin real hashes — registry currently has none). Host on GitHub Releases (2 GB/asset
  limit is fine), R2 fallback.
- **HEIC/RAW via macOS ImageIO** decode layer in front of the engine; explicit "unsupported" badge
  only for files macOS itself can't open. Nothing dropped ever silently disappears.

---

## Architecture

### A. Model artifacts — adopt pre-converted, convert only as fallback
v1 needs no from-scratch conversion. Adopt maintained Core ML artifacts and validate them; keep a
coremltools script (`../photo-restore/tools/convert/`) as the fallback for anything that fails a gate
or needs re-baking (e.g. a different ESRGAN input shape from the U4 benchmark).
- **Real-ESRGAN x4plus** — `john-rocky/CoreML-Models` `.mlmodel` (~67 MB, BSD-3). Re-bake only if the benchmark wants a non-default fixed tile size.
- **GFPGAN v1.4** — `john-rocky/CoreML-Models` `.mlmodel` (~337 MB, Apache-2), fixed 512×512. Watch the output multiarray→image normalization (documented `clamp` wrapper).
- **BiSeNet face-parsing** — `john-rocky/CoreML-Models` `.mlmodel` (~53 MB, MIT), 512×512 → 19-class mask, for facexlib's feathered paste-back.
- **Fallback conversion** uses the GFPGAN **clean arch** (`stylegan2_clean_arch`) to dodge the StyleGAN `upfirdn2d` op blocker.
- Validate each adopted artifact (coremltools predict / on-device) vs the PyTorch reference on a 512 crop: **SSIM ≥ 0.98 / PSNR ≥ 35 dB**, and end-to-end vs `../photo-restore/outputs/`. Catch FP16 regressions; FP32-fallback per net if SSIM drops.

### B. Native SwiftUI app (this directory)
Layering (no SwiftUI below the view-model line):
```
SwiftUI Views ─▶ @MainActor BatchViewModel ─▶ BatchCoordinator (actor: queue, backpressure, Config snapshots, output-path policy)
       ▲                                              │ one in-flight item
       │ AsyncStream<ProgressEvent> (Sendable)        ▼
       └───────────────────────── RestorePipeline (Contrast → Upscale(+Lanczos) → Faces; mirrors restore_image)
                                                      │
                                                      ▼
                                          InferenceEngine (actor: resident MLModels, serial ANE/GPU, tiling)
```
> *Directional guidance for review, not implementation spec.* Error propagation: a stage throws →
> caught at the stage boundary → item marked `failed` → batch continues. Cancellation flows
> top-down via `Task`; preview/state flows bottom-up via the single `Sendable` stream with one
> `@MainActor` hop.

### Classical-op mapping (Swift)
| Python op | Swift |
|---|---|
| Image decode incl. **HEIC/RAW** | ImageIO `CGImageSource` (native HEIC/RAW), honor + strip orientation |
| Luminance + percentile clip + shared stretch | vImage histogram (linear-interp ranks like `np.percentile`), Accelerate affine on all 3 channels |
| Lanczos resize to exact target | `CILanczosScaleTransform` (validate SSIM; kernel ≠ PIL exactly) |
| `_match_color` (YCrCb Cr/Cb swap) | Accelerate BT.601 matrix (+128 offset), swap chroma, invert |
| `_match_grain` (luma − Gaussian σ=1, std clip 20, ×0.5, same noise all channels) | vImage Gaussian + Accelerate std; Gaussian noise (match **statistics**, not pixels) |
| Grayscale detect (spread ≤6) / collapse to L | vImage / Accelerate; collapse at end |
| EXIF preserve | ImageIO `CGImageDestination` copy properties (note: BMP drops EXIF) |
| Resolution math, weight registry | Port `resolution.py` / `models.py` 1:1; **pin SHA-256s** |

---

## UI design (dirt-simple)

**Single window, three regions** + top bar:
1. **Drop zone / work area.** Empty/welcome state with a big drop target + picker button. Three
   explicit empty states: welcome, "downloading models (x%)", "folder had no supported images."
2. **Before/After viewer (one image at a time).** Split-slider wipe over the selected image; the
   "after" side shows the **live stage preview** for the *in-flight* image (others show before +
   final-after-if-done). Fit-to-viewer with letterboxing for tall/panorama images. Caption = current
   stage + determinate progress bar.
3. **Filmstrip tray (bottom).** `LazyHStack` of ImageIO-downsampled thumbnails for every queued
   image, with **non-color-dependent status badges**: queued / processing / done / done (no faces) /
   skipped (unsupported / cancelled) / error (reason on hover). Click to view. Header shows overall
   batch progress ("12 / 134 done"). Arrow-key navigation; VoiceOver labels on badges.

**Top bar:** output-folder picker (default `Restored/` next to input, or Pictures), Start/Pause,
Settings. Start is **gated only for settings that need an uncached model** (classical-only runs work
during download).

**Settings (sheet/drawer), Mac-native:**
- **Size:** segmented "Keep original / 2× / 3× / 4× / Custom…" — Custom is **fit-inside-box** (aspect preserved), labeled so; reject non-positive values; one axis may be blank.
- **Face restoration:** master on/off + a single **"Restoration intensity"** slider driving `face_blend`.
- **Advanced (collapsed):** match color, match grain, skip-already-sharp-faces + threshold, auto-contrast, compute device (Auto default; GPU disabled w/ tooltip when unavailable), output format PNG/JPEG (+ quality, shown only for JPEG), overwrite existing, include subfolders.
- Defaults match the CLI. Per-image settings apply **forward to queued items**; batch-scope settings (output dir, subfolders, overwrite) **lock during an active run**. Persisted via `@AppStorage`.

---

## Implementation Units

Grouped by phase; each phase has a **parity/acceptance gate**. A Swift parity harness (SSIM + PSNR
vs `../photo-restore/{inputs,outputs}/`, **grain off** for face regions) is built in U1.

### U1. Scaffold + parity harness + image I/O + classical stages (no ML)
**Goal:** SwiftUI app shell + the engine's non-ML foundation, validated against the CLI.
**Requirements:** R2, R5, R8.
**Files:** app target + `RestoreEngine/{ImageIO,Contrast,Lanczos,Resolution,Grayscale}.swift`; `ParityHarness/` test target.
**Approach:** ImageIO load/save (incl. HEIC/RAW), orientation honor+strip, grayscale detect (spread ≤6) + collapse-to-L, port `resolution.py` 1:1, contrast (luminance percentile stretch), Lanczos-to-exact-target. Pure functions, `Sendable`.
**Patterns to follow:** `imageio.py`, `contrast.py`, `resolution.py`.
**Test scenarios:**
- Happy: contrast-only output vs Python contrast-only — SSIM ≥ 0.97.
- Happy: resize-only (2× / fit-box) vs Python — SSIM ≥ 0.97; exact target dimensions match `resolve_dimensions`.
- Edge: B&W scan (RGB spread ≤6) collapses to gray; output has no chroma.
- Edge: HEIC + a common RAW decode to RGB; orientation applied; EXIF carried (and BMP-drops-EXIF noted).
- Edge: Custom "2000×2000" on a 3:2 photo → 2000×1333 (fit-inside), one-axis-blank handled, non-positive rejected.
**Verification:** harness prints SSIM/PSNR per stage; classical gates pass; app opens to the welcome empty state.

### U2. Adopt + validate pre-converted Core ML models (conversion as fallback)
**Goal:** Obtain validated Core ML models for Real-ESRGAN, GFPGAN, face-parsing — by adoption first.
**Requirements:** R2, R6.
**Dependencies:** none (parallel to U1).
**Files:** `tools/models/validate_parity.py` (reuses U1's SSIM/PSNR), `tools/convert/{realesrgan,gfpgan,parsenet}_to_coreml.py` (fallback only).
**Approach:** Download the `john-rocky/CoreML-Models` artifacts (Real-ESRGAN ~67 MB BSD-3, GFPGAN ~337 MB Apache-2, face-parsing ~53 MB MIT); run each on the reference crops and compare to the PyTorch reference + `../photo-restore/outputs/`. Record correct input scale/bias and the GFPGAN output `clamp(x*127.5+127.5)` normalization. Only if a model fails a gate (or U4 needs a different ESRGAN input shape) run the fallback coremltools conversion (clean arch for GFPGAN). Record provenance + SHA-256 for re-hosting in U3.
**Patterns to follow:** `models.py` registry; john-rocky / MLBoy (rockyshikoku) conversion + output-normalization write-ups.
**Test scenarios:**
- Happy: each adopted model vs PyTorch on a fixed 512 crop — SSIM ≥ 0.98 / PSNR ≥ 35 dB.
- Edge: FP16 vs FP32 delta measured; if FP16 < gate, use FP32 for that net.
- Edge: a model that fails the gate triggers the fallback conversion path and re-validates.
**Verification:** `validate_parity.py` green for all three adopted (or fallback-converted) models; provenance + SHA-256 recorded.

### U3. Model registry, resumable downloader, on-device compile + cache
**Goal:** First-launch model acquisition that survives a clean Mac.
**Requirements:** R6.
**Dependencies:** U2.
**Files:** `RestoreEngine/Models/{ModelRegistry,ModelDownloader,ModelStore}.swift`.
**Approach:** Registry points at **our re-hosted copies** of the U2-validated models (GitHub Releases, ≤2 GB/asset; R2 fallback) — not the john-rocky Google-Drive links — each with **pinned SHA-256** + modelVersion. `URLSessionDownloadTask` (streams to disk) with resume data; verify SHA-256; `MLModel.compileModel(at:)` → move `.mlmodelc` to Application Support keyed by version; check-before-recompile.
**Patterns to follow:** `models.py` (`.part` + atomic replace, min_bytes).
**Test scenarios:**
- Happy: cold download → verify → compile → cached; second launch loads `.mlmodelc` in seconds (no recompile).
- Error: no network → clear "models required" state + retry; interrupted download → resume; SHA-256 mismatch → reject + re-download; disk full → actionable error.
- Edge: quit mid-download → next launch resumes (or restarts that weight atomically, never corrupt).
**Verification:** clean-machine run downloads, verifies, compiles, and persists; offline relaunch loads cached models.

### U4. Tiling benchmark spike + Real-ESRGAN upscale stage
**Goal:** Lock tile size; implement tiled SR + Lanczos-to-target, faces off.
**Requirements:** R1, R2.
**Dependencies:** U1, U3.
**Files:** `RestoreEngine/Upscale/{TileBenchmark,TiledUpscaler,SeamBlender}.swift`.
**Execution note:** Start with the benchmark spike (512/768/1024 latency + peak memory on 8 GB) and record the chosen size before building the tiler. If the winning tile size differs from the adopted Real-ESRGAN model's fixed input shape, re-bake it via the U2 fallback conversion at that shape.
**Approach:** Overlapping tiles (~1/8 overlap), feathered seam blend over overlap bands only, write tiles into a pre-allocated destination; cap SR input so output ≤ ~1.5× target; preserve `needs_enlargement` skip. `autoreleasepool` per tile.
**Patterns to follow:** `upscale.py` (single-call semantics it replaces), `_build_background` ordering.
**Test scenarios:**
- Happy: `--no-face`-equivalent full pipeline vs Python — SSIM ≥ 0.95.
- Edge: seam regions show no visible discontinuity (local SSIM across seams ≥ 0.97).
- Edge: target ≤ source → SR skipped (Lanczos only); large scan capped (tile count within budget).
- Error: synthetic OOM → actionable error, optional CPU retry (mirror `_is_oom`).
**Verification:** benchmark numbers recorded in plan/notes; `--no-face` parity gate passes within memory budget.

### U5. Face detection + alignment (Apple Vision → 512 crop)
**Goal:** Reproduce facexlib's aligned 512 crops via Vision. **(Highest-risk — do early.)**
**Requirements:** R2.
**Dependencies:** U1.
**Files:** `RestoreEngine/Faces/{FaceDetector,Aligner}.swift`.
**Approach:** `VNDetectFaceLandmarksRequest` → derive 5 points → Umeyama similarity transform to facexlib's fixed 512 template → warp; keep inverse transform for paste-back; size-gate on source pixels (≤500).
**Patterns to follow:** `faces.py` template + `align_warp_face`.
**Test scenarios:**
- Happy: Swift 512 crops vs facexlib crops on the 3 reference images — landmark positions within a few px, crop SSIM ≥ 0.9.
- Edge: 0-face image → empty result (downstream pass-through); multi-face image → all crops + gating.
- Edge: tilted/profile face — flag if alignment exceeds tolerance (RetinaFace-conversion fallback decision).
**Verification:** crop-parity gate passes on reference set; gating matches `_should_restore`.

### U6. GFPGAN restore + parse-mask paste-back (headline end-to-end)
**Goal:** Full conservative pipeline matching `outputs/`.
**Requirements:** R2, R8.
**Dependencies:** U3, U4, U5.
**Files:** `RestoreEngine/Faces/{Restorer,ColorMatch,Blend,Grain,PasteBack}.swift`, `RestoreEngine/RestorePipeline.swift`.
**Approach:** Run GFPGAN on each crop; `_match_color` (YCrCb), `_blend` (α), `_match_grain` (stats-matched); parsenet mask + double Gaussian blur + 10 px trim + inverse-affine paste-back onto the upscaled background; final grayscale collapse. Assemble `RestorePipeline` mirroring `restore_image` ordering behind a small per-stage protocol.
**Patterns to follow:** `faces.py:restore_onto`, `pipeline.py:restore_image`.
**Test scenarios:**
- Happy: full pipeline vs `outputs/` — face-region SSIM ≥ 0.95 **with grain off**; full-image visual review with grain on.
- Edge: B&W scan — `_match_color` keeps it gray; no invented color survives collapse.
- Edge: size-gated large face — left to background upscaler (not regenerated).
- Integration: face composited onto upscaled background, never through SR (texture matches).
**Verification:** headline parity gate passes; visual spot-check on faded + B&W scans.

### U7. Engine concurrency: InferenceEngine + BatchCoordinator + progress stream
**Goal:** Batch-safe, cancellable, observable engine.
**Requirements:** R1, R3, R4, R7, R8.
**Dependencies:** U6.
**Files:** `RestoreEngine/{InferenceEngine,BatchCoordinator,ProgressEvent,RestoreResult}.swift`.
**Approach:** `InferenceEngine` actor: resident `MLModel`s, launch warm-up, serial ANE path, tiling funneled through it. `BatchCoordinator` actor: queue, backpressure (concurrency 1 on 8 GB / memory-aware semaphore), decode-on-demand, `Config` snapshot at enqueue, per-item status + error isolation, **output-path policy** (collision/skip/overwrite, hard-block output==input same-format, pre-flight writability probe). Emit `Sendable` `ProgressEvent` `AsyncStream`; cancellation at stage/tile/face boundaries.
**Patterns to follow:** `lru_cache` model caching; CLI per-file error continuation + resumable `exists()` skip.
**Test scenarios:**
- Happy: 100-image batch streams to completion within memory budget; overall + per-image progress correct.
- Error: one corrupt/OOM image fails its own item; batch continues; "retry failed" works.
- Edge: "no faces" item → done (no faces), not error.
- Edge: pause = finish-current-then-halt; cancel-current = mark skipped + advance; remove queued item = instant.
- Edge (data safety): output==input same format → Start blocked; existing outputs skipped unless overwrite; ejected output volume mid-batch → batch pauses with one actionable error.
- Integration: changing a per-image setting mid-batch applies forward only; batch-scope settings locked during run.
**Verification:** stress run (100+ mixed images, mid-batch drops/removes/pause) leaves no orphaned items and no data loss.

### U8. SwiftUI app: drag-drop, filmstrip, before/after viewer, live preview, settings
**Goal:** The dirt-simple UI wired to the engine.
**Requirements:** R1, R3, R4, R5, R7.
**Dependencies:** U7.
**Files:** `App/{ContentView,DropZone,FilmstripView,BeforeAfterView,SettingsView,BatchViewModel}.swift`.
**Approach:** `.dropDestination(for: URL.self)` + async folder enumeration off-main ("scanning… N found"); dedup by canonical path; `LazyHStack` filmstrip with downsampled thumbnails + status badges; split-slider before/after with letterboxing; `BatchViewModel` (`@MainActor`) consumes the `ProgressEvent` stream (single hop, throttled previews); settings drawer with forward-apply / batch-lock semantics; Start gated only on uncached-model settings.
**Patterns to follow:** the architecture diagram; ImageIO thumbnail downsampling.
**Test scenarios:**
- Happy: drop single file / folder / nested folders → filmstrip populates; Start → live preview improves; outputs land in chosen folder.
- Edge: mixed-content folder (non-images, HEIC) — images queued, HEIC decoded, undecodable shown "skipped"; nothing vanishes.
- Edge: drop more / same image twice / drop while paused — append + dedup, no auto-start.
- Edge: switch to a queued vs processing vs done item — preview behaves per spec; tall/panorama letterboxed.
- Edge: 1000-image folder enumerates off-main without UI hang; 100+ thumbnails scroll smoothly.
- Accessibility: arrow-key filmstrip nav; VoiceOver badge labels (not color-only).
**Verification:** end-to-end manual run on `../photo-restore/inputs/`; all empty states reachable.

### U9. Package, sign, notarize, ship
**Goal:** A double-clickable .app that runs on a clean Mac.
**Requirements:** R6.
**Dependencies:** U3, U8.
**Files:** entitlements, `Info.plist`, release/notarize tooling, app icon.
**Approach:** Non-sandboxed, Hardened Runtime (`--options runtime`, no `get-task-allow`), Developer-ID sign, `notarytool submit --wait`, `stapler staple` the .app, ship a stapled `.dmg`. First-launch model-download UX; verify offline launch.
**Test scenarios:**
- Happy: clean Mac (no dev tools) launches stapled app offline; first run downloads + compiles models; processes an image.
- Error: offline first-run → clear "models required" state, no crash.
**Verification:** notarization accepted; Gatekeeper passes offline; clean-VM smoke test green.

---

## System-Wide Impact
- **Interaction graph:** see the diagram in Architecture. The only `@MainActor` hop is `BatchViewModel`; the engine is SwiftUI-free.
- **Error propagation:** stage throw → stage boundary → item `failed` → batch continues; surfaced as a filmstrip badge + reason. OOM offers CPU retry.
- **State lifecycle:** `Config` snapshot per item at enqueue; resumable via output `exists()` skip; resident models released on batch end / app background.
- **Concurrency hazards:** ANE is a shared singleton — no inference parallelism; memory-aware backpressure prevents 100×12 MP blowup; per-tile/per-image `autoreleasepool`.
- **Data-safety surfaces:** output-path policy (no in-place overwrite), pre-flight writability, ejected-volume detection, SHA-256 model integrity.
- **Unchanged invariants:** "never colorize" (grayscale collapse), EXIF/orientation carry, faces composited onto background (never through SR), size-gate on source pixels.

---

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Adopted/FP16 Core ML model drifts from reference (incl. dropped pre/post-normalization) | Med | High | U2 parity gate vs `outputs/`; documented `clamp` output wrapper; FP32 fallback per-net; from-scratch re-convert |
| Pre-converted artifact abandoned / Google-Drive link rots | Low | Med | Re-host verified copies (SHA-256 pinned) in U3; fallback conversion script reproduces them |
| Vision landmarks misalign vs facexlib template (tilted faces) | Med | High | U5 crop-parity gate; RetinaFace-conversion fallback ready |
| Tile-count/memory OOM on 8 GB | Med | High | Benchmark-locked tile size, input cap, concurrency 1, decode-on-demand, autoreleasepool |
| SR seam artifacts (Python never tiled) | Med | Med | Feathered overlap blend; per-seam SSIM gate |
| First-launch download fails (network/disk/corrupt) | Med | Med | Resumable `URLSessionDownloadTask`, SHA-256, retry, offline state |
| Notarization rejection | Low | High | Hardened Runtime, no debug entitlements, pure Core ML (no JIT), staple |
| Live preview starves inference / stalls UI | Med | Med | Downsampled + coalesced previews off the inference queue; progress-fraction during tiling |
| `_match_grain` non-determinism misread as parity failure | High | Low | Gate with grain off; visual review with grain on |

**Dependencies:** Apple Silicon Mac; Developer ID cert + notarization account; model hosting (GitHub Releases + R2 fallback); the reference repo's `inputs/`+`outputs/` for parity gates.

---

## Documentation / Operational Notes
- Pin real SHA-256s in the registry before shipping (`models.py` currently has none).
- Model versioning is independent of app version (ship model fixes without re-notarizing).
- README: MIT for app code; bundled/downloaded model weights retain upstream licenses (GFPGAN permissive; CodeFormer non-commercial when added).
- Release pipeline: sign → notarytool submit --wait → staple → publish stapled `.dmg` + model assets.

---

## Verification
- **Per-phase parity gates** above (SSIM/PSNR vs `../photo-restore/{inputs,outputs}/`, grain off).
- **End-to-end:** drag `../photo-restore/inputs/` in; filmstrip populates, each image runs
  contrast→upscale→faces with the live "after" improving, progress advances, outputs land in the
  chosen folder. Spot-check: B&W scan stays gray; faded scan shows the contrast win; a HEIC drops in
  and restores; a 0-face image passes through as "done (no faces)."
- **Data-safety:** output==input same-format is blocked; existing outputs skipped unless overwrite.
- **Shareability:** notarized stapled .app launches offline on a clean Mac, downloads + compiles
  models on first run, and processes an image with no developer tooling installed.
