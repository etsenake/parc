import AppKit
import Metal
import SceneKit
import Testing
@testable import Parc
@testable import ParcCore

struct WindowFrameViewTestsDismissal {
    private typealias Support = WindowFrameViewTestsSupport

    private typealias Harness = Support.Harness
    private typealias Finish = Support.Finish

    @Test @MainActor
    func escapeDismissesAndLetsClicksThrough() {
        let h = Harness.escaping()
        let view = h.view
        #expect(view.phase == .dismissing(commit: false) && view.hitTest(h.superPoint(view.hub)) == nil)
    }

    @Test @MainActor
    func escapeRestoresTheReadoutImmediately() {
        let h = Harness.escaping()
        let view = h.view
        #expect(view.lights.readout == 10 && view.lights.litCount == 8)
    }

    @Test @MainActor
    func escapeRestoresTheAccessibleValueImmediately() {
        let h = Harness.escaping()
        let view = h.view
        #expect(view.value == 10 && (view.accessibilityValue() as? NSNumber)?.intValue == 10 && view.accessibilityValueDescription() == "10 points, Classic")
    }

    @Test @MainActor
    func keysDoNotChangeTheCrankWhileItIsLeaving() {
        let h = Harness.escaping()
        let view = h.view
        view.keyDown(with: h.key(126))
        #expect(view.crank.value == 12)
    }

    @Test @MainActor
    func escapeRestoresTheOriginalFrame() {
        let h = Harness.escaping()
        h.advance(0.6)
        #expect(h.finishes == [Finish(commit: false, value: 10)])
        #expect(h.previews.contains { $0 > 10.5 } && h.previews.last == 10)
    }

    @Test @MainActor
    func dismissalHidesTheSceneAndStopsTheTimer() {
        let h = Harness.escaping()
        let view = h.view
        h.advance(0.6)
        #expect(view.phase == .finished && view.sceneView.isHidden && view.alphaValue == 0 && !view.isAnimating)
    }

    @Test @MainActor
    func dismissalReleasesTheAudioOutput() {
        let h = Harness.escaping()
        h.advance(0.6)
        #expect(h.output.stops == 1)
    }

    @Test @MainActor
    func aSecondDismissDoesNotFinishAgain() {
        let h = Harness.escaping()
        let view = h.view
        h.advance(0.6)
        view.dismiss(commit: true)
        h.advance(0.5)
        #expect(h.finishes.count == 1)
    }

    @Test @MainActor
    func returnKeepsTheUpdatedFrame() {
        let keep = Harness(value: 7, palette: Support.dark)
        keep.view.present()
        keep.advance(0.5)
        keep.view.keyDown(with: keep.key(125))
        keep.view.keyDown(with: keep.key(36))
        keep.advance(0.5)
        #expect(keep.finishes == [Finish(commit: true, value: 6)])
    }

    @Test @MainActor
    func dismissingMidTurnKeepsTheNearestPoint() {
        let held = Harness(value: 10, palette: Support.light)
        held.view.present()
        held.advance(0.5)
        held.view.turn(by: 80)
        held.view.dismiss(commit: true)
        held.advance(0.6)
        #expect(held.finishes == [Finish(commit: true, value: 11)])
    }

    @Test(arguments: [true, false]) @MainActor
    func clickingInsideOrOutsideControlsDismissal(inside: Bool) {
        let h = Harness.presented(hosted: true)
        let point = inside ? CGPoint(x: h.view.hub.x, y: h.view.hub.y + 60) : CGPoint(x: -20, y: -20)
        h.view.outsideClick(h.mouse(.leftMouseDown, point))
        #expect(h.view.phase == (inside ? .shown : .dismissing(commit: true)))
        h.advance(0.5)
        if inside {
            #expect(h.finishes.isEmpty)
        } else {
            #expect(h.finishes == [Finish(commit: true, value: 10)])
        }
    }
}
