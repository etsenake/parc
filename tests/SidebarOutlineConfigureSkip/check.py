#!/usr/bin/env python3
"""P0-B leftover behavior lock: SidebarOutlineRow.configure skips setContent and
needsLayout when the configured content fingerprint already matches. Membership,
appearance, and size deltas still configure and dirty layout. Toggle still
refreshes on the skip path so AX disclosing keeps the entry's current closure.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
outline = (root / "Sources/ParcApp/SidebarOutline.swift").read_text()
skip = (root / "Sources/ParcCore/SidebarOutlineConfigureSkip.swift").read_text()
unit = (root / "tests/SidebarOutlineConfigureSkipTests.swift").read_text()

assert "struct SidebarOutlineConfigureFingerprint: Equatable" in skip, \
    "SidebarOutlineConfigureFingerprint missing"
assert "enum SidebarOutlineConfigureSkip" in skip, \
    "SidebarOutlineConfigureSkip helper missing"
assert "static func shouldSkip(" in skip, "shouldSkip predicate missing"
assert "previous == next" in skip, "shouldSkip must require an identical fingerprint"
for needle in (
    "contentIdentity",
    "cellHeight",
    "spanMinY",
    "spanHeight",
    "level",
    "isHidden",
    "expanded",
    "isItem",
    "disclosesNothing",
    "disclosedByKey",
):
    assert needle in skip, f"fingerprint no longer includes {needle}"

assert "private var lastConfigureFingerprint: SidebarOutlineConfigureFingerprint?" in outline, \
    "missing last-applied configure fingerprint on SidebarOutlineRow"

configure = re.search(
    r"fileprivate func configure\(_ entry: SidebarOutlineEntry\) \{(?P<body>.*?)\n    \}\n\n"
    r"    override func layout\(\) \{",
    outline, re.S)
assert configure, "SidebarOutlineRow.configure not found"
body = configure.group("body")

assert "SidebarOutlineConfigureSkip.shouldSkip(" in body, \
    "configure must gate on SidebarOutlineConfigureSkip.shouldSkip"
assert "lastConfigureFingerprint = fingerprint" in body, \
    "successful configure must record the applied fingerprint"
assert body.index("shouldSkip(") < body.index("cell.setContent("), \
    "fingerprint skip must precede setContent"
assert body.index("shouldSkip(") < body.index("needsLayout = true"), \
    "fingerprint skip must precede needsLayout"
assert "toggle = entry.toggle" in body, \
    "configure must still refresh toggle"
# Skip path refreshes toggle then returns before setContent/needsLayout.
skip_arm = body.split("cell.setContent(")[0]
assert "toggle = entry.toggle" in skip_arm, \
    "identical fingerprint must still refresh toggle before returning"
assert "return" in skip_arm, \
    "identical fingerprint must return before setContent/needsLayout"

assert "cell.setContent(entry.content)" in body, \
    "changed content must still call setContent"
assert "needsLayout = true" in body, \
    "membership/appearance/size changes must still dirty needsLayout"

assert "SidebarOutlineConfigureSkip.shouldSkip" in unit or "Skip.shouldSkip" in unit, \
    "SidebarOutlineConfigureSkipTests must exercise production shouldSkip"
assert "Identical configured content fingerprint is a true no-op skip" in unit, \
    "unit must lock the identical-fingerprint no-op"
assert "Content identity change must still setContent/needsLayout" in unit, \
    "unit must lock content identity changes"
assert "Size (cellHeight) change must still layout" in unit, \
    "unit must lock size changes"
assert "Appearance (isHidden) change must still layout" in unit, \
    "unit must lock appearance changes"
assert "Membership (disclosedByKey) change must still layout" in unit, \
    "unit must lock membership changes"

print("SidebarOutlineConfigureSkip: identical content fingerprint skips "
      "setContent/needsLayout; membership/appearance/size still layout")
