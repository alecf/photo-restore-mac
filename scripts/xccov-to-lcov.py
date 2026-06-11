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

            lines = run_json(["xcrun", "xccov", "view", "--file", path, "--json", xcresult])

            rel_path = os.path.relpath(path, repo_root)
            print(f"SF:{rel_path}")
            for entry in lines:
                if entry.get("isExecutable"):
                    print(f"DA:{entry['line']},{entry['count']}")
            print("end_of_record")


if __name__ == "__main__":
    main()
