import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct StartPageMarkGestureTestsTaffy {
    private typealias Pointer = StartPageMarkGestureTestsSupport.Pointer

    private func stretching() -> Pointer {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        _ = pointer.send(pointer.recognizer.pointerDragged(to: CGPoint(x: 10, y: 0), time: 0.05))
        return pointer
    }

    @Test func crossingTheSlopBeforeTheHoldTriggersTaffyOnce() {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        let first = pointer.recognizer.pointerDragged(to: CGPoint(x: 10, y: 0), time: 0.05)
        #expect(first == [.begin(.taffy), .track(CGVector(dx: 6, dy: 0))])
        #expect(pointer.recognizer.holdDeadline == nil)
        #expect(pointer.send(first) == [.track(CGVector(dx: 6, dy: 0))])
        #expect(pointer.session.phase == .interacting(.taffy, .motion))
    }

    @Test func laterDragsOnlyTrack() {
        var pointer = stretching()
        let second = pointer.recognizer.pointerDragged(to: CGPoint(x: 24, y: 7), time: 0.1)
        #expect(second.count == 1 && StartPageMarkGestureTestsSupport.isTrack(second[0]))
    }

    @Test func aLateHoldDeadlineDoesNotTurnADragIntoACharge() {
        var pointer = stretching()
        #expect(pointer.recognizer.holdElapsed(at: 1).isEmpty)
    }

    @Test func returningInsideTheSlopRelaxesTheStretchWithoutEndingIt() {
        var pointer = stretching()
        #expect(pointer.recognizer.pointerDragged(to: CGPoint(x: 2, y: 0), time: 1.1) == [.track(CGVector(dx: 0, dy: 0))])
    }

    @Test func releasingReportsTheFinalPullAndSnapsHomeWithAHaptic() {
        var pointer = stretching()
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 40, y: 0), time: 1.2)
        #expect(release == [.release(CGVector(dx: 36, dy: 0))])
        #expect(pointer.send(release) == [.play(.snap(CGVector(dx: 36, dy: 0))), .haptic])
        #expect(pointer.session.phase == .playing(.taffy, .motion))
    }

    @Test func aSecondReleaseDoesNotSnapAgain() {
        var pointer = stretching()
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 40, y: 0), time: 1.2)
        _ = pointer.send(release)
        #expect(pointer.send(release).isEmpty)
    }

    @Test func theSnapLandingDoesNotTickAgain() {
        var pointer = stretching()
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 40, y: 0), time: 1.2)
        _ = pointer.send(release)
        _ = pointer.send(release)
        #expect(pointer.session.land(generation: pointer.session.generation).isEmpty)
    }

    @Test func thePullStartsAtZeroAtTheSlop() {
        #expect(TaffyStretch.pull(CGVector(dx: 0, dy: -4)) == CGVector(dx: 0, dy: 0))
    }

    @Test func thePullKeepsTheDragsDirection() {
        let pull = TaffyStretch.pull(CGVector(dx: 30, dy: 40))
        #expect(abs(pull.dx - 30 * 46 / 50) < 1e-6 && abs(pull.dy - 40 * 46 / 50) < 1e-6)
    }

    @Test func movingBeforeTheThresholdStartsTaffy() {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        #expect(pointer.drag(CGPoint(x: 5, y: 0), 0.2) == [.track(CGVector(dx: 1, dy: 0))])
    }

    @Test func holdingAfterStartingTaffyKeepsIt() {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        _ = pointer.drag(CGPoint(x: 5, y: 0), 0.2)
        #expect(pointer.hold(0.4).isEmpty && pointer.session.phase == .interacting(.taffy, .motion))
        #expect(pointer.recognizer.clicks == nil)
    }
}
