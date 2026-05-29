#!/usr/bin/env python3
"""Download the pre-converted Core ML model artifacts listed in manifest.json from
Google Drive (handling the large-file confirmation interstitial via gdown), verify
their size, and record SHA-256 back into the manifest.

Run with uv:  uv run --with gdown python tools/models/download.py
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import gdown

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "manifest.json"
CACHE = HERE / "cache"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    CACHE.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text())
    changed = False

    for model in manifest["models"]:
        dest = CACHE / model["filename"]
        expected = model.get("expected_mb", 0) * 1_000_000 * 0.7  # generous floor
        if dest.exists() and dest.stat().st_size >= expected:
            print(f"[cached] {model['name']} -> {dest} ({dest.stat().st_size/1e6:.1f} MB)")
        else:
            url = f"https://drive.google.com/uc?id={model['drive_id']}"
            print(f"[download] {model['name']} <- {url}")
            gdown.download(url, str(dest), quiet=False)
            if not dest.exists() or dest.stat().st_size < expected:
                size = dest.stat().st_size if dest.exists() else 0
                print(f"  ERROR: {model['name']} too small ({size} bytes) — Drive interstitial?")
                return 1

        digest = sha256(dest)
        if model.get("sha256") != digest:
            model["sha256"] = digest
            changed = True
        print(f"  size={dest.stat().st_size/1e6:.1f}MB sha256={digest[:16]}…")

    if changed:
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
        print("manifest.json updated with SHA-256s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
