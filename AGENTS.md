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
    are written, and the models table (names, jobs, licenses, the ~460 MB total).
  - *Requirements* (hero line and FAQ): minimum macOS version (`project.yml` `deploymentTarget`),
    and supported architectures (the DMG is currently `arm64` only).
  - *FAQ*: signing and Gatekeeper steps (rewrite this entry if the app becomes Developer-ID signed
    and notarized), offline model install, and how updates are delivered.
- Keep the page plain static HTML with no build step. Preview it with
  `cd site && python3 -m http.server` (the version lookup doesn't work over `file://`).
