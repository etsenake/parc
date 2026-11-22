import Foundation

@MainActor
final class NextTurnCoalescer {
    typealias Schedule = (@escaping @MainActor () -> Void) -> Void

    private let enqueue: Schedule
    private var pending = false

    init(enqueue: @escaping Schedule = { work in
        DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
    }) {
        self.enqueue = enqueue
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        guard !pending else { return }
        pending = true
        enqueue {
            self.pending = false
            action()
        }
    }
}
