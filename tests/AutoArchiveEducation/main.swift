import AppKit

@MainActor
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
@MainActor
func pump(_ duration: TimeInterval = 0.05) {
    RunLoop.main.run(until: Date().addingTimeInterval(duration))
}
@MainActor
func run() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let root = NSView(frame: window.contentView!.bounds)
    window.contentView = root
    let field = NSTextField(string: "Original editor")
    field.frame = NSRect(x: 250, y: 20, width: 180, height: 30)
    root.addSubview(field)
    let card = NSButton(title: "Got it", target: nil, action: nil)
    let host = SidebarBannerHost(card: card)
    host.frame = NSRect(x: 8, y: 20, width: 220, height: 180)
    var changes: [Bool] = [], relinquished = 0
    host.onInteractionChanged = { changes.append($0) }
    host.onRelinquishFocus = { relinquished += 1; window.makeFirstResponder(field) }
    root.addSubview(host)
    window.makeFirstResponder(field)
    let original = window.firstResponder
    host.show(true)
    check(host.phase == .initial && !host.isInteractive, "Entry starts with no interactive card")
    pump()
    check(host.phase == .appeared && host.isInteractive, "Entry completes on the current window")
    check(window.firstResponder === original, "Appearance preserves original native responder")
    host.show(true); pump()
    check(host.phase == .appeared && changes == [true], "Unrelated state refresh does not replay entry")
    check(card.window === window, "SwiftUI retains the original native card in the original window")
    check(window.makeFirstResponder(card), "Inert native card can own focus")
    host.setInteractionAllowed(false)
    check(relinquished == 1 && window.firstResponder !== card, "Disabling a focused card relinquishes only its own responder")
    host.setInteractionAllowed(true)
    let beforeDismissal = window.firstResponder
    host.show(false)
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        check(host.phase == .absent && !host.isInteractive, "Reduced-motion exit settles immediately")
    } else {
        check(host.phase == .dismissing && !host.isInteractive && host.occupiesSpace, "Exit retains geometry but disables controls")
    }
    check(relinquished == 1 && window.firstResponder === beforeDismissal, "Background dismissal does not change focus")
    host.show(true); pump()
    check(host.phase == .appeared && host.isInteractive, "New presentation supersedes old exit")
    pump(SidebarBannerHost.dismissalLifetime + 0.05)
    check(host.phase == .appeared, "Stale exit cannot remove a newer presentation")
    host.setInteractionAllowed(false)
    check(!host.isInteractive && host.phase == .appeared, "Hidden sidebar bypasses controls without consuming shared state")
    host.setInteractionAllowed(true)
    check(host.isInteractive, "Visible sidebar restores controls")
    host.reset()
    check(host.phase == .absent && !host.occupiesSpace && !host.isInteractive, "Window reset ends lifetime immediately")
    host.show(true); host.reset(); pump()
    check(host.phase == .absent, "Cancelled entry cannot appear later")
    host.show(true); pump(); host.removeFromSuperview(); pump()
    check(host.phase == .absent && !host.isInteractive, "Detached original window invalidates card actions")
    root.addSubview(host); pump()
    check(host.phase == .appeared, "Pending card can attach to its own window again")
    host.show(false); pump(SidebarBannerHost.dismissalLifetime + 0.05)
    check(host.phase == .absent && host.isHidden, "Completed exit releases layout space")
    host.reset(); window.close()
    print("AutoArchiveEducation inert lifecycle checks passed")
}
MainActor.assumeIsolated { exitOnFailure(run) }
