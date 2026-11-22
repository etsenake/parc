import CoreGraphics
import Foundation
import Testing
@testable import Parc

private struct Pointer {
    var recognizer = StartPageMarkGestureRecognizer(clickInterval: 0.5)
    var session = StartPageMarkSession()
    var canAnimate = true
    var reduceMotion = false

    mutating func send(_ cues: [StartPageMarkCue]) -> [StartPageMarkSession.Effect] {
        var effects: [StartPageMarkSession.Effect] = []
        for cue in cues {
            let produced = session.handle(cue, canAnimate: canAnimate, reduceMotion: reduceMotion)
            if produced.contains(.reset) { recognizer.reset() }
            effects += produced
        }
        return effects
    }
    mutating func down(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
        send(recognizer.pointerDown(at: point, time: time, idle: session.isIdle))
    }
    mutating func drag(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
        send(recognizer.pointerDragged(to: point, time: time))
    }
    mutating func up(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
        send(recognizer.pointerUp(at: point, time: time))
    }
    mutating func hold(_ time: TimeInterval) -> [StartPageMarkSession.Effect] {
        send(recognizer.holdElapsed(at: time))
    }
    mutating func click(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
        down(point, time) + up(point, time + 0.08)
    }
}

private func isCancel(_ cue: StartPageMarkCue) -> Bool {
    if case .cancel = cue { return true }
    return false
}

private func isTrack(_ cue: StartPageMarkCue) -> Bool {
    if case .track = cue { return true }
    return false
}

private func isRelax(_ effect: StartPageMarkSession.Effect) -> Bool {
    if case .play(.relax) = effect { return true }
    return false
}

struct StartPageMarkClickTests {
    private let origin = CGPoint(x: 30, y: 40)

    @Test func pressingTheMarkDoesNothingOnItsOwnAndArmsOneHoldDeadline() {
        var recognizer = StartPageMarkGestureRecognizer(clickInterval: 0.5)
        #expect(recognizer.pointerDown(at: origin, time: 0, idle: true).isEmpty)
        #expect(recognizer.holdDeadline == StartPageMarkGestureRecognizer.holdDelay)
    }

    @Test func aSingleClickDoesNothingAndCountsAsAClick() {
        var recognizer = StartPageMarkGestureRecognizer(clickInterval: 0.5)
        _ = recognizer.pointerDown(at: origin, time: 0, idle: true)
        #expect(recognizer.pointerUp(at: origin, time: 0.1).isEmpty)
        #expect(recognizer.holdDeadline == nil)
        #expect(recognizer.clicks?.count == 1)
    }

    @Test func singleAndDoubleClicksLeaveTheMarkAtRest() {
        var pointer = Pointer()
        #expect(pointer.click(origin, 0).isEmpty)
        #expect(pointer.click(origin, 0.3).isEmpty)
        #expect(pointer.session.phase == .rest && pointer.session.generation == 0)
    }

    @Test func aWobbleInsideTheSlopDoesNotStartTheStretchOrCountAsAnythingMore() {
        var pointer = Pointer()
        _ = pointer.down(origin, 5)
        #expect(pointer.drag(CGPoint(x: 33, y: 42), 5.05).isEmpty)
        #expect(pointer.drag(CGPoint(x: 34, y: 40), 5.06).isEmpty)
        #expect(pointer.up(CGPoint(x: 33, y: 42), 5.1).isEmpty)
    }

    @Test func strayEventsWithoutAPressDoNothing() {
        var pointer = Pointer()
        #expect(pointer.drag(CGPoint(x: 90, y: 40), 5.2).isEmpty)
        #expect(pointer.up(CGPoint(x: 90, y: 40), 5.3).isEmpty)
        #expect(pointer.hold(6).isEmpty)
    }

    @Test func followUpCuesWithoutATriggerDoNothing() {
        var session = StartPageMarkSession()
        let cues: [StartPageMarkCue] = [.track(CGVector(dx: 5, dy: 0)), .release(CGVector(dx: 5, dy: 0)), .discharge(1), .cancel(1)]
        #expect(cues.flatMap { session.handle($0, canAnimate: true, reduceMotion: false) }.isEmpty)
        #expect(session.phase == .rest && session.generation == 0)
    }
}

