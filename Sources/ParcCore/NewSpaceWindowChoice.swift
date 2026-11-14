enum NewSpaceWindowChoice<ID: Equatable>: Equatable {
    case existing(ID)
    case openNew

    static func choose(from frontToBack: [(id: ID, isPrivate: Bool, isPopup: Bool)]) -> NewSpaceWindowChoice {
        frontToBack.first { !$0.isPrivate && !$0.isPopup }.map { .existing($0.id) } ?? .openNew
    }
}
