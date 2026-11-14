#!/bin/bash
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd)"
prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
if ! command -v brew >/dev/null 2>&1 && [ -x "$prefix/bin/brew" ]; then
  eval "$("$prefix/bin/brew" shellenv)"
fi
launch() {
  local python="$1"
  shift
  if [ -x "$python" ] && "$python" -c 'import sys; raise SystemExit(sys.version_info < (3, 12))' >/dev/null 2>&1; then
    exec "$python" "$here/release.py" "$@"
  fi
}
for name in python3 python3.14 python3.13 python3.12; do
  launch "$(command -v "$name" || true)" "$@"
done
shopt -s nullglob
for python in "$prefix"/bin/python3.[0-9][0-9] "$prefix"/opt/python@3.*/libexec/bin/python3; do
  launch "$python" "$@"
done
echo "error: production releases need Python 3.12 or later and none was found; install it once with: brew install python@3.13" >&2
exit 1
