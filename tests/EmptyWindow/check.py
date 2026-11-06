#!/usr/bin/env python3
"""A window with no tab: the empty content and page-card shadows on the
production views, and the floating-sidebar rule on every path that hides the
sidebar. No browser, input or window is shown."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
controller = (app / "BrowserWindowController.swift").read_text()


def body(name):
    match = re.search(rf"^    private func {name}\(.*?^    }}\n", controller, re.S | re.M)
    assert match, f"BrowserWindowController.{name} is missing"
    return match.group(0)


# Every request to hide reaches setSidebarPresentation, whose first statement
# applies the rule; the only direct writes are a window's initial state, which
# the first render refreshes.
setter = body("setSidebarPresentation")
mapping = "var presentation = EmptyWindowSidebarRule.presentation(for: requested, noActiveItem: emptyWindowHoldsSidebar)"
assert setter.splitlines()[1].strip() == mapping, "setSidebarPresentation no longer applies the no-tab rule before anything else"
# Hiding during Space creation cancels it first, which can leave the window
# without a tab, so the rule is applied again before anything uses the result.
assert ("if presentation == .hidden, spaceCreation != nil {\n"
        "            cancelSpaceCreation(restoreFocus: false)\n"
        "            // The cancel can return the window to having no tab.\n"
        "            presentation = EmptyWindowSidebarRule.presentation(for: requested, noActiveItem: emptyWindowHoldsSidebar)\n"
        "        }\n") in setter, "cancelling Space creation no longer re-applies the no-tab rule"
assert setter.count("EmptyWindowSidebarRule.presentation(") == 2
# The stored hover input follows the mapped request and precedes the no-op guard.
held = "if presentation == .floating { sidebarHoverActive = true }"
guard = "guard sidebarPresentation != presentation else { return }"
assert setter.index(mapping) < setter.index("cancelSpaceCreation(restoreFocus: false)") < setter.index(held) < setter.index(guard), \
    "the stored hover input no longer sits between the rule and the guard"
hides = re.findall(r"setSidebarPresentation\(\.hidden[,)]", controller)
assert len(hides) == 3, f"unexpected hide paths: {hides}"
for path in ("if self.sidebarPresentation == .floating && !self.sidebarPointerDown { self.setSidebarPresentation(.hidden) }",
             "if commit.collapses { setSidebarPresentation(.hidden, allowsMotion: false) }",
             "case .dismiss: setSidebarPresentation(.hidden)",
             "setSidebarPresentation(sidebarPresentation == .locked ? .hidden : .locked)"):
    assert path in controller, f"a hide path moved: {path}"
direct = re.findall(r"\bsidebarPresentation = ([^;\n} ]+)", controller)
assert sorted(direct) == [".hidden", ".hidden", "presentation", "presentation", "saved.sidebar"], \
    f"an unexpected direct presentation write: {direct}"
render = re.search(r"^    private func render\(_ sharedState: BrowserState\) \{.*?^    }\n", controller, re.S | re.M).group(0)
assert render.rstrip().endswith("lastChromeState = sharedState\n        refreshEmptyWindowSidebar()\n    }"), \
    "render no longer ends by applying the no-tab rule"
assert "layoutChrome()\n        refreshEmptyWindowSidebar()" in body("closeLibrary"), "closing the Library no longer applies the no-tab rule"
assert ("EmptyWindowSidebarRule.holdsSidebar(focusedTab: currentTabID, pendingSplitPane: splitInsertion != nil,\n"
        "                                            creatingSpace: spaceCreation != nil, popup: isPopupWindow, library: libraryView != nil)"
        ) in controller, "the window no longer feeds its focused tab and pending Add Split pane to the rule"
# Add Split's pending pane starts and ends with a render, which ends by
# applying the rule: opening it floats a hidden sidebar, and filling or
# cancelling it hands the sidebar back to the hover rule.
assert "splitInsertion = session\n        render(store.state)" in body("beginSplitInsertion"), "opening the pending pane no longer renders"
assert "splitInsertion = nil; session.cancel()\n        let panel = commandBar; commandBar = nil; panel?.dismiss(restoreFocus: false)\n        render(store.state)" \
    in body("cancelSplitInsertion"), "cancelling the pending pane no longer renders"
fill = body("fillSplitInsertionWithNewDocument")
assert fill.index("splitInsertion = nil; session.cancel()") < fill.index("focusedTabID = id; render(store.state)"), \
    "filling the pane with a document no longer renders after ending it"
assert controller.index("self.splitInsertion = nil; session.cancel()") < controller.index("self.focusedTabID = id; self.render(self.store.state)"), \
    "filling the pane with a result no longer renders after ending it"
assert controller.count("splitInsertion = nil; session.cancel()") == 3, "an unexpected end of the pending pane"
# The empty window shows the empty content through a clear, clipping host.
assert "let empty = SplitPanePlaceholder(frame: .zero)\n                empty.setAccessibilityLabel(\"No tab open\")" in controller
assert "splitView.configureBacking(in: pageHost, hasTranslucentPane: translucentPane || showsEmpty)" in controller
assert "pageShadow.isHidden = splitView.arrangedSubviews.count > 1 || nativeFullscreenTabID != nil" in controller

sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [app / name for name in (
    "SidebarMotionController.swift", "SidebarChromeLayout.swift", "WindowStandardButtons.swift", "ParcSplitView.swift",
    "SplitMarginHandle.swift", "SplitDropGeometry.swift", "PageCardShadow.swift", "SplitPaneMenu.swift", "MenuItemImage.swift",
    "SplitPaneHighlight.swift")]


def build(directory, name, replace=None):
    files = list(sources)
    if replace:
        source, old, new = replace
        text = (app / source).read_text()
        assert old in text, f"negative control no longer matches {source}: {old}"
        changed = Path(directory) / f"{name}-{source}"
        changed.write_text(text.replace(old, new))
        files = [changed if path == app / source else path for path in files]
    executable = Path(directory) / name
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *map(str, files), str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    return executable


with tempfile.TemporaryDirectory(prefix="parc-empty-window-") as directory:
    subprocess.run([str(build(directory, "check"))], check=True)
    # Without each piece the checks fail.
    controls = {
        "hiding with no tab": (("SidebarMotionController.swift", "requested == .hidden && noActiveItem ? .floating : requested",
                                "requested"), "hiding a window with no tab floats its sidebar"),
        "pending pane": (("SidebarMotionController.swift", "(focusedTab == nil || pendingSplitPane) && !creatingSpace",
                          "focusedTab == nil && !creatingSpace"), "a pending Add Split pane holds the sidebar although a tab exists"),
        "shadow over the card": (("PageCardShadow.swift", "        context.clear(canvas)\n", ""),
                                 "the card's interior is clear"),
        "circular clear": (("PageCardShadow.swift", "        shape.cornerCurve = .continuous\n", "        shape.cornerCurve = .circular\n"),
                           "every pixel inside the card's continuous corner is clear"),
        "shadow placed by its own flip": (("ParcSplitView.swift",
                                           "            shadow.frame = ContentShadowImage.frame(around: pane.layer?.frame ?? pane.frame)\n",
                                           "            var card = pane.frame\n"
                                           "            if !layer.isGeometryFlipped { card.origin.y = bounds.height - card.maxY }\n"
                                           "            shadow.frame = ContentShadowImage.frame(around: card)\n"),
                                          "a shadow surrounds the pane's layer"),
    }
    for name, (replace, failure) in controls.items():
        result = subprocess.run([str(build(directory, name.replace(" ", "-"), replace))], capture_output=True, text=True)
        assert result.returncode != 0 and failure in result.stderr, f"negative control did not fail: {name}\n{result.stderr[-1000:]}"
        print(f"EmptyWindow negative control fails as expected: {name}")
