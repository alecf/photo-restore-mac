# Photo Restore

A dirt-simple, native macOS app that restores old family-photo scans — faded prints, low-res
snapshots, soft faces. Drag in a photo or a folder, optionally pick an output folder, and watch
each photo restore with a live before/after preview. Everything runs **on-device** (Apple Silicon,
Core ML) — no cloud, no accounts, no data leaves your Mac.

It's a native Swift reimplementation of the [`photo-restore`](../photo-restore) Python CLI, using
the same models converted to Core ML.

## What it does

- **Auto-contrast** faded scans (luminance-preserving — never shifts color, never colorizes).
- **Upscale** with Real-ESRGAN x4plus (optional 2×/3×/4× or fit-to-size), tiled with feathered seams.
- **Restore faces** with GFPGAN, aligned via Apple Vision, composited back with a parsing mask so
  only the face is touched. Color-match (B&W stays gray), texture-preserving blend, matched grain.
- **Batch** 100+ images with live progress, a filmstrip of every image, and a before/after slider.

## Architecture

- **`PhotoRestore/`** — the SwiftUI app (drag-drop, filmstrip, before/after viewer, settings).
- **`RestoreEngine/`** — an internal, SwiftUI-free Swift package: the whole pipeline (image I/O,
  contrast, tiled upscale, Vision alignment, face restore + paste-back), the Core ML model store,
  and the serial `InferenceEngine` + `BatchCoordinator`. Fully unit-tested (`swift test`).
- **`tools/models/`** — Python tooling to download + validate the pre-converted Core ML models
  (see `tools/models/VALIDATION.md`).

## Build & run

Requires Xcode 16+ and [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open PhotoRestore.xcodeproj      # or: xcodebuild -scheme PhotoRestore build
cd RestoreEngine && swift test   # run the engine test suite
```

### Models

The app downloads its ~460 MB of Core ML models on first launch from a hosting bucket
(`ModelRegistry.baseURL` — wire to R2/S3, see `tools/models/HOSTING.md`). Until that's wired, or
for offline use, the app's first-run screen offers **Install from Folder…** — point it at a folder
containing `RealESRGAN4x.mlmodel`, `GFPGAN.mlmodel`, `FaceParsing.mlmodel` (e.g. produced by
`tools/models/download.py`). Each download is SHA-256-verified, compiled to `.mlmodelc`, and cached
in Application Support.

## Distribution

`scripts/dmg-local.sh` builds an ad-hoc `.dmg` for local testing. `scripts/release.sh` builds a
Developer-ID-signed, notarized, stapled `.dmg` — see `RELEASE.md` for the (Apple-account)
prerequisites.

## License

App code: **MIT** (see `LICENSE`). The restoration models carry their upstream licenses —
Real-ESRGAN (BSD-3), GFPGAN (Apache-2), BiSeNet face-parsing (MIT). (CodeFormer, a non-commercial
"balanced" face model, is a deferred future option.)
