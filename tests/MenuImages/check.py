#!/usr/bin/env python3
"""Menu item images: only the menus where Parc shows an image set one, and
each goes through NSMenuItem.showImage so macOS 27 shows it.

Parc 1.122 builds its sidebar, preview, page and window menus without images
(PArcContextMenuItem.icon and CallbackMenuItem's image are nil at every such
call site). It shows images in the split controls menu, its ShareMenu's
services, the main menu's Open in [Space], the Download Location picker, the
extension rows of its main-menu Extensions menu (16 pt icons,
BrowserExtensionsMainMenuProvider) and Easel's Export as Image row. Parc
doesn't build the Extensions rows yet. Compiles the real MenuAction and
MenuItemImage; no browser, menu tracking or window.
"""
from pathlib import Path
import re
import subprocess
import tempfile

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
    expect(use in (app / source).read_text(), f"{source} no longer shows the menu image: {use}")

#
# doesn't show; clearing an image is allowed. Menu item names are collected
# per function: constructed items, typed declarations and parameters, and items
# a menu returns.
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
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(app / "MenuItemImage.swift"), str(scratch / "MenuAction.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
print(f"Menu images: {checks} source checks passed")
