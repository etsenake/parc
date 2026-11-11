import Foundation

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
