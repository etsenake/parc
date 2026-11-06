#!/usr/bin/env python3
"""Sidebar edge-resize, window-width and page content-resize models and their
production AppKit parts (the strip, the page hold, PCBrowserView's report
adapter over a stub of the engine's view tree), and each window's width record
through the real session store; no browser or input.

Haptics and renderer reports are injected; the off-screen window is never made key.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
# AppDelegate and BrowserWindowController are not compiled here; AppKit's
# restoration and the launch fallback reach the checked record, order and
# seeding through these lines.
delegate = (root / "Sources/ParcApp/AppDelegate.swift").read_text()
for use in ("unrestoredWindowRecords = store.state.settings.restoreSession ? store.windowRecords : []",
            "guard let record = unrestoredWindowRecords.first(where: { $0.id == id }),",
            "makeBrowserWindow(renderInitialSelection: true, showImmediately: false, restoredRecord: record)",
            "let record = shouldRestoreFallback && store.state.settings.restoreSession ? unrestoredWindowRecords.first : nil",
            "createStandardWindow(showCommandBar: false, restoring: record)",
            "restoredRecord: restoredRecord)",
            "controller.onSessionRecordChange = { [weak self] in self?.scheduleWindowSessionRecord() }",
            "let indices = BrowserWindowRecord.sessionOrder(",
            "holdsFrameAutosave: standard.map { $0.window?.frameAutosaveName == BrowserWindowController.sharedFrameAutosaveName },",
            "BrowserWindowRecord.preservingUnrestored(live: live, unrestored: unrestoredWindowRecords)"):
    assert use in delegate, f"AppDelegate no longer restores or records window widths by the checked paths: {use}"
# AppKit's restoration above and createStandardWindow's fallback each pass their record on.
assert delegate.count("restoredRecord: record)") == 2, "AppDelegate no longer hands both restored records to their windows"
quit_start = delegate.index("guard windows.allSatisfy({ $0.prepareNotesToClose() }) else {")
assert delegate.index("recordWindowSessions()", quit_start) < delegate.index("terminationInProgress = true", quit_start), \
    "quit no longer records the windows before it starts closing them"
window = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
for use in ("didSet { if windowSidebarWidth != oldValue { onSessionRecordChange?() } }",
            "windowSidebarWidth = SidebarWindowWidth(lastUsed: store.state.settings.sidebarWidth, restored: restoredRecord?.sidebarWidth)",
            "BrowserWindowRecord(sidebarWidth: windowSidebarWidth.width, itemLastActiveDates: closedItems.itemLastActiveDates,"):
    assert use in window, f"BrowserWindowController no longer seeds or reports its width record by the checked paths: {use}"
model = root / "Sources/ParcCore/SidebarResize.swift"
hold = root / "Sources/ParcCore/PageContentResize.swift"
core = sorted((root / "Sources/ParcCore").glob("*.swift"))
with tempfile.TemporaryDirectory(prefix="parc-sidebar-resize-") as directory:
    for name, sources in [("gesture", [model, here / "SidebarResizeGestureTests.swift"]),
                          ("width", [model, here / "SidebarWindowWidthTests.swift"]),
                          ("session", [*core, here / "SidebarWindowSessionTests.swift"]),
                          ("region", [model, root / "Sources/ParcApp/SidebarResizeRegion.swift",
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
