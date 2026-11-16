enum PopupTabHandoff {
    struct Candidate<ID: Equatable>: Equatable {
        var id: ID
        var isPrivate = false
        var sharesSession = true
        var acceptsTabs = true
        var isMinimized = false
        var admitsHidden = true
        var canRestore = true
    }

    enum Choice<ID: Equatable>: Equatable {
        case existing(ID)
        case freshWindow
    }

    enum Arrival: Equatable {
        case deliver
        case awaitRestore
        case freshWindow
        case abandon
    }

    static func choose<ID>(sourceIsPrivate: Bool, candidates: [Candidate<ID>]) -> Choice<ID> {
        guard !sourceIsPrivate else { return .freshWindow }
        let chosen = candidates.last {
            !$0.isPrivate && $0.sharesSession && $0.acceptsTabs && ($0.isMinimized ? $0.canRestore : $0.admitsHidden)
        }
        return chosen.map { .existing($0.id) } ?? .freshWindow
    }

    static func arrival(sourceCurrent: Bool, destinationCurrent: Bool, isMinimized: Bool,
                        admitsHidden: Bool, mayAwaitRestore: Bool) -> Arrival {
        guard sourceCurrent else { return .abandon }
        guard destinationCurrent else { return .freshWindow }
        if isMinimized { return mayAwaitRestore ? .awaitRestore : .freshWindow }
        return admitsHidden ? .deliver : .freshWindow
    }
}
