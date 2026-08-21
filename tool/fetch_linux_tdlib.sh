#!/usr/bin/env bash
# Downloads a prebuilt libtdjson.so for Linux x86_64 (glibc) into linux/libs/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/linux/libs"
mkdir -p "$OUT"
VER="${1:-0.1008033.1}"
URL="https://cdn.jsdelivr.net/npm/@prebuilt-tdlib/linux-x64-glibc@${VER}/libtdjson.so"
echo "Downloading $URL ..."
curl -fL -C - --retry 40 --retry-delay 2 --connect-timeout 30 --max-time 0 \
  -o "$OUT/libtdjson.so" "$URL"
SIZE="$(stat -c%s "$OUT/libtdjson.so")"
if [[ "$SIZE" -lt 10000000 ]]; then
  echo "Download looks incomplete ($SIZE bytes)" >&2
  exit 1
fi
echo "Installed $OUT/libtdjson.so ($(du -h "$OUT/libtdjson.so" | cut -f1))"

# Also copy into an existing debug bundle if present (avoids full rebuild).
BUNDLE_LIB="$ROOT/build/linux/x64/debug/bundle/lib"
if [[ -d "$BUNDLE_LIB" ]]; then
  cp -f "$OUT/libtdjson.so" "$BUNDLE_LIB/libtdjson.so"
  echo "Also copied to $BUNDLE_LIB/libtdjson.so"
fi
