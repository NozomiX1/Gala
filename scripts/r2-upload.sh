#!/bin/bash
# Uploads one file to Cloudflare R2 using macOS curl's built-in AWS SigV4 support.
# Usage: scripts/r2-upload.sh <local-file> <object-key> [cache-control] [content-type]
# Required env: R2_ENDPOINT (e.g. https://<account-id>.r2.cloudflarestorage.com),
#               R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY
# Optional env: R2_BUCKET (defaults to gala-downloads)
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <local-file> <object-key> [cache-control] [content-type]" >&2
  exit 1
fi

LOCAL_FILE="$1"
OBJECT_KEY="${2#/}"
CACHE_CONTROL="${3:-public, max-age=31536000, immutable}"
CONTENT_TYPE="${4:-application/octet-stream}"

[ -f "$LOCAL_FILE" ] || { echo "error: file not found: $LOCAL_FILE" >&2; exit 1; }
: "${R2_ENDPOINT:?R2_ENDPOINT is required (e.g. https://<account-id>.r2.cloudflarestorage.com)}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is required}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is required}"
R2_BUCKET="${R2_BUCKET:-gala-downloads}"

ENDPOINT="${R2_ENDPOINT%/}"
# Accept either the account root endpoint or one that already ends with /<bucket>.
case "$ENDPOINT" in
  */"$R2_BUCKET") BASE_URL="$ENDPOINT" ;;
  *) BASE_URL="$ENDPOINT/$R2_BUCKET" ;;
esac

TARGET_URL="$BASE_URL/$OBJECT_KEY"
echo "Uploading $LOCAL_FILE -> $OBJECT_KEY"

# Pass credentials via stdin config so secrets never appear in process arguments.
printf 'user = "%s:%s"\n' "$R2_ACCESS_KEY_ID" "$R2_SECRET_ACCESS_KEY" | \
  curl --fail-with-body --show-error --silent \
    --aws-sigv4 "aws:amz:auto:s3" \
    --config - \
    -X PUT \
    -T "$LOCAL_FILE" \
    -H "Content-Type: $CONTENT_TYPE" \
    -H "Cache-Control: $CACHE_CONTROL" \
    "$TARGET_URL"
