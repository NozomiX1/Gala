#!/bin/bash
# Builds Gala.app in Release and writes three files to dist/:
#   Gala.dmg     the installer
#   Gala.md      this version's section of CHANGELOG.md
#   appcast.xml  the Sparkle update feed entry, signed with the update key
# The version comes from project.yml; nothing else needs editing for a release.
# The update key is read from $SPARKLE_PRIVATE_KEY if set, otherwise from the login keychain (account "gala").
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

rm -rf dist
mkdir -p dist
# shortcut: these hdiutil flags are deprecated as of macOS 27; move to `diskutil image create` once a build machine drops them.
hdiutil create -volname "Gala $VERSION" -srcfolder "$STAGE" -ov -format UDZO dist/Gala.dmg

awk -v v="$VERSION" 'index($0, "## [" v "]") == 1 { on = 1; next } /^## \[/ { on = 0 } on' CHANGELOG.md > dist/Gala.md
# The update window shows this file to users who read Chinese.
grep -q '^### 更新摘要' dist/Gala.md || { echo "CHANGELOG.md: the $VERSION section has no '### 更新摘要'" >&2; exit 1; }

SPARKLE_BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin
FEED_ARGS=(--embed-release-notes --download-url-prefix "https://github.com/NozomiX1/Gala/releases/download/v$VERSION/" dist)
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - "${FEED_ARGS[@]}"
else
  "$SPARKLE_BIN/generate_appcast" --account gala "${FEED_ARGS[@]}"
fi
# An unsigned feed entry would be rejected by every installed copy, so fail here instead.
grep -q 'sparkle:edSignature=' dist/appcast.xml || { echo "error: appcast.xml has no update signature" >&2; exit 1; }

echo "dist/Gala.dmg, dist/appcast.xml (Gala $VERSION)"
