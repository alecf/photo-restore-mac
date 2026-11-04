# Agent Instructions

## Pull Requests

- PR titles MUST follow the [Conventional Commits](https://www.conventionalcommits.org/) spec:
  `<type>[optional scope]: <description>`
  - Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.
  - Use the imperative mood and keep the description concise (e.g. `fix: clamp slider to photo bounds`).
  - Add a scope when it clarifies the area touched (e.g. `fix(slider): ...`).

## Landing page (`site/index.html`)

The GitHub Pages site is published from `site/` by `.github/workflows/deploy-pages.yml`, on every
release and on any push to `site/**`.

- **Updates automatically:** the version number and the download link. The page reads both from
  the newest `<item>` in `site/appcast.xml`, which the Release workflow writes. Don't hardcode
  either one in the HTML.
- **Needs a manual edit:** everything else. In any PR that makes a user-visible change, check
  whether the page still describes the app correctly, and update `site/index.html` in the same PR
  if it doesn't. In particular:
  - *What it does* / *How it works*: new, removed or reordered pipeline steps, output sizes,
    settings, or batch behavior.
  - *Your photos stay on your Mac*: anything the app sends or fetches over the network, how outputs
    are written, and the models table (names, jobs, licenses, the ~294 MB total, which is `ModelRegistry.totalBytes`).
  - *Requirements* (hero line and FAQ): minimum macOS version (`project.yml` `deploymentTarget`),
    and supported architectures (the DMG is currently `arm64` only).
  - *FAQ*: signing and Gatekeeper steps (rewrite this entry if the app becomes Developer-ID signed
    and notarized), offline model install, and how updates are delivered.
- Keep the page plain static HTML with no build step. Preview it with
  `cd site && python3 -m http.server` (the version lookup doesn't work over `file://`).

## Models (`tools/models/`, `ModelRegistry.swift`)

The app downloads its Core ML models from a GitHub release (`ModelRegistry.baseURL`, currently
`models-v2`). `ModelRegistry.swift` is the source of truth: release tag, file names, sizes and
SHA-256s. The **Models** workflow (`.github/workflows/models.yml`) builds the files on a macOS
runner and publishes the release. Never build or upload model files from a local machine for a
release.

A published release is never modified. The workflow fails if a release's assets stop matching the
pins, and the app rejects any file whose SHA-256 doesn't match.

**Changes that need a model rebuild.** Anything that changes the bytes of a model file:
- `tools/models/rewrite_gfpgan_ane.py`, its pinned scale factors
  (`tools/models/gfpgan_ane_scales.json`, regenerated with `--calibrate`), or
  `tools/models/requirements.txt`.
- An upstream model in `tools/models/manifest.json`, or adding or removing a model.

For these, in the same PR:
1. Point `ModelRegistry.baseURL` at a new tag (`models-v3`, and so on).
2. Update the changed model's `sha256` and `sizeBytes`, and bump its `version`. The compiled
   cache is keyed by version, so existing installs fetch and compile the new file.
3. Get the new pins from the PR's Models run: it rebuilds and its "Check built files against pins"
   step prints each file's size and SHA-256. Locally, the commands in `tools/models/HOSTING.md`
   print the same values.
4. Update the docs that state model names or sizes: README, `tools/models/HOSTING.md`,
   `MODEL_LICENSES.md`, and the landing page (see above).

CI has no Neural Engine, so before merging a rewrite change, run `swift test --filter
FaceRestorerIntegrationTests` in `RestoreEngine/` on Apple Silicon with the new model in
`tools/models/cache/`.

After merge, the Models run on `main` publishes the new release. Until it succeeds, new downloads
get a 404, so don't start an app release before then.

**Changes that don't.** Swift-side changes to how the app uses a model, such as compute units,
pre- or post-processing, or which output it reads, leave the files alone. No new tag is needed.
- Moving a model to a different compute unit: compare its raw output across `MLComputeUnits`. The
  Neural Engine computes in fp16, and GFPGAN's original build failed only there.
  `FaceRestorerIntegrationTests` shows how to check raw output.
- Changing a model's inputs, outputs or architecture is a rebuild (see above).

