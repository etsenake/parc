#!/usr/bin/env python3
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import subprocess
import tempfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
controller = browser_window_controller_source(app)


def body(name):
    match = re.search(rf"^    (?:private )?func {name}\(.*?^    }}\n", controller, re.S | re.M)
    assert match, f"BrowserWindowController.{name} is missing"
    return match.group(0)


setter = body("setSidebarPresentation")
mapping = "var presentation = PendingSplitPaneSidebarRule.presentation(for: requested, pendingPane: pendingPaneHoldsSidebar)"
assert setter.splitlines()[1].strip() == mapping, "setSidebarPresentation no longer applies the pending-pane rule before anything else"
assert ("if presentation == .hidden, spaceCreation != nil {\n"
        "            cancelSpaceCreation(restoreFocus: false)\n"
        "            presentation = PendingSplitPaneSidebarRule.presentation(for: requested, pendingPane: pendingPaneHoldsSidebar)\n"
        "        }\n") in setter, "cancelling Space creation no longer re-applies the pending-pane rule"
assert setter.count("PendingSplitPaneSidebarRule.presentation(") == 2
held = "if presentation == .floating { sidebarHoverActive = true }"
guard = "guard sidebarPresentation != presentation else { return }"
assert setter.index(mapping) < setter.index("cancelSpaceCreation(restoreFocus: false)") < setter.index(held) < setter.index(guard), \
    "the stored hover input no longer sits between the rule and the guard"
hides = re.findall(r"setSidebarPresentation\(\.hidden[,)]", controller)
assert len(hides) == 4, f"unexpected hide paths: {hides}"
for path in ("if sidebarPresentation == .floating { setSidebarPresentation(.hidden) }",
             "if self.sidebarPresentation == .floating && !self.sidebarPointerDown { self.setSidebarPresentation(.hidden) }",
             "if commit.collapses { setSidebarPresentation(.hidden, allowsMotion: false) }",
             "case .dismiss: setSidebarPresentation(.hidden)",
             "setSidebarPresentation(sidebarPresentation == .locked ? .hidden : .locked)"):
    assert path in controller, f"a hide path moved: {path}"
direct = re.findall(r"\bsidebarPresentation = ([^;\n} ]+)", controller)
assert sorted(direct) == [".hidden", ".hidden", "presentation", "presentation", "saved.sidebar"], \
    f"an unexpected direct presentation write: {direct}"
render = re.search(r"^    (?:private )?func render\(_ sharedState: BrowserState\) \{.*?^    }\n", controller, re.S | re.M).group(0)
tail = [line.strip() for line in render[render.index("        lastChromeState = sharedState\n"):].rstrip().removesuffix("}").splitlines()
        if line.strip()]
assert "refreshPendingPaneSidebar()" in tail, "render no longer ends by applying the pending-pane rule"
for later in tail[tail.index("refreshPendingPaneSidebar()") + 1:]:
    deferred = re.fullmatch(r"(\w+)\(\)", later)
    assert deferred, f"render changes state after applying the no-tab rule: {later}"
    scheduled = body(deferred.group(1))
    start = scheduled.find("\n        DispatchQueue.main.async {")
    now = scheduled[scheduled.index("{") + 1:start].splitlines()
    assert start > 0 and scheduled[scheduled.index("\n        }\n", start):] == "\n        }\n    }\n" \
        and all(re.fullmatch(r"|guard [^()]* else \{ return \}|\w+Scheduled = true", line.strip()) for line in now), \
        f"render changes state after applying the no-tab rule: {later}"
assert "layoutChrome()\n        refreshPendingPaneSidebar()" in body("closeLibrary"), "closing the Library no longer applies the pending-pane rule"
assert ("PendingSplitPaneSidebarRule.holdsSidebar(pendingSplitPane: splitInsertion != nil, creatingSpace: spaceCreation != nil,\n"
        "                                                 popup: isPopupWindow, library: libraryView != nil)"
        ) in controller, "the window no longer feeds its pending Add Split pane to the rule"
