#!/usr/bin/env python3
"""Isolated Space paging model and pager checks; no browser, window or posted events.

P1-AQ: spring ticks / place with an identical strip presentation fingerprint
skip setOffset; changed offsets still present; the 120 Hz timer idle-stops only
on settle and keeps running while motion can change pixels.
"""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/SidebarSpacePaging.swift").read_text()
assert "enum SidebarSpacePagingPresentationSkip" in source, "presentation skip helper missing"
assert "static func shouldSkip(previous: CGFloat?, next: CGFloat)" in source, \
    "shouldSkip predicate missing"
assert "previous == next" in source, "skip must be exact fingerprint equality only"
assert "present(value)" in source, "place/tick must present through the skip gate"
assert re.search(r"func tick\(\) \{.*?present\(value\)", source, re.S), \
    "tick must present spring samples through the skip gate"
assert "Timer(timeInterval: 1.0 / 120, repeats: true)" in source, \
    "120 Hz spring timer must remain while motion can change pixels"
assert "timer?.invalidate(); timer = nil" in source, \
    "settle via place must still idle-stop the timer"

#
# every scroll view in it offers its scrolls to the pager first.
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
for use in ("    private let scroll = SidebarPagingScrollView()\n",
            "        scroll.offerScroll = { [weak self] event in self?.spacePager.scrollWheel(event) ?? false }\n",
            "        spacesHost.offerScroll = scroll.offerScroll\n",
            "        miniPlayers.offerScroll = scroll.offerScroll\n"):
    assert use in sidebar, f"SidebarView no longer routes a sidebar scroll view to the pager: {use}"
assert "    private let scroll = SidebarPagingScrollView()\n" in (root / "Sources/ParcApp/MiniPlayerView.swift").read_text(), \
    "the Mini Player list keeps sideways swipes from the pager again"
assert "if overflows || !offerScroll(event) { super.scrollWheel(with: event) }" in \
    (root / "Sources/ParcApp/SidebarDockStrip.swift").read_text(), "the Space strip no longer pages unless it overflows"

with tempfile.TemporaryDirectory(prefix="parc-space-paging-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/SidebarSpacePaging.swift"),
                    str(root / "tests/Support/AppKitObservation.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
