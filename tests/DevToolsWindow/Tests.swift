import AppKit

/// Inert window: no ordering or activation. Overrides key state for focus checks.
@MainActor private final class GeometryWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}

@main
struct DevToolsWindowTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            precondition(condition(), message)
        }

        expect(DevToolsWindowGeometry.autosaveSuffix == ".devToolsWindowAutosaveFrame",
               "Recovered autosave suffix")
        expect(DevToolsWindowGeometry.frameAutosaveName(bundleIdentifier: "company.browser")
                == "company.browser.devToolsWindowAutosaveFrame",
               "Autosave name is bundle identifier plus recovered suffix")
        expect(DevToolsWindowGeometry.frameAutosaveName(bundleIdentifier: nil)
                == ".devToolsWindowAutosaveFrame",
               "Missing bundle identifier still appends the recovered suffix")
        expect(DevToolsWindowGeometry.styleMask.rawValue == 0x800f,
               "Recovered NSWindow style mask 0x800f")
        expect(DevToolsWindowGeometry.collectionBehavior == .fullScreenPrimary,
               "Recovered collection behavior 0x100")

        let chrome = GeometryWindow(contentRect: .zero,
                                    styleMask: DevToolsWindowGeometry.styleMask,
                                    backing: .buffered, defer: false)
        chrome.isReleasedWhenClosed = false
        DevToolsWindowGeometry.applyChrome(to: chrome)
        expect(!chrome.isOpaque, "Undocked tools window is not opaque")
        expect(chrome.collectionBehavior.contains(.fullScreenPrimary),
               "Undocked tools window is fullScreenPrimary")
        expect(chrome.titlebarAppearsTransparent, "Titlebar is transparent")
        expect(chrome.isMovableByWindowBackground, "Window is movable by background")
        expect(chrome.title == "Developer Tools", "Localized default title")
        expect(chrome.minSize == NSSize(width: 0, height: 0),
               "Constructor does not invent a minimum size")

        let defaults = UserDefaults.standard
        let name = "Parc.TESTS.DevToolsWindow.\(UUID().uuidString)"
        let saved = NSRect(x: 40, y: 50, width: 620, height: 480)
        chrome.setFrame(saved, display: false)
        chrome.saveFrame(usingName: name)
        let restored = GeometryWindow(contentRect: .zero,
                                      styleMask: DevToolsWindowGeometry.styleMask,
                                      backing: .buffered, defer: false)
        restored.isReleasedWhenClosed = false
        expect(DevToolsWindowGeometry.restoreFrame(restored, using: name),
               "setFrameUsingName restores a saved tools frame")
        expect(abs(restored.frame.width - saved.width) < 0.5
                && abs(restored.frame.height - saved.height) < 0.5,
               "Restored content size matches the saved frame")

        let missing = "Parc.TESTS.DevToolsWindow.missing.\(UUID().uuidString)"
        let fallback = GeometryWindow(contentRect: .zero,
                                      styleMask: DevToolsWindowGeometry.styleMask,
                                      backing: .buffered, defer: false)
        fallback.isReleasedWhenClosed = false
        expect(!DevToolsWindowGeometry.restoreFrame(fallback, using: missing,
                                                   fallbackContentSize: NSSize(width: 320, height: 240)),
               "Missing autosave name centers after the empty-rect fallback")
        expect(abs(fallback.frame.width - 320) < 1 && abs(fallback.frame.height - 240) < 40,
               "Empty restore uses the documented first-open fallback size")

        defaults.removeObject(forKey: "NSWindow Frame \(name)")
        chrome.close()
        restored.close()
        fallback.close()

        // P0-C: identical undocked root geometry skips frame writes / onLayout.
        let bounds = NSRect(x: 0, y: 0, width: 900, height: 700)
        let settled = DevToolsRootLayoutSkip.plan(
            bounds: bounds, sidePanelVisible: false, errorHidden: true)
        expect(DevToolsRootLayoutSkip.surfacesAlreadyMatch(
                settled,
                sidePanelFrame: settled.sidePanelFrame,
                sidePanelHidden: settled.sidePanelHidden,
                pageContainerFrame: settled.pageContainerFrame,
                errorLabelFrame: settled.errorLabelFrame),
               "Surfaces matching the plan are a true layout no-op")
        expect(!DevToolsRootLayoutSkip.surfacesAlreadyMatch(
                settled,
                sidePanelFrame: settled.sidePanelFrame,
                sidePanelHidden: settled.sidePanelHidden,
                pageContainerFrame: NSRect(x: 0, y: 0, width: 800, height: 700),
                errorLabelFrame: settled.errorLabelFrame),
               "A drifted page container still requires layout")
        let withPanel = DevToolsRootLayoutSkip.plan(
            bounds: bounds, sidePanelVisible: true, errorHidden: true)
        expect(withPanel.pageContainerFrame.width < settled.pageContainerFrame.width,
               "Side panel visibility shrinks the page container")
        expect(!DevToolsRootLayoutSkip.surfacesAlreadyMatch(
                withPanel,
                sidePanelFrame: settled.sidePanelFrame,
                sidePanelHidden: settled.sidePanelHidden,
                pageContainerFrame: settled.pageContainerFrame,
                errorLabelFrame: settled.errorLabelFrame),
               "Side panel visibility changes are not skipped")
        let withError = DevToolsRootLayoutSkip.plan(
            bounds: bounds, sidePanelVisible: false, errorHidden: false)
        expect(withError.pageContainerFrame.origin.y == 44
                && withError.pageContainerFrame.height == bounds.height - 44,
               "Error footer lifts the page container")
        expect(!DevToolsRootLayoutSkip.surfacesAlreadyMatch(
                withError,
                sidePanelFrame: settled.sidePanelFrame,
                sidePanelHidden: settled.sidePanelHidden,
                pageContainerFrame: settled.pageContainerFrame,
                errorLabelFrame: settled.errorLabelFrame),
               "Error-footer visibility changes are not skipped")

        print("DevToolsWindow: \(assertions) assertions passed")
    }
}
