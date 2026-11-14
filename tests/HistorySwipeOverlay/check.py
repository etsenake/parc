#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
sources = [root / "Sources/ParcCore/HistorySwipeInterface.swift",
           root / "Sources/ParcCore/HistorySwipeRecognizer.swift",
           root / "Sources/ParcApp/HistorySwipeOverlayMotion.swift",
           here / "main.swift"]
view = (root / "Sources/ParcApp/HistorySwipeOverlayView.swift").read_text()
for use in ("override func hitTest(_ point: NSPoint) -> NSView? { nil }",
            "material.material = .popover", "material.blendingMode = .withinWindow",
            "layer?.masksToBounds = true", "appearance = palette?.contentAppearance",
            "NSWorkspace.shared.accessibilityDisplayShouldReduceMotion",
            "HistorySwipeOverlayLook(dark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)",
            "case .levelChange: performer.perform(.levelChange", "case .generic: performer.perform(.generic",
            "case .alignment: performer.perform(.alignment", "\"chevron.left\" : \"chevron.right\"",
            "weight: .bold"):
    assert use in view, f"HistorySwipeOverlayView no longer has: {use}"
with tempfile.TemporaryDirectory(prefix="parc-history-swipe-overlay-") as directory:
    executable = Path(directory) / "history-swipe-overlay"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
