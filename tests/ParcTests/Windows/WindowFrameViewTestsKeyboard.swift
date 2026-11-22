import AppKit
import Metal
import SceneKit
import Testing
@testable import ParcCore
@testable import ParcSettings

struct WindowFrameViewTestsKeyboard {
    private typealias Harness = WindowFrameViewTestsSupport.Harness

    struct ArrowKey: CustomTestStringConvertible {
        let label: String
        let key: UInt16
        let point: Int

        var testDescription: String { label }
    }

    @Test(arguments: [
        ArrowKey(label: "Up", key: 126, point: 11),
        ArrowKey(label: "Right", key: 124, point: 11),
        ArrowKey(label: "Left", key: 123, point: 9),
        ArrowKey(label: "Down", key: 125, point: 9),
    ]) @MainActor
    func arrowKeysStepTheFrame(_ sample: ArrowKey) {
        let h = Harness.presented()
        h.view.keyDown(with: h.key(sample.key))
        #expect(h.view.crank.value == sample.point)
        #expect(h.events == [.notch(sample.point)])
    }

    @Test @MainActor
    func anArrowNotchClicksAndTicks() {
        let h = Harness.steppedUp()
        #expect(h.output.played == [.notch(11)] && h.haptics == [.alignment])
    }

    @Test @MainActor
    func aNotchUpdatesTheLightsAndReadout() {
        let view = Harness.steppedUp().view
        #expect(view.lights.litCount == 9 && view.lights.readout == 11)
    }

    @Test @MainActor
    func aNewlyLitPillPopsWithSparkles() {
        let view = Harness.steppedUp().view
        #expect(!view.lights.sparkles.isEmpty && view.lights.pop[8] < WindowFrameCrankLightsView.popDuration)
    }

    @Test @MainActor
    func anArrowStepSpringsToTheNewFrameWithASmallOvershoot() throws {
        let h = Harness.steppedUp()
        h.sample(0.6)
        let peak = try #require(h.previews.max())
        #expect(h.previews.last == 11)
        #expect(peak > 11 && peak < 11.2)
    }

    @Test @MainActor
    func settledSparklesStopTheAnimation() {
        let h = Harness.steppedUp()
        let view = h.view
        h.advance(1)
        #expect(view.lights.sparkles.isEmpty && !view.lights.isAnimating && !view.isAnimating)
    }

    @Test @MainActor
    func theRenderedArmRestsAtTheCrankAngle() {
        let h = Harness.steppedUp()
        let view = h.view
        h.advance(1)
        #expect(WindowFrameViewTestsSupport.near(CGFloat(view.model.armDegrees), CGFloat(view.crank.armDegrees), 0.0001))
    }
}
