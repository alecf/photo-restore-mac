# Sparkle auto-update — one-time key setup

The app ships with Sparkle for in-app auto-updates. Releases (DMGs) are signed with an EdDSA
key; the app verifies them against the public key pinned in `Info.plist`. You generate the key
pair once.

This is the only manual step in the release pipeline — everything else (build, DMG, GitHub
Release, appcast publish, Pages deploy) is automated in `.github/workflows/release.yml`.

## 1. Generate the key pair (once, on your Mac)

```sh
curl -sSL -o sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
mkdir -p sparkle-tools && tar -xf sparkle.tar.xz -C sparkle-tools
./sparkle-tools/bin/generate_keys
```

This prints your **public key** (and stores the private key in your login Keychain — approve the
Keychain prompt). Copy the public key string.

## 2. Pin the public key in the app

In `project.yml`, replace `REPLACE_WITH_SPARKLE_PUBLIC_KEY` (under `targets.PhotoRestore.info.properties.SUPublicEDKey`)
with your public key, then commit:

```sh
xcodegen generate   # regenerate the project so Info.plist picks it up
git commit -am "chore: pin Sparkle public key"
```

## 3. Export the private key and set it as a repo secret

```sh
./sparkle-tools/bin/generate_keys -x sparkle_private_key.txt   # exports the private key
gh secret set SPARKLE_PRIVATE_KEY < sparkle_private_key.txt
rm sparkle_private_key.txt                                     # don't keep it on disk
```

The release workflow reads `SPARKLE_PRIVATE_KEY` to sign each DMG. It refuses to run until the
secret is set.

## 4. Enable GitHub Pages

Settings → Pages → Build and deployment → Source: **GitHub Actions**. The `Deploy Pages` workflow
publishes `site/` (the appcast + a download page) to
`https://alecf.github.io/photo-restore-mac/`, which is the `SUFeedURL` the app checks.

## Notes
- The DMG is **ad-hoc signed** (no paid Apple Developer account). First launch on another Mac
  needs a right-click → Open to clear Gatekeeper. Sparkle updates still work.
- To cut a release: `gh workflow run release.yml`. git-cliff bumps the version from your
  conventional commits, builds, signs, publishes the Release + appcast.
