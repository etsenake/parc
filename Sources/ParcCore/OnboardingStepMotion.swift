import Foundation

package enum OnboardingTransitionDirection: Equatable {
    case forward, back
}

package enum OnboardingStepMotion {
    package struct Spring: Equatable {
        package let response: Double
        package let dampingFraction: Double
        package var stiffness: Double { pow(2 * .pi / response, 2) }
        package var damping: Double { 4 * .pi * dampingFraction / response }

        package init(response: Double, dampingFraction: Double) {
            self.response = response
            self.dampingFraction = dampingFraction
        }
    }

    package static let offset: Double = 400
    package static let titleSpring = Spring(response: 0.4, dampingFraction: 0.8)
    package static let messageSpring = Spring(response: 0.5, dampingFraction: 0.8)
    package static let contentFadeDuration: Double = 0.5
    package static let contentFadeCurve: (Float, Float, Float, Float) = (0.15, 0, 0.25, 1)
    package static let enabledFadeDuration: Double = 0.12

    package static func offsets(_ direction: OnboardingTransitionDirection) -> (insertion: Double, removal: Double) {
        direction == .forward ? (offset, -offset) : (-offset, offset)
    }

    package static func slidesText(reduceMotion: Bool) -> Bool { !reduceMotion }
    package static func fadesContent(reduceMotion: Bool) -> Bool { true }
    package static func fadesEnabledState(reduceMotion: Bool) -> Bool { true }
}
