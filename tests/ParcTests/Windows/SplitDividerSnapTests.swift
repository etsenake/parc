import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct SplitDividerSnapStateTests {
    private static func armed() -> SplitDividerSnapState {
        var state = SplitDividerSnapState()
        _ = state.update(distance: -14, velocity: 0)
        return state
    }

    @Test func theCentreStartsUnarmed() {
        var state = SplitDividerSnapState()
        let changed = state.update(distance: 0, velocity: 0)
        #expect(!changed)
        #expect(!state.canSnap && !state.isSnapped)
    }

    @Test func leavingTheFourteenPointBoundaryArms() {
        var state = SplitDividerSnapState()
        let changed = state.update(distance: -14, velocity: 0)
        #expect(!changed)
        #expect(state.canSnap)
    }

    @Test func movingAwayFromTheCentreDoesNotSnap() {
        var state = Self.armed()
        let changed = state.update(distance: -6, velocity: -50)
        #expect(!changed)
        #expect(!state.isSnapped)
    }

    @Test func aFastApproachPassesThrough() {
        var state = Self.armed()
        let changed = state.update(distance: -6, velocity: 121)
        #expect(!changed)
        #expect(!state.isSnapped)
    }

    @Test func aSlowApproachAtTheVelocityBoundarySnaps() {
        var state = Self.armed()
        let changed = state.update(distance: -6, velocity: 120)
        #expect(changed)
        #expect(state.isSnapped)
    }

    @Test func aSnappedDividerStaysSnappedWithinTheBand() {
        var state = Self.armed()
        _ = state.update(distance: -6, velocity: 120)
        let changed = state.update(distance: 13, velocity: 900)
        #expect(!changed)
        #expect(state.isSnapped)
    }

    @Test func leavingTheBandReleasesOnce() {
        var state = Self.armed()
        _ = state.update(distance: -6, velocity: 120)
        let changed = state.update(distance: 14, velocity: 900)
        #expect(changed)
        #expect(!state.isSnapped)
    }

    @Test func continuingOutsideTheBandDoesNotRepeatTheRelease() {
        var state = Self.armed()
        _ = state.update(distance: -6, velocity: 120)
        _ = state.update(distance: 14, velocity: 900)
        let changed = state.update(distance: 20, velocity: 900)
        #expect(!changed)
    }

    @Test func anOppositeSlowApproachAlsoSnaps() {
        var state = Self.armed()
        _ = state.update(distance: 14, velocity: 0)
        let changed = state.update(distance: 6, velocity: -50)
        #expect(changed)
        #expect(state.isSnapped)
    }

    @Test(arguments: [(Double.nan, 1.0), (3.0, Double.infinity)])
    func invalidInputCannotAlterTheState(_ distance: Double, _ velocity: Double) {
        var state = Self.armed()
        _ = state.update(distance: -6, velocity: 120)
        let changed = state.update(distance: distance, velocity: velocity)
        #expect(!changed)
        #expect(state.isSnapped)
    }
}

@MainActor
struct SplitDividerSnapTests {
    @MainActor private final class Host {
        let window: NSWindow
        let view: ParcSplitView
        let panes: [NSView]
        var commits: [[Double]] = []
        var pulses = 0

        init(factors: [Double] = [0.3, 0.3, 0.4], orientation: SplitOrientation = .horizontal) {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 1000), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            view = ParcSplitView(frame: window.contentView!.bounds)
            window.contentView!.addSubview(view)
            panes = (0..<3).map { _ in NSView() }
            panes.forEach(view.addArrangedSubview)
            view.configure(orientation: orientation, factors: factors)
            view.prepareDividerResize = { [weak self] in { self?.commits.append($0); return true } }
            view.onSnapTransition = { [weak self] in self?.pulses += 1 }
        }

        var frames: [NSRect] { panes.map(\.frame) }
        var firstDividerOrigin: NSPoint { NSPoint(x: panes[0].frame.maxX + 3, y: 100) }

        func mouseDown(at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }

