#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]


def body(path, start, end):
    text = browser_window_controller_source(root / "Sources/ParcApp") if path == controller else (root / path).read_text()
    assert text.count(start) == 1, f"{path}: expected one {start!r}"
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def require(text, where, present=(), absent=()):
    for token in present:
        assert token in text, f"{where} no longer checks {token!r}"
    for token in absent:
        assert token not in text, f"{where} depends on {token!r} again"


def refuses(text, where, *patterns):
    for pattern in patterns:
        assert re.search(pattern, text), f"{where} no longer refuses on {pattern!r}"


focus = ("isKeyWindow", "keyWindow", "NSApp.isActive", "NSApp.active", "firstResponder",
         "selectedNativePage", "focusedTabID", "makeKeyAndOrderFront", "orderFront", "makeFirstResponder",
         "activateIgnoringOtherApps", "NSApp activate", "NSApp.activate")

controller = "Sources/ParcApp/BrowserWindowController.swift"
allows = body(controller, "func nativeBrowser(_ browser: PCNativeBrowserWindow, allowsHistorySwipeFor page: PCNativePage) -> Bool {",
              "\n    }\n")
require(allows, "the shell's swipe rule", present=(
    "browser === nativeBinding", "!page.isClosed", "!isClosing", "!wholeWindowClose", "!windowClosePending",
    "!windowCloseApproved", "closingTabIDs.isEmpty", "modelRetirementIDs.isEmpty", "peekRetirementParents.isEmpty",
    "transferringTabIDs.isEmpty", "resolvingTransfers.isEmpty", "commandBar == nil", "libraryView == nil",
    "tabSwitcher == nil", "navigationHistory == nil", "themePopover == nil", "!siteControlCenterDefers",
    "pageCapture == nil", "menuTrackingDepth == 0", "window?.attachedSheet == nil",
    "PCNativeBrowserApplication.owner(of: page) === browser", "historySwipePages.contains"), absent=focus)
pages = body(controller, "var historySwipePages: [PCNativePage] {", "\n    }\n")
require(pages, "the swipeable page list", present=(
    "HistorySwipeTargets.pages(", "renderedPaneIDs", "activePeek", "selectedPage",
    "isInternal: tab.map { InternalPage.isInternal($0.url) } ?? true",
    "isHidden: browser?.isHiddenOrHasHiddenAncestor ?? true"), absent=focus)

engine = body("Engine/ParcNative/native_appkit_page.mm", "bool CanNativePageHistorySwipe(PCNativePage* page) {", "\n}\n")
require(engine, "the engine's swipe rule", present=("allowsHistorySwipeForPage",), absent=focus)
refuses(engine, "the engine's swipe rule", r"if \(!browser \|\| !window\.visible \|\| (?<!!)window\.miniaturized \|\|",
        r"\|\|\s+(?<!!)page\.nativeView\.hiddenOrHasHiddenAncestor \|\|",
        r"\|\|\s+(?<!!)PCNativeWindowHasSecurityReservation\(window\)\) return false;")

session = body("Engine/ParcNative/native_history_swipe.mm", "class SwipeSession final", "\n};\n")
require(session, "the swipe session", present=(
    "NSWindowWillCloseNotification", "NSWindowDidMiniaturizeNotification", "NSWindowWillBeginSheetNotification",
    "PCNativeWindowSecurityStateChanged", "RegisterWillDeactivate", "RegisterWillDetach", "DidStartNavigation",
    "PrimaryPageChanged", "OnVisibilityChanged", "WebContentsDestroyed", "HistoryUnchanged()",
    "CanNativePageHistorySwipe(page_)", "chrome::GoBack(web_contents())", "chrome::GoForward(web_contents())",
    "GetController().GoToIndex(index)"), absent=focus + ("ResignKey", "ResignActive", "NavigationBrowser("))

delegate = body("Engine/ParcNative/native_history_swipe.mm", "@implementation PCNativeHistorySwipeDelegate {", "\n@end\n")
require(delegate, "the swipe forwarder's engine half", present=(
    "CanNativePageHistorySwipe(", "HistorySwipingControl::FromWebContents", "_session->Current()",
    "historyOverlayContainer", "BackNavigationLikely"), absent=focus + (
    "[super handleEvent", "[super touches", "[super rendererHandled", "cancelHistorySwiping", "HistorySwiperDelegate"))
glue = "".join((root / path).read_text() for path in (
    "Sources/ParcApp/HistorySwipeForwarder.swift", "Sources/ParcApp/HistorySwipeDriver.swift"))
require(glue, "the swipe forwarder's Swift half", present=("source.navigate(back:", "source?.allowsHistorySwipe"),
        absent=focus + ("performNavigation", "navigationHistory("))

with tempfile.TemporaryDirectory(prefix="parc-history-swipe-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/HistorySwipeTargets.swift"), str(Path(__file__).with_name("main.swift")),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
