import Testing
@testable import Parc

struct ExtensionPopupActivityMotionTests {
    private typealias Bounce = ExtensionPopupBounce
    private typealias Fade = ExtensionPopupActivityFade
    private typealias Motion = ExtensionPopupActivityMotion
    private let past = 1e-6
    private var apex: Double { 10 + Bounce.delay + Bounce.hop * Bounce.rise }

    private func samples(_ from: Double, _ to: Double) -> [Double] {
        Array(stride(from: from, through: to, by: 1.0 / 120))
    }

    private func smooth(_ bounce: Bounce, _ from: Double, _ to: Double) -> Bool {
        let lifts = samples(from, to).map { bounce.lift(at: $0) }
        return zip(lifts, lifts.dropFirst()).allSatisfy { abs($0 - $1) <= 0.3 }
    }

    @Test func eachHopStaysWithinTheIconSpace() {
        let curve = stride(from: 0.0, through: 1.0, by: 0.001).map { Bounce.lift(atHopProgress: $0) }
        #expect(curve.allSatisfy { $0 >= 0 && $0 <= Bounce.height } && abs((curve.max() ?? 0) - Bounce.height) < 0.001)
        #expect(Bounce.lift(atHopProgress: 0) == 0 && Bounce.lift(atHopProgress: 1) == 0)
        let launch = Bounce.lift(atHopProgress: 0.02) / 0.02, touchdown = Bounce.lift(atHopProgress: 0.98) / 0.02
        #expect(launch > 8 * touchdown && Bounce.lift(atHopProgress: 0.98) < 0.02)
    }

    @Test func aLoadingPopupRepeatsItsHopAfterTheDelay() {
        let bouncing = Bounce(start: 10)
        #expect(samples(10, 10 + Bounce.delay).allSatisfy { bouncing.lift(at: $0) == 0 })
        #expect(samples(11, 12).allSatisfy { abs(bouncing.lift(at: $0) - bouncing.lift(at: $0 + Bounce.cycle)) < 0.0001 })
        #expect(smooth(bouncing, 10, 13) && !bouncing.isFinished(at: 30))
        #expect(samples(10, 13).contains { bouncing.lift(at: $0) > 0 } && samples(10, 13).contains { bouncing.lift(at: $0) == 0 })
    }

