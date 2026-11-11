#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/NoteEditorViewController.swift").read_text()
unit = (root / "tests/NoteEditorChromeLayoutSkipTests.swift").read_text()

assert "struct NoteEditorChromeFingerprint: Equatable" in source, \
    "NoteEditorChromeFingerprint missing"
assert "enum NoteEditorChromeLayoutSkip" in source, \
    "NoteEditorChromeLayoutSkip helper missing"
assert "static func shouldSkip(" in source, \
    "shouldSkip predicate missing"
assert "previous == next" in source, \
    "shouldSkip must require an identical fingerprint"
assert "private var lastAppliedChromeFingerprint: NoteEditorChromeFingerprint?" in source, \
    "missing last-applied note chrome fingerprint"

layout = re.search(
    r"private func layoutDocument\(\) \{(?P<body>.*?)\n    \}\n    func textDidBeginEditing",
    source, re.S)
assert layout, "layoutDocument not found"
body = layout.group("body")
assert "let fingerprint = NoteEditorChromeFingerprint(" in body, \
    "layoutDocument must build the chrome geometry fingerprint before work"
assert "NoteEditorChromeLayoutSkip.shouldSkip(" in body, \
    "layoutDocument must gate on NoteEditorChromeLayoutSkip.shouldSkip"
assert "reflowIfHeightChanged" in body, \
    "matching chrome must still allow document height reflow while typing"
assert "chromeLayoutCount += 1" in body, \
    "full chrome passes must still count layoutDocument work"
assert body.index("shouldSkip(") < body.index("chromeLayoutCount += 1"), \
    "fingerprint skip must precede chromeLayoutCount / full chrome writes"
assert "lastAppliedChromeFingerprint = fingerprint" in body, \
    "successful chrome passes must record the applied fingerprint"
assert "NoteAccessibility.wireKeyLoop" in body, \
    "full chrome pass must still wire the key loop"
assert body.index("shouldSkip(") < body.index("NoteAccessibility.wireKeyLoop"), \
    "true no-op must skip key-loop rewiring"

changed = re.search(
    r"func textDidChange\(_ notification: Notification\) \{(?P<body>.*?)\n    \}\n    func textViewDidChangeSelection",
    source, re.S)
assert changed, "textDidChange not found"
change_body = changed.group("body")
assert "view.needsLayout = true" not in change_body, \
    "textDidChange must not set needsLayout every keystroke"
assert "layoutDocument()" in change_body, \
    "textDidChange must still layout via layoutDocument (fingerprint skip + reflow)"

assert "previous == next" in unit, \
    "NoteEditorChromeLayoutSkipTests must mirror the production shouldSkip formula"
assert "struct NoteEditorChromeFingerprint: Equatable" in unit, \
    "unit must mirror NoteEditorChromeFingerprint"
assert "First layoutDocument apply must run full chrome" in unit, \
    "unit must lock the nil-previous first-apply path"
assert "Identical note chrome geometry is a true no-op skip" in unit, \
    "unit must lock the identical-fingerprint no-op"

print("NoteEditorChromeLayoutSkip: identical chrome geometry returns early; "
      "typing skips needsLayout; bounds/error still layout")
