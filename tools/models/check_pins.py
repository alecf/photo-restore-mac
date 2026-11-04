#!/usr/bin/env python3
r"""Check built model files against the pins in ModelRegistry.swift (the app's source of truth).

    python tools/models/check_pins.py [DIR]     # verify DIR/<fileName> size + SHA-256 for every model
    python tools/models/check_pins.py --tag     # print the release tag that baseURL points at
    python tools/models/check_pins.py --files   # print the model file names
    gh api repos/OWNER/REPO/releases/tags/TAG --jq '.assets[] | "\(.name) \(.size) \(.digest)"' \
        | python tools/models/check_pins.py --assets   # verify a published release, no download
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REGISTRY = HERE.parent.parent / "RestoreEngine/Sources/RestoreEngine/Models/ModelRegistry.swift"


def pins():
    src = REGISTRY.read_text()
    specs = re.findall(
        r'ModelSpec\(\s*name:\s*"([^"]+)",\s*fileName:\s*"([^"]+)",\s*sha256:\s*"([0-9a-f]{64})",\s*sizeBytes:\s*([0-9_]+)',
        src)
    base = re.search(r'releases/download/([^/"]+)/', src)
    if not specs or not base:
        sys.exit(f"could not parse {REGISTRY}")
    return base.group(1), [(n, f, h, int(s.replace("_", ""))) for n, f, h, s in specs]


def main() -> int:
    tag, specs = pins()
    if "--tag" in sys.argv[1:]:
        print(tag)
        return 0
    if "--files" in sys.argv[1:]:
        print(" ".join(f for _, f, _, _ in specs))
        return 0
    if "--assets" in sys.argv[1:]:
        # Lines of "<name> <size> <digest>" from the releases API (digest is "sha256:<hex>").
        found = {}
        for line in sys.stdin:
            parts = line.split()
            if len(parts) == 3:
                found[parts[0]] = (int(parts[1]), parts[2].removeprefix("sha256:"))
        lookup = lambda fname: found.get(fname)
    else:
        d = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "cache"
        def lookup(fname):
            p = d / fname
            if not p.exists():
                return None
            data = p.read_bytes()
            return len(data), hashlib.sha256(data).hexdigest()
    ok = True
    for name, fname, sha, size in specs:
        got_pair = lookup(fname)
        if got_pair is None:
            print(f"MISSING  {fname}"); ok = False; continue
        got_size, got = got_pair
        good = got == sha and got_size == size
        ok &= good
        print(f"{'OK      ' if good else 'MISMATCH'} {fname}  {got_size} bytes  {got}" + ("" if good else f"  (pinned {size} bytes {sha})"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
