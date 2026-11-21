import AppKit
import Testing
@testable import Parc

struct SidebarSpacePagingModelTests {
    typealias M = SidebarSpacePagingModel
    typealias G = SidebarSpaceCreationGesture

    @Test func onlyPhasedOrMomentumPreciseScrollsAreGestures() {
        #expect(M.isGestural(phase: .began, momentumPhase: [], precise: true))
        #expect(M.isGestural(phase: [], momentumPhase: .changed, precise: true))
        #expect(!M.isGestural(phase: .began, momentumPhase: [], precise: false))
        #expect(!M.isGestural(phase: [], momentumPhase: [], precise: true))
    }

    @Test(arguments: [
        (120.0, 6.0, 0, 1), (120.0, -6.0, 1, 0), (90.0, 1.0, 0, 0), (110.0, 1.0, 0, 1),
        (700.0, 900.0, 1, 2), (-80.0, -900.0, 0, 0), (650.0, 900.0, 3, 3),
    ] as [(CGFloat, CGFloat, Int, Int)])
    func theReleaseTargetMovesAtMostOnePageWithinTheStrip(position: CGFloat, velocity: CGFloat, begin: Int, expected: Int) {
        #expect(M.target(position: position, velocity: velocity, width: 200, count: 4, begin: begin) == expected)
    }

    @Test func discreteScrollsAccumulateThenCoolDown() {
        var model = M()
        #expect(model.discrete(deltaX: 0.6, inverted: false, now: 10) == 0)
        #expect(model.discrete(deltaX: 0.6, inverted: false, now: 10.02) == -1)
        #expect(model.discrete(deltaX: -3, inverted: false, now: 10.1) == 0)
        #expect(model.discrete(deltaX: -3, inverted: false, now: 10.3) == 1)
    }

    @Test func aGapOver50MillisecondsRestartsTheDiscreteSum() {
        var model = M()
        #expect(model.discrete(deltaX: 0.8, inverted: false, now: 11) == 0)
        #expect(model.discrete(deltaX: 0.8, inverted: false, now: 11.2) == 0)
    }

    @Test func invertedDevicesReverseTheDiscreteDirection() {
        var model = M()
        #expect(model.discrete(deltaX: -2, inverted: true, now: 12) == -1)
    }

    @Test func aLegacySwipeRightGoesBack() {
        #expect(M.swipeStep(deltaX: 1) == -1 && M.swipeStep(deltaX: -1) == 1 && M.swipeStep(deltaX: 0) == 0)
    }

    @Test func settleVelocityKeepsOnlyMotionTowardTheTarget() {
        #expect(M.settleVelocity(50, position: 100, targetOrigin: 0) == 0)
        #expect(M.settleVelocity(-50, position: 100, targetOrigin: 0) == -50)
    }

    @Test func velocityIsStripPointsPerSecondAndAPauseHasNone() {
        #expect(abs(M.velocity([(1.0, 0), (1.05, 10)], at: 1.05) - 200) < 0.001)
        #expect(M.velocity([(1.0, 0), (1.05, 10)], at: 1.3) == 0)
    }

    @Test func thePagingSpringIsCriticallyDampedAndSettlesIn400Milliseconds() {
        #expect(abs(M.springValue(from: 100, velocity: 0, time: 0) - 100) < 0.001)
        #expect(abs(M.springValue(from: 100, velocity: 0, time: 1.2)) < 0.5)
        #expect(M.springValue(from: 100, velocity: 0, time: 0.2) > 0)
        let omega = 2 * CGFloat.pi / 0.4
        #expect(abs(M.springValue(from: 1, velocity: 0, time: 0.3) - (1 + omega * 0.3) * exp(-omega * 0.3)) < 1e-12)
    }

