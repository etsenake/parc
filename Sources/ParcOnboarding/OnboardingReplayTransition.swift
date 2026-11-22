import Foundation

@MainActor
package struct OnboardingReplayTransition {
    package enum CloseResult: Equatable {
        case cancelled, restoreForTermination, present
    }

    package private(set) var isClosing = false
    package private(set) var isActive = false
    private var deferredTermination: (() -> Void)?
    package init(deferredTermination: (() -> Void)? = nil) {
        self.deferredTermination = deferredTermination
    }

    package mutating func begin() {
        isActive = true
        isClosing = true
    }

    package mutating func deferTerminationWhileClosing(_ terminate: @escaping () -> Void) -> Bool {
        guard isClosing else { return false }
        deferredTermination = terminate
        return true
    }

    package mutating func closeResolved(approved: Bool) -> CloseResult {
        isClosing = false
        guard approved else {
            deferredTermination = nil
            return .cancelled
        }
        return deferredTermination == nil ? .present : .restoreForTermination
    }

    package mutating func restored() {
        isActive = false
    }

    package mutating func takeDeferredTermination() -> (() -> Void)? {
        defer { deferredTermination = nil }
        return deferredTermination
    }

    package static func restoreOwner<Owner: AnyObject>(savedID: UUID?, returning owner: Owner?,
                                               owners: [Owner], sessionID: (Owner) -> UUID,
                                               ready: (Owner) -> Bool, standard: (Owner) -> Bool,
                                               make: () throws -> Owner) rethrows -> Owner {
        if let savedID { return try owners.first { sessionID($0) == savedID } ?? make() }
        if let owner, let live = owners.first(where: { $0 === owner && ready($0) }) { return live }
        return try owners.first { standard($0) && ready($0) } ?? make()
    }
}

@MainActor
package struct OnboardingReadOnly<Owner: AnyObject> {
    private let originals: [(Owner, Bool)]
    private let isReadOnly: ReferenceWritableKeyPath<Owner, Bool>

    package init(_ owners: [Owner], isReadOnly: ReferenceWritableKeyPath<Owner, Bool>) {
        self.isReadOnly = isReadOnly
        var seen = Set<ObjectIdentifier>()
        originals = owners.compactMap { owner in
            guard seen.insert(ObjectIdentifier(owner)).inserted else { return nil }
            let wasReadOnly = owner[keyPath: isReadOnly]
            owner[keyPath: isReadOnly] = true
            return (owner, wasReadOnly)
        }
    }

    package func restore() {
        for (owner, wasReadOnly) in originals { owner[keyPath: isReadOnly] = wasReadOnly }
    }
}

@MainActor
package final class OnboardingAuxiliaryConsent<Page: AnyObject> {
    private let identities: Set<ObjectIdentifier>
    private let originals: [Page]
    private var consented = false

    package init?(_ pages: [Page]) {
        identities = Set(pages.map(ObjectIdentifier.init))
        guard identities.count == pages.count else { return nil }
        originals = pages
    }

    package func matches(_ pages: [Page], stillOwned: (Page) -> Bool) -> Bool {
        Set(pages.map(ObjectIdentifier.init)) == identities && originals.allSatisfy(stillOwned)
    }

    package func recordConsent(current: Bool) -> Bool {
        consented = current
        return false
    }

    package func approved(_ current: @autoclosure () -> Bool) -> Bool { consented && current() }
}
