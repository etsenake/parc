import Foundation

/// Owns the web Peek dismissal decision and prompt lifetime. A nil reason
/// permits the original controller to request close; it never closes a page.
@MainActor
final class PeekDismissalConfirmation {
    enum Reason: Equatable {
        case escape, mediaInput

        //
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

    ///
    /// reason before live capture. Background/swipe cannot confirm Hang up.
    /// An explicit Escape/Close can confirm either pending reason.
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
        // The original updater increments awaiting attempts; a fresh prompt
        // starts at one. Attempts do not turn a background click into consent.
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
        DispatchQueue.main.asyncAfter(deadline: .now() + reason.duration, execute: reset)
    }

    /// Invalidates even a callback already enqueued when its owner goes away.
    func cancel() {
        generation = nil
        pendingReset?.cancel()
        pendingReset = nil
        reason = nil
        attempts = 0
    }

    deinit { pendingReset?.cancel() }
}
