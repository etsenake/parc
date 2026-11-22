import AppKit
import Testing
@testable import Parc

@MainActor
struct PaneTitleMenuAvailabilityTests {
    private final class Host: NSWindow {
        var key = true
        override var isKeyWindow: Bool { key }
    }

    enum Blocker: CaseIterable {
        case disabled, hidden, inactive, detached
    }

    @Test(arguments: [nil] + Blocker.allCases.map(Optional.some))
    func titleMenuFollowsTheControlsAvailability(blocker: Blocker?) {
        _ = NSApplication.shared
        let window = Host(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                          styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let control = PaneTitleControl(frame: NSRect(x: 0, y: 0, width: 120, height: 30),
                                       displayOptionsCenter: NotificationCenter())
        let menu = NSMenu()
        var requests = 0
        control.menuProvider = { requests += 1; return menu }
        if blocker != .detached { window.contentView?.addSubview(control) }
        window.key = blocker != .inactive
        control.isEnabled = blocker != .disabled
        control.isHidden = blocker == .hidden

        if blocker == nil {
            #expect(control.titleMenu() === menu)
            #expect(requests == 1)
        } else {
            #expect(control.titleMenu() == nil)
            #expect(requests == 0)
        }
    }
}
