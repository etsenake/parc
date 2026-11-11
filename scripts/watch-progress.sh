#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
interval="${1:-5}"

status() {
  echo "=== $(date '+%H:%M:%S') ==="
  ps -eo etime,pcpu,command 2>/dev/null \
    | rg 'engine-source\.py (build|sync)|siso ninja|swift-driver|swiftc |scripts/build\.py' \
    | rg -v 'rg |watch-progress' \
    || echo "(no active engine/package process)"
  echo
  if [[ -f "$root/build/engine-build.log" ]]; then
    echo "--- build/engine-build.log (last 5) ---"
    tail -n 5 "$root/build/engine-build.log" 2>/dev/null || true
    echo
  fi
  latest=""
  for dir in "$root"/build/local-* "$HOME"/ParcBuild/runs/local-*; do
    [[ -d "$dir" ]] || continue
    latest="$dir"
  done
  if [[ -n "$latest" ]]; then
    echo "--- run: $latest ---"
    du -sh "$latest"/.parc-package-* 2>/dev/null || true
    if [[ -d "$latest/development/Parc.app" ]]; then
      echo "Parc.app: READY"
    else
      echo "Parc.app: not published yet"
    fi
    for log in seal.log package.log; do
      if [[ -s "$latest/$log" ]]; then
        echo "--- $log (last 5) ---"
        tail -n 5 "$latest/$log"
      fi
    done
  fi
}

while true; do
  clear
  status
  sleep "$interval"
done
