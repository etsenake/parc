import AppKit
import Metal
import SceneKit
import Testing
@testable import Parc
@testable import ParcCore

struct WindowFrameViewTestsPointer {
    private typealias Harness = WindowFrameViewTestsSupport.Harness

    @Test @MainActor
    func trackpadScrollTurnsTheCrankOneToOne() {
        let h = Harness.presented()
        let reference = h.scrollTrackpad()
        #expect(h.view.crank == reference)
        #expect(h.previews.last == CGFloat(reference.displayed))
    }

    @Test @MainActor
    func scrollMomentumDoesNotContinueTurning() {
        let h = Harness.presented()
        let held = h.scrollTrackpad()
        h.view.scrollWheel(with: h.scroll(400, precise: true, momentum: 2))
        #expect(h.view.crank == held)
    }

    @Test @MainActor
    func liftingTheTrackpadFingersSettlesAtTheNearestPoint() {
        let h = Harness.presented()
        var expected = h.scrollTrackpad()
        h.view.scrollWheel(with: h.scroll(0, precise: true, phase: 4))
        expected.release()
        #expect(h.view.crank == expected)
        h.advance(1)
        #expect(h.previews.last == CGFloat(expected.value))
    }

    @Test @MainActor
    func aMouseWheelClickTurnsTheCrank() {
        let h = Harness.presented()
        h.view.scrollWheel(with: h.scroll(-3, precise: false))
        #expect(h.view.crank.displayed != 10)
    }

    @Test @MainActor
    func theWheelReleasesAfterItsShortIdleDelay() {
        let h = Harness.presented()
        h.view.scrollWheel(with: h.scroll(-3, precise: false))
        h.advance(0.24)
        #expect(h.view.isWaitingForGesture)
        h.advance(0.02)
        #expect(h.view.crank.displayed == Double(h.view.crank.value))
        #expect(!h.view.isWaitingForGesture)
    }

    @Test @MainActor
    func draggingTheKnobClockwiseByAThirdOfATurnAddsAPoint() {
        let h = Harness.presented()
        h.dragKnob(degrees: 120)
        #expect(h.view.crank.value == 11)
        #expect(h.events.last == .notch(11))
    }

    @Test @MainActor
    func releasingTheKnobSettlesTheFrame() {
        let h = Harness.presented()
        h.dragKnob(degrees: 100)
        h.view.mouseUp(with: h.mouse(.leftMouseUp, h.view.hub))
        #expect(h.view.crank.displayed == 11)
    }

    @Test @MainActor
    func draggingTheLightsDoesNotTurnTheCrank() {
        let h = Harness.presented()
        let view = h.view
        let hub = view.hub
        let before = view.crank
        view.mouseDown(with: h.mouse(.leftMouseDown, CGPoint(x: hub.x, y: hub.y + 100)))
        view.mouseDragged(with: h.mouse(.leftMouseDragged, CGPoint(x: hub.x + 100, y: hub.y)))
        view.mouseUp(with: h.mouse(.leftMouseUp, CGPoint(x: hub.x + 100, y: hub.y)))
        #expect(view.crank == before)
    }
}
