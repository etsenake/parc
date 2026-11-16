#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tests/Support"))
from app_sources import compile_swift
with tempfile.TemporaryDirectory(prefix="parc-popup-chrome-") as directory:
    executable = Path(directory) / "check"
    text = (root / "Sources/ParcApp/SiteControlCenter.swift").read_text()
    artwork = Path(directory) / "SiteControlCenterArtwork.swift"
    artwork.write_text(text[:text.index("enum SiteControlCenterMetrics")])
    compile_swift(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library",
                    "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/PopupChromeView.swift"),
                    str(root / "Sources/ParcApp/PointerCover.swift"),
                    str(root / "Sources/ParcApp/BlockedContentSign.swift"),
                    str(root / "Sources/ParcApp/BlockedPageContent.swift"), str(artwork),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)])
    subprocess.run([str(executable)], check=True)