struct StartPageMarkTaffyGestureTests {
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
        #expect(second.count == 1 && isTrack(second[0]))
    }

    @Test func aLateHoldDeadlineDoesNotTurnADragIntoACharge() {
        var pointer = stretching()
        #expect(pointer.recognizer.holdElapsed(at: 1).isEmpty)
    }

    @Test func returningInsideTheSlopRelaxesTheStretchWithoutEndingIt() {
        var pointer = stretching()
        #expect(pointer.recognizer.pointerDragged(to: CGPoint(x: 2, y: 0), time: 1.1) == [.track(CGVector(dx: 0, dy: 0))])
    }

    @Test func releasingReportsTheFinalPullAndSnapsHomeOnceWithOneHaptic() {
        var pointer = stretching()
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 40, y: 0), time: 1.2)
        #expect(release == [.release(CGVector(dx: 36, dy: 0))])
        #expect(pointer.send(release) == [.play(.snap(CGVector(dx: 36, dy: 0))), .haptic])
        #expect(pointer.session.phase == .playing(.taffy, .motion))
        #expect(pointer.send(release).isEmpty)
        #expect(pointer.session.land(generation: pointer.session.generation).isEmpty)
    }

    @Test func thePullStartsAtZeroAtTheSlop() {
        #expect(TaffyStretch.pull(CGVector(dx: 0, dy: -4)) == CGVector(dx: 0, dy: 0))
    }

    @Test func thePullKeepsTheDragsDirection() {
        let pull = TaffyStretch.pull(CGVector(dx: 30, dy: 40))
        #expect(abs(pull.dx - 30 * 46 / 50) < 1e-6 && abs(pull.dy - 40 * 46 / 50) < 1e-6)
    }

    @Test func movingBeforeTheThresholdStartsTaffyAndHoldingStillAfterwardKeepsIt() {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        #expect(pointer.drag(CGPoint(x: 5, y: 0), 0.2) == [.track(CGVector(dx: 1, dy: 0))])
        #expect(pointer.hold(0.4).isEmpty && pointer.session.phase == .interacting(.taffy, .motion))
        #expect(pointer.recognizer.clicks == nil)
    }
}

struct StartPageMarkChargeGestureTests {
    @Test func theHoldDeadlineIsOneBoundedDelayAway() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        #expect(pointer.recognizer.holdDeadline == 10 + StartPageMarkGestureRecognizer.holdDelay)
    }

    @Test func anEarlyDeadlineCheckAndAStillPressInsideTheSlopDoNotCharge() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        #expect(pointer.hold(10.2).isEmpty)
        #expect(pointer.drag(CGPoint(x: 22, y: 31), 10.3).isEmpty)
    }

    @Test func holdingStillPastTheThresholdStartsChargingOnce() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        #expect(pointer.hold(10.36) == [.charge(.motion)])
        #expect(pointer.session.phase == .interacting(.charge, .motion))
        #expect(pointer.recognizer.holdDeadline == nil)
        #expect(pointer.hold(11).isEmpty)
        #expect(pointer.drag(CGPoint(x: 26, y: 34), 10.5).isEmpty)
    }

    @Test func releasingAFullChargeLoopsTheLoopAndTicksOnceOnLanding() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        _ = pointer.hold(10.36)
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 26, y: 34), time: 10.36 + StartPageMarkCharge.ramp + 0.05)
        #expect(release == [.discharge(1)])
        #expect(pointer.send(release) == [.play(.loop)])
        let generation = pointer.session.generation
        #expect(pointer.session.landing)
        #expect(pointer.session.land(generation: generation - 1).isEmpty)
        #expect(pointer.session.land(generation: generation) == [.haptic])
        #expect(pointer.session.land(generation: generation).isEmpty)
        pointer.session.finish(generation: generation)
        #expect(pointer.session.phase == .rest)
    }

    @Test func aShortChargeReportsItsLevelAndRelaxesWithoutALoopOrATick() {
        var weak = Pointer()
        _ = weak.down(.zero, 0)
        _ = weak.hold(0.35)
        let short = weak.recognizer.pointerUp(at: .zero, time: 0.55)
        let level = StartPageMarkCharge.level(held: 0.55 - 0.35)
        #expect(short == [.discharge(level)])
        #expect(abs(level - 0.2 / StartPageMarkCharge.ramp) < 1e-6)
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
        #expect(cancel.count == 1 && isCancel(cancel[0]))
        #expect(!cancel.contains(.begin(.taffy)))
        let effects = pointer.send(cancel)
        #expect(effects.count == 1 && !effects.contains(.haptic) && isRelax(effects[0]))
    }

    @Test func aCancelledGestureStaysInert() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 10, y: 10), 0)
        _ = pointer.hold(0.35)
        _ = pointer.send(pointer.recognizer.pointerDragged(to: CGPoint(x: 19, y: 10), time: 0.55))
        #expect(pointer.drag(CGPoint(x: 80, y: 10), 0.6).isEmpty)
        #expect(pointer.up(CGPoint(x: 80, y: 10), 0.7).isEmpty)
    }

    @Test func movementAfterTheHoldThresholdChargesRatherThanStretching() {
        var late = Pointer()
        _ = late.down(.zero, 0)
        let cues = late.recognizer.pointerDragged(to: CGPoint(x: 12, y: 0), time: 0.5)
        #expect(cues == [.begin(.charge), .cancel(StartPageMarkCharge.level(held: 0.5 - StartPageMarkGestureRecognizer.holdDelay))])
    }
}

