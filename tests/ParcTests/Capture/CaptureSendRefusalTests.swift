import AppKit
import Testing
@testable import Parc

@MainActor
struct CaptureSendRefusalTests {
    private final class KeyWindow: NSWindow { override var isKeyWindow: Bool { true } }

    private func window<W: NSWindow>(_ type: W.Type) -> W {
        _ = NSApplication.shared
        let window = W(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func anActiveWindowWithoutASheetSendsTheCapture() {
        #expect(CaptureSendRefusal.check(window(KeyWindow.self)) == nil)
    }

    @Test func aWindowThatCannotBecomeActiveSaysSoInsteadOfDroppingTheClick() {
        let refusal = CaptureSendRefusal.check(window(NSWindow.self))
        #expect(refusal == .windowNotActive)
        #expect(refusal?.localizedDescription.isEmpty == false)
    }

    @Test func everyRefusalExplainsItself() {
        for refusal in [CaptureSendRefusal.windowNotActive, .sheetOpen, .captureExpired, .windowBusy] {
            #expect(refusal.errorDescription?.isEmpty == false)
        }
    }
}
