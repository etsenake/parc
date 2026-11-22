import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct PeekSwipeDismissalTestsDragAndReturn {
    private typealias Support = PeekSwipeDismissalTestsSupport

    @Test func theCardIsFullyOffOncePastThePanesRightEdgeAndItsShadow() {
        #expect(Support.geometry.exitDistance == 463)
        #expect(Support.geometry.paneWidth == 508)
    }

    struct MotionDuration: CustomTestStringConvertible {
        let label: String
        let duration: Double
        let expected: Double

        var testDescription: String { label }
    }

    @Test(arguments: [
        MotionDuration(label: "Spring response", duration: PeekDismissalTiming.springResponse, expected: 0.34),
        MotionDuration(label: "Slide", duration: PeekDismissalTiming.slide, expected: 0.22),
        MotionDuration(label: "Fade", duration: PeekDismissalTiming.fade, expected: 0.2),
        MotionDuration(label: "Reduce Motion fade", duration: PeekDismissalTiming.reduced, expected: 0.15),
    ])
    func theMotionDurationMatchesTheTransition(_ sample: MotionDuration) {
        #expect(sample.duration == sample.expected)
    }

    @Test func aNewCardRestsInPlaceFullyShown() {
        let m = PeekDismissalMotion(geometry: Support.geometry)
        #expect(m.frame(at: 0) == .rest)
        #expect(!m.isAnimating(at: 0))
    }

    @Test func theCardSlidesWithTheFingersAndTheWashFades() {
        var m = Support.dragging()
        m.follow(0.4)
        let drag = m.frame(at: 0)
        #expect(Support.near(Double(drag.offset), 0.4 * 463))
        #expect(drag.card == 1)
        #expect(Support.near(drag.wash, 0.6))
    }

    @Test func theCardStopsOnceItIsFullyOff() {
        var m = Support.dragging()
        m.follow(1.4)
        #expect(m.frame(at: 0).offset == 463)
        #expect(m.frame(at: 0).wash == 0)
    }

    @Test func pullingPastTheStartHoldsItAtRest() {
        var m = Support.dragging()
        m.follow(-0.2)
        #expect(m.frame(at: 0) == PeekDismissalFrame(offset: 0, card: 1, wash: 1))
    }

    private static func springingHome() -> PeekDismissalMotion {
        var m = Support.dragging()
        m.follow(0.35)
        m.springBack(velocity: 0, at: 10)
        return m
    }

    struct SpringSample: CustomTestStringConvertible {
        let label: String
        let step: Int

        var testDescription: String { label }
    }

    @Test(arguments: (1...60).map { SpringSample(label: "Frame \($0)", step: $0) })
    func theWashReturnsWithTheCard(_ sample: SpringSample) {
        let frame = Self.springingHome().frame(at: 10 + Double(sample.step) / 120)
        #expect(Support.near(frame.wash, 1 - min(max(Double(frame.offset) / 463, 0), 1)))
    }

    @Test func theSpringBringsTheCardHomeWithoutPassingItsRestingPlace() {
        let m = Self.springingHome()
        var lowest = CGFloat.infinity, previous = m.frame(at: 10).offset, monotonic = true
        for step in 1...60 {
            let frame = m.frame(at: 10 + Double(step) / 120)
            if frame.offset > previous + 1e-9 && frame.offset > 0 { monotonic = false }
            lowest = min(lowest, frame.offset)
            previous = frame.offset
        }
        #expect(monotonic)
        #expect(lowest == 0)
    }

    @Test func theSpringSettlesWithinASecond() {
        let m = Self.springingHome()
        #expect(!m.isAnimating(at: 11))
        #expect(m.frame(at: 11) == .rest)
    }

    @Test func aCardLetGoWhileStillMovingOutCarriesOnBrieflyBeforeReturning() {
        var flung = Support.dragging()
        flung.follow(0.3)
        flung.springBack(velocity: 2, at: 0)
        #expect(flung.frame(at: 0.02).offset > 0.3 * 463)
    }

    @Test func aHardFlickBackLandsTheCardAtRestNeverPastIt() {
        var thrown = Support.dragging()
        thrown.follow(0.5)
        thrown.springBack(velocity: -12, at: 0)
        var leftmost = CGFloat.infinity
        for step in 0...60 { leftmost = min(leftmost, thrown.frame(at: Double(step) / 120).offset) }
        #expect(leftmost == 0)
        #expect(thrown.frame(at: 2) == .rest)
    }
}
