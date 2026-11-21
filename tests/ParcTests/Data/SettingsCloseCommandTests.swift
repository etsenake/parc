import AppKit
import Testing
@testable import Parc

@MainActor
struct SettingsCloseCommandTests {
    @MainActor
    private final class ProbeWindow: NSWindow {
        var shown = true
        var key = true
        var testSheet: NSWindow?
        var closeRequests = 0
        override var isVisible: Bool { shown }
        override var isKeyWindow: Bool { key }
        override var attachedSheet: NSWindow? { testSheet }
        override func performClose(_ sender: Any?) { closeRequests += 1 }

        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    @Test func theOriginalSettingsWindowIsClosedOnce() {
        let settings = ProbeWindow(), browser = ProbeWindow()
        SettingsCloseCommand.perform(window: settings, appIsActive: true, sender: nil)
        #expect(settings.closeRequests == 1)
        #expect(browser.closeRequests == 0)
    }

    @Test func aWindowThatIsNotKeyIsNotClosed() {
        let settings = ProbeWindow()
        settings.key = false
        SettingsCloseCommand.perform(window: settings, appIsActive: true, sender: nil)
        #expect(settings.closeRequests == 0)
    }

    @Test func aWindowWithASheetIsNotClosed() {
        let settings = ProbeWindow()
        settings.testSheet = ProbeWindow()
        SettingsCloseCommand.perform(window: settings, appIsActive: true, sender: nil)
        #expect(settings.closeRequests == 0)
    }

    @Test func aWindowThatIsNotVisibleIsNotClosed() {
        let settings = ProbeWindow()
        settings.shown = false
        SettingsCloseCommand.perform(window: settings, appIsActive: true, sender: nil)
        #expect(settings.closeRequests == 0)
    }

    @Test func anInactiveApplicationDoesNotCloseTheWindow() {
        let settings = ProbeWindow()
        SettingsCloseCommand.perform(window: settings, appIsActive: false, sender: nil)
        #expect(settings.closeRequests == 0)
    }

    @Test func noWindowMeansTheCommandIsUnavailable() {
        #expect(!SettingsCloseCommand.isAvailable(window: nil, appIsActive: true))
    }
}
