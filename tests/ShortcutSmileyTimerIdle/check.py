#!/usr/bin/env python3
"""P1 behavior lock: ShortcutSmileyView 60 Hz timer idle-stops and skips true
no-ops. Hidden/detached/settled ticks must stopFrames; identical presentation
fingerprints must skip needsDisplay. Active keyframe motion still dirties.
Do not change shortcut binding behavior.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/ShortcutSmileyView.swift").read_text()

assert "func presentationFingerprint(seconds: Double, size: CGSize) -> Int" in source, \
    "artwork must expose a presentation fingerprint for hold-region skips"
assert "private func stopFrames()" in source and "private func startFrames()" in source, \
    "cue must use startFrames/stopFrames idle-stop helpers"
assert "fingerprint != lastDisplayFingerprint" in source, \
    "identical presentation must skip needsDisplay"
assert "leftRestingPose" in source, \
    "settle must require leaving the end-frame pose before treating a return as settle"
assert "leftRestingPose && fingerprint == endFingerprint" in source, \
    "return to end-frame pose after motion must idle-stop"
assert "elapsed >= artwork.duration" in source, \
    "duration remain an idle-stop bound"
assert "!isHidden" in source, \
    "hidden cues must not keep the timer armed"
assert "invalidateDisplay()" in source, \
    "dirties must write needsDisplay through invalidateDisplay"

tick = re.search(r"private func tick\(_ timer: Timer\) \{(?P<body>.*?)\n    \}", source, re.S)
assert tick, "ShortcutSmileyView.tick not found"
body = tick.group("body")
assert "needsDisplay = true" not in body, \
    "tick must not unconditionally dirty; go through fingerprint / invalidateDisplay"
assert "stopFrames()" in body, "tick must idle-stop"
assert "presentationFingerprint" in body, "tick must sample the presentation fingerprint"

print("ShortcutSmileyTimerIdle: fingerprint skip + hidden/settled idle-stop locked.")
