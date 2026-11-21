import AppKit

@MainActor
enum EaselCanvasHaptics {
    static var perform: (NSHapticFeedbackManager.FeedbackPattern) -> Void = { pattern in
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    static func snap() { perform(.alignment) }
    static func thud() { perform(.levelChange) }
    static func refuse() { perform(.generic) }
}

@MainActor
struct EaselSnapTicker<Key: Hashable> {
    private var engaged: Set<Key> = []

    mutating func update(_ current: Set<Key>) {
        defer { engaged = current }
        guard !current.subtracting(engaged).isEmpty else { return }
        EaselCanvasHaptics.snap()
    }

    mutating func reset() { engaged.removeAll() }
}
