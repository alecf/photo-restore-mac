# Model hosting

The app downloads its Core ML models on first launch, keeping them out of the signed app bundle.
They're hosted as assets on a GitHub release of this repo:

    https://github.com/alecf/photo-restore-mac/releases/tag/models-v2

`ModelRegistry.baseURL` points at that release's download path. Downloads from a public repo's
releases are free, have no bandwidth cap, and allow files up to 2 GB.

| File | Bytes | Source |
|---|---|---|
| `RealESRGAN4x.mlmodel` | 66,857,221 | `download.py`, unchanged |
| `GFPGAN-ANE.mlmodel` | 173,946,571 | `rewrite_gfpgan_ane.py` applied to `download.py`'s `GFPGAN.mlmodel` |
| `FaceParsing.mlmodel` | 53,182,369 | `download.py`, unchanged |

SHA-256s are pinned in `RestoreEngine/Sources/RestoreEngine/Models/ModelRegistry.swift`.

## Publishing

```
uv run --with gdown python tools/models/download.py
uv run --python 3.12 --with coremltools --with numpy --with pillow \
    python tools/models/rewrite_gfpgan_ane.py
shasum -a 256 tools/models/cache/*.mlmodel     # must match ModelRegistry.swift
curl -fsSL https://raw.githubusercontent.com/TencentARC/GFPGAN/master/LICENSE \
    -o tools/models/cache/GFPGAN-LICENSE.txt      # Apache-2.0 asks for a copy of the license
gh release create models-v2 --latest=false --title "Models v2" --notes-file <notes> \
    tools/models/cache/RealESRGAN4x.mlmodel \
    tools/models/cache/GFPGAN-ANE.mlmodel \
    tools/models/cache/FaceParsing.mlmodel \
    tools/models/MODEL_LICENSES.md \
    tools/models/cache/GFPGAN-LICENSE.txt
```

`--latest=false` keeps the app's own releases marked as latest. Upload the files exactly as built;
the app rejects any file whose SHA-256 doesn't match.

## Changing a model

Upload under a new release tag (`models-v3`), point `baseURL` at it, and bump the changed model's
`version` in `ModelRegistry`. The compiled cache is keyed by version, so existing installs fetch
and compile the new file. Old releases can stay up for older app versions.

## Checking the URLs

```
curl -fsIL "https://github.com/alecf/photo-restore-mac/releases/download/models-v2/GFPGAN-ANE.mlmodel" | grep -iE "^HTTP|content-length"
```
