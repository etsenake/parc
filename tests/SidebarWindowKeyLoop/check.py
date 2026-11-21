#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-window-key-loop-") as directory:
    executable = Path(directory) / "checks"
    presentation = (root / "Sources/ParcApp/SidebarPreviewPresentation.swift").read_text()
    surface = Path(directory) / "SidebarPreviewSurface.swift"
    surface.write_text(presentation[:presentation.index("final class SidebarPreviewItemView")])
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/SidebarAccessibility.swift"),
                    str(root / "Sources/ParcApp/WindowKeyViewLoop.swift"), str(surface),
                    str(root / "Sources/ParcApp/PopoverBackgroundView.swift"),
                    str(Path(__file__).with_name("SidebarWindowKeyLoopTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
