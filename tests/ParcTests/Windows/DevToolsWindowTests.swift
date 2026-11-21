import AppKit
import Testing
@testable import Parc

@MainActor private final class GeometryWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}

struct DevToolsWindowTests {
    @MainActor private static func window() -> GeometryWindow {
        _ = NSApplication.shared
        let window = GeometryWindow(contentRect: .zero, styleMask: DevToolsWindowGeometry.styleMask, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @MainActor @Test func theRecoveredAutosaveSuffix() {
        #expect(DevToolsWindowGeometry.autosaveSuffix == ".devToolsWindowAutosaveFrame")
    }

    @MainActor @Test func theAutosaveNameIsTheBundleIdentifierPlusTheRecoveredSuffix() {
        #expect(DevToolsWindowGeometry.frameAutosaveName(bundleIdentifier: "company.browser") == "company.browser.devToolsWindowAutosaveFrame")
    }

    @MainActor @Test func aMissingBundleIdentifierStillAppendsTheSuffix() {
        #expect(DevToolsWindowGeometry.frameAutosaveName(bundleIdentifier: nil) == ".devToolsWindowAutosaveFrame")
    }

    @MainActor @Test func theRecoveredStyleMaskAndCollectionBehavior() {
        #expect(DevToolsWindowGeometry.styleMask.rawValue == 0x800f)
        #expect(DevToolsWindowGeometry.collectionBehavior == .fullScreenPrimary)
    }

    @MainActor @Test func anUndockedToolsWindowIsNotOpaqueAndIsFullScreenPrimary() {
        let chrome = Self.window()
        DevToolsWindowGeometry.applyChrome(to: chrome)
        #expect(!chrome.isOpaque)
        #expect(chrome.collectionBehavior.contains(.fullScreenPrimary))
        chrome.close()
    }

    @MainActor @Test func theTitlebarIsTransparentAndTheWindowMovableByItsBackground() {
        let chrome = Self.window()
        DevToolsWindowGeometry.applyChrome(to: chrome)
        #expect(chrome.titlebarAppearsTransparent)
        #expect(chrome.isMovableByWindowBackground)
        chrome.close()
    }

    @MainActor @Test func theDefaultTitleIsDeveloperTools() {
        let chrome = Self.window()
        DevToolsWindowGeometry.applyChrome(to: chrome)
        #expect(chrome.title == "Developer Tools")
        chrome.close()
    }

    @MainActor @Test func theConstructorDoesNotInventAMinimumSize() {
        let chrome = Self.window()
        DevToolsWindowGeometry.applyChrome(to: chrome)
        #expect(chrome.minSize == NSSize(width: 0, height: 0))
        chrome.close()
    }

    @MainActor private static func savedFrame(_ name: String) -> NSRect {
        let chrome = window()
        DevToolsWindowGeometry.applyChrome(to: chrome)
        let saved = NSRect(x: 40, y: 50, width: 620, height: 480)
        chrome.setFrame(saved, display: false)
        chrome.saveFrame(usingName: name)
        chrome.close()
        return saved
    }

    @MainActor @Test func aSavedToolsFrameIsRestoredByName() {
        let name = "Parc.TESTS.DevToolsWindow.\(UUID().uuidString)"
        let saved = Self.savedFrame(name)
        let restored = Self.window()
        #expect(DevToolsWindowGeometry.restoreFrame(restored, using: name))
        #expect(abs(restored.frame.width - saved.width) < 0.5)
        #expect(abs(restored.frame.height - saved.height) < 0.5)
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
        restored.close()
    }

    @MainActor @Test func aMissingAutosaveNameCentersAfterTheEmptyRectFallback() {
        let fallback = Self.window()
        let restored = DevToolsWindowGeometry.restoreFrame(fallback, using: "Parc.TESTS.DevToolsWindow.missing.\(UUID().uuidString)",
                                                           fallbackContentSize: NSSize(width: 320, height: 240))
        #expect(!restored)
        fallback.close()
    }

    @MainActor @Test func anEmptyRestoreUsesTheFirstOpenFallbackSize() {
        let fallback = Self.window()
        _ = DevToolsWindowGeometry.restoreFrame(fallback, using: "Parc.TESTS.DevToolsWindow.missing.\(UUID().uuidString)",
                                                fallbackContentSize: NSSize(width: 320, height: 240))
        #expect(abs(fallback.frame.width - 320) < 1)
        #expect(abs(fallback.frame.height - 240) < 40)
        fallback.close()
    }

    private static let bounds = NSRect(x: 0, y: 0, width: 900, height: 700)
    private static let settled = DevToolsRootLayoutSkip.plan(bounds: bounds, sidePanelVisible: false, errorHidden: true)

    private static func matches(_ plan: DevToolsRootLayoutPlan, pageContainerFrame: NSRect? = nil) -> Bool {
        DevToolsRootLayoutSkip.surfacesAlreadyMatch(plan, sidePanelFrame: settled.sidePanelFrame, sidePanelHidden: settled.sidePanelHidden,
            pageContainerFrame: pageContainerFrame ?? settled.pageContainerFrame, errorLabelFrame: settled.errorLabelFrame)
    }

    @Test func surfacesMatchingThePlanAreATrueLayoutNoOp() {
        #expect(Self.matches(Self.settled))
    }

    @Test func aDriftedPageContainerStillRequiresLayout() {
        #expect(!Self.matches(Self.settled, pageContainerFrame: NSRect(x: 0, y: 0, width: 800, height: 700)))
    }

    @Test func sidePanelVisibilityShrinksThePageContainer() {
        let withPanel = DevToolsRootLayoutSkip.plan(bounds: Self.bounds, sidePanelVisible: true, errorHidden: true)
        #expect(withPanel.pageContainerFrame.width < Self.settled.pageContainerFrame.width)
    }

    @Test func sidePanelVisibilityChangesAreNotSkipped() {
        let withPanel = DevToolsRootLayoutSkip.plan(bounds: Self.bounds, sidePanelVisible: true, errorHidden: true)
        #expect(!Self.matches(withPanel))
    }

    @Test func theErrorFooterLiftsThePageContainer() {
        let withError = DevToolsRootLayoutSkip.plan(bounds: Self.bounds, sidePanelVisible: false, errorHidden: false)
        #expect(withError.pageContainerFrame.origin.y == 44)
        #expect(withError.pageContainerFrame.height == Self.bounds.height - 44)
    }

    @Test func errorFooterVisibilityChangesAreNotSkipped() {
        let withError = DevToolsRootLayoutSkip.plan(bounds: Self.bounds, sidePanelVisible: false, errorHidden: false)
        #expect(!Self.matches(withError))
    }
}
