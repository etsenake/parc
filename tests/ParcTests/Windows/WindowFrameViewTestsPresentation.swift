import AppKit
import Metal
import SceneKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSettings

struct WindowFrameViewTestsPresentation {
    private typealias Support = WindowFrameViewTestsSupport

    private typealias CrankView = Support.CrankView
    private typealias Harness = Support.Harness

    @Test @MainActor
    func anEntranceStartsAtTheCorner() {
        #expect(CrankView.presentation(0, reduceMotion: false) == (0, CrankView.slideDistance))
    }

    @Test @MainActor
    func anEntranceSettlesInPlace() {
        #expect(CrankView.presentation(CrankView.presentDuration, reduceMotion: false) == (1, 0))
    }

    @Test @MainActor
    func theEntranceSlideOvershoots() {
        #expect(CrankView.presentation(0.15, reduceMotion: false).offset < 0)
    }

    @Test @MainActor
    func reduceMotionFadesInWithoutSliding() {
        let fixture = Harness(reduceMotion: true)
        fixture.view.present()
        fixture.advance(0.1)
        #expect(fixture.view.stageOffset == .zero)
        #expect(fixture.view.alphaValue > 0 && fixture.view.alphaValue < 1)
    }

    @Test @MainActor
    func aReduceMotionEntranceFadesToFullyVisible() {
        let fixture = Harness(reduceMotion: true)
        fixture.view.present()
        fixture.advance(0.1)
        fixture.advance(0.1)
        #expect(fixture.view.stageOffset == .zero)
        #expect(fixture.view.alphaValue == 1)
    }

    @Test @MainActor
    func dismissalReachesZeroAlpha() {
        #expect(CrankView.dismissal(CrankView.dismissDuration, reduceMotion: false).alpha == 0)
    }

    @Test @MainActor
    func reduceMotionDismissalDoesNotSlide() {
        #expect(CrankView.dismissal(0.1, reduceMotion: true).offset == 0)
    }

    @Test @MainActor
    func theSettleSpringOvershootsBeforeReturningToRest() {
        #expect(CrankView.settleRemaining(0, reduceMotion: false) == 1)
        #expect((CrankView.settleRemaining(0.15, reduceMotion: false) ?? 0) < 0)
        #expect(CrankView.settleRemaining(CrankView.settleDuration, reduceMotion: false) == nil)
    }

    @Test(arguments: 0..<15) @MainActor
    func reduceMotionSettlesWithoutOvershoot(sample: Int) {
        let t = Double(sample) / 100
        #expect((CrankView.settleRemaining(t, reduceMotion: true) ?? 0) >= 0)
    }

    @Test @MainActor
    func anIdleCrankIsHiddenAndLetsClicksThrough() {
        let h = Harness(value: 10, palette: Support.light)
        let view = h.view
        #expect(view.phase == .idle && view.alphaValue == 0 && view.sceneView.isHidden)
        #expect(view.hitTest(h.superPoint(view.hub)) == nil)
    }

    @Test @MainActor
    func presentingMakesTheCrankVisibleAndStartsItsSlide() {
        let fixture = Harness()
        let view = fixture.view
        view.present()
        #expect(view.phase == .presenting)
        #expect(!view.sceneView.isHidden)
        #expect(view.stageOffset.x < 0 && view.stageOffset.y < 0)
        #expect(view.isAnimating)
    }

    @Test @MainActor
    func presentationSettlesAndStopsTheTimer() {
        let view = Harness.presented().view
        #expect(view.phase == .shown)
        #expect(view.alphaValue == 1)
        #expect(view.stageOffset == .zero)
        #expect(!view.isAnimating)
    }

    struct HitLocation: CustomTestStringConvertible {
        let label: String
        let xOffset: CGFloat
        let yOffset: CGFloat
        let catches: Bool

        var testDescription: String { label }
    }

    @Test(arguments: [
        HitLocation(label: "Hub", xOffset: 0, yOffset: 0, catches: true),
        HitLocation(label: "Inside the lights", xOffset: 115, yOffset: 0, catches: true),
        HitLocation(label: "Beyond the lights", xOffset: 118, yOffset: 0, catches: false),
        HitLocation(label: "Outside corner", xOffset: -142, yOffset: -142, catches: false),
    ]) @MainActor
    func hitTestingFollowsTheCircularLights(_ sample: HitLocation) {
        let view = Harness.presented().view
        let point = CGPoint(x: view.hub.x + sample.xOffset, y: view.hub.y + sample.yOffset)
        #expect((view.hitTest(point) === view) == sample.catches)
    }

    @Test @MainActor
    func theCrankIsAnAccessibleSlider() {
        let view = Harness().view
        #expect(view.isAccessibilityElement() && view.accessibilityRole() == .slider && view.accessibilityLabel() == "Window frame")
        #expect(view.accessibilityValueDescription() == "10 points, Classic")
        #expect((view.accessibilityValue() as? NSNumber)?.intValue == 10)
        #expect((view.accessibilityMinValue() as? NSNumber)?.intValue == 3 && (view.accessibilityMaxValue() as? NSNumber)?.intValue == 13)
    }

    struct VoiceOverStep: CustomTestStringConvertible {
        let label: String
        let up: Bool
        let point: Int
        let description: String

        var testDescription: String { label }
    }

    @Test(arguments: [
        VoiceOverStep(label: "Increment", up: true, point: 11, description: "11 points, Roomy"),
        VoiceOverStep(label: "Decrement", up: false, point: 9, description: "9 points, Comfy"),
    ]) @MainActor
    func voiceOverStepsTheFrame(_ sample: VoiceOverStep) {
        let view = Harness.presented().view
        let accepted = sample.up ? view.accessibilityPerformIncrement() : view.accessibilityPerformDecrement()
        #expect(accepted)
        #expect(view.crank.value == sample.point)
        #expect(view.accessibilityValueDescription() == sample.description)
    }

    @Test @MainActor
    func changingPaletteUpdatesBothTheMetalAndLights() {
        let view = Harness().view
        view.palette = Support.dark
        #expect(view.lights.palette == Support.dark && Support.near(view.model.scene.lightingEnvironment.intensity, 1.6, 0.001))
    }

    @Test @MainActor
    func dismissingMidEntranceStartsFromTheCurrentPresentation() {
        let early = Harness(value: 10, palette: Support.light)
        early.view.present()
        early.advance(0.05)
        let alpha = early.view.alphaValue, offset = early.view.stageOffset
        #expect(alpha > 0 && alpha < 0.9)
        early.view.dismiss(commit: true)
        early.advance(1.0 / 60)
        #expect(early.view.alphaValue <= alpha && early.view.stageOffset.x <= offset.x + 0.001 && early.view.stageOffset.x > offset.x - 2)
    }

    @Test @MainActor
    func dismissalStartsAtTheSuppliedEntranceState() {
        #expect(CrankView.dismissal(0, reduceMotion: false, from: (0.3, 5)) == (0.3, 5))
    }
}
