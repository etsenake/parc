import AppKit
import Testing
@testable import ParcSettings

struct SettingsCloseCommandTests {
    @MainActor private final class Window: NSWindow {
        var shown = true
        var key = true
        var testSheet: NSWindow?
        var closeRequests = 0
        override var isVisible: Bool { shown }
        override var isKeyWindow: Bool { key }
        override var attachedSheet: NSWindow? { testSheet }
        override func performClose(_ sender: Any?) { closeRequests += 1 }

        init() {
            _ = NSApplication.shared
            super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                       styleMask: .borderless, backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    @Test @MainActor func closeTargetsOnlyTheOriginalSettingsWindow() {
        let settings = Window(), other = Window()
        SettingsCloseCommand.perform(window: settings, appIsActive: true, sender: nil)
        #expect(settings.closeRequests == 1)
        #expect(other.closeRequests == 0)
    }

    @Test(arguments: [(false, true, false, true), (true, true, true, true),
                      (true, false, false, true), (true, true, false, false)])
    @MainActor func aSettingsWindowThatCannotOwnCloseIgnoresIt(key: Bool, shown: Bool, sheet: Bool, active: Bool) {
        let settings = Window()
        settings.key = key
        settings.shown = shown
        settings.testSheet = sheet ? Window() : nil
        SettingsCloseCommand.perform(window: settings, appIsActive: active, sender: nil)
        #expect(settings.closeRequests == 0)
    }

    @Test @MainActor func aMissingWindowIsUnavailable() {
        #expect(!SettingsCloseCommand.isAvailable(window: nil, appIsActive: true))
    }
}
