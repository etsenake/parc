import Foundation

///
enum OnboardingTransitionDirection: Equatable {
    case forward, back
}

///
/// are keyed on the step and slide fully opaque with
/// `.asymmetric(insertion: .offset(x: ±400), removal: .offset(x: ∓400))`:
///
/// The step content crossfades with `.opacity.animation(.default)`
///
/// card's own checks compile it alone.
enum OnboardingStepMotion {
    /// SwiftUI `.spring(response:dampingFraction:)` as Core Animation's
    /// unit-mass spring.
    struct Spring: Equatable {
        let response: Double
        let dampingFraction: Double
        var stiffness: Double { pow(2 * .pi / response, 2) }
        var damping: Double { 4 * .pi * dampingFraction / response }
    }

    static let offset: Double = 400
    static let titleSpring = Spring(response: 0.4, dampingFraction: 0.8)
    static let messageSpring = Spring(response: 0.5, dampingFraction: 0.8)
    /// `.default` on the macOS 15.5 SDK: a 0.5 s spring with no bounce.
    static let contentFadeDuration: Double = 0.5
    /// Cubic stand-in for that spring, within 2.4% opacity of it.
    static let contentFadeCurve: (Float, Float, Float, Float) = (0.15, 0, 0.25, 1)
    ///
    static let enabledFadeDuration: Double = 0.12

    /// Where incoming text starts and outgoing text ends.
    static func offsets(_ direction: OnboardingTransitionDirection) -> (insertion: Double, removal: Double) {
        direction == .forward ? (offset, -offset) : (-offset, offset)
    }

    ///
    /// people who asked for less motion and keeps the fades.
    static func slidesText(reduceMotion: Bool) -> Bool { !reduceMotion }
    static func fadesContent(reduceMotion: Bool) -> Bool { true }
    static func fadesEnabledState(reduceMotion: Bool) -> Bool { true }
}
