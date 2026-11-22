import AppKit
import ParcCore

package enum ThemeHapticFeedback {
    package static func shouldPerformNoise(from previous: Double, to current: Double,
                                   gesture: SpaceThemeNoiseGesture) -> Bool {
        guard gesture == .rotation || gesture == .drag else { return false }
        return crossesDetent(from: previous, to: current, step: 0.1)
    }

    package static func shouldPerformIntensity(from previous: Double, to current: Double) -> Bool {
        crossesDetent(from: previous, to: current, step: 0.2)
    }

    private static func crossesDetent(from previous: Double, to current: Double, step: Double) -> Bool {
        guard previous.isFinite, current.isFinite, previous != current else { return false }
        let interval = min(previous, current)...max(previous, current)
        return stride(from: 0.0, through: 1.0, by: step).contains { interval.contains($0) }
    }

    @MainActor package static func perform() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
