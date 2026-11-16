#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-page-tool-appearance.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
python3 - "$repo_root" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
page = (root / "Engine/ParcNative/native_page_tool_appearance.h").read_text()
swift = (root / "tests/PageToolAppearance/PageToolAppearance.swift").read_text()

def const(src, name):
    match = re.search(rf"{name}\s*=\s*([^;]+);", src)
    if not match:
        raise SystemExit(f"missing {name}")
    return match.group(1).strip()

def swift_num(enum_name, name):
    block = re.search(rf"enum {enum_name} \{{(.*?)\n    \}}", swift, re.S)
    if not block:
        raise SystemExit(f"missing Swift enum {enum_name}")
    match = re.search(rf"static let {name}: CGFloat = ([0-9.]+)", block.group(1))
    if not match:
        raise SystemExit(f"missing Swift {enum_name}.{name}")
    return match.group(1)

pairs = [
    ("kPCPageToolPrivateDecisionWidth", "DataDialog", "decisionWidth", page),
    ("kPCPageToolPrivateDecisionHeight", "DataDialog", "decisionHeight", page),
]
for native, enum_name, swift_name, src in pairs:
    native_val = const(src, native)
    swift_val = swift_num(enum_name, swift_name)
    if float(native_val) != float(swift_val):
        raise SystemExit(f"{native} {native_val} != Swift {enum_name}.{swift_name} {swift_val}")

reader = (root / "Engine/ParcNative/native_reader.cc").read_text()
if 'kPCPageToolReaderScheme' not in reader:
    raise SystemExit("native_reader.cc must use kPCPageToolReaderScheme")
file_dialog = (root / "Engine/ParcNative/file_dialog.mm").read_text()
for token in ('IDC_PRINT', 'IDC_SAVE_PAGE'):
    if token not in file_dialog:
        raise SystemExit(f"file_dialog.mm missing {token}")
if 'chrome-distiller' not in page:
    raise SystemExit("native_page_tool_appearance.h missing chrome-distiller")
print("Page tool appearance: native/Swift metrics pinned")
PY
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/tests/PageToolAppearance/PageToolAppearance.swift" \
  "$repo_root/tests/PageToolAppearance/Tests.swift" \
  -o "$check_dir/page-tool-appearance"
"$check_dir/page-tool-appearance"
