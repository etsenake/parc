import AppKit
import Testing
@testable import Parc

private final class Flipped: NSView { override var isFlipped: Bool { true } }

@MainActor private final class DragScene {
    let rect = NSRect(x: 0, y: 0, width: 900, height: 600)
    let window: NSWindow, otherWindow: NSWindow
    let root: Flipped
    let page: NSView
    let grabber = WebpageWindowGrabber()
    let owner = NSObject()
    var eligible = true, current = true
    var currentProbes = 0, eligibilityProbes = 0
    var drags: [NSEvent] = []
    var duringDrag: (() -> Void)?
    var event: NSEvent? { didSet { WebpageWindowDragOverrides.currentEvent = event } }
    var arrow = true { didSet { WebpageWindowDragOverrides.cursor = arrow ? .arrow : .iBeam } }

    init() {
        _ = NSApplication.shared
        WebpageWindowDragOverrides.install()
        WebpageWindowDragOverrides.reset()
        window = NSWindow(contentRect: rect, styleMask: [], backing: .buffered, defer: false)
        otherWindow = NSWindow(contentRect: rect, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        otherWindow.isReleasedWhenClosed = false
        root = Flipped(frame: rect)
        window.contentView = root
        page = NSView(frame: rect)
        root.addSubview(page)
        WebpageWindowDragOverrides.cursor = .arrow
        root.addSubview(grabber)
        grabber.frame = WebpageWindowDragState.region(in: rect, topStripHeight: 0)
        WebpageWindowDragOverrides.windowDrag = { [weak self] target, event in
            guard let self else { return }
            #expect(target === window)
            drags.append(event)
            duringDrag?()
        }
        configure()
    }

    deinit {
        MainActor.assumeIsolated {
            WebpageWindowDragOverrides.reset()
            window.contentView = nil
        }
    }

    func configure(_ object: NSObject? = nil, _ revision: UInt = 1) {
        grabber.configure(owner: object ?? owner, revision: revision, isCurrent: { [weak self] in
            self?.currentProbes += 1
            return self?.current ?? false
        }, eligibility: { [weak self] _ in
            self?.eligibilityProbes += 1
            return self?.eligible ?? false
        })
    }

    func make(_ type: NSEvent.EventType, _ target: NSWindow? = nil) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: 30, y: 570), modifierFlags: [], timestamp: 1,
                           windowNumber: (target ?? window).windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
    }

    @discardableResult
    func hit(_ type: NSEvent.EventType) -> NSView? {
        event = make(type)
        return root.hitTest(NSPoint(x: 30, y: 570))
    }

    func resetProbes() {
        WebpageWindowDragOverrides.cursorReads = 0
        currentProbes = 0
        eligibilityProbes = 0
    }

    var probed: Bool { WebpageWindowDragOverrides.cursorReads + currentProbes + eligibilityProbes > 0 }
}

@Suite(.serialized) struct WebpageWindowGrabberTests {
    @MainActor @Test func anOriginalDownPassesIntoThePage() {
        let s = DragScene()
        #expect(s.hit(.leftMouseDown) === s.page)
    }

