# Releasing Photo Restore (notarized .dmg)

The app is distributed **outside the Mac App Store** as a Developer-ID-signed, notarized, stapled
`.dmg`. It is intentionally **not sandboxed** (a folder-batch tool fights the sandbox), so it needs
no entitlements file — just Hardened Runtime (set via `ENABLE_HARDENED_RUNTIME` in `project.yml`)
and a Developer ID signature.

## One-time prerequisites (your Apple Developer account)

These are the only things the build can't supply itself:

1. **Developer ID Application certificate** installed in your login keychain
   (Xcode → Settings → Accounts → Manage Certificates → +).
2. A **notarytool keychain profile** with an app-specific password:
   ```sh
   xcrun notarytool store-credentials photorestore \
     --apple-id "you@example.com" --team-id "YOURTEAMID" --password "app-specific-password"
   ```
3. Your **Team ID** (10 chars, from developer.apple.com → Membership).

## Cut a release

```sh
TEAM_ID=YOURTEAMID NOTARY_PROFILE=photorestore scripts/release.sh
# → build/PhotoRestore.dmg  (signed, notarized, stapled)
```

The script archives Release, exports a Developer-ID app, submits to notarytool (`--wait`), staples
the ticket (so it launches offline on a clean Mac), and packages a `.dmg`.

## Notes / gotchas

- **Stapling matters:** without it, first launch on a truly offline Mac fails Gatekeeper's online
  check. The script staples both the app and the dmg.
- **Models are not in the bundle:** the ~460 MB of Core ML models download on first launch (or via
  the in-app *Install from Folder…*), so the signed app stays tiny and the notarization upload is
  fast. Host the models per `tools/models/HOSTING.md` and set `ModelRegistry.baseURL`.
- **No JIT / no special entitlements:** inference is pure Core ML (data, not executable code), so
  there's nothing that trips Hardened Runtime. Do not add `get-task-allow` to the release build.
- **Local testing without an account:** `scripts/dmg-local.sh` builds an ad-hoc `.dmg` (other Macs
  need right-click → Open to bypass Gatekeeper).
