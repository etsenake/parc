#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
motion = (root / "Sources/ParcApp/SidebarMotionController.swift").read_text()
with tempfile.TemporaryDirectory(prefix="parc-sidebar-motion-") as directory:
    controller = Path(directory) / "checks.swift"
    controller.write_text(motion)
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-target", "arm64-apple-macos13.0", str(controller),
        str(root / "Sources/ParcApp/SidebarChromeLayout.swift"),
        str(root / "Sources/ParcApp/WindowStandardButtons.swift"),
        str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
