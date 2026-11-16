#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
delegate = (root / "Sources/ParcApp/AppDelegate.swift").read_text()
for use in ("unrestoredWindowRecords = store.state.settings.restoreSession ? store.windowRecords : []",
            "guard let record = unrestoredWindowRecords.first(where: { $0.id == id }),",
            "makeBrowserWindow(renderInitialSelection: true, showImmediately: false, restoredRecord: record)",
            "let record = shouldRestoreFallback && store.state.settings.restoreSession ? unrestoredWindowRecords.first : nil",
            "createStandardWindow(showCommandBar: false, restoring: record)",
            "restoredRecord: record, restoresSavedFrame: record != nil)",
            "restoredRecord: restoredRecord, restoresSavedFrame: restoresSavedFrame)",
            "controller.onSessionRecordChange = { [weak self] in self?.scheduleWindowSessionRecord() }",
            "let indices = BrowserWindowRecord.sessionOrder(",
            "holdsFrameAutosave: standard.map { $0.window?.frameAutosaveName == BrowserWindowController.sharedFrameAutosaveName },",
            "BrowserWindowRecord.preservingUnrestored(live: live, unrestored: unrestoredWindowRecords)",
            "!windows.contains(where: { $0.window?.frameAutosaveName == BrowserWindowController.sharedFrameAutosaveName }) {",
            "standard[first].keepSharedFrame()",
            "replayWindow = ReplayWindow(record: original.sessionRecord, frame: original.savedFrame?.rect ?? window.frame,"):
    assert use in delegate, f"AppDelegate no longer restores or records window widths by the checked paths: {use}"
assert delegate.count("restoredRecord: record)") == 1 and delegate.count("restoredRecord: record, restoresSavedFrame: record != nil)") == 1, \
    "AppDelegate no longer hands both restored records to their windows, with only its own fallback placing the saved frame"
assert delegate.count("restoresSavedFrame:") == 3, "a window other than the fallback now places itself from its saved frame"
quit_start = delegate.index("guard windows.allSatisfy({ $0.prepareNotesToClose() }) else {")
assert delegate.index("recordWindowSessions()", quit_start) < delegate.index("terminationInProgress = true", quit_start), \
    "quit no longer records the windows before it starts closing them"
window = browser_window_controller_source(root / "Sources/ParcApp")
for use in ("didSet { if windowSidebarWidth != oldValue { onSessionRecordChange?() } }",
            "windowSidebarWidth = SidebarWindowWidth(lastUsed: store.state.settings.sidebarWidth, restored: restoredRecord?.sidebarWidth)",
            "BrowserWindowRecord(sidebarWidth: windowSidebarWidth.width, itemLastActiveDates: closedItems.itemLastActiveDates,",
            "frame: savedFrame)",
            "if fullscreenPhase != nil || window.styleMask.contains(.fullScreen) { return windowedFrame }",
            "if fullscreenPhase == nil, let frame = window.flatMap({ SavedWindowFrame($0.frame) }) { windowedFrame = frame }",
            "windowedFrame = restoredRecord?.frame",
            "if restoresSavedFrame, let frame = Self.restoredFrame(restoredRecord, minimumSize: window.minSize) {",
            "} else if nativeWindowRequest == nil && restoredRecord == nil { Self.placeNewStandardWindow(window) }",
            "record?.frame?.placed(minimumSize: minimumSize, screens: NSScreen.screens.map(\\.visibleFrame))",
            "guard let window, fullscreenPhase == nil, !window.styleMask.contains(.fullScreen) else { return }",
            "func windowDidMove(_ notification: Notification) {\n        if window?.inLiveResize != true { reportFrameChange() }",
            "func windowDidResize(_ notification: Notification) {\n        if window?.inLiveResize != true { reportFrameChange() }",
            "func windowDidEndLiveResize(_ notification: Notification) { reportFrameChange() }"):
    assert use in window, f"BrowserWindowController no longer seeds or reports its width record by the checked paths: {use}"
model = root / "Sources/ParcCore/SidebarResize.swift"
placement = root / "Sources/ParcCore/SavedWindowFrame.swift"
hold = root / "Sources/ParcCore/PageContentResize.swift"
core = sorted((root / "Sources/ParcCore").glob("*.swift"))
with tempfile.TemporaryDirectory(prefix="parc-sidebar-resize-") as directory:
    for name, sources in [("gesture", [model, here / "SidebarResizeGestureTests.swift"]),
                          ("width", [model, here / "SidebarWindowWidthTests.swift"]),
                          ("placement", [placement, here / "SavedWindowFrameTests.swift"]),
                          ("session", [*core, here / "SidebarWindowSessionTests.swift"]),
                          ("region", [model, root / "Sources/ParcApp/SidebarResizeRegion.swift", root / "Sources/ParcApp/PointerCover.swift",
                                      here / "SidebarResizeRegionTests.swift"]),
                          ("hold", [hold, here / "PageContentResizeTests.swift"]),
                          ("resizer", [hold, root / "Sources/ParcApp/PageContentResizer.swift",
                                       here / "PageContentResizerTests.swift"]),
                          ("frames", [hold, root / "Sources/ParcApp/PageContentResizer.swift",
                                      root / "Sources/ParcApp/PageRenderFrames.swift",
                                      here / "EngineStub.swift", here / "PageRenderFramesTests.swift"])]:
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
