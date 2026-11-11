import Foundation

struct CommandBarFavoriteAction: Equatable, Identifiable {
    enum Operation: String {
        case favorite, unfavorite
        var title: String { self == .favorite ? "Favorite Tab" : "Unfavorite Tab" }
    }
    struct Target: Equatable {
        let id: UUID
        let createdAt: Date
        let spaceID: UUID
        let kind: TabKind
        let folderID: UUID?
        init(_ tab: BrowserTab) {
            id = tab.id; createdAt = tab.createdAt; spaceID = tab.spaceID
            kind = tab.kind; folderID = tab.folderID
        }
    }
    let operation: Operation
    let spaceID: UUID
    let profileID: UUID
    let targets: [Target]
    var tabIDs: [UUID] { targets.map(\.id) }
    var title: String { operation.title }
    var id: String {
        ([operation.rawValue, profileID.uuidString, spaceID.uuidString] + targets.map {
            "\($0.id.uuidString):\($0.createdAt.timeIntervalSinceReferenceDate):\($0.spaceID.uuidString):\($0.kind.rawValue):\($0.folderID?.uuidString ?? "root")"
        }).joined(separator: ":")
    }

    init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard !items.isEmpty, Set(items).count == items.count,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }) else { return nil }
        var tabs: [BrowserTab] = []
        for item in items {
            guard case .tab(let id) = item,
                  let tab = state.tabs.first(where: { $0.id == id && $0.profileID == profileID && $0.archivedAt == nil }),
                  tab.kind == .favorite || tab.spaceID == spaceID,
                  !state.splitLayouts.contains(where: { $0.tabIDs.contains(id) }) else { return nil }
            if let folderID = tab.folderID {
                guard tab.kind == .pinned,
                      state.folders.contains(where: { $0.id == folderID && $0.spaceID == spaceID }) else { return nil }
            }
            tabs.append(tab)
        }
        if tabs.allSatisfy({ $0.kind == .favorite }) { operation = .unfavorite }
        else if tabs.allSatisfy({ $0.kind != .favorite }) { operation = .favorite }
        else { return nil }
        self.spaceID = spaceID; self.profileID = profileID; targets = tabs.map(Target.init)
    }

    func isCurrent(in state: BrowserState) -> Bool {
        Self(items: tabIDs.map(SidebarItemReference.tab), spaceID: spaceID, profileID: profileID, state: state) == self
    }

    func matches(query: String) -> Bool {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
        let text = title.lowercased()
        return !words.isEmpty && words.allSatisfy { text.contains($0) }
    }

    func applying(to state: BrowserState) -> BrowserState? {
        guard isCurrent(in: state) else { return nil }
        let ids = Set(tabIDs)
        var next = state
        for target in targets where target.kind != .favorite {
            let location = SidebarContainerLocation(spaceID: target.spaceID, folderID: target.folderID, section: target.kind)
            next.sidebarItemOrder[location.key] = SidebarHierarchy.children(in: location, state: state)
                .filter { item in if case .tab(let id) = item { return !ids.contains(id) }; return true }
                .map { item in
                    if case .split(let id) = item, let anchor = state.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
                    return item
                }
        }
        var moved = tabIDs.compactMap { id in state.tabs.first { $0.id == id } }
        for i in moved.indices {
            let previousKind = moved[i].kind
            moved[i].kind = operation == .favorite ? .favorite : .today
            moved[i].folderID = nil
            if operation == .unfavorite { moved[i].spaceID = spaceID }
            if previousKind == .today || operation == .unfavorite {
                moved[i].savedURL = moved[i].url; moved[i].savedTitle = moved[i].title
            }
        }
        next.tabs.removeAll { ids.contains($0.id) }
        if operation == .favorite { next.tabs.append(contentsOf: moved) }
        else {
            next.tabs.insert(contentsOf: moved, at: 0)
            let destination = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .today)
            next.sidebarItemOrder[destination.key] = tabIDs.map(SidebarItemReference.tab)
                + SidebarHierarchy.children(in: destination, state: state).map { item in
                    if case .split(let id) = item, let anchor = state.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
                    return item
                }
        }
        return next
    }
}