struct StartPageMarkSwoopGestureTests {
    private let spot = CGPoint(x: 30, y: 50)

    @Test func twoQuickClicksAreCounted() {
        var pointer = Pointer()
        _ = pointer.click(spot, 0)
        _ = pointer.click(CGPoint(x: 33, y: 52), 0.2)
        #expect(pointer.recognizer.clicks?.count == 2)
    }

    @Test func theThirdQuickClickSwoopsAtOnceConsumingTheClicks() {
        var pointer = Pointer()
        _ = pointer.click(spot, 0)
        _ = pointer.click(CGPoint(x: 33, y: 52), 0.2)
        let third = pointer.recognizer.pointerDown(at: CGPoint(x: 34, y: 47), time: 0.4, idle: true)
        #expect(third == [.begin(.swoop)])
        #expect(pointer.recognizer.holdDeadline == nil && pointer.recognizer.clicks == nil)
        #expect(pointer.send(third) == [.play(.swoop)])
        #expect(pointer.session.phase == .playing(.swoop, .motion) && pointer.session.landing)
    }

    @Test func draggingOrReleasingTheThirdPressDoesNothingMoreAndTheSwoopTicksOnLanding() {
        var pointer = Pointer()
        _ = pointer.click(spot, 0)
        _ = pointer.click(CGPoint(x: 33, y: 52), 0.2)
        _ = pointer.down(CGPoint(x: 34, y: 47), 0.4)
        #expect(pointer.drag(CGPoint(x: 80, y: 80), 0.45).isEmpty)
        #expect(pointer.up(CGPoint(x: 80, y: 80), 0.5).isEmpty)
        #expect(pointer.session.land(generation: pointer.session.generation) == [.haptic])
    }

    @Test func aSlowThirdClickDoesNotSwoopAndStartsANewCount() {
        var slow = Pointer()
        _ = slow.click(spot, 0)
        _ = slow.click(spot, 0.3)
        #expect(slow.down(spot, 0.38 + 0.51).isEmpty)
        #expect(slow.recognizer.clicks == nil)
    }

    @Test func aThirdClickAwayFromTheFirstDoesNotSwoop() {
        var far = Pointer()
        _ = far.click(spot, 0)
        _ = far.click(spot, 0.2)
        #expect(far.down(CGPoint(x: spot.x + 9, y: spot.y), 0.4).isEmpty)
    }

    @Test func theClickIntervalFollowsTheSystemSetting() {
        var system = Pointer()
        system.recognizer.clickInterval = 1.5
        _ = system.click(spot, 0)
        _ = system.click(spot, 1)
        #expect(system.down(spot, 2) == [.play(.swoop)])
    }

    @Test func aDragBetweenClicksBreaksTheTripleClick() {
        var broken = Pointer()
        _ = broken.click(spot, 0)
        _ = broken.down(spot, 0.2)
        _ = broken.drag(CGPoint(x: spot.x + 20, y: spot.y), 0.25)
        _ = broken.up(CGPoint(x: spot.x + 20, y: spot.y), 0.3)
        broken.session.finish(generation: broken.session.generation)
        _ = broken.click(spot, 0.4)
        #expect(broken.down(spot, 0.6).isEmpty)
    }
}

struct StartPageMarkBusyTests {
    private func playingTaffy() -> (Pointer, Int) {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        _ = pointer.drag(CGPoint(x: 0, y: 20), 0.1)
        _ = pointer.up(CGPoint(x: 0, y: 20), 0.2)
        return (pointer, pointer.session.generation)
    }

