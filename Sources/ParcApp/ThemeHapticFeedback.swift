import AppKit

///
/// change touches a detent. It neither accumulates crossings nor delays them.
enum ThemeHapticFeedback {
    static func shouldPerformNoise(from previous: Double, to current: Double,
                                   gesture: SpaceThemeNoiseGesture) -> Bool {
        guard gesture == .rotation || gesture == .drag else { return false }
        return crossesDetent(from: previous, to: current, step: 0.1)
    }

    static func shouldPerformIntensity(from previous: Double, to current: Double) -> Bool {
        crossesDetent(from: previous, to: current, step: 0.2)
    }

    private static func crossesDetent(from previous: Double, to current: Double, step: Double) -> Bool {
        guard previous.isFinite, current.isFinite, previous != current else { return false }
        let interval = min(previous, current)...max(previous, current)
        //
        // arriving at and leaving a detent are separate changed actions.
        return stride(from: 0.0, through: 1.0, by: step).contains { interval.contains($0) }
    }

    @MainActor static func perform() {
        // Request a fresh performer: AppKit owns current device availability,
        // touch contact, accessibility settings and user preference suppression.
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
