#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
core = [root / "Sources/ParcCore/HistorySwipeInterface.swift",
        root / "Sources/ParcCore/HistorySwipeRecognizer.swift",
        root / "Sources/ParcApp/HistorySwipeOverlayMotion.swift"]
view_source = root / "Sources/ParcApp/HistorySwipeOverlayView.swift"
view = view_source.read_text()
for use in ("model.prefersReducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion",
            "case .levelChange: performer.perform(.levelChange, performanceTime: .default)",
            "case .generic: performer.perform(.generic, performanceTime: .now)",
            "case .alignment: performer.perform(.alignment, performanceTime: .now)",
            "NSImage(systemSymbolName: direction == .back ? \"chevron.left\" : \"chevron.right\"",
            ".withSymbolConfiguration(.init(pointSize: M.chevronPointSize, weight: .bold))"):
    assert view.count(use) == 1, f"HistorySwipeOverlayView no longer has exactly one: {use}"
builds = {"history-swipe-overlay": [*core, here / "main.swift"],
          "history-swipe-overlay-view": [*core, view_source, here / "ViewTests.swift"]}
with tempfile.TemporaryDirectory(prefix="parc-history-swipe-overlay-") as directory:
    for name, sources in builds.items():
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
