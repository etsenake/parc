import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct StartPageMarkGestureTestsCharge {
    private typealias Pointer = StartPageMarkGestureTestsSupport.Pointer

    @Test func theHoldDeadlineIsOneBoundedDelayAway() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        #expect(pointer.recognizer.holdDeadline == 10 + StartPageMarkGestureRecognizer.holdDelay)
    }

    @Test func anEarlyDeadlineCheckDoesNotCharge() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        #expect(pointer.hold(10.2).isEmpty)
    }

    @Test func movementInsideTheSlopBeforeTheDeadlineDoesNotCharge() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        _ = pointer.hold(10.2)
        #expect(pointer.drag(CGPoint(x: 22, y: 31), 10.3).isEmpty)
    }

    @Test func holdingStillPastTheThresholdStartsCharging() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        #expect(pointer.hold(10.36) == [.charge(.motion)])
        #expect(pointer.session.phase == .interacting(.charge, .motion))
        #expect(pointer.recognizer.holdDeadline == nil)
    }

    @Test func aSecondHoldDeadlineDoesNotStartAnotherCharge() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        _ = pointer.hold(10.36)
        #expect(pointer.hold(11).isEmpty)
    }

    @Test func aDragInsideTheChargeSlopDoesNotStartAnotherCharge() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        _ = pointer.hold(10.36)
        _ = pointer.hold(11)
        #expect(pointer.drag(CGPoint(x: 26, y: 34), 10.5).isEmpty)
    }

    @Test func releasingAFullChargeLoopsTheLoop() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        _ = pointer.hold(10.36)
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 26, y: 34), time: 10.36 + StartPageMarkCharge.ramp + 0.05)
        #expect(release == [.discharge(1)])
        #expect(pointer.send(release) == [.play(.loop)])
        #expect(pointer.session.landing)
    }

    @Test func aStaleLandingDoesNotTick() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        _ = pointer.hold(10.36)
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 26, y: 34), time: 10.36 + StartPageMarkCharge.ramp + 0.05)
        _ = pointer.send(release)
        let generation = pointer.session.generation
        #expect(pointer.session.land(generation: generation - 1).isEmpty)
    }

    @Test func theLoopTicksOnLanding() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        _ = pointer.hold(10.36)
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 26, y: 34), time: 10.36 + StartPageMarkCharge.ramp + 0.05)
        _ = pointer.send(release)
        let generation = pointer.session.generation
        _ = pointer.session.land(generation: generation - 1)
        #expect(pointer.session.land(generation: generation) == [.haptic])
    }

    @Test func aSecondLandingDoesNotTick() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        _ = pointer.hold(10.36)
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 26, y: 34), time: 10.36 + StartPageMarkCharge.ramp + 0.05)
        _ = pointer.send(release)
        let generation = pointer.session.generation
        _ = pointer.session.land(generation: generation - 1)
        _ = pointer.session.land(generation: generation)
        #expect(pointer.session.land(generation: generation).isEmpty)
    }

    @Test func finishingTheLoopReturnsTheMarkToRest() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        _ = pointer.hold(10.36)
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 26, y: 34), time: 10.36 + StartPageMarkCharge.ramp + 0.05)
        _ = pointer.send(release)
        let generation = pointer.session.generation
        _ = pointer.session.land(generation: generation - 1)
        _ = pointer.session.land(generation: generation)
        _ = pointer.session.land(generation: generation)
        pointer.session.finish(generation: generation)
        #expect(pointer.session.phase == .rest)
    }

    @Test func aShortChargeReportsItsLevel() {
        var weak = Pointer()
        _ = weak.down(.zero, 0)
        _ = weak.hold(0.35)
        let short = weak.recognizer.pointerUp(at: .zero, time: 0.55)
        let level = StartPageMarkCharge.level(held: 0.55 - 0.35)
        #expect(short == [.discharge(level)])
        #expect(abs(level - 0.2 / StartPageMarkCharge.ramp) < 1e-6)
    }

    @Test func aShortChargeRelaxesWithoutALoopOrATick() {
        var weak = Pointer()
        _ = weak.down(.zero, 0)
        _ = weak.hold(0.35)
        let short = weak.recognizer.pointerUp(at: .zero, time: 0.55)
        let level = StartPageMarkCharge.level(held: 0.55 - 0.35)
        #expect(weak.send(short) == [.play(.relax(level, .motion))])
        #expect(!weak.session.landing && weak.session.land(generation: weak.session.generation).isEmpty)
    }

    @Test func theLoopNeedsTheMockupsSixtyPercentCharge() {
        #expect(StartPageMarkCharge.launches(StartPageMarkCharge.launchLevel))
        #expect(!StartPageMarkCharge.launches(0.59))
    }

    @Test func aReleaseAfterTheThresholdWithoutATimerIsAHoldChargedFromWhenItBegan() {
        var late = Pointer()
        _ = late.down(.zero, 0)
        let level = StartPageMarkCharge.level(held: 0.5 - StartPageMarkGestureRecognizer.holdDelay)
        #expect(late.up(.zero, 0.5) == [.charge(.motion), .play(.relax(level, .motion))])
        #expect(late.recognizer.clicks == nil)
    }

    @Test func movingInsideTheChargeSlopKeepsCharging() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 10, y: 10), 0)
        _ = pointer.hold(0.35)
        #expect(pointer.drag(CGPoint(x: 16, y: 14), 0.45).isEmpty)
        #expect(pointer.session.phase == .interacting(.charge, .motion))
    }

    @Test func movingPastTheChargeSlopCancelsTheChargeQuietly() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 10, y: 10), 0)
        _ = pointer.hold(0.35)
        let cancel = pointer.recognizer.pointerDragged(to: CGPoint(x: 19, y: 10), time: 0.55)
        #expect(cancel.count == 1 && StartPageMarkGestureTestsSupport.isCancel(cancel[0]))
        #expect(!cancel.contains(.begin(.taffy)))
        let effects = pointer.send(cancel)
        #expect(effects.count == 1 && !effects.contains(.haptic) && StartPageMarkGestureTestsSupport.isRelax(effects[0]))
    }

    @Test func draggingAfterCancellationStaysInert() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 10, y: 10), 0)
        _ = pointer.hold(0.35)
        _ = pointer.send(pointer.recognizer.pointerDragged(to: CGPoint(x: 19, y: 10), time: 0.55))
        #expect(pointer.drag(CGPoint(x: 80, y: 10), 0.6).isEmpty)
    }

    @Test func releasingAfterCancellationStaysInert() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 10, y: 10), 0)
        _ = pointer.hold(0.35)
        _ = pointer.send(pointer.recognizer.pointerDragged(to: CGPoint(x: 19, y: 10), time: 0.55))
        _ = pointer.drag(CGPoint(x: 80, y: 10), 0.6)
        #expect(pointer.up(CGPoint(x: 80, y: 10), 0.7).isEmpty)
    }

    @Test func movementAfterTheHoldThresholdChargesRatherThanStretching() {
        var late = Pointer()
        _ = late.down(.zero, 0)
        let cues = late.recognizer.pointerDragged(to: CGPoint(x: 12, y: 0), time: 0.5)
        #expect(cues == [.begin(.charge), .cancel(StartPageMarkCharge.level(held: 0.5 - StartPageMarkGestureRecognizer.holdDelay))])
    }
}
