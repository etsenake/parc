import AppKit
import Testing
@testable import Parc

struct PopupWindowTests {
    @MainActor private static func window() -> BrowserPopupWindow {
        _ = NSApplication.shared
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        return BrowserPopupWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: style, backing: .buffered, defer: false)
    }

    @MainActor @Test func aPopupCanBecomeKeyAndMain() {
        let window = Self.window()
        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
        window.close()
    }

    @MainActor @Test func aPopupIsNeverRestoredOrHiddenOnDeactivate() {
        let window = Self.window()
        #expect(!window.isRestorable)
        #expect(!window.hidesOnDeactivate)
        #expect(!window.becomesKeyOnlyIfNeeded)
        window.close()
    }

    @MainActor @Test func aPopupIsManagedAndNotVisibleUntilShown() {
        let window = Self.window()
        #expect(window.collectionBehavior.contains(.managed))
        #expect(!window.isVisible)
        window.close()
    }
}
