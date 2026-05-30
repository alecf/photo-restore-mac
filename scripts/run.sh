#!/usr/bin/env bash
# Build (CLI, no Xcode GUI) and launch Photo Restore — the "swift run" equivalent for the app.
# Usage: scripts/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d PhotoRestore.xcodeproj ] || xcodegen generate

DD="$PWD/build/dd"
xcodebuild -project PhotoRestore.xcodeproj -scheme PhotoRestore -configuration Debug \
  -derivedDataPath "$DD" -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DD/Build/Products/Debug/Photo Restore.app"
echo "launching $APP"
open "$APP"