assert "focusedTab" not in (app / "SidebarMotionController.swift").read_text(), "an empty Space holds the sidebar again"
assert "splitInsertion = session\n        render(store.state)" in body("beginSplitInsertion"), "opening the pending pane no longer renders"
assert "splitInsertion = nil; session.cancel()\n        let panel = commandBar; commandBar = nil; panel?.dismiss(restoreFocus: false)\n        render(store.state)" \
    in body("cancelSplitInsertion"), "cancelling the pending pane no longer renders"
fill = body("fillSplitInsertionWithNewDocument")
assert fill.index("splitInsertion = nil; session.cancel()") < fill.index("focusedTabID = id; render(store.state)"), \
    "filling the pane with a document no longer renders after ending it"
assert controller.index("self.splitInsertion = nil; session.cancel()") < controller.index("self.focusedTabID = id; self.render(self.store.state)"), \
    "filling the pane with a result no longer renders after ending it"
assert controller.count("splitInsertion = nil; session.cancel()") == 3, "an unexpected end of the pending pane"
assert "            } else {\n                wanted = [startPage]\n            }" in controller, "an empty Space no longer shows the start page"
assert ("let showsEmpty = splitView.arrangedSubviews.count == 1\n"
        "            && (splitView.arrangedSubviews.first is SplitPanePlaceholder || splitView.arrangedSubviews.first === loadedStartPage)") in controller
assert re.search(r"splitView\.configureBacking\(in: pageHost, hasTranslucentPane: translucentPane \|\| showsEmpty[,)]", controller)
assert "pageShadow.isHidden = splitView.arrangedSubviews.count > 1 || nativeFullscreenTabID != nil" in controller
assert "        if focusResidentCommandBar() { return }\n        presentCommandBar(newTab: true)" in controller, \
    "Command-T no longer focuses the start page's command bar"
assert "        if !isPopupWindow, focusResidentCommandBar() { return }\n        presentCommandBar(newTab: false, addressAnchor: anchor)" \
    in controller, "Command-L no longer focuses the start page's command bar"
start_page = body("refreshStartPage")
assert "panel.presentResident(in: startPage.commandBarSlot)" in start_page, "the start page no longer hosts a resident command bar"
assert "ContentFocusRequest.holdsContentFocus(window.firstResponder, window: window, content: self.startPage)" in start_page, \
    "the start page's field takes focus away from another control"
assert "canOwnDownloadDialog(for: owner.profileID)" in start_page, "a resident bar is rebuilt for a Profile that cannot own it"
assert "noteReturnGate()\n        refreshStartPage()\n        refreshPendingPaneSidebar()" in render, "render no longer refreshes the start page"
assert "else if showsStartPage, let bar = residentCommandBar { bar.focusResident() }" in body("closeLibrary"), \
    "closing the Library over the start page leaves nothing focused"
assert "self.currentTabID == nil, self.showsStartPage {\n                self.residentCommandBar?.focusResident(); return" in controller, \
    "dismissing a palette over the start page leaves nothing focused"
assert "residentTypedCommands = (items, commands)\n                bar.updateTypedCommands(commands)" in controller, \
    "the resident bar keeps the typed commands it was built with"
assert "if residentCommandInputs != stamp {" in controller, "the start page redoes command bar bookkeeping on every render"
assert "if let bar = residentCommandBar { residentCommandBar = nil; bar.dismiss(restoreFocus: false) }; shutdownBrowsers();" in controller, \
    "closing the window leaves the resident command bar behind"

close = body("startTabClose")
assert close.index("fade.isClosing { return .started }") < close.index("prepareNotesToClose([id])") \
    < close.index("tabCloseAvailable(id)") < close.index("beginCloseFade(id)") < close.index("commitTabClose(id)"), \
    "closing the last tab no longer fades the page before the real close"