    @MainActor @Test func anEligibleDownArmsTheOriginalOwner() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        #expect(s.grabber.drag.phase == .began)
    }

    @MainActor @Test func theNativeReHitTestCommitsDragging() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        #expect(s.hit(.leftMouseDragged) === s.grabber)
    }

    @MainActor @Test func theSameEventStartsTheDragWithNoSyntheticReplay() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.hit(.leftMouseDragged)
        #expect(s.drags.count == 1)
        #expect(s.drags.last === s.event)
    }

    @MainActor @Test func aCommittedHitDoesNotStartASecondDrag() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.hit(.leftMouseDragged)
        #expect(s.hit(.leftMouseDragged) === s.grabber)
        #expect(s.drags.count == 1)
    }

    @MainActor @Test func anUpInAnotherWindowIsUntouched() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.hit(.leftMouseDragged)
        let foreign = s.make(.leftMouseUp, s.otherWindow)
        #expect(s.grabber.filterCommittedEvent(foreign) === foreign)
    }

    @MainActor @Test func aZeroMovementUpPassesAndClearsTheState() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.hit(.leftMouseDragged)
        let up = s.make(.leftMouseUp)
        #expect(s.grabber.filterCommittedEvent(up) === up)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func textAndLinkCursorsDoNotArm() {
        let s = DragScene()
        s.arrow = false
        #expect(s.hit(.leftMouseDown) === s.page)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func captureModalOrOwnershipRefusalPassesDown() {
        let s = DragScene()
        s.eligible = false
        #expect(s.hit(.leftMouseDown) === s.page)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func aChangedCursorCancelsBeforeCommit() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.arrow = false
        #expect(s.hit(.leftMouseDragged) === s.page)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func aLostDocumentOrPageOwnerCannotCommit() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.current = false
        #expect(s.hit(.leftMouseDragged) === s.page)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func aDocumentRevisionCancelsTheArmedSequence() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.configure(s.owner, 2)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func geometryInvalidationCancelsTheArmedSequence() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.grabber.frame.size.width -= 1
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func aPageReplacementCancelsTheArmedSequence() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.configure(NSObject(), 2)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func aHiddenOwnerCancels() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.grabber.isHidden = true
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func aSynchronousNativeDragInvalidationCannotResurrectTheOwner() {
        let s = DragScene()
        s.duringDrag = { [grabber = s.grabber] in grabber.configure(owner: nil, revision: 0, isCurrent: nil, eligibility: nil) }
        s.hit(.leftMouseDown)
        #expect(s.hit(.leftMouseDragged) === s.page)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func aCommittedOwnerLossReleasesTheMonitor() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.hit(.leftMouseDragged)
        s.current = false
        let up = s.make(.leftMouseUp)
        #expect(s.grabber.filterCommittedEvent(up) === up)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func aWindowDetachCancels() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.grabber.removeFromSuperview()
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func anInactiveLeftDragSkipsTheEligibilityAndCursorProbes() {
        let s = DragScene()
        s.resetProbes()
        #expect(s.hit(.leftMouseDragged) === s.page)
        #expect(!s.probed)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func repeatedInactiveLeftDragsStayANoOpSkip() {
        let s = DragScene()
        s.resetProbes()
        s.hit(.leftMouseDragged)
        #expect(s.hit(.leftMouseDragged) === s.page)
        #expect(!s.probed)
    }

    @MainActor @Test func theInactiveSkipIgnoresFlippedEligibilityInputs() {
        let s = DragScene()
        s.resetProbes()
        s.arrow = false
        s.eligible = false
        s.current = false
        s.resetProbes()
        #expect(s.hit(.leftMouseDragged) === s.page)
        #expect(!s.probed)
        #expect(s.grabber.drag.phase == .inactive)
    }

    @MainActor @Test func anEligibleLeftDownStillProbesAndArms() {
        let s = DragScene()
        s.resetProbes()
        #expect(s.hit(.leftMouseDown) === s.page)
        #expect(s.probed)
        #expect(s.grabber.drag.phase == .began)
    }

    @MainActor @Test func anArmedDragStillProbesEligibilityBeforeCommit() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        let reads = WebpageWindowDragOverrides.cursorReads, current = s.currentProbes, eligibility = s.eligibilityProbes
        s.eligible = false
        #expect(s.hit(.leftMouseDragged) === s.page)
        #expect(s.grabber.drag.phase == .inactive)
        #expect(WebpageWindowDragOverrides.cursorReads > reads)
        #expect(s.currentProbes > current)
        #expect(s.eligibilityProbes > eligibility)
    }

    @MainActor @Test func theCommitPathEvaluatesEligibilityBeforePerformDrag() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.resetProbes()
        let before = s.drags.count
        #expect(s.hit(.leftMouseDragged) === s.grabber)
        #expect(s.drags.count == before + 1)
        #expect(s.probed)
    }

    @MainActor @Test func aCommittedLeftDragStillRechecksEligibility() {
        let s = DragScene()
        s.hit(.leftMouseDown)
        s.hit(.leftMouseDragged)
        s.resetProbes()
        #expect(s.hit(.leftMouseDragged) === s.grabber)
        #expect(s.probed)
        s.grabber.cancel()
    }

    @MainActor @Test func theComponentsNeverShowWindows() {
        let s = DragScene()
        #expect(!s.window.isVisible)
        #expect(!s.otherWindow.isVisible)
    }
}
