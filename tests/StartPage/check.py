#!/usr/bin/env python3
from concurrent.futures import ThreadPoolExecutor
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
for use in ("let paper = StartPagePaperView()",
            "        paper.theme = theme\n        mark.theme = theme\n",
            "            paper.pagingTransition = pagingTransition\n            mark.pagingTransition = pagingTransition\n",
            "            paper.incognito = incognito; mark.incognito = incognito\n",
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
               "    func invalidateCoordinates() {", "    var style = ParcBrandMark.Style.borderless {"):
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

sources = [root / "Sources/ParcCore/SpaceTheme.swift", root / "Sources/ParcCore/HistorySwipeInterface.swift",
           root / "Sources/ParcCore/HistorySwipeRecognizer.swift"] + [app / name for name in (
    "ThemeRenderer.swift", "WindowStandardButtons.swift", "SidebarChromeLayout.swift", "SidebarTablistBackground.swift",
    "SidebarAccessibility.swift", "SidebarMotionController.swift", "TranslucentButtonFace.swift", "ReloadControl.swift",
    "PointingHand.swift", "PointerCover.swift", "StartPagePaper.swift", "StartPageView.swift",
    "PeekCloseTransition.swift", "PeekDismissalMotion.swift", "PeekFocusReturn.swift", "TabCloseFade.swift")]

arrival = slice_between((app / "BrowserWindowController+StartPage.swift").read_text(),
                        "    private func playStartPageArrival() {", "\n    }\n}", "BrowserWindowController+StartPage.swift")
for use in ("let faded = takeCloseFadeArrival()", "startPage.alphaValue = 1", "context.duration = 0.15",
            "slot.animator().alphaValue = 1"):
    assert use in arrival, f"a start page the close fade already showed no longer just brings in its bar: {use}"
assert arrival.index("let faded = takeCloseFadeArrival()") < arrival.index("startPage.alphaValue = 0"), \
    "the arrival fade restarts a start page the close fade already showed"
fade_source = (app / "TabCloseFade.swift").read_text()
assert "guard restoring, phase == .resting, sheetEndObserver == nil, !motion.isAnimating(at: now()) else { return }" in fade_source, \
    "a refused close fade can be torn down before focus returns from a dialog"
assert "NSWindow.didEndSheetNotification" in slice_between(fade_source, "    private func returnFocusWhenClear() {",
                                                           "    private func stopWaitingForSheetEnd() {", "TabCloseFade.swift"), \
    "a refused page no longer waits for a dialog to close before taking focus back"



def build(scratch, name, support, replace=None):
    files = list(sources)
    if replace:
        source, old, new = replace
        text = (app / source).read_text()
        assert old in text, f"negative control no longer matches {source}: {old}"
        changed = scratch / f"{name}-{source}"
        changed.write_text(text.replace(old, new))
        files = [changed if path == app / source else path for path in files]
    executable = scratch / name
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *map(str, files + support), str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    return executable


controls = {
    "paper ignores appearance": (("StartPagePaper.swift",
                                  "var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }",
                                  "var isDark: Bool { false }"), "the paper follows the NSAppearanceNameDarkAqua appearance"),
    "glows lost": (("StartPagePaper.swift", "glows = zip(colors, Self.anchors).map { Glow(color: $0, anchor: $1) }", "glows = []"),
                   "every theme colour glows from its corner"),
    "dropped swipe": (("StartPageView.swift", "            paper.pagingTransition = pagingTransition\n", ""),
                      "a Space swipe prepares the incoming Space's paper"),
    "slot swallows clicks": (("StartPageView.swift", "        return hit === self ? nil : hit\n", "        return hit\n"),
                             "the slot below the bar card falls through to the page background"),
    "unlocked close fade": (("TabCloseFade.swift", "startPage?.alphaValue = 1 - card", "startPage?.alphaValue = (1 - card) * (1 - card)"),
                            "the start page fades in exactly as the page fades out"),
    "early close": (("TabCloseFade.swift", "                schedule(duration) { [weak self] in", "                schedule(duration * 0) { [weak self] in"),
                    "the real close waits for the Peek close fade's 0.2 seconds"),
    "Leave lingers": (("TabCloseFade.swift", "        apply(transition.finish())\n        paint()\n", "        transition = PeekCloseTransition()\n"),
                      "after Leave the page goes at once"),
    "chrome never shows": (("StartPageView.swift", "if sidebarButton.isHidden == showsWindowChrome { sidebarButton.isHidden = !showsWindowChrome }",
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
    with ThreadPoolExecutor() as pool:
        main = pool.submit(build, scratch, "checks", support)
        built = {name: pool.submit(build, scratch, name.replace(" ", "-"), support, replace)
                 for name, (replace, _) in controls.items()}
    subprocess.run([str(main.result())], check=True, timeout=120)
    for name, (replace, failure) in controls.items():
        result = subprocess.run([str(built[name].result())], capture_output=True, text=True, timeout=120)
        assert result.returncode >= 0, f"negative control crashed with signal {-result.returncode} instead of failing: {name}\n{result.stderr[-1000:]}"
        assert result.returncode != 0 and failure in result.stderr, f"negative control did not fail: {name}\n{result.stderr[-1000:]}"
        print(f"StartPage negative control fails as expected: {name}")
print("StartPage check passed")
