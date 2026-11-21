#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
sidebar = (app / "SidebarView.swift").read_text()
menu_action = sidebar[sidebar.index("final class MenuAction"):sidebar.index("class LayoutView")]

with tempfile.TemporaryDirectory(prefix="parc-menu-images-") as directory:
    scratch = Path(directory)
    (scratch / "MenuAction.swift").write_text("import AppKit\n" + menu_action)
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(app / "MenuItemImage.swift"), str(scratch / "MenuAction.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
