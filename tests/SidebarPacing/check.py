#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
motion = (app / "SidebarMotionController.swift").read_text()

def build(directory, name, motion_source):
    source = Path(directory) / f"{name}-SidebarMotionController.swift"
    source.write_text(motion_source)
    executable = Path(directory) / name
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/SpaceTheme.swift"), str(root / "Sources/ParcCore/WindowFrame.swift"),
                    str(app / "ThemeRenderer.swift"), str(source),
                    str(app / "SidebarChromeLayout.swift"), str(app / "WindowStandardButtons.swift"),
                    str(app / "ReloadControl.swift"), str(app / "PageLoadingIndicator.swift"), str(app / "PageCardShadow.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    return executable

with tempfile.TemporaryDirectory(prefix="parc-sidebar-pacing-") as directory:
    shutil.copytree(root / "Resources/FloatingSidebar", Path(directory) / "FloatingSidebar")
    subprocess.run([str(build(directory, "pacing", motion))], check=True)
