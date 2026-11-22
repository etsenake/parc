import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeOverlayMetricsTests {
    @Test
    func circleMetricsMatchTheRestingAndArmedDesign() {
        #expect(HistorySwipeOverlaySupport.Metrics.restingDiameter == 72 && HistorySwipeOverlaySupport.Metrics.armedDiameter == 82 && HistorySwipeOverlaySupport.Metrics.edgeInset == 14)
    }

    @Test
    func chevronMetricsMatchTheRestingAndArmedDesign() {
        #expect(HistorySwipeOverlaySupport.Metrics.restingChevron == 28 && HistorySwipeOverlaySupport.Metrics.armedChevron == 34 && HistorySwipeOverlaySupport.Metrics.chevronPointSize == 28 && HistorySwipeOverlaySupport.Metrics.restingChevronOpacity == 0.5)
    }

    @Test
    func cardMetricsFitHistoryRows() {
        #expect(HistorySwipeOverlaySupport.Metrics.cardWidth == 200 && HistorySwipeOverlaySupport.Metrics.rowHeight == 38 && HistorySwipeOverlaySupport.Metrics.cardInset == 8 && HistorySwipeOverlaySupport.Metrics.cardRadius == 18)
    }

    @Test
    func rowMetricsFitTitlesAndFavicons() {
        #expect(HistorySwipeOverlaySupport.Metrics.highlightRadius == 10 && HistorySwipeOverlaySupport.Metrics.faviconSize == 16 && HistorySwipeOverlaySupport.Metrics.faviconRadius == 4 && HistorySwipeOverlaySupport.Metrics.titleSize == 13 && HistorySwipeOverlaySupport.Metrics.titleGap == 8)
    }

    @Test
    func ringAndShadowMetricsMatchTheIndicator() {
        #expect(HistorySwipeOverlaySupport.Metrics.ringWidth == 1 && HistorySwipeOverlaySupport.Metrics.shadowRadius == 8 && HistorySwipeOverlaySupport.Metrics.shadowDrop == 2)
    }

    @Test
    func overlaySpringsUseTheGestureTimings() {
        #expect(HistorySwipeOverlaySupport.Timing.arm == .init(damping: 0.70, response: 0.18) && HistorySwipeOverlaySupport.Timing.morph == .init(damping: 0.77, response: 0.22)
              && HistorySwipeOverlaySupport.Timing.selection == .init(damping: 0.9, response: 0.27))
    }

    @Test
    func theListSwapFadesScalesAndBlurs() {
        #expect(HistorySwipeOverlaySupport.Timing.fade == 0.18 && HistorySwipeOverlaySupport.Timing.swap == 0.22 && HistorySwipeOverlaySupport.Timing.swapScale == 0.9 && HistorySwipeOverlaySupport.Timing.blur == 10)
    }

    @Test
    func endingScalesTheIndicatorDown() {
        #expect(HistorySwipeOverlaySupport.Timing.collapse == 0.2 && HistorySwipeOverlaySupport.Timing.collapseScale == 0.01)
    }

    @Test
    func reduceMotionMetricsUseShortCrossfades() {
        #expect(HistorySwipeOverlaySupport.Metrics.reducedAppearance == 0.2 && HistorySwipeOverlaySupport.Timing.reducedFade == 0.12 && HistorySwipeOverlaySupport.Timing.reducedSwap == 0.15 && HistorySwipeOverlaySupport.Timing.reducedCollapse == 0.15)
    }

    @Test
    func theLeanUsesARubberBand() {
        #expect(HistorySwipeOverlaySupport.Metrics.rowLean == 0.1)
    }

    @Test
    func easingCurvesHaveFixedEndpoints() {
        let out = HistorySwipeCurve.easeOut, ease = HistorySwipeCurve.easeIn
        #expect(out(0) == 0 && out(1) == 1 && ease(0) == 0 && ease(1) == 1)
    }

    @Test
    func easingCurvesBiasTheMidpoint() {
        let out = HistorySwipeCurve.easeOut, ease = HistorySwipeCurve.easeIn
        #expect(HistorySwipeOverlaySupport.close(out(0.5), 0.7713235628639843, 1e-6) && HistorySwipeOverlaySupport.close(ease(0.5), 0.31535681250589304, 1e-6))
    }

    @Test(arguments: 0..<100)
    func easeOutNeverRunsBackward(sample: Int) {
        let current = Double(sample) / 100
        let next = Double(sample + 1) / 100
        #expect(HistorySwipeCurve.easeOut(current) <= HistorySwipeCurve.easeOut(next))
    }

    @Test
    func linearEasingPreservesProgress() {
        #expect(HistorySwipeCurve.linear(0.3) == 0.3)
    }

    @Test
    func springPositionAndVelocityAreIndependentOfFrameRate() {
        var arm = HistorySwipeSpring(72, HistorySwipeOverlaySupport.Timing.arm, tolerance: 0.01)
        var stepped = arm
        arm.advance(toward: 82, by: 0.1)
        for _ in 0..<100 { stepped.advance(toward: 82, by: 0.001) }
        #expect(HistorySwipeOverlaySupport.close(arm.value, stepped.value, 1e-9) && HistorySwipeOverlaySupport.close(arm.velocity, stepped.velocity, 1e-7))
    }

    @Test
    func armingSpringPeaksAtTheDampedHalfPeriod() {
        let zeta = 0.70, omega = 2 * Double.pi / 0.18, damped = omega * (1 - zeta * zeta).squareRoot()
        var peak = HistorySwipeSpring(72, HistorySwipeOverlaySupport.Timing.arm, tolerance: 0.0001)
        peak.advance(toward: 82, by: Double.pi / damped)
        #expect(HistorySwipeOverlaySupport.close(peak.value, 82 + 10 * exp(-zeta * Double.pi / (1 - zeta * zeta).squareRoot()), 1e-9)
              && abs(peak.velocity) < 1e-9)
    }

    @Test
    func armingSpringSnapsToRest() {
        var settle = HistorySwipeSpring(72, HistorySwipeOverlaySupport.Timing.arm, tolerance: 0.01)
        settle.advance(toward: 82, by: 0.6)
        #expect(settle.value == 82 && settle.velocity == 0)
    }

    @Test
    func criticalAndOverdampedSpringsApproachWithoutOvershoot() {
        var critical = HistorySwipeSpring(0, .init(damping: 1, response: 0.2), tolerance: 1e-6)
        var heavy = HistorySwipeSpring(0, .init(damping: 1.5, response: 0.2), tolerance: 1e-6)
        critical.advance(toward: 1, by: 0.1)
        heavy.advance(toward: 1, by: 0.1)
        #expect(critical.value > 0 && critical.value < 1 && heavy.value > 0 && heavy.value < critical.value)
    }
}
