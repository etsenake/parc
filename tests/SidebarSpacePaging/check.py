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

with tempfile.TemporaryDirectory(prefix="parc-space-paging-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/SidebarSpacePaging.swift"),
                    str(root / "tests/Support/AppKitObservation.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
