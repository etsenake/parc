#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-preview-titles-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
        str(root / "Sources/ParcCore/SidebarPreviewTitles.swift"), str(root / "Sources/ParcCore/SidebarPreviewActivation.swift"),
        str(Path(__file__).with_name("main.swift")),
        "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
