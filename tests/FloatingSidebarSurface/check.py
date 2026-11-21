#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
artwork = root / "Resources/FloatingSidebar"
with tempfile.TemporaryDirectory(prefix="parc-floating-sidebar-surface-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/SpaceTheme.swift"), str(app / "ThemeRenderer.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    shutil.copytree(artwork, Path(directory) / "FloatingSidebar")
    shutil.copytree(root / "Resources/ThemeTextures", Path(directory) / "ThemeTextures")
    subprocess.run([str(executable)], check=True, timeout=120)
print("FloatingSidebarSurface check passed")
