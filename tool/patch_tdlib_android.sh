#!/usr/bin/env bash
# Re-apply AGP namespace fix after `flutter pub get` (tdlib 1.6.0 omits it).
set -euo pipefail
GRADLE="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/tdlib-1.6.0/android/build.gradle"
if [[ ! -f "$GRADLE" ]]; then
  echo "tdlib android build.gradle not found at $GRADLE"
  exit 0
fi
if grep -q "namespace 'org.naji.td.tdlib'" "$GRADLE"; then
  echo "tdlib namespace already set"
  exit 0
fi
python3 - <<'PY'
from pathlib import Path
import os
path = Path(os.path.expanduser(os.environ.get("PUB_CACHE", "~/.pub-cache"))) / "hosted/pub.dev/tdlib-1.6.0/android/build.gradle"
text = path.read_text()
if "namespace 'org.naji.td.tdlib'" in text:
    raise SystemExit(0)
old = "android {\n    compileSdkVersion 31"
new = "android {\n    namespace 'org.naji.td.tdlib'\n    compileSdkVersion 35"
if old not in text:
    # already partially patched or different version
    if "namespace" not in text:
        text = text.replace("android {", "android {\n    namespace 'org.naji.td.tdlib'", 1)
        path.write_text(text)
        print("patched namespace (fallback)")
    raise SystemExit(0)
text = text.replace(old, new, 1).replace("minSdkVersion 16", "minSdkVersion 21", 1)
path.write_text(text)
print(f"patched {path}")
PY
