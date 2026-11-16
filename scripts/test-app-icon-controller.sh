#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
PYTHONDONTWRITEBYTECODE=1 python3 - "$check_dir" <<'PY'
from pathlib import Path
import shutil
import sys
sys.path.insert(0, "scripts")
from app_icons import package_app_icons
root = Path(sys.argv[1])
for name in ("source", "packaged"):
    shutil.copytree("Resources/AppIcons", root / name / "AppIcons")
package_app_icons(root / "packaged")
PY
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -whole-module-optimization -parse-as-library -target arm64-apple-macos13.0 \
    Sources/ParcApp/AppIconController.swift tests/AppIcons/AppIconControllerTests.swift -o "$check_dir/check"
"$check_dir/check" "$check_dir"
