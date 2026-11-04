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

The **Models** workflow (`.github/workflows/models.yml`) builds and publishes the release on a
GitHub macOS runner; nothing is uploaded from a developer machine. It reads the tag, file names
and SHA-256s from `ModelRegistry.swift`, then:

1. downloads the originals (`download.py --strict`, cached between runs),
2. builds `GFPGAN-ANE.mlmodel` (`rewrite_gfpgan_ane.py`, Python packages pinned in
   `requirements.txt` so the bytes are reproducible),
3. checks every file against the pins (`check_pins.py`),
4. on `main` only, creates the release (marked not-latest, so the app's own releases stay
   latest) with the models, `MODEL_LICENSES.md` and GFPGAN's license, then downloads the
   published assets and checks them again.

It only runs when model tooling, `ModelRegistry.swift` or the workflow changes. On pull requests it
always runs steps 1–3, so tooling changes are proven to reproduce the pinned bytes. On `main`, if
the release already exists, it only checks the release's asset digests against the pins (no
rebuild, no download). Published releases are never modified: see AGENTS.md for how to ship a
changed model.

To reproduce the build locally:

```
uv run --python 3.12 --with-requirements tools/models/requirements.txt python tools/models/download.py
uv run --python 3.12 --with-requirements tools/models/requirements.txt python tools/models/rewrite_gfpgan_ane.py
python3 tools/models/check_pins.py
```

## Changing a model

Point `baseURL` at a new release tag (`models-v3`), update the changed model's pins, and bump its
`version` in `ModelRegistry`. Merging that to `main` makes the workflow publish the new release. The compiled cache is keyed by version, so existing installs fetch
and compile the new file. Old releases can stay up for older app versions.

## Checking the URLs

```
curl -fsIL "https://github.com/alecf/photo-restore-mac/releases/download/models-v2/GFPGAN-ANE.mlmodel" | grep -iE "^HTTP|content-length"
```