    @Test func anIdenticalPresentationFingerprintIsSkipped() {
        #expect(SidebarSpacePagingPresentationSkip.shouldSkip(previous: 12, next: 12))
        #expect(!SidebarSpacePagingPresentationSkip.shouldSkip(previous: 12, next: 12.1))
        #expect(!SidebarSpacePagingPresentationSkip.shouldSkip(previous: nil, next: 0))
    }

    static func pages(_ selected: Int, _ offset: CGFloat, within reach: ClosedRange<Int>? = nil) -> (left: Int, progress: CGFloat)? {
        M.themePages(selected: selected, offset: offset, width: 240, count: 3, within: reach)
    }

    static func same(_ a: (left: Int, progress: CGFloat)?, _ b: (left: Int, progress: CGFloat)?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.left == b.left && abs(a.progress - b.progress) < 1e-9
    }

    @Test func themePagesFollowTheStripPosition() {
        #expect(Self.same(Self.pages(1, -96), (1, 0.4)) && Self.same(Self.pages(1, 96), (0, 0.6)))
        #expect(Self.same(Self.pages(1, -96), Self.pages(2, 144)))
        #expect(Self.same(Self.pages(0, -312), (1, 0.3)))
        #expect(Self.same(Self.pages(2, 264), (0, 0.9)))
    }

    @Test func beyondTheStripsEndsItsEndPageShowsAlone() {
        #expect(Self.same(Self.pages(0, 72), (0, 0)) && Self.same(Self.pages(2, -72), (1, 1)))
    }

    @Test func thereIsNoThemePairWithoutTwoPagesAndAWidth() {
        #expect(M.themePages(selected: 0, offset: 10, width: 240, count: 1) == nil)
        #expect(M.themePages(selected: 0, offset: 10, width: 0, count: 3) == nil)
    }

    @Test func aSwipeReachesItsOwnSpaceAndTheSpacesEitherSide() {
        #expect(M.reach(begin: 0, count: 3) == 0...1 && M.reach(begin: 1, count: 3) == 0...2 && M.reach(begin: 2, count: 3) == 1...2)
        #expect(M.reach(begin: 0, count: 1) == 0...0)
    }

    @Test func withinAReachTheColourRestsOnTheSwipesTwoSpaces() {
        #expect(Self.same(Self.pages(0, -312, within: 0...1), (0, 1)) && Self.same(Self.pages(2, 312, within: 1...2), (1, 0)))
        #expect(Self.same(Self.pages(1, -40, within: 0...1), (0, 1)))
        #expect(Self.same(Self.pages(1, 96, within: 0...2), Self.pages(1, 96)) && Self.same(Self.pages(1, -96, within: 0...2), Self.pages(1, -96)))
    }

    @Test func nothingStretchesAtOrInsideAnEdge() {
        #expect(M.stretch(0, width: 240) == 0 && M.stretch(-5, width: 240) == 0 && M.stretch(30, width: 0) == 0)
    }

    @Test func theStretchStartsAt055OfTheDrag() {
        #expect(abs(M.stretch(0.01, width: 240) / 0.01 - 0.55) < 0.001)
    }

    @Test func theStretchStiffensAndNeverReachesATenthOfThePage() {
        let stretches = stride(from: 10, through: 4000, by: 10).map { M.stretch(CGFloat($0), width: 240) }
        let gains = zip(stretches.dropFirst(), stretches).map { $0 - $1 }
        #expect(zip(gains.dropFirst(), gains).allSatisfy { $0 > 0 && $0 < $1 })
        #expect(stretches.last! < 24)
    }

    @Test func theStretchScalesWithTheSidebarsWidth() {
        #expect(abs(M.stretch(100, width: 480) - 2 * M.stretch(50, width: 240)) < 1e-9)
    }

    @Test func theStripFollowsBetweenItsEndsAndStretchesPastThem() {
        let middle = M.Edges(reach: 0...1, width: 240, opensPastEnd: false, holding: 120)
        #expect(middle.resisted(315) == 240 + M.stretch(75, width: 240))
        #expect(middle.resisted(-60) == -M.stretch(60, width: 240))
        #expect(middle.resisted(130) == 130)
    }