    @Test func revealingDuringAHopLetsItLandNaturally() {
        let bouncing = Bounce(start: 10)
        let midHop = 10 + Bounce.delay + Bounce.cycle + 0.2
        var landing = bouncing
        landing.land(at: midHop)
        let touchdownTime = 10 + Bounce.delay + Bounce.cycle + Bounce.hop
        #expect(abs(landing.landingTime(after: midHop) - touchdownTime) < 0.0001 && !landing.isFinished(at: touchdownTime - 0.01))
        #expect(samples(midHop, touchdownTime - 0.001).allSatisfy { landing.lift(at: $0) == bouncing.lift(at: $0) })
        #expect(landing.isFinished(at: touchdownTime + past)
                  && samples(touchdownTime + past, touchdownTime + 2).allSatisfy { landing.lift(at: $0) == 0 })
        #expect(smooth(landing, midHop - 0.5, touchdownTime + 0.5))
    }

    @Test func revealBetweenHopsStopsImmediately() {
        let bouncing = Bounce(start: 10)
        let restTime = 10 + Bounce.delay + Bounce.hop + 0.05
        var resting = bouncing
        resting.land(at: restTime)
        #expect(resting.isFinished(at: restTime) && resting.lift(at: restTime + 0.1) == 0)
    }

    @Test func aQuickPopupNeverMovesTheIcon() {
        var quick = Bounce(start: 10)
        quick.land(at: 10.1)
        #expect(quick.isFinished(at: 10.1) && samples(10.1, 12).allSatisfy { quick.lift(at: $0) == 0 })
    }

    @Test func aFailureBringsTheIconStraightDown() {
        let bouncing = Bounce(start: 10)
        var dropped = bouncing
        dropped.drop(at: apex)
        #expect(abs(dropped.lift(at: apex) - Bounce.height) < 0.0001)
        #expect(zip(samples(apex, apex + Bounce.drop), samples(apex, apex + Bounce.drop).dropFirst())
                  .allSatisfy { dropped.lift(at: $1) <= dropped.lift(at: $0) })
        #expect(dropped.isFinished(at: apex + Bounce.drop + past) && dropped.lift(at: apex + Bounce.drop + past) == 0
                  && !dropped.isFinished(at: apex + Bounce.drop - 0.01))
        #expect(apex + Bounce.drop < 10 + Bounce.delay + Bounce.hop)
        #expect(smooth(dropped, apex - 0.2, apex + 0.5))
    }

    @Test func aFailureBetweenHopsStopsImmediately() {
        let bouncing = Bounce(start: 10)
        let restTime = 10 + Bounce.delay + Bounce.hop + 0.05
        var grounded = bouncing
        grounded.drop(at: restTime)
        #expect(grounded.isFinished(at: restTime))
    }

    @Test func loadingAgainDuringAnOrdinaryLandingKeepsTheRhythm() {
        let bouncing = Bounce(start: 10)
        let midHop = 10 + Bounce.delay + Bounce.cycle + 0.2
        var landing = bouncing
        landing.land(at: midHop)
        var resumed = landing
        resumed.resume(at: midHop + 0.1)
        #expect(samples(midHop, midHop + 3).allSatisfy { resumed.lift(at: $0) == bouncing.lift(at: $0) } && !resumed.isFinished(at: 40))
    }

    @Test func loadingDuringAFailureLandingFinishesTheLandingBeforeAnotherHop() {
        var dropped = Bounce(start: 10)
        dropped.drop(at: apex)
        var recovered = dropped
        recovered.resume(at: apex + 0.05)
        #expect(abs(recovered.lift(at: apex + 0.05) - dropped.lift(at: apex + 0.05)) < 0.0001
                  && samples(apex + Bounce.drop + past, apex + Bounce.drop + Bounce.delay - past).allSatisfy { recovered.lift(at: $0) == 0 })
        #expect(samples(apex, apex + 2).contains { $0 > apex + Bounce.drop + Bounce.delay && recovered.lift(at: $0) > 0 }
                  && smooth(recovered, apex, apex + 2))
    }

    @Test func revealingDuringAFailureLandingKeepsTheIconDown() {
        var recovered = Bounce(start: 10)
        recovered.drop(at: apex)
        recovered.resume(at: apex + 0.05)
        var settled = recovered
        settled.land(at: apex + 0.08)
        #expect(settled.isFinished(at: apex + Bounce.drop + past) && settled.lift(at: apex + 1) == 0)
    }

    @Test func changingDirectionContinuesFromTheCurrentFill() {
        var fade = Fade()
        #expect(fade.value(at: 0) == 0 && fade.isFinished(at: 0))
        fade.retarget(1, at: 5)
        let lighting = samples(5, 5 + Fade.lighten).map { fade.value(at: $0) }
        #expect(zip(lighting, lighting.dropFirst()).allSatisfy { $1 >= $0 } && fade.value(at: 5 + Fade.lighten + past) == 1)
        #expect(fade.value(at: 5.05) > 0 && fade.value(at: 5.05) < 1 && !fade.isFinished(at: 5.05))
        let partway = fade.value(at: 5.09)
        fade.retarget(0, at: 5.09)
        #expect(fade.value(at: 5.09) == partway && fade.value(at: 5.1) < partway)
        #expect(fade.value(at: 5.09 + Fade.dim + past) == 0 && fade.isFinished(at: 5.09 + Fade.dim + past))
    }

    @Test func anOpenPopupRestsLitAndClosingEasesOutTheFill() {
        var motion = Motion()
        motion.show(.loading, at: 0, reduceMotion: false)
        #expect(motion.frame(at: 0, reduceMotion: false) == ExtensionPopupActivityFrame(fill: 0, lift: 0, finished: false))
        #expect(motion.frame(at: 1, reduceMotion: false).fill == 1 && !motion.frame(at: 5, reduceMotion: false).finished)
        let revealAt = Bounce.delay + 0.1
        motion.show(.open, at: revealAt, reduceMotion: false)
        let landed = Bounce.delay + Bounce.hop
        #expect(!motion.frame(at: landed - 0.01, reduceMotion: false).finished
                  && motion.frame(at: landed - 0.01, reduceMotion: false).lift > 0)
        #expect(motion.frame(at: landed + past, reduceMotion: false) == ExtensionPopupActivityFrame(fill: 1, lift: 0, finished: true))
        motion.show(nil, at: 3, reduceMotion: false)
        #expect(motion.frame(at: 3 + Fade.dim + past, reduceMotion: false) == ExtensionPopupActivityFrame(fill: 0, lift: 0, finished: true))
    }

    @Test func aPopupRefusedImmediatelyNeverFlashes() {
        var refused = Motion()
        refused.show(.loading, at: 0, reduceMotion: false)
        refused.show(nil, at: 0, reduceMotion: false)
        #expect(refused.frame(at: 0, reduceMotion: false) == ExtensionPopupActivityFrame(fill: 0, lift: 0, finished: true))
    }

    @Test func failureDuringAHopLandsTheIconAndDimsTheButton() {
        var failing = Motion()
        failing.show(.loading, at: 0, reduceMotion: false)
        failing.show(nil, at: apex - 10, reduceMotion: false)
        #expect(failing.frame(at: apex - 10, reduceMotion: false).lift > 2.9
                  && failing.frame(at: apex - 10 + Bounce.drop + past, reduceMotion: false).lift == 0
                  && failing.frame(at: apex - 10 + Fade.dim + past, reduceMotion: false).finished)
    }

    @Test func loadingAgainFromTheSameButtonKeepsTheLight() {
        let revealAt = Bounce.delay + 0.1
        var again = Motion()
        again.show(.loading, at: 0, reduceMotion: false)
        again.show(.open, at: revealAt, reduceMotion: false)
        again.show(.loading, at: revealAt + 0.1, reduceMotion: false)
        #expect(!again.frame(at: 10, reduceMotion: false).finished && again.frame(at: revealAt + 0.1, reduceMotion: false).fill == 1)
    }

    @Test func reduceMotionKeepsTheLightWithoutBouncing() {
        var still = Motion()
        still.show(.loading, at: 0, reduceMotion: true)
        #expect(samples(0, 3).allSatisfy { still.frame(at: $0, reduceMotion: true).lift == 0 }
                  && still.frame(at: Fade.lighten + past, reduceMotion: true) == ExtensionPopupActivityFrame(fill: 1, lift: 0, finished: true))
    }

    @Test func turningOnReduceMotionStopsTheCurrentHop() {
        var turnedOn = Motion()
        turnedOn.show(.loading, at: 0, reduceMotion: false)
        #expect(turnedOn.frame(at: apex - 10, reduceMotion: true).lift == 0)
    }
}
