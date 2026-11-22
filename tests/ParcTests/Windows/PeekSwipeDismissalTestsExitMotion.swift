import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct PeekSwipeDismissalTestsExitMotion {
    private typealias Support = PeekSwipeDismissalTestsSupport

    private static func slidOut() -> (PeekDismissalMotion, Double) {
        var exit = Support.dragging()
        exit.follow(0.62)
        let duration = exit.exit(.slide, velocity: 1.2, reducesMotion: false, at: 5)
        return (exit, duration)
    }

    @Test func theSlideMatchesTheApprovedMockupHalfwayThrough() {
        let (exit, duration) = Self.slidOut()
        let start = 0.62 * 463.0, travel = 1.2 * 463 * 0.22 / 2
        let middle = exit.frame(at: 5.11)
        #expect(duration == 0.22)
        #expect(Support.near(Double(middle.offset), start + travel * 0.75, 1e-3))
        #expect(Support.near(middle.card, 0.75))
        #expect(Support.near(middle.wash, 0.38 * 0.25, 1e-9))
    }

    @Test func theSlideEndsFullyFadedWhereItStopped() {
        let (exit, _) = Self.slidOut()
        let start = 0.62 * 463.0, travel = 1.2 * 463 * 0.22 / 2
        let end = exit.frame(at: 5.2201)
        #expect(end.card == 0)
        #expect(end.wash == 0)
        #expect(Support.near(Double(end.offset), start + travel, 1e-3))
        #expect(!exit.isAnimating(at: 5.2201))
    }

    @Test func settlingAFinishedSlideNeverBringsTheCardBackForAFrame() {
        var (exit, _) = Self.slidOut()
        exit.complete(at: 5.3)
        #expect(exit.frame(at: 6).card == 0)
    }

    @Test func aThreeFingerSwipeOrMagicMouseCloseStillSlidesAShortWayWhileItFades() {
        var still = PeekDismissalMotion(geometry: Support.geometry)
        _ = still.exit(.slide, velocity: 0, reducesMotion: false, at: 0)
        #expect(Support.near(Double(still.frame(at: 0.22).offset), 0.12 * 508, 1e-6))
    }

    @Test func aVeryFastFlickTravelsAtMostHalfThePane() {
        var fast = PeekDismissalMotion(geometry: Support.geometry)
        _ = fast.exit(.slide, velocity: 20, reducesMotion: false, at: 0)
        #expect(Support.near(Double(fast.frame(at: 0.22).offset), 0.5 * 508, 1e-6))
    }

    @Test func escapeAClickOutsideOrCloseFadeInPointTwoSeconds() {
        var fade = PeekDismissalMotion(geometry: Support.geometry)
        #expect(fade.exit(.fade, velocity: 3, reducesMotion: false, at: 0) == 0.2)
    }

    @Test func theQuickFadeDimsCardAndWashTogetherWithoutMoving() {
        var fade = PeekDismissalMotion(geometry: Support.geometry)
        _ = fade.exit(.fade, velocity: 3, reducesMotion: false, at: 0)
        #expect(fade.frame(at: 0.1).offset == 0)
        #expect(Support.near(fade.frame(at: 0.1).card, 0.25))
        #expect(Support.near(fade.frame(at: 0.1).wash, 0.25))
    }

    @Test func theQuickFadeEndsInvisible() {
        var fade = PeekDismissalMotion(geometry: Support.geometry)
        _ = fade.exit(.fade, velocity: 3, reducesMotion: false, at: 0)
        #expect(fade.frame(at: 0.2).card == 0)
        #expect(!fade.isAnimating(at: 0.2))
    }

    @Test func aRefusedFadeOutFadesBackInPlace() {
        var fade = PeekDismissalMotion(geometry: Support.geometry)
        _ = fade.exit(.fade, velocity: 3, reducesMotion: false, at: 0)
        fade.reappear(reducesMotion: false, at: 1)
        #expect(fade.frame(at: 1.1).offset == 0)
        #expect(fade.frame(at: 1.1).card > 0)
        #expect(fade.frame(at: 1.2) == .rest)
    }

    private static func vanished() -> (PeekDismissalMotion, PeekDismissalFrame) {
        var back = Support.dragging()
        back.follow(0.64)
        _ = back.exit(.slide, velocity: 1.5, reducesMotion: false, at: 0)
        back.vanish(at: 0.22)
        return (back, back.frame(at: 0.22))
    }

    @Test func aVanishedCardStaysOffAndInvisible() {
        let (_, gone) = Self.vanished()
        #expect(gone.card == 0)
        #expect(gone.offset > 0.64 * 463)
    }

    @Test func aCardThePageRefusedToLoseSpringsBackInFadingUpAsItComes() {
        var (back, gone) = Self.vanished()
        back.reappear(reducesMotion: false, at: 1)
        let early = back.frame(at: 1.06), later = back.frame(at: 1.14)
        #expect(early.offset < gone.offset)
        #expect(early.card > 0 && early.card < 1)
        #expect(later.card > early.card)
        #expect(Support.near(early.wash, early.card))
    }

    @Test func theSpringBackFromOffScreenSettlesAtRest() {
        var (back, _) = Self.vanished()
        back.reappear(reducesMotion: false, at: 1)
        #expect(back.frame(at: 2) == .rest)
        #expect(!back.isAnimating(at: 2))
    }
}