    @Test func pastTheLastSpaceTheCreatePullFollowsTheDrag() {
        let pastEnd = M.Edges(reach: 1...2, width: 240, opensPastEnd: true, holding: 360)
        #expect(pastEnd.last == nil && pastEnd.resisted(525) == 525 && pastEnd.resisted(200) == 240 - M.stretch(40, width: 240))
    }

    @Test func pickedUpPastAnEdgeTheStripSpendsOnlyTheRemainingGive() {
        let held = M.Edges(reach: 0...1, width: 240, opensPastEnd: false, holding: -10)
        #expect(held.first == -10 && held.resisted(-10) == -10 && held.resisted(30) == 30)
        #expect(held.resisted(-400) > -24 && held.resisted(-400) < -10)
    }

    @Test func beyondTheWholeGiveTheStripGoesNoFurtherButFollowsBack() {
        let spent = M.Edges(reach: 1...2, width: 240, opensPastEnd: false, holding: 197)
        #expect(spent.first == 197 && spent.firstGive == 0 && spent.resisted(100) == 197 && spent.resisted(230) == 230)
    }

    @Test func pullPastNineteenTwentiethsOfTheGiveIsNotBanked() {
        let held = M.Edges(reach: 0...1, width: 240, opensPastEnd: false, holding: -10)
        let spent = M.Edges(reach: 1...2, width: 240, opensPastEnd: false, holding: 197)
        let middle = M.Edges(reach: 0...1, width: 240, opensPastEnd: false, holding: 120)
        #expect(spent.held(100) == 197 && spent.held(230) == 230)
        #expect(abs(held.held(-9000) - (-10 - 14 * 19 / 0.55)) < 1e-9)
        #expect(middle.held(-5000) < -800 && middle.held(5000) > 1000)
        #expect(abs(M.stretch(-middle.held(-5000), width: 240) - 0.95 * 24) < 1e-9)
    }

    @Test func aReachWidensOnlyTowardSpacesThatExist() {
        #expect(M.widened(1...2, toward: 197, width: 240, count: 3) == 0...2)
        #expect(M.widened(0...1, toward: 120, width: 240, count: 3) == 0...1)
        #expect(M.widened(1...2, toward: 600, width: 240, count: 3) == 1...2)
        #expect(M.widened(0...1, toward: -30, width: 240, count: 3) == 0...1)
    }

    @Test func aSwipeLeavesOutTheSideWhereAPageStandsIn() {
        #expect(M.reach(begin: 2, count: 4, without: -1) == 2...3 && M.reach(begin: 1, count: 4, without: 1) == 0...1)
        #expect(M.reach(begin: 3, count: 4, without: -1) == 3...3 && M.reach(begin: 0, count: 3, without: 1) == 0...0)
    }

    @Test func thePageAClickLeftShowsOnlyOnItsOwnSide() {
        #expect(M.shownSource(0, selected: 2, offset: 100) == 0 && M.shownSource(3, selected: 1, offset: -50) == 3)
        #expect(M.shownSource(0, selected: 2, offset: -100) == nil && M.shownSource(3, selected: 1, offset: 50) == nil)
        #expect(M.shownSource(0, selected: 2, offset: 0) == nil && M.shownSource(nil, selected: 2, offset: 100) == nil)
    }

    @Test func theCreateEdgeMeasuresHowFarPastTheLastPageTheStripIs() {
        #expect(G.overscroll(selected: 2, offset: -30, width: 240, count: 3) == 30)
        #expect(G.overscroll(selected: 1, offset: -270, width: 240, count: 3) == 30)
        #expect(G.overscroll(selected: 1, offset: 0, width: 240, count: 3) < 0 && G.overscroll(selected: 2, offset: 0, width: 240, count: 3) == 0)
    }

