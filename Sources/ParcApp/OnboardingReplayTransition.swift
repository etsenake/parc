import Foundation

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

    static func restoreOwner<Owner: AnyObject>(savedID: UUID?, returning owner: Owner?,
                                               owners: [Owner], sessionID: (Owner) -> UUID,
                                               ready: (Owner) -> Bool, standard: (Owner) -> Bool,
                                               make: () throws -> Owner) rethrows -> Owner {
        if let savedID { return try owners.first { sessionID($0) == savedID } ?? make() }
        if let owner, let live = owners.first(where: { $0 === owner && ready($0) }) { return live }
        return try owners.first { standard($0) && ready($0) } ?? make()
    }
}
