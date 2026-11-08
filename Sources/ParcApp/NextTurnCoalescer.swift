import Foundation

/// Runs an action once on the main queue's next turn, however often it is
/// scheduled before then: a burst of engine changes costs one pass, and a
/// single change still applies on the next turn.
@MainActor
final class NextTurnCoalescer {
    private var pending = false
    func schedule(_ action: @escaping @MainActor () -> Void) {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.pending = false
                action()
            }
        }
    }
}
