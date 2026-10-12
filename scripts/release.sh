#!/bin/bash
# Builds Gala.app in Release and packages it as dist/Gala.dmg.
# The version comes from project.yml; nothing else needs editing for a release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"$/\1/p' project.yml)
[ -n "$VERSION" ] || { echo "error: MARKETING_VERSION not found in project.yml" >&2; exit 1; }

xcodegen generate
xcodebuild -project Gala.xcodeproj -scheme Gala -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build build

APP=build/Build/Products/Release/Gala.app
# The update check compares against the bundle version, so a wrong one ships a broken updater.
BUILT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[ "$BUILT" = "$VERSION" ] || { echo "error: built app reports version $BUILT, expected $VERSION" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
# shortcut: these hdiutil flags are deprecated as of macOS 27; move to `diskutil image create` once a build machine drops them.
hdiutil create -volname "Gala $VERSION" -srcfolder "$STAGE" -ov -format UDZO dist/Gala.dmg
echo "dist/Gala.dmg (Gala $VERSION)"