    @Test func aPressDuringPlaybackIsIgnoredForItsWholeGesture() {
        var (pointer, playing) = playingTaffy()
        #expect(pointer.session.phase == .playing(.taffy, .motion))
        #expect(pointer.recognizer.pointerDown(at: .zero, time: 0.3, idle: false).isEmpty)
        #expect(pointer.recognizer.holdDeadline == nil)
        #expect(pointer.drag(CGPoint(x: 20, y: 0), 0.35).isEmpty)
        pointer.session.finish(generation: playing)
        #expect(pointer.drag(CGPoint(x: 40, y: 0), 0.45).isEmpty)
        #expect(pointer.up(CGPoint(x: 40, y: 0), 0.5).isEmpty)
    }

    @Test func clicksDuringPlaybackNeverCountTowardASwoop() {
        var clicks = Pointer()
        _ = clicks.down(.zero, 0)
        _ = clicks.hold(0.35)
        _ = clicks.up(.zero, 1.5)
        let loop = clicks.session.generation
        _ = clicks.click(.zero, 1.6)
        _ = clicks.click(.zero, 1.8)
        clicks.session.finish(generation: loop)
        #expect(clicks.down(.zero, 2.0).isEmpty)
        #expect(clicks.recognizer.clicks == nil)
    }

    @Test func holdingDuringARelaxDoesNotChargeAgain() {
        var holding = Pointer()
        _ = holding.down(.zero, 0)
        _ = holding.hold(0.35)
        _ = holding.up(.zero, 0.6)
        _ = holding.recognizer.pointerDown(at: .zero, time: 0.7, idle: holding.session.isIdle)
        #expect(holding.hold(1.1).isEmpty)
    }

    @Test(arguments: [StartPageMarkCue.begin(.swoop), .begin(.charge), .begin(.taffy), .track(CGVector(dx: 9, dy: 0)),
                      .release(CGVector(dx: 9, dy: 0)), .discharge(1), .cancel(1)])
    func aTriggerDuringPlaybackIsIgnored(cue: StartPageMarkCue) {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.swoop), canAnimate: true, reduceMotion: false)
        #expect(session.handle(cue, canAnimate: true, reduceMotion: false).isEmpty)
        #expect(session.phase == .playing(.swoop, .motion))
    }

    @Test func aStaleCompletionCannotEndANewerPlay() {
        var stale = StartPageMarkSession()
        _ = stale.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        _ = stale.handle(.release(.zero), canAnimate: true, reduceMotion: false)
        let old = stale.generation
        _ = stale.pause()
        _ = stale.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        _ = stale.handle(.release(.zero), canAnimate: true, reduceMotion: false)
        stale.finish(generation: old)
        #expect(stale.phase == .playing(.taffy, .motion))
        stale.finish(generation: stale.generation)
        #expect(stale.phase == .rest)
    }

    @Test func aCompletionCannotEndAChargeThatIsStillHeld() {
        var interacting = StartPageMarkSession()
        _ = interacting.handle(.begin(.charge), canAnimate: true, reduceMotion: false)
        interacting.finish(generation: interacting.generation)
        #expect(interacting.phase == .interacting(.charge, .motion))
    }

    @Test func aChargeReleaseCannotEndAStretchAndAStretchReleaseCannotEndACharge() {
        var mismatched = StartPageMarkSession()
        _ = mismatched.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        #expect(mismatched.handle(.discharge(1), canAnimate: true, reduceMotion: false).isEmpty)
        _ = mismatched.pause()
        _ = mismatched.handle(.begin(.charge), canAnimate: true, reduceMotion: false)
        #expect(mismatched.handle(.release(.zero), canAnimate: true, reduceMotion: false).isEmpty)
    }
}

struct StartPageMarkReduceMotionTests {
    @Test func reduceMotionSelectsTheShimmerAndMotionIsTheDefault() {
        #expect(StartPageMarkMotionStyle(reduceMotion: true) == .shimmer)
        #expect(StartPageMarkMotionStyle(reduceMotion: false) == .motion)
    }

