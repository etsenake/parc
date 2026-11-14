#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources

page = (app / "StartPageView.swift").read_text()
for use in ("let background = ThemeRendererView()",
            "background.theme = Self.untextured(theme)",
            "background.pagingTransition = pagingTransition.map(Self.untextured)",
            "background.coordinateSpace = coordinateSpace; mark.coordinateSpace = coordinateSpace",
            "let windowButtons = WindowStandardButtons()",
            "let sidebarButton = ActionButton(StartPageView.sidebarButtonTitle, symbol: \"sidebar.left\")",
            "LiveShortcutToolTip.set(sidebarButton, Self.sidebarButtonTitle, commandID: \"toggleSidebar:\")",
            "guard let window, let superview, hitTest(superview.convert(event.locationInWindow, from: nil)) === self else {",
            "switch SidebarTablistBackground.press(clickCount: event.clickCount, modifiers: event.modifierFlags) {",
            "            NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: window)\n"
            "            window.performDrag(with: event)\n"):
    assert use in page, f"StartPageView no longer wires the checked behaviour: {use}"
sidebar = (app / "SidebarView.swift").read_text()
for use in ("toggle.translucentFace = TranslucentButtonFace(view: toggle)",
            "toggle.focusRingCornerRadius = 5",
            "guard let window, isTablistBackground(event) else { super.mouseDown(with: event); return }",
            "case .dragWindow:\n            NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: window)\n"
            "            window.performDrag(with: event)\n"):
    assert use in sidebar, f"the sidebar changed the control or drag the start page mirrors: {use}"


def slice_between(text, start, end, name):
    assert start in text and end in text, f"{name} no longer contains its slice markers"
    return text[text.index(start):text.index(end)]


mark = (app / "StartPageMarkView.swift").read_text()
for member in ("final class StartPageMarkView: NSView {", "    var theme = SpaceTheme()", "    var incognito = false",
               "    weak var coordinateSpace: NSView?", "    override var intrinsicContentSize: NSSize {",
               "    weak var effectsHost: NSView?", "    var pagingTransition: ThemePagingTransition?",
               "    func invalidateCoordinates() {"):
    assert member in mark, f"StartPageMarkView no longer offers what the start page uses: {member.strip()}"
MARK_STAND_IN = """import AppKit

@MainActor
final class StartPageMarkView: NSView {
    var theme = SpaceTheme()
    var incognito = false
    weak var coordinateSpace: NSView?
    weak var effectsHost: NSView?
    var pagingTransition: ThemePagingTransition?
    func invalidateCoordinates() {}
    override var isFlipped: Bool { true }
}
"""

sources = [root / "Sources/ParcCore/SpaceTheme.swift"] + [app / name for name in (
    "ThemeRenderer.swift", "WindowStandardButtons.swift", "SidebarChromeLayout.swift", "SidebarTablistBackground.swift",
    "SidebarAccessibility.swift", "SidebarMotionController.swift", "TranslucentButtonFace.swift", "ReloadControl.swift",
    "PointingHand.swift", "PointerCover.swift", "NotePaper.swift", "StartPageView.swift")]



def build(scratch, name, support, replace=None):
    files = list(sources)
    if replace:
        old, new = replace
        text = (app / "StartPageView.swift").read_text()
        assert old in text, f"negative control no longer matches StartPageView.swift: {old}"
        changed = scratch / f"{name}-StartPageView.swift"
        changed.write_text(text.replace(old, new))
        files = [changed if path == app / "StartPageView.swift" else path for path in files]
    executable = scratch / name
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *map(str, files + support), str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    return executable


controls = {
    "textured background": (("background.theme = Self.untextured(theme)", "background.theme = theme"),
                            "the page background draws no texture"),
    "private coordinate space": (("background.coordinateSpace = coordinateSpace; mark.coordinateSpace = coordinateSpace",
                                  "mark.coordinateSpace = coordinateSpace"), "background and mark share the window's gradient space"),
    "dropped swipe": (("background.pagingTransition = pagingTransition.map(Self.untextured)", "background.pagingTransition = nil"),
                      "a Space swipe reaches the background"),
    "slot swallows clicks": (("        return hit === self ? nil : hit\n", "        return hit\n"),
                             "the slot below the bar card falls through to the page background"),
    "chrome never shows": (("if sidebarButton.isHidden == showsWindowChrome { sidebarButton.isHidden = !showsWindowChrome }",
                            "sidebarButton.isHidden = true"), "a hidden sidebar shows the window buttons and the sidebar button"),
}

with tempfile.TemporaryDirectory(prefix="parc-start-page-") as directory:
    scratch = Path(directory)
    button = scratch / "StartPageActionButton.swift"
    button.write_text("import AppKit\n\n" + slice_between(sidebar, "extension NSColor {\n    convenience init(parcHex:",
                                                          "enum SidebarNewTabAppearance", "SidebarView.swift"))
    stand_in = scratch / "StartPageMarkView.swift"
    stand_in.write_text(MARK_STAND_IN)
    support = [button, stand_in] + tooltip_sources(root, scratch, [str(path) for path in sources])
    shutil.copytree(root / "Resources/ThemeTextures", scratch / "ThemeTextures")
    subprocess.run([str(build(scratch, "checks", support))], check=True, timeout=120)
    for name, (replace, failure) in controls.items():
        result = subprocess.run([str(build(scratch, name.replace(" ", "-"), support, replace))], capture_output=True, text=True, timeout=120)
        assert result.returncode != 0 and failure in result.stderr, f"negative control did not fail: {name}\n{result.stderr[-1000:]}"
        print(f"StartPage negative control fails as expected: {name}")
print("StartPage check passed")
