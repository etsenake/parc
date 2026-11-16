#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
sources = [root / "Sources/ParcCore/HistorySwipeInterface.swift",
           root / "Sources/ParcCore/HistorySwipeRecognizer.swift",
           here / "HistorySwipeRecognizerTests.swift"]
with tempfile.TemporaryDirectory(prefix="parc-history-swipe-") as directory:
    executable = Path(directory) / "history-swipe"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
