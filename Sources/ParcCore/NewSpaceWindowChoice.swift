enum NewSpaceWindowChoice<ID: Equatable>: Equatable {
    case existing(ID)
    case openNew

    static func choose(from frontToBack: [(id: ID, isPrivate: Bool, isPopup: Bool, isMinimized: Bool, isCreating: Bool)]) -> NewSpaceWindowChoice {
        let regular = frontToBack.filter { !$0.isPrivate && !$0.isPopup }
        let chosen = regular.first(where: \.isCreating) ?? regular.first(where: { !$0.isMinimized }) ?? regular.first
        return chosen.map { .existing($0.id) } ?? .openNew
    }
}
