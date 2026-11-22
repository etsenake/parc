import AppKit
import Metal
import SceneKit
import Testing
@testable import Parc
@testable import ParcCore

struct WindowFrameViewTestsGestureInterruption {
    private typealias CrankView = WindowFrameViewTestsSupport.CrankView
    private typealias Harness = WindowFrameViewTestsSupport.Harness

    @Test @MainActor
    func aTrackpadTurnRemainsHeldThroughAShortPause() {
        let h = Harness.presented()
        h.view.scrollWheel(with: h.scroll(30, precise: true, phase: 1))
        #expect(h.view.crank.displayed > 10.2 && h.view.isWaitingForGesture)
        h.advance(0.3)
        #expect(h.view.crank.displayed > 10.2 && h.view.isWaitingForGesture)
    }

    @Test @MainActor
    func aMissingTrackpadEndReleasesAfterTheGestureIdleDelay() {
        let h = Harness.presented()
        h.view.scrollWheel(with: h.scroll(30, precise: true, phase: 1))
        h.advance(0.59)
        #expect(h.view.isWaitingForGesture)
        h.advance(0.02)
        #expect(h.view.crank.displayed == Double(h.view.crank.value))
        #expect(!h.view.isWaitingForGesture)
    }

    @Test @MainActor
    func horizontalTrackpadInputAlsoTurnsTheCrank() {
        let h = Harness.presented()
        let view = h.view
        var reference = view.crank
        let sideways = h.scroll(0, precise: true, phase: 1, horizontal: 20)
        view.scrollWheel(with: sideways)
        reference.turn(degrees: WindowFrameCrank.scrollDegrees(deltaY: Double(sideways.scrollingDeltaX), precise: true))
        #expect(view.crank == reference)
    }

    struct ScrollAxes: CustomTestStringConvertible {
        let label: String
        let x: CGFloat
        let y: CGFloat
        let delta: CGFloat

        var testDescription: String { label }
    }

    @Test(arguments: [
        ScrollAxes(label: "Horizontal dominates", x: 3, y: -1, delta: 3),
        ScrollAxes(label: "Vertical dominates", x: 1, y: -2, delta: -2),
    ]) @MainActor
    func theLargerScrollAxisWins(_ sample: ScrollAxes) {
        #expect(CrankView.scrollDelta(x: sample.x, y: sample.y) == sample.delta)
    }

    @Test @MainActor
    func grabbingMidSettleContinuesFromTheDisplayedPoint() {
        let h = Harness.presented()
        let view = h.view
        view.keyDown(with: h.key(126))
        h.advance(0.03)
        let shown = h.previews.last ?? 0
        #expect(abs(shown - CGFloat(view.crank.value)) > 0.05)
        view.turn(by: 1)
        #expect(abs((h.previews.last ?? 0) - (shown + 1 / 120)) < 0.0001)
    }

    @Test @MainActor
    func grabbingDuringSpringBackContinuesFromTheGive() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 40)
        view.releaseTurn()
        h.advance(0.02)
        let strained = h.previews.last ?? 0
        #expect(strained > 13)
        view.turn(by: -1)
        #expect(abs((h.previews.last ?? 0) - CGFloat(WindowFrameCrank.rubber(WindowFrameCrankView.raw(showing: Double(strained)) - 1.0 / 120))) < 0.0001)
    }

    @Test(arguments: [13.2, 2.9]) @MainActor
    func theGiveTransformCanBeInverted(point: Double) {
        #expect(abs(WindowFrameCrank.rubber(CrankView.raw(showing: point)) - point) < 0.0001)
    }
}
