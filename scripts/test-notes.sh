#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
bash "$repo_root/scripts/test-notes-editor.sh" "$@"
