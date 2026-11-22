import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct PeekSwipeDismissalTestsReduceMotion {
    private typealias Support = PeekSwipeDismissalTestsSupport

    private static func reduced() -> PeekDismissalMotion {
        var m = PeekDismissalMotion(geometry: Support.geometry)
        m.begin(reducesMotion: true)
        m.follow(0.5)
        return m
    }

    @Test func withReduceMotionTheFingersFadeTheCardInPlaceInsteadOfSlidingIt() {
        #expect(Self.reduced().frame(at: 0) == PeekDismissalFrame(offset: 0, card: 0.65, wash: 0.5))
    }

    @Test func withReduceMotionLettingGoEarlyFadesBackInPointOneFiveSeconds() {
        var m = Self.reduced()
        m.springBack(velocity: 2, at: 0)
        #expect(m.frame(at: 0.075).offset == 0)
        #expect(m.frame(at: 0.075).card > 0.65)
        #expect(m.frame(at: 0.15) == .rest)
    }

    @Test func reduceMotionFadesOutInPointOneFiveSeconds() {
        var m = Self.reduced()
        m.follow(0.62)
        #expect(m.exit(.slide, velocity: 3, reducesMotion: true, at: 1) == 0.15)
    }

    @Test func nothingSlidesUnderReduceMotion() {
        var m = Self.reduced()
        m.follow(0.62)
        _ = m.exit(.slide, velocity: 3, reducesMotion: true, at: 1)
        var offsets = Set<CGFloat>()
        for step in 0...10 { offsets.insert(m.frame(at: 1 + Double(step) * 0.015).offset) }
        #expect(offsets == [0])
        #expect(m.frame(at: 1.1501).card == 0)
    }

    @Test func aRefusedCloseUnderReduceMotionFadesBackInPlace() {
        var m = Self.reduced()
        m.follow(0.62)
        _ = m.exit(.slide, velocity: 3, reducesMotion: true, at: 1)
        m.reappear(reducesMotion: true, at: 2)
        #expect(m.frame(at: 2.07).offset == 0)
        #expect(m.frame(at: 2.1501) == .rest)
    }

    @Test func settlingOtherMotionLeavesALiveDragUnderTheFingers() {
        var settled = Support.dragging()
        settled.follow(0.5)
        settled.complete(at: 0)
        #expect(settled.frame(at: 0).offset == 0.5 * 463)
    }

    @Test func settlingASpringPutsTheCardHomeAtOnce() {
        var settled = Support.dragging()
        settled.follow(0.5)
        settled.springBack(velocity: 0, at: 0)
        settled.complete(at: 0.01)
        #expect(settled.frame(at: 0.01) == .rest)
    }

    @Test func settlePutsTheCardBackAtRest() {
        var settled = Support.dragging()
        settled.follow(0.3)
        settled.settle()
        #expect(settled.frame(at: 0) == .rest)
        #expect(!settled.isFollowing)
    }
}
