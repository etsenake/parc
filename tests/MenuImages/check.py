#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
checks = 0


def expect(condition, message):
    global checks
    assert condition, message
    checks += 1


visibility = [path.name for path in app.glob("*.swift") if "preferredImageVisibility" in path.read_text()]
expect(visibility == ["MenuItemImage.swift"], f"menu image visibility is set outside showImage: {visibility}")
for source, use in (("PaneTitleControl.swift", "entry.showImage(service.image)"),
                    ("BrowserWindowController.swift", "item.showImage(icon)"),
                    ("DownloadLocationPicker.swift", "folder.showImage(NSImage(size: size, flipped: false)"),
                    ("SplitPaneMenu.swift", "item.showImage(SplitPaneMenuArtwork.image(artwork))"),
                    ("EaselImageExport.swift", "item.showImage(SidebarIconCatalog.featherImage(0xE9CA, size: 14))")):
    text = browser_window_controller_source(app) if source == "BrowserWindowController.swift" else (app / source).read_text()
    expect(use in text, f"{source} no longer shows its menu image: {use}")

declarations = (
    re.compile(r"\b(?:let|var)\s+(\w+)\s*(?::\s*NSMenuItem\s*)?=\s*(?:NSMenuItem\(|MenuAction\.item)"),
    re.compile(r"(\w+)\s*:\s*NSMenuItem\b"),
    re.compile(r"\b(?:let|var)\s+(\w+)[^=]*=\s*\w+\.addItem\(withTitle:"),
    re.compile(r"\b(?:let|var)\s+(\w+)[^=]*=\s*\w+\.item\("),
)
unnamed = re.compile(r"(?:lastItem|items\.\w+|item\((?:at|withTitle):[^)]*\))\??\.image\s*=(?!=|\s*nil\b)")
direct = []
for path in sorted(app.glob("*.swift")):
    names = set()
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if re.search(r"\bfunc ", line):
            names = set()
        for pattern in declarations:
            names.update(match.group(1) for match in pattern.finditer(line))
        if unnamed.search(line) or any(re.search(rf"\b{name}\??\.image\s*=(?!=|\s*nil\b)", line) for name in names):
            direct.append(f"{path.name}:{number}")
expect(not direct, f"menu item images set without showImage: {direct}")

sidebar = (app / "SidebarView.swift").read_text()
menu_action = sidebar[sidebar.index("final class MenuAction"):sidebar.index("class LayoutView")]
expect("image" not in menu_action.split("static func item", 1)[1], "MenuAction items set an image again")

with tempfile.TemporaryDirectory(prefix="parc-menu-images-") as directory:
    scratch = Path(directory)
    (scratch / "MenuAction.swift").write_text("import AppKit\n" + menu_action)
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(app / "MenuItemImage.swift"), str(scratch / "MenuAction.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
print(f"Menu images: {checks} source checks passed")
