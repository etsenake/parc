import AppKit
import Testing
@testable import Parc
@testable import ParcKit

struct NavigationLoadingTestsTiming {
    @MainActor private static func stroke(_ t: Double) -> (CGFloat, CGFloat) {
        let s = PageLoadingIndicator.stroke(at: t)
        return (s.start, s.end)
    }

    @MainActor @Test func theCycleStartsEmpty() {
        #expect(Self.stroke(0) == (0, 0))
    }

    @MainActor @Test func theStrokeGrowsFromTheStart() {
        #expect(NavigationLoadingTestsSupport.near(Self.stroke(0.1875).1, 0.5))
        #expect(Self.stroke(0.1875).0 == 0)
    }

    @MainActor @Test func theStrokeShrinksFromTheStart() {
        #expect(NavigationLoadingTestsSupport.near(Self.stroke(0.5625).0, 0.5))
        #expect(Self.stroke(0.5625).1 == 1)
    }

    @MainActor @Test func theLastThirdIsEmpty() {
        #expect(Self.stroke(0.9) == (0, 0))
        #expect(PageLoadingIndicator.stroke(at: 0.9) == (0, 0))
    }

    @MainActor @Test func theCycleRepeatsEveryOnePointOneTwoFiveSeconds() {
        #expect(NavigationLoadingTestsSupport.near(Self.stroke(1.125 + 0.1875).1, 0.5))
    }

    @MainActor @Test func theSweepComesAfterThreePointTwoSeconds() {
        #expect(PageLoadingIndicator.sweepDelay == 3.2)
    }

    @MainActor @Test func theReloadSpringStartsAtRest() {
        #expect(ReloadGlyph.spring(0) == 0)
    }

    @MainActor @Test func theReloadSpringSettlesWithinItsEnvelope() {
        #expect(abs(ReloadGlyph.spring(ReloadGlyph.settlingTime) - 1) < 0.001)
    }

    @MainActor @Test func theReloadSpringSettlesInUnderHalfASecond() {
        #expect(ReloadGlyph.settlingTime > 0.3)
        #expect(ReloadGlyph.settlingTime < 0.5)
    }

    @MainActor @Test func theReloadSpringIsUnderdampedWithAnOvershoot() {
        #expect((1...40).map { ReloadGlyph.spring(Double($0) / 200) }.max()! > 1.05)
    }

    struct GlyphDelay: CustomTestStringConvertible {
        let label: String
        let entering: Bool
        let seconds: Double

        var testDescription: String { label }
    }

    @Test(arguments: [
        GlyphDelay(label: "Entering loading", entering: true, seconds: 0.2),
        GlyphDelay(label: "Leaving loading", entering: false, seconds: 0.1),
    ]) @MainActor
    func theGlyphDelayDependsOnTheLoadingDirection(_ sample: GlyphDelay) {
        #expect(ReloadGlyph.delay(enteringLoading: sample.entering) == sample.seconds)
    }

    @MainActor @Test func theGlyphClipsToASixPointCornerRadius() {
        #expect(ReloadGlyph.clipCornerRadius == 6)
    }

    @MainActor @Test func theActionSpinTurnsOneRevolution() {
        #expect(ReloadGlyph.actionRotation == 2 * .pi)
    }

    @MainActor @Test func theActionSpinUsesItsOwnSpring() {
        #expect(ReloadGlyph.actionResponse == 0.4)
        #expect(ReloadGlyph.actionDamping == 0.6)
    }

    @MainActor @Test func theClickSpinLastsLongerThanTheStopCrossfade() {
        #expect(ReloadGlyph.actionSettlingTime > ReloadGlyph.settlingTime)
    }
}
