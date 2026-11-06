#!/bin/bash
# One command for the complete, resumable Parc production release.
set -euo pipefail
exec python3 "$(cd -- "$(dirname -- "$0")" && pwd)/release.py" "$@"
