#!/usr/bin/env python3
"""Prepend a new release <item> to the Sparkle appcast. Invoked by the release workflow."""
from __future__ import annotations

import argparse
import re
from email.utils import formatdate

MIN_SYSTEM = "14.0"


def signature_attrs(fragment: str) -> str:
    # sign_update emits e.g.  sparkle:edSignature="…" length="123"
    return fragment.strip()


def build_item(version: str, download_url: str, sig_fragment: str, changelog: str) -> str:
    pub_date = formatdate(localtime=False, usegmt=True)
    body = changelog.strip() or f"Version {version}"
    return f"""    <item>
      <title>Version {version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MIN_SYSTEM}</sparkle:minimumSystemVersion>
      <description><![CDATA[
{body}
      ]]></description>
      <enclosure url="{download_url}" type="application/octet-stream" {signature_attrs(sig_fragment)} />
    </item>"""


SKELETON = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Photo Restore</title>
    <description>Updates for Photo Restore</description>
    <language>en</language>
  </channel>
</rss>
"""


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--appcast", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--tag", required=True)
    p.add_argument("--signature-fragment", required=True)
    p.add_argument("--download-url", required=True)
    p.add_argument("--changelog", default="")
    args = p.parse_args()

    from pathlib import Path
    path = Path(args.appcast)
    xml = path.read_text() if path.exists() else SKELETON

    item = build_item(args.version, args.download_url, args.signature_fragment, args.changelog)
    # Insert the new item right after <channel> ... first descriptive lines.
    # Simplest robust insertion: place it just before the first existing <item>, else
    # before </channel>.
    if "<item>" in xml:
        xml = xml.replace("    <item>", item + "\n    <item>", 1)
    else:
        xml = xml.replace("  </channel>", item + "\n  </channel>", 1)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(xml)
    print(f"appcast updated with version {args.version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
