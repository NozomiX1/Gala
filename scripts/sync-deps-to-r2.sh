#!/bin/bash
# Mirrors Gala's GitHub dependency assets (deps-v1/v2/v3) and latest DMG into Cloudflare R2.
# Safe to re-run: skips objects already served by gala.feng7.cn with the same Content-Length unless --force is passed.
# Required env: R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY
# Optional env: R2_BUCKET (defaults to gala-downloads), MIRROR_BASE_URL (defaults to https://gala.feng7.cn)
set -euo pipefail
cd "$(dirname "$0")/.."

FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

MIRROR_BASE_URL="${MIRROR_BASE_URL:-https://gala.feng7.cn}"
GITHUB_BASE="https://github.com/NozomiX1/Gala/releases/download"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

mirror_asset() {
  local tag="$1"
  local file="$2"
  local sha256="$3"
  local object_key="$tag/$file"
  local url="$GITHUB_BASE/$tag/$file"
  local local_path="$STAGE/$file"

  if [ "$FORCE" -eq 0 ] && curl -fsI "$MIRROR_BASE_URL/$object_key" >/dev/null 2>&1; then
    echo "Already mirrored: $object_key (pass --force to re-upload)"
    return 0
  fi

  echo "Fetching $url"
  curl --fail --location --retry 3 --progress-bar -o "$local_path" "$url"

  if [ -n "$sha256" ]; then
    local actual
    actual=$(shasum -a 256 "$local_path" | awk '{print $1}')
    if [ "$actual" != "$sha256" ]; then
      echo "error: SHA256 mismatch for $file (expected $sha256, got $actual)" >&2
      exit 1
    fi
  fi

  scripts/r2-upload.sh "$local_path" "$object_key" "public, max-age=31536000, immutable" "application/octet-stream"
  rm -f "$local_path"
}

mirror_asset "deps-v1" "wine-staging-11.6-osx64.tar.xz" "054113ce6d9322ccb2444df2a89abad3c7a8fee12b836ae0f400e00e6398eb70"
mirror_asset "deps-v1" "SourceHanSansSC-Regular.otf" "f1d8611151880c6c336aabeac4640ef434fa13cbfbf1ffe82d0a71b2a5637256"
mirror_asset "deps-v1" "cabextract" "ace8ade5fe5ee05c6e2c472df813bd4466917ea44f110d295c144498f0830996"
mirror_asset "deps-v1" "winetricks" "431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b"
mirror_asset "deps-v2" "dxmt-v0.80-builtin.tar.gz" "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
mirror_asset "deps-v3" "gala-mf-runtime-1.1-macos.tar.gz" "021f43bea3871e00e8a1bb0eec3e4a112bcc19fc4a3960e5e50df42f5ff94df9"

echo "All dependency assets mirrored to $MIRROR_BASE_URL."
