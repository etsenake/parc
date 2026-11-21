#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-plus-menu-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(
        [
            "xcrun",
            "swiftc", str(root / "tests/Support/TestFailure.swift"),
            "-warnings-as-errors",
            "-parse-as-library",
            "-target",
            "arm64-apple-macos13.0",
            *map(str, sorted((root / "Sources/ParcCore").glob("*.swift"))),
            str(root / "Sources/ParcApp/ThemeRenderer.swift"),
            str(root / "Sources/ParcApp/ParcMenuColors.swift"),
            str(root / "Sources/ParcApp/SidebarPlusMenu.swift"),
            str(Path(__file__).with_name("PlusMenuTests.swift")),
            "-o",
            str(executable),
        ],
        check=True,
    )
    shutil.copytree(root / "Resources/SidebarPlusMenu", Path(directory) / "SidebarPlusMenu")
    subprocess.run([str(executable)], check=True)
