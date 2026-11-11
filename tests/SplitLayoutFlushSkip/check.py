#!/usr/bin/env python3
"""Behavior lock: split drop reserve and divider-drag skip only true no-ops.

Drop clear/end / applyFrames still flush when geometry moves or the subtree is
dirty. Divider drag applies frames on the first move and whenever factors
change; later identical-factor moves skip applyFrames. Snap haptics stay
outside that gate. configure still enters applySavedFrames on identical
publishes (dirty flush / clearLayoutAnimation). finishDividerResize still
invokes commit when moved (window-command side effects retained).
InteractivePaneEdit's 50ms external-drop fallback timer stays.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp" / "ParcSplitView.swift"
core = root / "Sources/ParcCore" / "SplitLayoutFlushSkip.swift"
split = app.read_text()
skip = core.read_text()

assert "enum SplitLayoutFlushSkip" in skip, "SplitLayoutFlushSkip helper missing"
assert "static func shouldFlush(" in skip, "shouldFlush predicate missing"
assert "frameChanged || needsLayout || subtreeNeedsLayout" in skip, \
    "shouldFlush must require a moved frame or dirty tree"
assert "static func shouldApplyDividerMove(factorsChanged: Bool, alreadyMoved: Bool)" in skip, \
    "shouldApplyDividerMove predicate missing"
assert "factorsChanged || !alreadyMoved" in skip, \
    "shouldApplyDividerMove must materialize the first move"
assert "shouldRefreshDividerChrome" not in skip, \
    "divider chrome/hover rewrite is not a true no-op skip"
assert "shouldCommitResize" not in skip, \
    "end-of-drag commit skip is not a true no-op of window-command effects"

assert "fileprivate func applyDropReserveLayout()" in split, \
    "applyDropReserveLayout helper missing"
assert split.count("owner.applyDropReserveLayout()") == 3, \
    "proposal / clear / end must all use applyDropReserveLayout"
assert "owner.updateContainerMinimum(); owner.applySavedFrames(); owner.layoutSubtreeIfNeeded()" not in split, \
    "unconditional drop-path applySavedFrames + layoutSubtree must stay gone"

helper = re.search(
    r"fileprivate func applyDropReserveLayout\(\) \{(?P<body>.*?)\n    \}\n",
    split, re.S)
assert helper, "applyDropReserveLayout body not found"
body = helper.group("body")
assert "updateContainerMinimum()" in body and "applySavedFrames()" in body, \
    "applyDropReserveLayout must still update minimum and apply frames"
assert "SplitLayoutFlushSkip.shouldFlush(" in body, \
    "applyDropReserveLayout must gate layoutSubtree on shouldFlush"
assert "layoutSubtreeIfNeeded()" in body, \
    "applyDropReserveLayout must still flush when shouldFlush is true"

apply = re.search(
    r"private func applyFrames\(factors proposedFactors: \[Double\]\) \{(?P<body>.*?)\n    \}\n    private func divider",
    split, re.S)
assert apply, "applyFrames not found"
af = apply.group("body")
assert "pane.needsLayout = true\n            pane.layoutSubtreeIfNeeded()" not in af, \
    "applyFrames must not unconditionally dirty + layout every pane"
assert "if frameChanged { pane.needsLayout = true }" in af, \
    "applyFrames must dirty a pane only when its frame moved"
assert "SplitLayoutFlushSkip.shouldFlush(" in af, \
    "applyFrames must gate pane layoutSubtree on shouldFlush"
assert "if anyFrameChanged { needsDisplay = true }" in af, \
    "applyFrames must skip needsDisplay when no pane frame moved"
assert "synchronizeDividerPresentation(animated: false)" in af, \
    "applyFrames must still refresh divider chrome (hover/cursor contract)"
assert "updateTrackingAreas()" in af, \
    "applyFrames must still refresh tracking/hover"

configure = re.search(
    r"func configure\(orientation: SplitOrientation, factors: \[Double\]\) \{(?P<body>.*?)\n    \}\n",
    split, re.S)
assert configure, "configure not found"
cf = configure.group("body")
assert "else if !isTrackingDivider { applySavedFrames() }" in cf, \
    "configure must still applySavedFrames on identical publishes"
assert "guard changed else { return }" not in cf, \
    "configure must not skip applySavedFrames on !changed"

update = re.search(
    r"func updateDividerResize\(at point: NSPoint, velocity: CGFloat\) \{(?P<body>.*?)\n    \}\n",
    split, re.S)
assert update, "updateDividerResize not found"
up = update.group("body")
assert "SplitLayoutFlushSkip.shouldApplyDividerMove(" in up, \
    "updateDividerResize must gate applyFrames on shouldApplyDividerMove"
assert "current.moved = true\n        resize = current\n        applyFrames(factors: current.factors)" not in up, \
    "updateDividerResize must not applyFrames on every pan move"
assert "if transitioned { onSnapTransition() }" in up, \
    "snap haptic must stay outside the applyFrames gate"

finish = re.search(
    r"func finishDividerResize\(commit: Bool\) \{(?P<body>.*?)\n    \}\n",
    split, re.S)
assert finish, "finishDividerResize not found"
fn = finish.group("body")
assert "if commit, valid, current.moved, current.commit(current.factors) { savedFactors = current.factors }" in fn, \
    "finishDividerResize must still commit when moved (window-command effects)"
assert "shouldCommitResize" not in fn, \
    "finishDividerResize must not gate away performWindowCommand side effects"

minimum = re.search(
    r"private func updateContainerMinimum\(\) \{(?P<body>.*?)\n    \}\n\n    fileprivate func applyDropReserveLayout\(\) \{",
    split, re.S)
assert minimum, "updateContainerMinimum not found"
mn = minimum.group("body")
assert "SplitLayoutFlushSkip.shouldFlush(" in mn, \
    "updateContainerMinimum must gate host layoutSubtree"
assert "host.layoutSubtreeIfNeeded()" in mn, \
    "updateContainerMinimum must still flush the host when constraints move"

# External-drop fallback must remain (not softened to an early end).
assert "Timer(timeInterval: 0.05, repeats: true)" in split, \
    "InteractivePaneEdit 50ms fallback timer must remain"
assert "RunLoop.main.add(timer, forMode: .common)" in split, \
    "fallback timer must stay on .common for external-drop cleanup"
assert "func endIfDragReleased()" in split and "primaryMouseButtonIsDown" in split, \
    "fallback must still end only after the primary button is up"

print("SplitLayoutFlushSkip: drop flush + identical-factor divider-move skip; "
      "configure/commit/chrome contracts kept; 50ms external-drop timer kept")
