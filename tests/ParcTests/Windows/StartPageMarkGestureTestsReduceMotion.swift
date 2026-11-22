import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct StartPageMarkGestureTestsReduceMotion {
    private typealias Pointer = StartPageMarkGestureTestsSupport.Pointer

    struct MotionPreference: CustomTestStringConvertible {
        let label: String
        let reduced: Bool
        let style: StartPageMarkMotionStyle

        var testDescription: String { label }
    }

    @Test(arguments: [
        MotionPreference(label: "Reduce Motion", reduced: true, style: .shimmer),
        MotionPreference(label: "Default motion", reduced: false, style: .motion),
    ])
    func theMotionPreferenceSelectsTheStyle(_ sample: MotionPreference) {
        #expect(StartPageMarkMotionStyle(reduceMotion: sample.reduced) == sample.style)
    }

    @Test func reduceMotionKeepsTaffyFromStretching() {
        var taffy = Pointer()
        taffy.reduceMotion = true
        _ = taffy.down(.zero, 0)
        #expect(taffy.drag(CGPoint(x: 20, y: 0), 0.1).isEmpty)
        #expect(taffy.session.phase == .interacting(.taffy, .shimmer))
    }

    @Test func changingTheSettingMidGestureKeepsTheShimmer() {
        var taffy = Pointer()
        taffy.reduceMotion = true
        _ = taffy.down(.zero, 0)
        _ = taffy.drag(CGPoint(x: 20, y: 0), 0.1)
        taffy.reduceMotion = false
        #expect(taffy.drag(CGPoint(x: 30, y: 9), 0.2).isEmpty)
    }

    @Test func releasingKeepsTheShimmerChosenAtTheTrigger() {
        var taffy = Pointer()
        taffy.reduceMotion = true
        _ = taffy.down(.zero, 0)
        _ = taffy.drag(CGPoint(x: 20, y: 0), 0.1)
        taffy.reduceMotion = false
        _ = taffy.drag(CGPoint(x: 30, y: 9), 0.2)
        #expect(taffy.up(CGPoint(x: 30, y: 9), 0.3) == [.shimmer, .haptic])
        #expect(taffy.session.phase == .playing(.taffy, .shimmer))
    }

    @Test func reduceMotionReplacesTheSwoopWithTheShimmer() {
        var swoop = Pointer()
        swoop.reduceMotion = true
        _ = swoop.click(.zero, 0)
        _ = swoop.click(.zero, 0.2)
        #expect(swoop.down(.zero, 0.4) == [.shimmer, .haptic])
        #expect(!swoop.session.landing && swoop.session.land(generation: swoop.session.generation).isEmpty)
    }

    @Test func reduceMotionChargesWithTheGlowOnly() {
        var charge = Pointer()
        charge.reduceMotion = true
        _ = charge.down(.zero, 0)
        #expect(charge.hold(0.35) == [.charge(.shimmer)])
    }

    @Test func reduceMotionReplacesTheLoopWithTheShimmer() {
        var charge = Pointer()
        charge.reduceMotion = true
        _ = charge.down(.zero, 0)
        _ = charge.hold(0.35)
        #expect(charge.up(.zero, 1.2) == [.shimmer, .haptic])
        #expect(!charge.session.landing)
    }

    @Test func anUnderchargedReduceMotionReleaseOnlyFadesTheGlow() {
        var weak = Pointer()
        weak.reduceMotion = true
        _ = weak.down(.zero, 0)
        _ = weak.hold(0.35)
        #expect(weak.up(.zero, 0.5) == [.play(.relax(StartPageMarkCharge.level(held: 0.5 - 0.35), .shimmer))])
    }
}
