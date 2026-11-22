import Foundation

@MainActor
final class PeekDismissalConfirmation {
    enum Reason: Equatable {
        case escape, mediaInput

        var duration: TimeInterval { self == .escape ? 1 : 10 }
    }

    enum Dismissal: Equatable {
        case escape(prefersConfirmation: Bool)
        case closeButton, background, closeShortcut, swipe, exit
    }

    private(set) var reason: Reason?
    private(set) var attempts = 0
    private var pendingReset: DispatchWorkItem?
    private var generation: UUID?
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void

    init(schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, item in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }) {
        self.schedule = schedule
    }

    static func requiredReason(for dismissal: Dismissal, awaiting reason: Reason?,
                               mediaInput: Bool) -> Reason? {
        if let reason {
            switch dismissal {
            case .background, .swipe: return reason == .mediaInput ? .mediaInput : nil
            case .escape, .closeButton, .closeShortcut, .exit: return nil
            }
        }
        if case .escape(let prefersConfirmation) = dismissal {
            return prefersConfirmation ? .escape : nil
        }
        return mediaInput ? .mediaInput : nil
    }

    @discardableResult
    func request(_ dismissal: Dismissal, mediaInput: Bool,
                 onExpiry: @escaping @MainActor () -> Void) -> Reason? {
        guard let next = Self.requiredReason(for: dismissal, awaiting: reason, mediaInput: mediaInput) else {
            cancel()
            return nil
        }
        arm(next, onExpiry: onExpiry)
        return next
    }

    func arm(_ reason: Reason, onExpiry: @escaping @MainActor () -> Void) {
        let nextAttempt = self.reason == nil ? 1 : attempts + 1
        cancel()
        self.reason = reason
        attempts = nextAttempt
        let generation = UUID()
        self.generation = generation
        let reset = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.cancel()
                onExpiry()
            }
        }
        pendingReset = reset
        schedule(reason.duration, reset)
    }

    func cancel() {
        generation = nil
        pendingReset?.cancel()
        pendingReset = nil
        reason = nil
        attempts = 0
    }

    deinit { pendingReset?.cancel() }
}
