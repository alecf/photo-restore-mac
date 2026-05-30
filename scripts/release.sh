#!/usr/bin/env bash
# Build, Developer-ID sign, notarize, staple, and package Photo Restore as a .dmg.
#
# Prerequisites (your Apple Developer account — these are the blocker the agent can't supply):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A notarytool keychain profile:
#        xcrun notarytool store-credentials photorestore \
#          --apple-id "you@example.com" --team-id "YOURTEAMID" --password "app-specific-pw"
#   3. Set TEAM_ID below (or edit scripts/ExportOptions.plist).
#
# Usage: TEAM_ID=ABCDE12345 NOTARY_PROFILE=photorestore scripts/release.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD="$ROOT/build"
NOTARY_PROFILE="${NOTARY_PROFILE:-photorestore}"
TEAM_ID="${TEAM_ID:-}"

rm -rf "$BUILD"; mkdir -p "$BUILD"

# Bake TEAM_ID into a temp export options if provided.
EXPORT_PLIST="$ROOT/scripts/ExportOptions.plist"
if [ -n "$TEAM_ID" ]; then
  EXPORT_PLIST="$BUILD/ExportOptions.plist"
  sed "s/REPLACE_TEAM_ID/$TEAM_ID/" "$ROOT/scripts/ExportOptions.plist" > "$EXPORT_PLIST"
fi

echo "▸ Generating project"
xcodegen generate

echo "▸ Archiving (Release, Hardened Runtime)"
xcodebuild -project PhotoRestore.xcodeproj -scheme PhotoRestore -configuration Release \
  -archivePath "$BUILD/PhotoRestore.xcarchive" \
  archive

echo "▸ Exporting Developer ID app"
xcodebuild -exportArchive \
  -archivePath "$BUILD/PhotoRestore.xcarchive" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$BUILD/export"

APP="$BUILD/export/Photo Restore.app"

echo "▸ Notarizing"
ditto -c -k --keepParent "$APP" "$BUILD/PhotoRestore.zip"
xcrun notarytool submit "$BUILD/PhotoRestore.zip" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling"
xcrun stapler staple "$APP"

echo "▸ Building .dmg"
DMG_SRC="$BUILD/dmg"; mkdir -p "$DMG_SRC"
cp -R "$APP" "$DMG_SRC/"
ln -s /Applications "$DMG_SRC/Applications"
hdiutil create -volname "Photo Restore" -srcfolder "$DMG_SRC" -ov -format UDZO "$BUILD/PhotoRestore.dmg"
xcrun stapler staple "$BUILD/PhotoRestore.dmg"

echo "✓ $BUILD/PhotoRestore.dmg — notarized, stapled, ready to distribute"
