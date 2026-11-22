import AppKit
import Metal
import SceneKit
import Testing
@testable import Parc
@testable import ParcCore

struct WindowFrameViewTestsStrain {
    private typealias Harness = WindowFrameViewTestsSupport.Harness

    @Test @MainActor
    func keysStopAtTheThickestPointWithAThunk() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.keyDown(with: h.key(126))
        #expect(view.crank.value == 13 && h.events.last == .end(.thick) && h.output.played.last == .end(.thick))
    }

    @Test @MainActor
    func theEndFlashFades() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.keyDown(with: h.key(126))
        #expect(view.flash == 1)
        h.advance(1)
        #expect(view.flash == 0)
    }

    @Test @MainActor
    func pushingPastTheEndAddsGiveAndFlashes() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 60)
        #expect(h.events.last == .end(.thick) && view.crank.strain > 0 && view.flash == 1)
    }

    @Test @MainActor
    func theCrankTremblesAndKeepsAnimatingWhileStrained() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 60)
        h.advance(0.05)
        #expect(view.tremble != 0 && !WindowFrameViewTestsSupport.near(CGFloat(view.model.armDegrees), CGFloat(view.crank.armDegrees), 0.0001))
        #expect(view.isAnimating)
    }

    @Test @MainActor
    func reduceMotionStillsTheTremble() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 60)
        h.advance(0.05)
        h.reduceMotion = true
        h.advance(0.05)
        #expect(view.tremble == 0)
    }

    @Test @MainActor
    func lettingGoOfStrainSpringsBackToTheEndpoint() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 60)
        view.releaseTurn()
        h.advance(1)
        #expect(view.crank.value == 13 && h.previews.last == 13 && view.crank.strain == 0)
    }

    @Test @MainActor
    func reduceMotionUpdatesLightsWithoutSparkles() {
        let h = Harness.presented(value: 13, reduceMotion: true)
        let view = h.view
        let sparkles = view.lights.sparkles.count
        view.keyDown(with: h.key(125))
        #expect(view.lights.sparkles.count == sparkles && view.lights.litCount == 10)
        h.advance(1)
        #expect(h.previews.last == 12)
    }
}
