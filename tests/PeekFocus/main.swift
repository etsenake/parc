import AppKit

@MainActor private final class FocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor private final class GateWindow: NSWindow {
    var reportVacant = false
    override var firstResponder: NSResponder? { reportVacant ? nil : super.firstResponder }
    func vacate() {
        willChangeValue(forKey: "firstResponder"); reportVacant = true
        didChangeValue(forKey: "firstResponder")
    }
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if reportVacant {
            willChangeValue(forKey: "firstResponder"); reportVacant = false
            let result = super.makeFirstResponder(responder)
            didChangeValue(forKey: "firstResponder"); return result
        }
        return super.makeFirstResponder(responder)
    }
}

@main struct PeekFocusTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        func makeWindow() -> GateWindow {
            let window = GateWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            return window
        }
        let window = makeWindow(), otherWindow = makeWindow()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        window.contentView!.addSubview(root)
        let renderer = FocusView(frame: root.bounds), control = FocusView(frame: .zero)
        root.addSubview(renderer); root.addSubview(control)
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        renderer.addSubview(editor)
        let outside = FocusView(frame: .zero); window.contentView!.addSubview(outside)
        var delivered = 0
        expect(window.makeFirstResponder(editor), "Native editable descendant receives focus")
        editor.string = "actual native selection"
        editor.setSelectedRange(NSRange(location: 7, length: 6))
        let original = PeekFocusReturn(source: root)!
        expect(original.perform(in: window, ownerIsAvailable: { true }) { responder in
            delivered += 1
            expect(responder === editor, "Captures exact native editor, not page root")
            expect(window.firstResponder === editor, "Lease never moves focus itself")
        }, "Original window and descendant are admitted")
        expect(editor.selectedRange() == NSRange(location: 7, length: 6), "Native text selection is untouched")
        expect(!original.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 }, "Lease is one-use")
        expect(delivered == 1, "Delivery occurs once")

        let sameModal = PeekFocusReturn(source: root)!
        expect(window.makeFirstResponder(control), "Native Tab/control transition succeeds")
        expect(!sameModal.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 }, "New control owns focus even inside Peek")
        let outsideReturn = PeekFocusReturn(source: root)!
        expect(window.makeFirstResponder(outside), "Unrelated control takes focus")
        expect(window.makeFirstResponder(control), "Control can later return to original")
        expect(!outsideReturn.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 }, "Leaving and returning never revives stale lease")

        let vacant = PeekFocusReturn(source: root)!
        window.vacate()
        expect(vacant.perform(in: window, ownerIsAvailable: { true }) { responder in
            expect(responder === control, "Temporary vacancy retains weak original identity")
            delivered += 1
        }, "AppKit vacancy during teardown permits original return")
        expect(window.makeFirstResponder(control), "Real control is restored for next interaction")
        let changedThenVacant = PeekFocusReturn(source: root)!
        expect(window.makeFirstResponder(outside), "Outside ownership is observed")
        window.vacate()
        expect(!changedThenVacant.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 }, "Vacancy after an unrelated owner cannot bypass cancellation")
        expect(window.makeFirstResponder(control), "Real responder after vacancy")
        let removed = PeekFocusReturn(source: root)!
        root.removeFromSuperview(); window.vacate()
        expect(removed.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 }, "Original disappearing hierarchy can return to surviving parent")
        window.contentView!.addSubview(root)
        expect(window.makeFirstResponder(control), "Reattached original test hierarchy")

        let refusedOwner = PeekFocusReturn(source: root)!
        expect(!refusedOwner.perform(in: window, ownerIsAvailable: { false }) { _ in delivered += 1 }, "Unavailable page/profile/window/security owner refuses")
        expect(!refusedOwner.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 }, "Later owner availability cannot revive refused operation")
        let wrongWindow = PeekFocusReturn(source: root)!
        expect(!wrongWindow.perform(in: otherWindow, ownerIsAvailable: { true }) { _ in delivered += 1 }, "No other physical window can consume original lease")
        let cancelled = PeekFocusReturn(source: root)!
        cancelled.cancel()
        expect(!cancelled.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 }, "Hidden/finished Peek cancels outstanding return")
        expect(window.makeFirstResponder(outside), "Unrelated control remains eligible for normal AppKit focus")
        expect(PeekFocusReturn(source: root) == nil, "Cannot capture a control outside original hierarchy")
        let unattached = FocusView(frame: .zero)
        expect(PeekFocusReturn(source: unattached) == nil, "Detached source has no focus ownership")

        expect(window.makeFirstResponder(control), "Original control before deallocation check")
        weak var weakWindow: NSWindow?, weakView: NSView?
        var weakLease: PeekFocusReturn?
        autoreleasepool {
            let temporary = makeWindow(); weakWindow = temporary
            let view = FocusView(frame: .zero); weakView = view
            temporary.contentView!.addSubview(view)
            expect(temporary.makeFirstResponder(view), "Temporary native owner receives focus")
            weakLease = PeekFocusReturn(source: view)
            temporary.close()
        }
        expect(weakWindow == nil && weakView == nil, "Lease does not retain closed window or responder")
        expect(!weakLease!.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 }, "Lost original owner cannot resolve to current window")
        expect(delivered == 3, "Only exact original/temporary-vacancy/removal cases delivered")
        window.close(); otherWindow.close()
        print("PASS: \(checks) original Peek-focus return assertions")
    }
}