commit = body("commitTabClose")
assert commit.index("self.closeFadeLanded(id, approved: approved)") < commit.index("self.render(self.store.state)"), \
    "the close fade no longer hears that the close landed before the start page renders"
fade = body("beginCloseFade")
for use in ("closeEmptiesSpace(id)", "splitView.arrangedSubviews.count == 1, splitView.arrangedSubviews.first === pane",
            "peek(over: id) == nil", "!startPageDeparting", "!switchHold.isHolding", "window.attachedSheet == nil",
            "page.alphaValue = 0", "pageHost.addSubview(page, positioned: .below, relativeTo: splitView)",
            "refreshPageHostBacking()", "fade.begin()"):
    assert use in fade, f"the close fade lost a condition or step: {use}"
assert fade.index("closeFade = fade") < fade.index("refreshPageHostBacking()") < fade.index("fade.begin()"), \
    "the Space colour must be uncovered before the close fade starts"
assert "reconcileCloseFade()\n        refreshPageHostBacking()" in render, "render no longer settles the close fade before the page backing"
assert "let translucentPane = closeFade != nil ||" in body("refreshPageHostBacking"), \
    "the Space colour no longer shows through the close fade"
ended = body("endCloseFade")
assert "page.superview === pageHost, !startPageDeparting" in ended and "page.alphaValue = 1" in ended, \
    "an ended close fade leaves its start page behind"
assert "if let pane = panes[fade.tabID], pane.superview === splitView { pane.alphaValue = 1 }" in ended, \
    "a close fade cut short can leave a still-shown or held page invisible"
handoff = body("reconcileCloseFade")
assert handoff.index("if fade.phase == .finished, startPagePresented { endCloseFade(); return }") \
    < handoff.index("fade.handOff(); return") < handoff.rindex("endCloseFade()"), \
    "the start page blinks when it takes over from the close fade, or a spent fade lingers"
assert "windowUndoOwnerAvailable && window?.attachedSheet == nil && closeFade?.isClosing != true" in controller, \
    "Undo during the close fade would act on an older change while the tab still closes"
assert "activePeek == nil, closeFade?.isClosing != true," in controller, \
    "Reopen Closed Tab during the close fade would reopen an older tab"
assert "heldOverSwitch || passesInput ? nil : super.hitTest(point)" in controller, "a fading page still takes clicks"
assert "heldOverSwitch = false; passesInput = false; alphaValue = 1; super.viewWillMove(toSuperview: newSuperview)" in controller, \
    "a faded page could come back invisible"
select = controller[controller.index("    func nativeBrowser(_ browser: PCNativeBrowserWindow, didSelect page: PCNativePage) {"):]
select = select[:select.index("\n    }\n")]
admission = ("guard presentation.admitsEngineSelection(of: id, closing: { closingTabIDs.contains($0) || modelRetirementIDs.contains($0) }) else {\n"
             "            browser.synchronizeSelectionAndLayout(); presentation.engineSelectionSynchronized(); return\n        }")
assert admission in select and select.index("existingNativeSelection(browser, page)") < select.index(admission) \
    < select.index("next.selectExistingTab(id"), "the engine's own pick after a close can move the window to another Space"
release = body("releaseClosedTab")
assert "presentation.remove(id)" not in release and release.index("let replacement = closedItself ? closedPageReplacement(id) : nil") \
    < release.index("presentation.closePage(id)") < release.index("presentation.finishFolderRemoval(replacement") \
    < release.index("ownership.release(id, owner: presentationID)"), "a page closing itself no longer hands over by the close rules"
assert "self.render(self.store.state); self.requestNativeSelection(); self.focusSelectedLocalContent()" in release, \
    "a page closing itself leaves the engine's pick in place"
