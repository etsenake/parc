#!/usr/bin/env python3
"""P2 behavior lock: ThemeAppearanceButton 60 Hz timer idle-stops and skips true
no-ops. Hidden/detached/unselected ticks must stopFrames; identical presentation
fingerprints must skip needsDisplay. Active keyframe motion still dirties.
Do not change appearance selection behavior.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/SpaceThemeEditorView.swift").read_text()

assert "func presentationFingerprint(seconds: Double, size: CGSize) -> Int" in source, \
    "animation must expose a presentation fingerprint for hold-region skips"
assert "private func stopFrames()" in source and "private func startFrames()" in source, \
    "cue must use startFrames/stopFrames idle-stop helpers"
assert "fingerprint != lastDisplayFingerprint" in source, \
    "identical presentation must skip needsDisplay"
assert "!isHiddenOrHasHiddenAncestor" in source, \
    "hidden cues (including ancestor hides) must not keep the timer armed"
assert "viewDidHide()" in source and "viewDidUnhide()" in source, \
    "hide/unhide must re-evaluate playback"
assert "invalidateDisplay()" in source, \
    "dirties must write needsDisplay through invalidateDisplay"
assert "shouldPlay" in source, \
    "playback gate must centralize selected/visible/attached/Reduce Motion"

tick = re.search(r"private func tick\(_ timer: Timer\) \{(?P<body>.*?)\n    \}", source, re.S)
assert tick, "ThemeAppearanceButton.tick not found"
body = tick.group("body")
assert "needsDisplay = true" not in body, \
    "tick must not unconditionally dirty; go through fingerprint / invalidateDisplay"
assert "stopFrames()" in body, "tick must idle-stop when shouldPlay fails"
assert "presentationFingerprint" in body, "tick must sample the presentation fingerprint"
assert "self.needsDisplay = true" not in source.split("private func tick(_ timer: Timer)")[1].split("private func startFrames()")[0], \
    "tick body must not write needsDisplay directly"

print("ThemeAppearanceTimerIdle: fingerprint skip + hidden/settled idle-stop locked.")
