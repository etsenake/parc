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

        let parent = FocusView(frame: .zero); window.contentView!.addSubview(parent)
        expect(window.makeFirstResponder(control), "Peek control holds focus as its close begins")
        let lent = PeekFocusReturn(source: root)!
        lent.lend(in: window) { window.makeFirstResponder(parent) }
        expect(window.firstResponder === parent, "A leaving Peek hands typing to the surviving parent at once")
        lent.lend(in: window) { window.makeFirstResponder(outside) }
        expect(window.firstResponder === parent, "Focus is lent only once")
        expect(lent.perform(in: window, ownerIsAvailable: { true }) { responder in
            expect(responder === control, "A refused close returns to the Peek's own control")
            delivered += 1
        }, "Focus lent to the parent still returns when the card comes back")
        expect(window.makeFirstResponder(control), "Peek control before a second close")
        let movedOn = PeekFocusReturn(source: root)!
        movedOn.lend(in: window) { window.makeFirstResponder(parent) }
        expect(window.makeFirstResponder(outside), "The person picks another control during the fade")
        expect(!movedOn.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 },
               "A choice made during the fade is never overridden")
        expect(window.makeFirstResponder(control), "Peek control before a refused handover")
        let parked = PeekFocusReturn(source: root)!
        parked.lend(in: window) { false }
        expect(window.firstResponder === window, "When the parent can't take typing, the leaving page still lets go")
        expect(parked.perform(in: window, ownerIsAvailable: { true }) { _ in delivered += 1 },
               "A parked return still completes after the close")
        expect(window.makeFirstResponder(control), "Peek control before a handover the selection isn't ready for")
        let late = PeekFocusReturn(source: root)!
        expect(late.lend(in: window) { false } && window.firstResponder === window,
               "The leaving page lets go when the parent can't take typing yet")
        expect(late.lend(in: window) { window.makeFirstResponder(parent) } && window.firstResponder === parent,
               "Once the parent's page is selected, a later handover gives it the keyboard")
        expect(!late.lend(in: window) { window.makeFirstResponder(outside) } && window.firstResponder === parent,
               "A completed late handover is not repeated")
        expect(late.perform(in: window, ownerIsAvailable: { true }) { responder in
            expect(responder === control, "A refusal after a late handover returns to the Peek's control")
            delivered += 1
        }, "A late handover still returns when the card comes back")
        expect(window.makeFirstResponder(control), "Peek control before a choice made while the keyboard is parked")
        let chosen = PeekFocusReturn(source: root)!
        chosen.lend(in: window) { false }
        expect(window.makeFirstResponder(outside), "The person picks another control while nobody holds the keyboard")
        expect(!chosen.lend(in: window) { window.makeFirstResponder(parent) } && window.firstResponder === outside,
               "A later handover never takes the keyboard from a control the person picked")
        expect(window.makeFirstResponder(control), "Peek control before an unparked vacancy")
        let unparked = PeekFocusReturn(source: root)!
        window.vacate()
        expect(!unparked.lend(in: window) { window.makeFirstResponder(parent) } && window.firstResponder == nil,
               "Only a keyboard the leaving page itself let go can be handed over later")
        expect(unparked.isActive, "A return that couldn't lend stays live, so a refusal can still bring typing back")
        expect(!chosen.isActive, "A return the person overrode is spent")
        expect(window.makeFirstResponder(control), "Peek control after the vacancy check")
        expect(window.makeFirstResponder(control), "Peek control before focus leaves on its own")
        let stale = PeekFocusReturn(source: root)!
        expect(window.makeFirstResponder(outside), "Another control takes focus before the fade")
        stale.lend(in: window) { window.makeFirstResponder(parent) }
        expect(window.firstResponder === outside, "Focus that already left the Peek is not moved")
        expect(window.makeFirstResponder(control), "Peek control before a hidden Peek's close")
        let hidden = PeekFocusReturn(source: root)!
        hidden.cancel()
        hidden.lend(in: window) { window.makeFirstResponder(parent) }
        expect(window.firstResponder === control && !hidden.isActive, "A cancelled return lends nothing and is spent")
        parent.removeFromSuperview()

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
        expect(delivered == 6, "Only exact original/temporary-vacancy/removal/lent/parked/late cases delivered")
        window.close(); otherWindow.close()
        print("PASS: \(checks) original Peek-focus return assertions")
    }
}