assert "binding.synchronizeSelectionAndLayout()\n        presentation.engineSelectionSynchronized()" in body("flushPendingNativeSelection"), \
    "the window never takes the engine's selections again after a close"
assert body("requestNativeSelection").count("pushNativeSelection()") == 2 and "nativeBinding?.synchronizeSelectionAndLayout()" \
    not in body("requestNativeSelection"), "a Peek or Easel selection push leaves the engine's selections refused"
assert release.index("pushedByClose = store.retiringTabIDs.contains(id)") < release.index("if updateSavedTab { store.closeTab(id) }") \
    < release.index("guard shown, closedItself || !pushedByClose else { return }") \
    < release.index("guard closedItself else { self.requestNativeSelection(); return }"), \
    "a shown page closed outside a store close leaves the engine's selections refused"

sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [app / name for name in (
    "SidebarMotionController.swift", "SidebarChromeLayout.swift", "WindowStandardButtons.swift", "ParcSplitView.swift",
    "SplitMarginHandle.swift", "SplitDropGeometry.swift", "PageCardShadow.swift", "SplitPaneMenu.swift", "MenuItemImage.swift",
    "SplitPaneHighlight.swift", "PointerCover.swift")]


def build(directory, name, replace=None):
    files = list(sources)
    if replace:
        source, old, new = replace
        target = root / source if "/" in source else app / source
        text = target.read_text()
        assert old in text, f"negative control no longer matches {source}: {old}"
        changed = Path(directory) / f"{name}-{target.name}"
        changed.write_text(text.replace(old, new))
        files = [changed if path == target else path for path in files]
    executable = Path(directory) / name
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *map(str, files), str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    return executable


with tempfile.TemporaryDirectory(prefix="parc-empty-window-") as directory:
    controls = {
        "hiding with a pending pane": (("SidebarMotionController.swift", "requested == .hidden && pendingPane ? .floating : requested",
                                        "requested"), "hiding while a pane is pending floats the sidebar"),
        "empty Space holds": (("SidebarMotionController.swift", "pendingSplitPane && !creatingSpace", "!creatingSpace"),
                              "an empty Space leaves the sidebar to Command-S"),
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
        "engine follows a closing tab": (("Sources/ParcCore/WindowPresentation.swift",
                                          "!awaitsCloseReplacement && !selectedTabIDs.contains(where: closing)", "!awaitsCloseReplacement"),
                                         "the current Space is kept and a second Space isn't selected while the last tab is closing"),
        "engine follows a closed tab": (("Sources/ParcCore/WindowPresentation.swift",
                                         "if isReady, selectedTabIDs.contains(id) { awaitsCloseReplacement = true }\n", ""),
                                        "a single Space is unchanged"),
        "survivor refused": (("Sources/ParcCore/WindowPresentation.swift", "selectedTabIDs.contains(id) || ", ""),
                             "an engine pick of the pane still on screen is followed as before"),
        "engine ignored for good": (("Sources/ParcCore/WindowPresentation.swift",
                                     "mutating func engineSelectionSynchronized() { awaitsCloseReplacement = false }",
                                     "mutating func engineSelectionSynchronized() {}"),
                                    "once the window pushed its choice a page asking for focus is followed again"),
    }
    with ThreadPoolExecutor() as pool:
        main = pool.submit(build, directory, "check")
        built = {name: pool.submit(build, directory, name.replace(" ", "-"), replace)
                 for name, (replace, _) in controls.items()}
    subprocess.run([str(main.result())], check=True)
    for name, (replace, failure) in controls.items():
        result = subprocess.run([str(built[name].result())], capture_output=True, text=True)
        assert result.returncode >= 0, f"negative control crashed with signal {-result.returncode} instead of failing: {name}\n{result.stderr[-1000:]}"
        assert result.returncode != 0 and failure in result.stderr, f"negative control did not fail: {name}\n{result.stderr[-1000:]}"
        print(f"EmptyWindow negative control fails as expected: {name}")
