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

@MainActor
struct OnboardingReadOnly<Owner: AnyObject> {
    private let originals: [(Owner, Bool)]
    private let isReadOnly: ReferenceWritableKeyPath<Owner, Bool>

    init(_ owners: [Owner], isReadOnly: ReferenceWritableKeyPath<Owner, Bool>) {
        self.isReadOnly = isReadOnly
        var seen = Set<ObjectIdentifier>()
        originals = owners.compactMap { owner in
            guard seen.insert(ObjectIdentifier(owner)).inserted else { return nil }
            let wasReadOnly = owner[keyPath: isReadOnly]
            owner[keyPath: isReadOnly] = true
            return (owner, wasReadOnly)
        }
    }

    func restore() {
        for (owner, wasReadOnly) in originals { owner[keyPath: isReadOnly] = wasReadOnly }
    }
}

@MainActor
final class OnboardingAuxiliaryConsent<Page: AnyObject> {
    private let identities: Set<ObjectIdentifier>
    private let originals: [Page]
    private var consented = false

    init?(_ pages: [Page]) {
        identities = Set(pages.map(ObjectIdentifier.init))
        guard identities.count == pages.count else { return nil }
        originals = pages
    }

    func matches(_ pages: [Page], stillOwned: (Page) -> Bool) -> Bool {
        Set(pages.map(ObjectIdentifier.init)) == identities && originals.allSatisfy(stillOwned)
    }

    func recordConsent(current: Bool) -> Bool {
        consented = current
        return false
    }

    func approved(_ current: @autoclosure () -> Bool) -> Bool { consented && current() }
}
