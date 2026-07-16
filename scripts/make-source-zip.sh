#!/usr/bin/env bash
# Create a source zip suitable for "download and ./install.sh"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/grok-build-multi-vendor-source.zip}"
mkdir -p "$(dirname "$OUT")"
cd "$ROOT"
rm -f "$OUT"
# Prefer git archive if clean enough; fall back to zip excluding target
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git archive --format=zip --prefix=grok-build-multi-vendor/ -o "$OUT" HEAD
else
  zip -r "$OUT" . \
    -x './target/*' \
    -x './.git/*' \
    -x '*together_api_key*' \
    -x './dist/*'
fi
echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