        func dragToCentre(from origin: NSPoint) {
            view.updateDividerResize(at: NSPoint(x: origin.x + 40, y: origin.y), velocity: 200)
            view.updateDividerResize(at: NSPoint(x: origin.x + 6, y: origin.y), velocity: -50)
        }
    }

    @Test func pageContentOptsOutBeforeNativeRecognition() throws {
        let host = Host()
        let recognizer = try #require(host.view.gestureRecognizers.compactMap { $0 as? NSPanGestureRecognizer }.first)
        #expect(!host.view.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: host.mouseDown(at: NSPoint(x: 100, y: 100))))
    }

    @Test func theDividerAdmitsTheNativePan() throws {
        let host = Host()
        let recognizer = try #require(host.view.gestureRecognizers.compactMap { $0 as? NSPanGestureRecognizer }.first)
        #expect(host.view.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: host.mouseDown(at: host.firstDividerOrigin)))
        #expect(host.view.gestureRecognizerShouldBegin(recognizer))
    }

    @Test func aPairSnapsToItsCentreWithOneTransition() {
        let host = Host()
        let origin = host.firstDividerOrigin
        host.view.beginDividerResize(at: origin)
        host.dragToCentre(from: origin)
        #expect(host.pulses == 1)
        #expect(abs(host.panes[0].frame.width - host.panes[1].frame.width) < 0.001)
    }

    @Test func snappingLeavesTheOtherPaneAndDurableDataAlone() {
        let host = Host()
        let before = host.frames
        let origin = host.firstDividerOrigin
        host.view.beginDividerResize(at: origin)
        host.dragToCentre(from: origin)
        #expect(host.panes[2].frame == before[2])
        #expect(host.commits.isEmpty)
    }

    @Test func stayingInTheBandDoesNotRepeatTheTransition() {
        let host = Host()
        let origin = host.firstDividerOrigin
        host.view.beginDividerResize(at: origin)
        host.dragToCentre(from: origin)
        host.view.updateDividerResize(at: NSPoint(x: origin.x + 8, y: origin.y), velocity: 500)
        #expect(host.pulses == 1)
    }

    @Test func leavingTheBandEmitsTheReleaseOnce() {
        let host = Host()
        let origin = host.firstDividerOrigin
        host.view.beginDividerResize(at: origin)
        host.dragToCentre(from: origin)
        host.view.updateDividerResize(at: NSPoint(x: origin.x + 20, y: origin.y), velocity: 200)
        #expect(host.pulses == 2)
    }

    @Test func aCancelledGestureRestoresTheFramesWithoutPersisting() {
        let host = Host()
        let before = host.frames
        let origin = host.firstDividerOrigin
        host.view.beginDividerResize(at: origin)
        host.dragToCentre(from: origin)
        host.view.finishDividerResize(commit: false)
        #expect(host.commits.isEmpty)
        #expect(host.frames == before)
    }

    @Test func completionKeepsThePairShareAndCommitsOnce() {
        let host = Host()
        let origin = host.firstDividerOrigin
        #expect(host.view.beginDividerResize(at: origin))
        host.view.updateDividerResize(at: NSPoint(x: origin.x - 40, y: origin.y), velocity: -200)
        host.view.finishDividerResize(commit: true)
        host.view.finishDividerResize(commit: true)
        #expect(host.commits.count == 1)
        #expect(abs(host.commits[0][0] + host.commits[0][1] - 0.6) < 0.000001)
        #expect(host.commits[0][2] == 0.4)
    }

    @Test func aVerticalDividerEasedOntoTheCentreSnapsOnItsVerticalSpeed() {
        let host = Host(orientation: .vertical)
        let before = host.frames
        let origin = NSPoint(x: 100, y: host.panes[0].frame.maxY + 3)
        #expect(host.view.beginDividerResize(at: origin))
        host.view.updateDividerResize(at: NSPoint(x: 100, y: origin.y + 40), panVelocity: NSPoint(x: -2, y: 300))
        host.view.updateDividerResize(at: NSPoint(x: 100, y: origin.y + 6), panVelocity: NSPoint(x: 3, y: -30))
        #expect(abs(host.panes[0].frame.height - host.panes[1].frame.height) < 0.001)
        #expect(host.panes[2].frame == before[2])
        #expect(host.pulses == 1)
    }

    @Test func aChangedOrientationCancelsTheOldCompletion() {
        let host = Host(orientation: .vertical)
        let origin = NSPoint(x: 100, y: host.panes[0].frame.maxY + 3)
        #expect(host.view.beginDividerResize(at: origin))
        host.view.configure(orientation: .horizontal, factors: [0.2, 0.3, 0.5])
        host.view.finishDividerResize(commit: true)
        #expect(host.commits.isEmpty)
        #expect(host.view.isVertical)
    }

    @Test func theCurrentLayoutCanStartAnotherGestureAfterACancel() {
        let host = Host()
        let origin = host.firstDividerOrigin
        #expect(host.view.beginDividerResize(at: origin))
        host.view.configure(orientation: .horizontal, factors: [0.2, 0.3, 0.5])
        host.view.finishDividerResize(commit: true)
        #expect(host.view.beginDividerResize(at: NSPoint(x: host.panes[0].frame.maxX + 3, y: 100)))
    }

    @Test func detachmentCancelsTheGesture() {
        let host = Host()
        let origin = host.firstDividerOrigin
        #expect(host.view.beginDividerResize(at: origin))
        host.view.updateDividerResize(at: NSPoint(x: origin.x + 40, y: 100), velocity: 1)
        host.view.removeFromSuperview()
        host.view.finishDividerResize(commit: true)
        #expect(host.commits.isEmpty)
    }
}

