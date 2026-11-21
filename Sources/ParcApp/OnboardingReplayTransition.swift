@MainActor
struct OnboardingReplayTransition {
    enum CloseResult: Equatable {
        case cancelled, restoreForTermination, present
    }

    private(set) var isClosing = false
    private(set) var isActive = false
    private var deferredTermination: (() -> Void)?

    mutating func begin() {
        isActive = true
        isClosing = true
    }

    mutating func deferTerminationWhileClosing(_ terminate: @escaping () -> Void) -> Bool {
        guard isClosing else { return false }
        deferredTermination = terminate
        return true
    }

    mutating func closeResolved(approved: Bool) -> CloseResult {
        isClosing = false
        guard approved else {
            deferredTermination = nil
            return .cancelled
        }
        return deferredTermination == nil ? .present : .restoreForTermination
    }

    mutating func restored() {
        isActive = false
    }

    mutating func takeDeferredTermination() -> (() -> Void)? {
        defer { deferredTermination = nil }
        return deferredTermination
    }
}
