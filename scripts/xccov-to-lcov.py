#!/usr/bin/env python3
"""Convert the code coverage in an .xcresult bundle into lcov format.

Usage: xccov-to-lcov.py <path-to.xcresult> <repo-root>
"""
import json
import os
import subprocess
import sys


def run_json(args):
    result = subprocess.run(args, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def parse_count(token):
    token = token.strip()
    if token.endswith("k") or token.endswith("K"):
        return int(float(token[:-1]) * 1_000)
    if token.endswith("M"):
        return int(float(token[:-1]) * 1_000_000)
    return int(token)


def file_line_counts(xcresult, path):
    result = subprocess.run(
        ["xcrun", "xccov", "view", "--file", path, xcresult],
        capture_output=True, text=True, check=True,
    )
    for line in result.stdout.splitlines():
        line_no_str, sep, rest = line.partition(":")
        line_no_str = line_no_str.strip()
        rest = rest.strip()
        if not sep or not line_no_str.isdigit() or rest in ("", "*"):
            continue
        yield int(line_no_str), parse_count(rest)


def main():
    xcresult, repo_root = sys.argv[1], os.path.abspath(sys.argv[2])

    report = run_json(["xcrun", "xccov", "view", "--report", "--json", xcresult])

    seen_paths = set()
    for target in report.get("targets", []):
        for file_entry in target.get("files", []):
            path = file_entry["path"]
            if path in seen_paths or not path.startswith(repo_root):
                continue
            seen_paths.add(path)

            rel_path = os.path.relpath(path, repo_root)
            print(f"SF:{rel_path}")
            for line_no, count in file_line_counts(xcresult, path):
                print(f"DA:{line_no},{count}")
            print("end_of_record")


if __name__ == "__main__":
    main()