    @Test func theEdgeSlidesInOver15PointsAndTheRingFillsOver22AndAHalf() {
        #expect(G.presentation(7.5) == 0.5 && G.presentation(40) == 1 && G.presentation(-3) == 0)
        #expect(G.progress(11.25) == 0.5 && G.progress(22.5) == 1 && G.progress(-3) == 0)
    }

    @Test func fillingTheRingActivatesItOnceWithAHaptic() {
        var gesture = G()
        do {
            let r0 = gesture.update(progress: 0.6, pulling: true, now: 10)
            #expect(!r0 && !gesture.isActivated)
        }
        do {
            let r0 = gesture.update(progress: 1, pulling: true, now: 10.01)
            #expect(r0 && gesture.isActivated)
        }
        do {
            let r0 = gesture.update(progress: 1, pulling: true, now: 10.05)
            #expect(!r0)
        }
    }

    @Test func aReleaseWithinATenthOfASecondOfFillingCreatesNothing() {
        var gesture = G()
        _ = gesture.update(progress: 1, pulling: true, now: 10.01)
        do {
            let r0 = gesture.release(now: 10.1)
            #expect(!r0)
        }
    }

    @Test func emptyingTheRingDeactivatesItWithAHaptic() {
        var gesture = G()
        _ = gesture.update(progress: 1, pulling: true, now: 10.01)
        do {
            let r0 = gesture.update(progress: 0.4, pulling: true, now: 10.2)
            #expect(r0 && !gesture.isActivated)
        }
    }

    @Test func dippingBelowFullRestartsTheHold() {
        var gesture = G()
        _ = gesture.update(progress: 1, pulling: true, now: 11)
        _ = gesture.update(progress: 0.9, pulling: true, now: 11.05)
        _ = gesture.update(progress: 1, pulling: true, now: 11.1)
        do {
            let r0 = gesture.release(now: 11.15)
            #expect(!r0)
        }
    }

    @Test func aReleaseHeldFullForATenthOfASecondCreatesOnce() {
        var gesture = G()
        _ = gesture.update(progress: 1, pulling: true, now: 12)
        do {
            let r0 = gesture.release(now: 12.2)
            #expect(r0)
        }
        do {
            let r0 = gesture.release(now: 12.3)
            #expect(!r0)
        }
    }

    @Test func aRingFilledAfterTheFingersLetGoNeverArms() {
        var released = G()
        do {
            let r0 = released.update(progress: 1, pulling: false, now: 13)
            #expect(!r0 && !released.isActivated)
        }
        do {
            let r0 = released.update(progress: 0, pulling: false, now: 13.1)
            let r1 = released.release(now: 13.2)
            #expect(!r0 && !r1)
        }
    }

    @Test func aRingTheFingersFilledStaysArmedAndStillTapsAsItEmpties() {
        var released = G()
        _ = released.update(progress: 1, pulling: true, now: 14)
        do {
            let r0 = released.update(progress: 1, pulling: false, now: 14.2)
            #expect(!r0 && released.isActivated)
        }
        do {
            let r0 = released.update(progress: 0.5, pulling: false, now: 14.3)
            #expect(r0 && !released.isActivated)
        }
    }

    @Test func theEdgeSpringRetargetsFromTheSamePlaceAndSpeedThenSettles() {
        var spring = SidebarSpring(response: 0.4, damping: 0.8)
        spring.retarget(1, now: 0)
        let before = spring.value(at: 0.1), speed = spring.speed(at: 0.1)
        #expect(before > 0 && before < 1 && speed > 0)
        spring.retarget(0.2, now: 0.1)
        #expect(abs(spring.value(at: 0.1) - before) < 1e-9 && abs(spring.speed(at: 0.1) - speed) < 1e-9)
        #expect(!spring.isSettled(at: 0.2) && spring.isSettled(at: 2) && abs(spring.value(at: 2) - 0.2) < 0.001)
    }
}
