#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-popup-window-") as directory:
    executable = Path(directory) / "check"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library",
                    "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/BrowserPopupWindow.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
