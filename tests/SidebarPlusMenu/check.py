#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
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
    controls = Path(directory) / "ActionButton.swift"
    controls.write_text(sidebar[:sidebar.index("final class MenuAction")])
    button_checks = Path(directory) / "button-checks"
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
            str(root / "Sources/ParcApp/LibraryArtwork.swift"),
            str(root / "Sources/ParcApp/BoxOfThingsIcon.swift"),
            str(root / "Sources/ParcApp/SidebarPlusButtonFace.swift"),
            str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/PointerCover.swift"),
            str(root / "Sources/ParcApp/ReloadControl.swift"), str(root / "Sources/ParcApp/PointingHand.swift"),
            str(controls),
            str(Path(__file__).with_name("PlusButtonTests.swift")),
            "-o",
            str(button_checks),
        ],
        check=True,
    )
    subprocess.run([str(button_checks)], check=True)
