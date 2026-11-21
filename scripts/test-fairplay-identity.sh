#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/FairPlayIdentity/managed_media_source.mjs"
  node "$repo_root/tests/FairPlayIdentity/webkit_media_keys.mjs"
  node "$repo_root/tests/FairPlayIdentity/safari_media_keys.mjs"
  node "$repo_root/tests/FairPlayIdentity/webkit_presentation.mjs"
  node "$repo_root/tests/FairPlayIdentity/webkit_playback_target.mjs"
else
  echo "managed media source, webkit media keys, safari media keys, webkit presentation, webkit playback target: skipped (node not installed)"
fi
