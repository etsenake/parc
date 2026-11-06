#!/usr/bin/env python3
"""P1-AP behavior lock: CaptureElementLens 60 Hz timer idle-stops and skips
true no-ops. Identical settled focus (inset == focusRect, !isAnimating) must
return before motion.target / startFrames; ticks must skip path rebuild when
motion.rect is unchanged, then stopFrames when !motion.isAnimating. Do not
drop frames that change presentation.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/PageCaptureController.swift").read_text()

lens = re.search(
    r"private final class CaptureElementLens: CaptureFlippedView \{(?P<body>.*?)\n    static func cameraCursor",
    source, re.S)
assert lens, "CaptureElementLens not found"
body = lens.group("body")

assert "if inset == focusRect, !motion.isAnimating" in body, \
    "identical settled focus must short-circuit before motion.target"
assert "stopFrames()" in body and "startFrames()" in body, \
    "lens must use startFrames/stopFrames idle-stop helpers"
assert "applyMotionPresentation()" in body, \
    "ticks/setTarget must go through applyMotionPresentation"
assert "guard next != focusRect else { return }" in body, \
    "identical motion.rect must skip path rebuild"
assert "if motion.isAnimating { startFrames() } else { stopFrames() }" in body, \
    "setTarget must arm timer only while animating"
assert "if !motion.isAnimating { stopFrames() }" in body, \
    "tick must idle-stop when springs settle"

set_target = re.search(r"func setTarget\(_ rect: NSRect\?, animated: Bool\) \{(?P<body>.*?)\n    \}", body, re.S)
assert set_target, "CaptureElementLens.setTarget not found"
st = set_target.group("body")
assert "if inset == focusRect, !motion.isAnimating" in st, \
    "identical settled skip must live in setTarget"
assert st.index("if inset == focusRect, !motion.isAnimating") < st.index("motion.target("), \
    "identical settled skip must precede motion.target"
assert "startFrames()" in st and "stopFrames()" in st, \
    "setTarget must start/stop frames from isAnimating"

tick = re.search(r"private func tick\(\) \{(?P<body>.*?)\n    \}", body, re.S)
assert tick, "CaptureElementLens.tick not found"
tb = tick.group("body")
assert "applyMotionPresentation()" in tb, "tick must apply presentation"
assert "if !motion.isAnimating { stopFrames() }" in tb, "tick must idle-stop"
assert "updatePaths()" not in tb, \
    "tick must not call updatePaths directly (would rebuild on identical rect)"

print("CaptureLensTimerIdle: identical settled focus skips re-arm; "
      "unchanged rect skips paths; timer idle-stops when !isAnimating.")
