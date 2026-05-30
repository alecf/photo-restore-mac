# Model hosting (R2/S3) — wiring for U3's downloader

The app downloads its Core ML models on first launch (kept out of the signed bundle). Host
the three U2-validated artifacts on **Cloudflare R2** (zero egress) or S3 and point the app at
them.

## Steps
1. Create a public bucket/prefix, e.g. `photo-restore/models/v1/`.
2. Upload the three files from `tools/models/cache/` **unchanged** (their SHA-256s are pinned in
   `RestoreEngine/Sources/RestoreEngine/Models/ModelRegistry.swift`):
   - `RealESRGAN4x.mlmodel` (66,857,221 bytes)
   - `GFPGAN.mlmodel` (337,392,296 bytes)
   - `FaceParsing.mlmodel` (53,182,369 bytes)
3. Set `ModelRegistry.baseURL` to the public base URL (must end in `/`), e.g.
   `https://<bucket>.r2.cloudflarestorage.com/photo-restore/models/v1/`.

## Integrity / versioning
- The app verifies each download against the pinned SHA-256 before compiling — a wrong/corrupt
  file is rejected and re-fetched. Do not re-compress or alter the files after hashing.
- Models are versioned by the `version` field on each `ModelSpec` (compiled cache is keyed by it).
  To ship a new model build, upload under a new prefix (`…/v2/`) and bump that model's `version`;
  old and new can coexist during migration.

## Verifying the wired URL
With `baseURL` set, the app's first launch downloads + compiles into
`~/Library/Application Support/com.alecf.PhotoRestore/Models/compiled/v1/`. A quick check that the
URLs resolve:

```
curl -fsI "$BASE/RealESRGAN4x.mlmodel" | head -1   # expect 200 + correct Content-Length
```
