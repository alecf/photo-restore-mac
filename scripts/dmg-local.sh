#!/usr/bin/env bash
# Build a local, ad-hoc-signed .dmg for testing on this machine (NOT notarized — other Macs
# will need a right-click → Open to bypass Gatekeeper). Needs no Apple credentials.
#
# Usage: scripts/dmg-local.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD="$ROOT/build"
rm -rf "$BUILD"; mkdir -p "$BUILD"

xcodegen generate
xcodebuild -project PhotoRestore.xcodeproj -scheme PhotoRestore -configuration Release \
  -derivedDataPath "$BUILD/dd" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  build

APP="$BUILD/dd/Build/Products/Release/Photo Restore.app"
DMG_SRC="$BUILD/dmg"; mkdir -p "$DMG_SRC"
cp -R "$APP" "$DMG_SRC/"
ln -s /Applications "$DMG_SRC/Applications"
hdiutil create -volname "Photo Restore" -srcfolder "$DMG_SRC" -ov -format UDZO "$BUILD/PhotoRestore-local.dmg"
echo "✓ $BUILD/PhotoRestore-local.dmg (ad-hoc, local testing only)"
