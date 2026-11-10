#!/usr/bin/env python3
"""Every Parc button shows the pointing hand (PointingHand.swift).

Source check only. A new AppKit button or clickable control, a SwiftUI button
with a built-in style or a custom ButtonStyle fails here until it shows the
hand or is listed below with the reason it keeps another cursor.
"""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"

CONTROLS = "NSButton|NSPopUpButton|NSSwitch|NSSegmentedControl|NSColorWell"
KEEP_CURSOR = {
    "CommandBarScopeHint": "a hint with no action",
    "FavoriteTile": "a tab, which keeps the arrow like the sidebar's rows",
    "NoteFormatButton": "a row of the note format menus",
    "PictureInPictureBarControl": "its own cursor rect: the PiP panel is rarely key",
    "SidebarPlusRowButton": "a menu row",
    "ThemeIconButton": "the hand, enabled or not",
    "ThemeAppearanceButton": "the hand, enabled or not",
    "UpdateBannerKeyStop": "its own cursor rect over the SwiftUI control it stands in for",
}
# The bookmark picker keeps the arrow over its rows on purpose.
PLAIN_BUTTON_FILES = {"OnboardingImportBookmarksPicker.swift"}
# The update banners' key stops show the hand over these styles' buttons.
STYLES_SHOWN_BY_KEY_STOPS = {("UpdateReadyCard.swift", "Bare"), ("UpdateReadyCard.swift", "Style")}

failures = []
for path in sorted(app.glob("*.swift")):
    if path.name == "PointingHand.swift":
        continue
    text = path.read_text()
    lines = text.splitlines()
    for match in re.finditer(rf"class (\w+): ({CONTROLS})\b", text):
        if match.group(1) not in KEEP_CURSOR:
            failures.append(f"{path.name}: {match.group(1)} should subclass PointingHand{match.group(2)[2:]}")
    for match in re.finditer(rf"(?<![\w.])({CONTROLS})\(", text):
        line = text.count("\n", 0, match.start()) + 1
        failures.append(f"{path.name}:{line}: use PointingHand{match.group(1)[2:]} instead of {match.group(1)}")
    if path.name not in PLAIN_BUTTON_FILES:
        for index, line in enumerate(lines):
            if re.search(r"\.buttonStyle\(\.\w+\)", line):
                around = "\n".join(lines[max(0, index - 20):index + 6])
                if "pointingHandCursor()" not in around and "updateBannerKeyStop(" not in around:
                    failures.append(f"{path.name}:{index + 1}: give this button .pointingHandCursor()")
    for match in re.finditer(r"^( *)(?:@MainActor )?(?:private |fileprivate )?struct (\w+): [^{]*\bButtonStyle\b[^{]*\{$", text, re.M):
        indent, name = match.groups()
        end = text.find(f"\n{indent}}}", match.end())
        if (path.name, name) not in STYLES_SHOWN_BY_KEY_STOPS and "pointingHandCursor()" not in text[match.end():end]:
            failures.append(f"{path.name}: {name} should end its body with .pointingHandCursor()")

if failures:
    sys.exit("Pointing hand:\n  " + "\n  ".join(failures))
print("PASS: every Parc button shows the pointing hand")
