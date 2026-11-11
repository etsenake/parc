#!/usr/bin/env python3
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


setter = body("setSidebarPresentation")
mapping = "var presentation = EmptyWindowSidebarRule.presentation(for: requested, noActiveItem: emptyWindowHoldsSidebar)"
assert setter.splitlines()[1].strip() == mapping, "setSidebarPresentation no longer applies the no-tab rule before anything else"
assert ("if presentation == .hidden, spaceCreation != nil {\n"
        "            cancelSpaceCreation(restoreFocus: false)\n"
        "            presentation = EmptyWindowSidebarRule.presentation(for: requested, noActiveItem: emptyWindowHoldsSidebar)\n"
        "        }\n") in setter, "cancelling Space creation no longer re-applies the no-tab rule"
assert setter.count("EmptyWindowSidebarRule.presentation(") == 2
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
tail = [line.strip() for line in render[render.index("        lastChromeState = sharedState\n"):].rstrip().removesuffix("}").splitlines()
        if line.strip()]
assert "refreshEmptyWindowSidebar()" in tail, "render no longer ends by applying the no-tab rule"
for later in tail[tail.index("refreshEmptyWindowSidebar()") + 1:]:
    deferred = re.fullmatch(r"(\w+)\(\)", later)
    assert deferred, f"render changes state after applying the no-tab rule: {later}"
    scheduled = body(deferred.group(1))
    start = scheduled.find("\n        DispatchQueue.main.async {")
    now = scheduled[scheduled.index("{") + 1:start].splitlines()
    assert start > 0 and scheduled[scheduled.index("\n        }\n", start):] == "\n        }\n    }\n" \
        and all(re.fullmatch(r"|guard [^()]* else \{ return \}|\w+Scheduled = true", line.strip()) for line in now), \
        f"render changes state after applying the no-tab rule: {later}"
assert "layoutChrome()\n        refreshEmptyWindowSidebar()" in body("closeLibrary"), "closing the Library no longer applies the no-tab rule"
assert ("EmptyWindowSidebarRule.holdsSidebar(focusedTab: currentTabID, pendingSplitPane: splitInsertion != nil,\n"
        "                                            creatingSpace: spaceCreation != nil, popup: isPopupWindow, library: libraryView != nil)"
        ) in controller, "the window no longer feeds its focused tab and pending Add Split pane to the rule"
assert "splitInsertion = session\n        render(store.state)" in body("beginSplitInsertion"), "opening the pending pane no longer renders"
assert "splitInsertion = nil; session.cancel()\n        let panel = commandBar; commandBar = nil; panel?.dismiss(restoreFocus: false)\n        render(store.state)" \
    in body("cancelSplitInsertion"), "cancelling the pending pane no longer renders"
fill = body("fillSplitInsertionWithNewDocument")
assert fill.index("splitInsertion = nil; session.cancel()") < fill.index("focusedTabID = id; render(store.state)"), \
    "filling the pane with a document no longer renders after ending it"
assert controller.index("self.splitInsertion = nil; session.cancel()") < controller.index("self.focusedTabID = id; self.render(self.store.state)"), \
    "filling the pane with a result no longer renders after ending it"
assert controller.count("splitInsertion = nil; session.cancel()") == 3, "an unexpected end of the pending pane"
assert "let empty = SplitPanePlaceholder(frame: .zero)\n                empty.setAccessibilityLabel(\"No tab open\")" in controller
assert "let showsEmpty = splitView.arrangedSubviews.count == 1 && splitView.arrangedSubviews.first is SplitPanePlaceholder" in controller
assert re.search(r"splitView\.configureBacking\(in: pageHost, hasTranslucentPane: translucentPane \|\| showsEmpty[,)]", controller)
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