@MainActor
struct SplitStackSnapTests {
    @MainActor private final class Host {
        let window: NSWindow
        let stacked: ParcSplitView
        let panes: [NSView]
        var changes: [SplitStackResize] = []
        var pulses = 0
        let shape = BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.5, 0.5], stackFactors: [[0.4, 0.6], [1]])

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 1000), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            stacked = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1010, height: 710))
            window.contentView!.addSubview(stacked)
            panes = (0..<3).map { _ in NSView() }
            panes.forEach(stacked.addArrangedSubview)
            stacked.prepareStackedResize = { [weak self] in { self?.changes.append($0); return self?.shape } }
            stacked.onSnapTransition = { [weak self] in self?.pulses += 1 }
            stacked.configure(orientation: .horizontal, factors: shape.flattenedFactors, stacks: shape)
        }

        var origin: NSPoint { NSPoint(x: 250, y: panes[0].frame.maxY + 3) }
    }

    @Test func aStackDividerAdmitsAPan() {
        let host = Host()
        #expect(host.stacked.beginDividerResize(at: host.origin))
    }

    @Test func aStackDividerSnapsToTheCentreOfItsOwnColumnWithOneHaptic() {
        let host = Host()
        let origin = host.origin
        host.stacked.beginDividerResize(at: origin)
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 100), velocity: 200)
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 65), velocity: 50)
        #expect(host.pulses == 1)
        #expect(abs(host.panes[0].frame.height - host.panes[1].frame.height) < 0.001)
        #expect(host.panes[2].frame == NSRect(x: 510, y: 0, width: 500, height: 710))
    }

    @Test func theSnappedStackDividerCommitsAnEvenPairOnce() throws {
        let host = Host()
        let origin = host.origin
        host.stacked.beginDividerResize(at: origin)
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 100), velocity: 200)
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 65), velocity: 50)
        host.stacked.finishDividerResize(commit: true)
        #expect(host.changes.count == 1)
        guard case .divider(0, slot: 0, let share)? = host.changes.first else {
            Issue.record("the stack divider did not commit a stacked divider change")
            return
        }
        #expect(abs(share - 0.5) < 0.000001)
    }

    @Test func aStackDividerEasedOntoItsColumnsCentreFromBelowSnapsToo() {
        let host = Host()
        let origin = host.origin
        host.stacked.beginDividerResize(at: origin)
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 100), panVelocity: NSPoint(x: -2, y: 300))
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 75), panVelocity: NSPoint(x: 2, y: -60))
        #expect(host.pulses == 1)
        #expect(abs(host.panes[0].frame.height - host.panes[1].frame.height) < 0.001)
    }

    @Test func aQuickDragBackThroughTheCentreReleasesOnceAndPassesStraightThrough() {
        let host = Host()
        let origin = host.origin
        host.stacked.beginDividerResize(at: origin)
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 100), panVelocity: NSPoint(x: -2, y: 300))
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 75), panVelocity: NSPoint(x: 2, y: -60))
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 120), panVelocity: NSPoint(x: 0, y: 900))
        host.stacked.updateDividerResize(at: NSPoint(x: 250, y: origin.y + 75), panVelocity: NSPoint(x: 0, y: -400))
        #expect(host.pulses == 2)
        #expect(host.panes[0].frame.height != host.panes[1].frame.height)
    }
}
