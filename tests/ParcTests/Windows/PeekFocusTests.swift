import AppKit
import Testing
@testable import Parc

@MainActor private final class FocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor private final class GateWindow: NSWindow {
    var reportVacant = false
    override var firstResponder: NSResponder? { reportVacant ? nil : super.firstResponder }

    func vacate() {
        willChangeValue(forKey: "firstResponder")
        reportVacant = true
        didChangeValue(forKey: "firstResponder")
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if reportVacant {
            willChangeValue(forKey: "firstResponder")
            reportVacant = false
            let result = super.makeFirstResponder(responder)
            didChangeValue(forKey: "firstResponder")
            return result
        }
        return super.makeFirstResponder(responder)
    }
}

@MainActor private final class Scene {
    let window = Scene.makeWindow(), otherWindow = Scene.makeWindow()
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    let renderer: FocusView, control = FocusView(frame: .zero)
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
    let outside = FocusView(frame: .zero), parent = FocusView(frame: .zero)
    var delivered = 0

    static func makeWindow() -> GateWindow {
        _ = NSApplication.shared
        let window = GateWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    init() {
        renderer = FocusView(frame: root.bounds)
        window.contentView!.addSubview(root)
        root.addSubview(renderer)
        root.addSubview(control)
        renderer.addSubview(editor)
        window.contentView!.addSubview(outside)
        window.contentView!.addSubview(parent)
    }

    deinit {
        MainActor.assumeIsolated { window.close(); otherWindow.close() }
    }

    func focus(_ view: NSResponder?) { #expect(window.makeFirstResponder(view)) }

    func perform(_ lease: PeekFocusReturn, in target: NSWindow? = nil, owner: Bool = true, expecting: ((NSResponder?) -> Void)? = nil) -> Bool {
        lease.perform(in: target ?? window, ownerIsAvailable: { owner }) { [unowned self] responder in
            delivered += 1
            expecting?(responder)
        }
    }
}

struct PeekFocusTests {
    @MainActor @Test func theOriginalWindowAndDescendantAreAdmitted() throws {
        let s = Scene()
        s.focus(s.editor)
        let original = try #require(PeekFocusReturn(source: s.root))
        var seen: NSResponder?
        var current: NSResponder?
        #expect(s.perform(original) { seen = $0; current = s.window.firstResponder })
        #expect(seen === s.editor)
        #expect(current === s.editor)
    }

    @MainActor @Test func nativeTextSelectionIsUntouched() throws {
        let s = Scene()
        s.focus(s.editor)
        s.editor.string = "actual native selection"
        s.editor.setSelectedRange(NSRange(location: 7, length: 6))
        let original = try #require(PeekFocusReturn(source: s.root))
        _ = s.perform(original)
        #expect(s.editor.selectedRange() == NSRange(location: 7, length: 6))
    }

    @MainActor @Test func aLeaseIsOneUse() throws {
        let s = Scene()
        s.focus(s.editor)
        let original = try #require(PeekFocusReturn(source: s.root))
        _ = s.perform(original)
        #expect(!s.perform(original))
        #expect(s.delivered == 1)
    }

    @MainActor @Test func aNewControlOwnsFocusEvenInsideThePeek() throws {
        let s = Scene()
        s.focus(s.editor)
        let lease = try #require(PeekFocusReturn(source: s.root))
        s.focus(s.control)
        #expect(!s.perform(lease))
    }

    @MainActor @Test func leavingAndReturningNeverRevivesAStaleLease() throws {
        let s = Scene()
        s.focus(s.control)
        let lease = try #require(PeekFocusReturn(source: s.root))
        s.focus(s.outside)
        s.focus(s.control)
        #expect(!s.perform(lease))
    }

    @MainActor @Test func aTemporaryVacancyRetainsTheWeakOriginalIdentity() throws {
        let s = Scene()
        s.focus(s.control)
        let vacant = try #require(PeekFocusReturn(source: s.root))
        s.window.vacate()
        var seen: NSResponder?
        #expect(s.perform(vacant) { seen = $0 })
        #expect(seen === s.control)
    }

    @MainActor @Test func aVacancyAfterAnUnrelatedOwnerCannotBypassCancellation() throws {
        let s = Scene()
        s.focus(s.control)
        let lease = try #require(PeekFocusReturn(source: s.root))
        s.focus(s.outside)
        s.window.vacate()
        #expect(!s.perform(lease))
    }

    @MainActor @Test func theOriginalDisappearingHierarchyCanReturnToTheSurvivingParent() throws {
        let s = Scene()
        s.focus(s.control)
        let removed = try #require(PeekFocusReturn(source: s.root))
        s.root.removeFromSuperview()
        s.window.vacate()
        #expect(s.perform(removed))
    }

    @MainActor @Test func anUnavailableOwnerRefuses() throws {
        let s = Scene()
        s.focus(s.control)
        let lease = try #require(PeekFocusReturn(source: s.root))
        #expect(!s.perform(lease, owner: false))
    }

    @MainActor @Test func laterOwnerAvailabilityCannotReviveARefusedOperation() throws {
        let s = Scene()
        s.focus(s.control)
        let lease = try #require(PeekFocusReturn(source: s.root))
        _ = s.perform(lease, owner: false)
        #expect(!s.perform(lease))
    }

    @MainActor @Test func noOtherWindowCanConsumeTheLease() throws {
        let s = Scene()
        s.focus(s.control)
        let lease = try #require(PeekFocusReturn(source: s.root))
        #expect(!s.perform(lease, in: s.otherWindow))
    }

    @MainActor @Test func aHiddenOrFinishedPeekCancelsTheOutstandingReturn() throws {
        let s = Scene()
        s.focus(s.control)
        let lease = try #require(PeekFocusReturn(source: s.root))
        lease.cancel()
        #expect(!s.perform(lease))
    }

    @MainActor @Test func aControlOutsideTheOriginalHierarchyCannotBeCaptured() {
        let s = Scene()
        s.focus(s.outside)
        #expect(PeekFocusReturn(source: s.root) == nil)
    }

    @MainActor @Test func aDetachedSourceHasNoFocusOwnership() {
        #expect(PeekFocusReturn(source: FocusView(frame: .zero)) == nil)
    }

    @MainActor @Test func aLeavingPeekHandsTypingToTheSurvivingParentAtOnce() throws {
        let s = Scene()
        s.focus(s.control)
        let lent = try #require(PeekFocusReturn(source: s.root))
        lent.lend(in: s.window) { s.window.makeFirstResponder(s.parent) }
        #expect(s.window.firstResponder === s.parent)
    }

    @MainActor @Test func focusIsLentOnlyOnce() throws {
        let s = Scene()
        s.focus(s.control)
        let lent = try #require(PeekFocusReturn(source: s.root))
        lent.lend(in: s.window) { s.window.makeFirstResponder(s.parent) }
        lent.lend(in: s.window) { s.window.makeFirstResponder(s.outside) }
        #expect(s.window.firstResponder === s.parent)
    }

    @MainActor @Test func aRefusedCloseReturnsToThePeeksOwnControl() throws {
        let s = Scene()
        s.focus(s.control)
        let lent = try #require(PeekFocusReturn(source: s.root))
        lent.lend(in: s.window) { s.window.makeFirstResponder(s.parent) }
        var seen: NSResponder?
        #expect(s.perform(lent) { seen = $0 })
        #expect(seen === s.control)
    }

    @MainActor @Test func aChoiceMadeDuringTheFadeIsNeverOverridden() throws {
        let s = Scene()
        s.focus(s.control)
        let movedOn = try #require(PeekFocusReturn(source: s.root))
        movedOn.lend(in: s.window) { s.window.makeFirstResponder(s.parent) }
        s.focus(s.outside)
        #expect(!s.perform(movedOn))
    }

    @MainActor @Test func whenTheParentCannotTakeTypingTheLeavingPageStillLetsGo() throws {
        let s = Scene()
        s.focus(s.control)
        let parked = try #require(PeekFocusReturn(source: s.root))
        parked.lend(in: s.window) { false }
        #expect(s.window.firstResponder === s.window)
    }

    @MainActor @Test func aParkedReturnStillCompletesAfterTheClose() throws {
        let s = Scene()
        s.focus(s.control)
        let parked = try #require(PeekFocusReturn(source: s.root))
        parked.lend(in: s.window) { false }
        #expect(s.perform(parked))
    }

    @MainActor private static func late(_ s: Scene) throws -> PeekFocusReturn {
        s.focus(s.control)
        let late = try #require(PeekFocusReturn(source: s.root))
        late.lend(in: s.window) { false }
        return late
    }

    @MainActor @Test func theLeavingPageLetsGoWhenTheParentCannotTakeTypingYet() throws {
        let s = Scene()
        s.focus(s.control)
        let late = try #require(PeekFocusReturn(source: s.root))
        #expect(late.lend(in: s.window) { false })
        #expect(s.window.firstResponder === s.window)
    }

    @MainActor @Test func onceTheParentsPageIsSelectedALaterHandoverGivesItTheKeyboard() throws {
        let s = Scene()
        let late = try Self.late(s)
        #expect(late.lend(in: s.window) { s.window.makeFirstResponder(s.parent) })
        #expect(s.window.firstResponder === s.parent)
    }

    @MainActor @Test func aCompletedLateHandoverIsNotRepeated() throws {
        let s = Scene()
        let late = try Self.late(s)
        _ = late.lend(in: s.window) { s.window.makeFirstResponder(s.parent) }
        #expect(!late.lend(in: s.window) { s.window.makeFirstResponder(s.outside) })
        #expect(s.window.firstResponder === s.parent)
    }

    @MainActor @Test func aRefusalAfterALateHandoverReturnsToThePeeksControl() throws {
        let s = Scene()
        let late = try Self.late(s)
        _ = late.lend(in: s.window) { s.window.makeFirstResponder(s.parent) }
        var seen: NSResponder?
        #expect(s.perform(late) { seen = $0 })
        #expect(seen === s.control)
    }

    @MainActor @Test func aLaterHandoverNeverTakesTheKeyboardFromAControlThePersonPicked() throws {
        let s = Scene()
        let chosen = try Self.late(s)
        s.focus(s.outside)
        #expect(!chosen.lend(in: s.window) { s.window.makeFirstResponder(s.parent) })
        #expect(s.window.firstResponder === s.outside)
        #expect(!chosen.isActive)
    }

    @MainActor @Test func onlyAKeyboardTheLeavingPageLetGoCanBeHandedOverLater() throws {
        let s = Scene()
        s.focus(s.control)
        let unparked = try #require(PeekFocusReturn(source: s.root))
        s.window.vacate()
        #expect(!unparked.lend(in: s.window) { s.window.makeFirstResponder(s.parent) })
        #expect(s.window.firstResponder == nil)
        #expect(unparked.isActive)
    }

    @MainActor @Test func focusThatAlreadyLeftThePeekIsNotMoved() throws {
        let s = Scene()
        s.focus(s.control)
        let stale = try #require(PeekFocusReturn(source: s.root))
        s.focus(s.outside)
        stale.lend(in: s.window) { s.window.makeFirstResponder(s.parent) }
        #expect(s.window.firstResponder === s.outside)
    }

    @MainActor @Test func aCancelledReturnLendsNothingAndIsSpent() throws {
        let s = Scene()
        s.focus(s.control)
        let hidden = try #require(PeekFocusReturn(source: s.root))
        hidden.cancel()
        hidden.lend(in: s.window) { s.window.makeFirstResponder(s.parent) }
        #expect(s.window.firstResponder === s.control)
        #expect(!hidden.isActive)
    }

    @MainActor @Test func aLeaseRetainsNeitherAClosedWindowNorItsResponder() {
        weak var weakWindow: NSWindow?, weakView: NSView?
        var lease: PeekFocusReturn?
        autoreleasepool {
            let temporary = Scene.makeWindow()
            weakWindow = temporary
            let view = FocusView(frame: .zero)
            weakView = view
            temporary.contentView!.addSubview(view)
            _ = temporary.makeFirstResponder(view)
            lease = PeekFocusReturn(source: view)
            temporary.close()
        }
        #expect(weakWindow == nil)
        #expect(weakView == nil)
        _ = lease
    }

    @MainActor @Test func aLostOriginalOwnerCannotResolveToTheCurrentWindow() {
        let s = Scene()
        _ = s.delivered
        var lease: PeekFocusReturn?
        autoreleasepool {
            let temporary = Scene.makeWindow()
            let view = FocusView(frame: .zero)
            temporary.contentView!.addSubview(view)
            _ = temporary.makeFirstResponder(view)
            lease = PeekFocusReturn(source: view)
            temporary.close()
        }
        #expect(lease.map { !s.perform($0) } ?? true)
    }
}
