import Foundation

enum OnboardingTransitionDirection: Equatable {
    case forward, back
}

enum OnboardingStepMotion {
    struct Spring: Equatable {
        let response: Double
        let dampingFraction: Double
        var stiffness: Double { pow(2 * .pi / response, 2) }
        var damping: Double { 4 * .pi * dampingFraction / response }
    }

    static let offset: Double = 400
    static let titleSpring = Spring(response: 0.4, dampingFraction: 0.8)
    static let messageSpring = Spring(response: 0.5, dampingFraction: 0.8)
    static let contentFadeDuration: Double = 0.5
    static let contentFadeCurve: (Float, Float, Float, Float) = (0.15, 0, 0.25, 1)
    static let enabledFadeDuration: Double = 0.12

    static func offsets(_ direction: OnboardingTransitionDirection) -> (insertion: Double, removal: Double) {
        direction == .forward ? (offset, -offset) : (-offset, offset)
    }

    static func slidesText(reduceMotion: Bool) -> Bool { !reduceMotion }
    static func fadesContent(reduceMotion: Bool) -> Bool { true }
    static func fadesEnabledState(reduceMotion: Bool) -> Bool { true }
}
