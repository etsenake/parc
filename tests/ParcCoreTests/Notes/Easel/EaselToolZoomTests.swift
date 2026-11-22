import Foundation
import Testing
@testable import ParcCore

struct EaselToolZoomTests {
    func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    @Test
    func zoomingKeepsThePointUnderThePointerStill() {
        let origin = EaselPoint(x: 100, y: 50)
        let anchor = EaselPoint(x: 300, y: 250)
        let zoomedIn = EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 1, after: 2)
        #expect(near(zoomedIn.x, 200) && near(zoomedIn.y, 150), "Zooming in keeps the point under the pointer still")
        let zoomedOut = EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 2, after: 1)
        #expect(near(zoomedOut.x, -100) && near(zoomedOut.y, -150), "Zooming out keeps the point under the pointer still")
    }

    @Test
    func unchangedOrInvalidZoomLeavesTheOriginAlone() {
        let origin = EaselPoint(x: 100, y: 50)
        let anchor = EaselPoint(x: 300, y: 250)
        #expect(EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 1, after: 1) == origin, "No zoom change leaves the view alone")
        #expect(EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 1, after: 0) == origin, "Nonsense zoom leaves the view alone")
    }

    @Test
    func anInvalidZoomAnchorLeavesTheOriginAlone() {
        let origin = EaselPoint(x: 100, y: 50)
        #expect(EaselZoom.anchoredOrigin(anchor: EaselPoint(x: .nan, y: 0), visibleOrigin: origin, before: 1, after: 2) == origin, "A nonsense pointer leaves the view alone")
    }

    @Test
    func scrollingPastTheZoomLimitDoesNotDrift() {
        let origin = EaselPoint(x: 100, y: 50)
        let anchor = EaselPoint(x: 300, y: 250)
        let clampedAfter = EaselZoom.clamped(10, minimum: 0.3333, maximum: 4)
        let atLimit = EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 4, after: clampedAfter)
        #expect(atLimit == origin, "Wheeling past the zoom limit does not drift the view")
    }

    private struct ZoomStep: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let from: Double
        let zoomingIn: Bool
        let minimum: Double
        let maximum: Double
        let expected: Double

        init(_ label: String, _ from: Double, _ zoomingIn: Bool, _ minimum: Double, _ maximum: Double, _ expected: Double) {
            testDescription = label
            self.from = from
            self.zoomingIn = zoomingIn
            self.minimum = minimum
            self.maximum = maximum
            self.expected = expected
        }
    }

    @Test(arguments: [
        ZoomStep("Zoom in from 100% goes to 150%", 1, true, 0.3333, 4, 1.5),
        ZoomStep("Zoom out from 100% goes to 75%", 1, false, 0.3333, 4, 0.75),
        ZoomStep("Off-step zoom in lands on the next level", 0.8, true, 0.3333, 4, 1),
        ZoomStep("Off-step zoom out lands on the previous level", 0.8, false, 0.3333, 4, 0.75),
        ZoomStep("Zoom in stops at the maximum", 4, true, 0.3333, 4, 4),
        ZoomStep("Zoom out stops at the minimum", 0.3333, false, 0.3333, 4, 0.3333),
        ZoomStep("Below the levels zoom out halves", 0.12, false, 0.01, 4, 0.06),
        ZoomStep("From a tiny fit, zoom in finds the first level", 0.12, true, 0.01, 4, 0.25),
        ZoomStep("Nonsense zoom resets to 100%", .nan, true, 0.3333, 4, 1),
        ZoomStep("Nonsense zoom resets inside the allowed range", .nan, true, 2, 4, 2),
    ])
    private func steppingZoomSelectsTheNextSupportedLevel(_ step: ZoomStep) {
        #expect(EaselZoom.stepped(from: step.from, zoomingIn: step.zoomingIn, minimum: step.minimum, maximum: step.maximum) == step.expected)
    }

    @Test
    func zoomStepsReachTheMaximumInAtMostEightSteps() {
        var value = 1.0, steps = 0
        while value < 4, steps < 20 { value = EaselZoom.stepped(from: value, zoomingIn: true, minimum: 0.3333, maximum: 4); steps += 1 }
        #expect(value == 4 && steps <= 8, "Zooming in walks to the maximum in a handful of steps")
    }

    @Test
    func zoomMenuOffersThreePresets() {
        #expect(EaselZoom.presets == [0.5, 1, 2], "The zoom menu offers 50%, 100% and 200%")
    }

    @Test
    func zoomPercentagesRoundAndSaturate() {
        #expect(EaselZoom.percent(0.3333) == 33 && EaselZoom.percent(1) == 100 && EaselZoom.percent(1.499) == 150, "Percentages round")
        #expect(EaselZoom.percent(.greatestFiniteMagnitude) == 100_000, "Huge magnifications never overflow the percentage")
    }

    @Test
    func zoomClampsToTheRangeAndRefusesInvalidValues() {
        #expect(EaselZoom.clamped(9, minimum: 0.3333, maximum: 4) == 4 && EaselZoom.clamped(-1, minimum: 0.3333, maximum: 4) == 1, "Clamping keeps zoom in range and refuses nonsense")
    }

    @Test
    func animatedZoomInterpolatesEvenlyInScale() {
        let mid = EaselZoom.interpolated(from: 1, to: 4, progress: 0.5)
        #expect(near(mid, 2), "Animated zoom moves evenly in scale")
    }

    @Test
    func animatedZoomEasesOut() {
        #expect(EaselZoom.eased(0) == 0 && EaselZoom.eased(1) == 1 && EaselZoom.eased(0.5) > 0.5, "Zoom eases out")
    }

    @Test
    func wheelZoomFollowsTheScrollDirection() {
        #expect(EaselZoom.wheelFactor(deviceDelta: 0, precise: true) == 1, "No scroll, no zoom")
        #expect(EaselZoom.wheelFactor(deviceDelta: 10, precise: true) > 1 && EaselZoom.wheelFactor(deviceDelta: -10, precise: true) < 1, "Scrolling up zooms in and down zooms out")
    }

    @Test
    func notchedWheelsZoomFurtherThanPreciseScrolling() {
        #expect(EaselZoom.wheelFactor(deviceDelta: 1, precise: false) > EaselZoom.wheelFactor(deviceDelta: 1, precise: true), "A mouse wheel notch zooms further than a trackpad pixel")
    }

    @Test
    func wheelAccelerationIsCapped() {
        #expect(EaselZoom.wheelFactor(deviceDelta: 10_000, precise: false) == EaselZoom.wheelFactor(deviceDelta: 3, precise: false), "A runaway wheel burst is limited")
        #expect(EaselZoom.wheelFactor(deviceDelta: 10, precise: false) < 1.8, "An accelerated flick zooms a step, not across the range")
    }

    @Test
    func eachWheelEventCanAtMostHalveOrDoubleScale() {
        for delta in [-10_000.0, -10, -1, 1, 10, 10_000] {
            for precise in [true, false] {
                let factor = EaselZoom.wheelFactor(deviceDelta: delta, precise: precise)
                #expect(factor >= 0.5 && factor <= 2, "One wheel event never more than halves or doubles the zoom")
            }
        }
    }

    @Test
    func fitUsesTheContentSizeWithinTheZoomLimits() {
        let content = EaselRect(x: 0, y: 0, width: 2000, height: 1000)
        let fit = EaselZoom.fitting(content, viewport: (1096, 896), minimum: 0.3333, maximum: 4)
        #expect(fit.map { near($0, 0.5) } == true, "A board twice the viewport's width fits at 50%")
        let small = EaselZoom.fitting(EaselRect(x: 10, y: 10, width: 20, height: 20), viewport: (1000, 800), minimum: 0.3333, maximum: 4)
        #expect(small == 4, "A tiny selection zooms in only to the maximum")
        let huge = EaselZoom.fitting(EaselRect(x: 0, y: 0, width: 100_000, height: 100), viewport: (1000, 800), minimum: 0.3333, maximum: 4)
        #expect(huge == 0.3333, "A giant board stops at the minimum")
    }

    @Test
    func fittingRequiresNonemptyContentAndViewport() {
        let content = EaselRect(x: 0, y: 0, width: 2000, height: 1000)
        #expect(EaselZoom.fitting(EaselRect(x: 0, y: 0, width: 0, height: 10), viewport: (1000, 800), minimum: 0.3333, maximum: 4) == nil, "Empty content has nothing to fit")
        #expect(EaselZoom.fitting(content, viewport: (0, 800), minimum: 0.3333, maximum: 4) == nil, "A hidden viewport has nothing to fit")
    }

    @Test
    func fitBoundsWrapEveryObject() {
        let bounds = EaselZoom.bounds(of: [EaselRect(x: 10, y: 20, width: 30, height: 40), EaselRect(x: -5, y: 50, width: 10, height: 100)])
        #expect(bounds == EaselRect(x: -5, y: 20, width: 45, height: 130), "Fit bounds wrap every object")
        #expect(EaselZoom.bounds(of: []) == nil, "No objects, no bounds")
    }

    @Test
    func aMouseWheelNotchUsesTheZoomChord() {
        var wheel = EaselWheelGesture()
        #expect(wheel.route(.discrete, zoomChord: true) == .zoom && wheel.route(.discrete, zoomChord: false) == .pan, "A mouse wheel notch zooms with ⌘ and pans without it")
    }

    @Test
    func aTrackpadPanKeepsPanningThroughMomentum() {
        var wheel = EaselWheelGesture()
        #expect(wheel.route(.active, zoomChord: false) == .pan, "A plain trackpad scroll pans")
        #expect(wheel.route(.ending, zoomChord: true) == .pan, "Pressing ⌘ as the fingers lift doesn't turn the pan into a zoom")
        #expect(wheel.route(.momentum, zoomChord: true) == .pan, "A pan's glide keeps panning when ⌘ goes down")
    }

    @Test
    func aTrackpadZoomDropsMomentumAfterTheFingersLift() {
        var wheel = EaselWheelGesture()
        #expect(wheel.route(.active, zoomChord: true) == .zoom && wheel.route(.active, zoomChord: true) == .zoom, "⌘ with the trackpad zooms")
        #expect(wheel.route(.ending, zoomChord: false) == .zoom, "Letting go of ⌘ as the fingers lift still ends the zoom")
        #expect(wheel.route(.momentum, zoomChord: true) == .drop && wheel.route(.momentum, zoomChord: false) == .drop, "The zoom stops when the fingers lift, like a pinch")
    }

    @Test
    func releasingTheZoomChordMidGestureSwitchesToPanning() {
        var wheel = EaselWheelGesture()
        #expect(wheel.route(.active, zoomChord: true) == .zoom && wheel.route(.active, zoomChord: false) == .pan
               && wheel.route(.ending, zoomChord: false) == .pan && wheel.route(.momentum, zoomChord: false) == .pan, "Letting go of ⌘ mid-gesture pans, and the glide follows the pan")
    }

    @Test
    func pressingTheZoomChordMidGestureSwitchesToZooming() {
        var wheel = EaselWheelGesture()
        #expect(wheel.route(.active, zoomChord: false) == .pan && wheel.route(.active, zoomChord: true) == .zoom
               && wheel.route(.momentum, zoomChord: true) == .drop, "Pressing ⌘ mid-gesture zooms and the glide is dropped")
    }

    @Test
    func aNewGestureCanPanAfterAZoom() {
        var wheel = EaselWheelGesture()
        #expect(wheel.route(.active, zoomChord: false) == .pan && wheel.route(.active, zoomChord: true) == .zoom
               && wheel.route(.momentum, zoomChord: true) == .drop, "Pressing ⌘ mid-gesture zooms and the glide is dropped")
        #expect(wheel.route(.active, zoomChord: false) == .pan && wheel.route(.momentum, zoomChord: true) == .pan, "The next gesture starts fresh after a zoom")
    }

    @Test func theClipViewsRoundingWhileZoomedOutDoesntCount() {
        #expect(EaselZoom.extentMatches((3110.895928713965, 1874.7443725386834), (3110.895928713965, 1874.7443725386831)), "The clip view's rounding while zoomed out doesn't count as a new canvas size")
        #expect(EaselZoom.extentMatches((1200, 1400), (1200.004, 1399.996)), "Differences far below a pixel at 400% leave the canvas alone")
        #expect(!EaselZoom.extentMatches((1200.25, 1400), (1200, 1400)), "A quarter-point drag at the edge still grows the canvas")
        #expect(!EaselZoom.extentMatches((1200, 1399), (1200, 1400)), "A shorter viewport shrinks the canvas")
        #expect(!EaselZoom.extentMatches((.nan, 1400), (1200, 1400)), "Nonsense sizes never count as settled")
    }
}
