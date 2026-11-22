package enum PopupTabHandoff {
    package struct Candidate<ID: Equatable>: Equatable {
        var id: ID
        var isPrivate = false
        package var sharesSession = true
        package var acceptsTabs = true
        package var isMinimized = false
        package var admitsHidden = true
        package var canRestore = true

        package init(id: ID, isPrivate: Bool = false, sharesSession: Bool = true, acceptsTabs: Bool = true, isMinimized: Bool = false, admitsHidden: Bool = true, canRestore: Bool = true) {
            self.id = id
            self.isPrivate = isPrivate
            self.sharesSession = sharesSession
            self.acceptsTabs = acceptsTabs
            self.isMinimized = isMinimized
            self.admitsHidden = admitsHidden
            self.canRestore = canRestore
        }
    }

    package enum Choice<ID: Equatable>: Equatable {
        case existing(ID)
        case freshWindow
    }

    package enum Arrival: Equatable {
        case deliver
        case awaitRestore
        case freshWindow
        case abandon
    }

    package static func choose<ID>(sourceIsPrivate: Bool, candidates: [Candidate<ID>]) -> Choice<ID> {
        guard !sourceIsPrivate else { return .freshWindow }
        let chosen = candidates.last {
            !$0.isPrivate && $0.sharesSession && $0.acceptsTabs && ($0.isMinimized ? $0.canRestore : $0.admitsHidden)
        }
        return chosen.map { .existing($0.id) } ?? .freshWindow
    }

    package static func arrival(sourceCurrent: Bool, destinationCurrent: Bool, isMinimized: Bool,
                        admitsHidden: Bool, mayAwaitRestore: Bool) -> Arrival {
        guard sourceCurrent else { return .abandon }
        guard destinationCurrent else { return .freshWindow }
        if isMinimized { return mayAwaitRestore ? .awaitRestore : .freshWindow }
        return admitsHidden ? .deliver : .freshWindow
    }
}