    @Test func reduceMotionNeverStretchesTheMarkAndKeepsTheShimmerChosenAtTheTrigger() {
        var taffy = Pointer()
        taffy.reduceMotion = true
        _ = taffy.down(.zero, 0)
        #expect(taffy.drag(CGPoint(x: 20, y: 0), 0.1).isEmpty)
        #expect(taffy.session.phase == .interacting(.taffy, .shimmer))
        taffy.reduceMotion = false
        #expect(taffy.drag(CGPoint(x: 30, y: 9), 0.2).isEmpty)
        #expect(taffy.up(CGPoint(x: 30, y: 9), 0.3) == [.shimmer, .haptic])
        #expect(taffy.session.phase == .playing(.taffy, .shimmer))
    }

    @Test func reduceMotionReplacesTheSwoopWithTheShimmer() {
        var swoop = Pointer()
        swoop.reduceMotion = true
        _ = swoop.click(.zero, 0)
        _ = swoop.click(.zero, 0.2)
        #expect(swoop.down(.zero, 0.4) == [.shimmer, .haptic])
        #expect(!swoop.session.landing && swoop.session.land(generation: swoop.session.generation).isEmpty)
    }

    @Test func reduceMotionChargesWithTheGlowOnlyAndReplacesTheLoopWithTheShimmer() {
        var charge = Pointer()
        charge.reduceMotion = true
        _ = charge.down(.zero, 0)
        #expect(charge.hold(0.35) == [.charge(.shimmer)])
        #expect(charge.up(.zero, 1.2) == [.shimmer, .haptic])
        #expect(!charge.session.landing)
    }

    @Test func anUnderchargedReduceMotionReleaseOnlyFadesTheGlow() {
        var weak = Pointer()
        weak.reduceMotion = true
        _ = weak.down(.zero, 0)
        _ = weak.hold(0.35)
        #expect(weak.up(.zero, 0.5) == [.play(.relax(StartPageMarkCharge.level(held: 0.5 - 0.35), .shimmer))])
    }
}

struct StartPageMarkPauseTests {
    private let visible = StartPageMarkActivity(windowVisible: true, occluded: false, miniaturized: false, hidden: false)

    @Test func aVisibleWindowAnimates() {
        #expect(visible.canAnimate)
    }

    @Test func anOccludedMiniaturizedHiddenOrInvisibleWindowPauses() {
        var occluded = visible, miniaturized = visible, hidden = visible, closed = visible
        occluded.occluded = true
        miniaturized.miniaturized = true
        hidden.hidden = true
        closed.windowVisible = false
        #expect(!occluded.canAnimate && !miniaturized.canAnimate && !hidden.canAnimate && !closed.canAnimate)
    }

    @Test func aMarkWithoutAWindowPauses() {
        #expect(!StartPageMarkActivity.inactive.canAnimate)
    }

    @Test(arguments: [StartPageMarkEasterEgg.taffy, .swoop, .charge])
    func aTriggerInAPausedWindowIsSkipped(egg: StartPageMarkEasterEgg) {
        var session = StartPageMarkSession()
        #expect(session.handle(.begin(egg), canAnimate: false, reduceMotion: false).isEmpty && session.phase == .rest)
    }

    @Test func pausingAtRestDoesNothing() {
        var session = StartPageMarkSession()
        #expect(session.pause().isEmpty && session.generation == 0)
    }

    @Test func losingVisibilityMidStretchPutsTheMarkBackAtRest() {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        #expect(session.handle(.track(CGVector(dx: 9, dy: 0)), canAnimate: false, reduceMotion: false) == [.reset])
    }

    @Test func aReleaseInAPausedWindowNeitherPlaysNorTicks() {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.charge), canAnimate: true, reduceMotion: false)
        #expect(session.handle(.discharge(1), canAnimate: false, reduceMotion: false) == [.reset])
    }

    @Test func occludingTheWindowMidSwoopSkipsToRestAndTheLandingNeverTicks() {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.swoop), canAnimate: true, reduceMotion: false)
        let generation = session.generation
        #expect(session.pause() == [.reset] && session.phase == .rest)
        #expect(session.land(generation: generation).isEmpty)
        session.finish(generation: generation)
        #expect(session.phase == .rest && session.generation == generation + 1)
    }

    @Test func hidingTheWindowMidChargeResetsItAndEndsTheGesture() {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        _ = pointer.hold(0.35)
        pointer.canAnimate = false
        #expect(pointer.drag(CGPoint(x: 12, y: 0), 0.4) == [.reset])
        #expect(pointer.recognizer.press == nil && pointer.recognizer.holdDeadline == nil)
    }
}
