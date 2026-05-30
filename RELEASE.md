# Releasing Photo Restore

Releases are automated via GitHub Actions, modeled on the memwatch flow. The app is
**ad-hoc signed** (no paid Apple Developer account) and auto-updates via **Sparkle**.

## How a release works

1. Land changes on `main` via PRs. PR titles must be conventional commits (`feat:`, `fix:`, …) —
   enforced by `.github/workflows/pr-title.yml`, and the basis for versioning. CI
   (`.github/workflows/ci.yml`) builds the app + runs the engine tests on every PR.
2. Run the release: **`gh workflow run release.yml`** (or the Actions tab → Release → Run).
   `.github/workflows/release.yml` then:
   - uses **git-cliff** to compute the next semver + changelog from the commits since the last tag,
   - builds the Release app (xcodebuild) and **ad-hoc signs** it (incl. the Sparkle framework),
   - packages a `PhotoRestore-<version>-arm64.dmg`,
   - signs the DMG with the **Sparkle EdDSA** key (`SPARKLE_PRIVATE_KEY` secret),
   - tags `v<version>`, creates the **GitHub Release** with the DMG + changelog,
   - prepends the release to `site/appcast.xml` and pushes it, which triggers
     `deploy-pages.yml` to publish the appcast so installed apps see the update.

## One-time setup (required before the first release)

See **`docs/sparkle-setup.md`** — generate the Sparkle key pair, pin the public key in
`project.yml` (`SUPublicEDKey`), set the `SPARKLE_PRIVATE_KEY` repo secret, and enable GitHub
Pages (Source: GitHub Actions). The release workflow refuses to run until the secret is set.

## Local builds (no CI)

- `scripts/run.sh` — build + launch (dev loop).
- `scripts/dmg-local.sh` — ad-hoc `.dmg` for local testing.
- `scripts/release.sh` + `RELEASE` notes for a **Developer-ID notarized** DMG — only if you later
  get a paid Apple Developer account and want notarization (better first-launch UX). Not required;
  the CI release path uses ad-hoc signing.

## Gatekeeper note

Ad-hoc signed apps aren't notarized, so the first launch on another Mac needs a right-click →
**Open** to clear Gatekeeper. Sparkle auto-updates work regardless.
