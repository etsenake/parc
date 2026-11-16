#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
sources = [root / "Sources/ParcCore/HistorySwipeInterface.swift",
           root / "Sources/ParcCore/HistorySwipeRecognizer.swift",
           root / "Sources/ParcApp/HistorySwipeDriver.swift",
           Path(__file__).with_name("main.swift")]
with tempfile.TemporaryDirectory(prefix="parc-history-swipe-driver-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
