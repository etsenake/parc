import Foundation

struct CommandBarFolderMoveSource: Equatable {
    let hierarchy: SidebarHierarchySnapshot
    let roots: [SidebarItemReference]
    let targets: [CommandBarFavoriteAction.Target]
    let groupIDs: [UUID]
    var spaceID: UUID { hierarchy.spaceID }
    var profileID: UUID { hierarchy.profileID }
    var tabIDs: [UUID] { targets.map(\.id) }

    init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard let hierarchy = SidebarHierarchySnapshot(state: state, spaceID: spaceID, profileID: profileID),
              !items.isEmpty, Set(items).count == items.count else { return nil }
        guard let projected = Self.projectingFavorites(items, spaceID: spaceID, profileID: profileID, state: state),
              let roots = SidebarHierarchy.roots(items, state: projected, spaceID: spaceID), !roots.isEmpty else { return nil }
        let ids = roots.flatMap { SidebarHierarchy.tabIDs(in: $0, state: projected, spaceID: spaceID) }
        guard Set(ids).count == ids.count else { return nil }
        var tabs: [BrowserTab] = []
        for id in ids {
            guard let tab = state.tab(id, where: { $0.profileID == profileID && $0.archivedAt == nil }) else { return nil }
            tabs.append(tab)
        }
        let groups = state.splitLayouts.filter { !$0.tabIDs.allSatisfy { !ids.contains($0) } }
        guard groups.allSatisfy({ group in
            group.spaceID == spaceID && group.tabIDs.allSatisfy(ids.contains)
                && roots.contains(where: { root in
                    if case .split(let id) = root { return id == group.id }
                    if case .folder = root { return group.tabIDs.allSatisfy(SidebarHierarchy.tabIDs(in: root, state: projected, spaceID: spaceID).contains) }
                    return false
                })
        }) else { return nil }
        self.hierarchy = hierarchy; self.roots = roots; targets = tabs.map(CommandBarFavoriteAction.Target.init)
        groupIDs = groups.map(\.id)
    }

    func isCurrent(in state: BrowserState) -> Bool {
        Self(items: roots, spaceID: spaceID, profileID: profileID, state: state) == self
    }
    func projected(_ state: BrowserState) -> BrowserState? {
        guard isCurrent(in: state) else { return nil }
        return Self.projectingFavorites(roots, spaceID: spaceID, profileID: profileID, state: state)
    }
    private static func projectingFavorites(_ items: [SidebarItemReference], spaceID: UUID,
                                             profileID: UUID, state: BrowserState) -> BrowserState? {
        var next = state
        for item in items {
            guard case .tab(let id) = item else { continue }
            guard let index = next.tabIndex(id, where: { $0.profileID == profileID && $0.archivedAt == nil }) else { return nil }
            if next.tabs[index].kind == .favorite {
                guard next.tabs[index].folderID == nil, !state.splitLayouts.contains(where: { $0.tabIDs.contains(id) }) else { return nil }
                next.tabs[index].spaceID = spaceID; next.tabs[index].kind = .pinned
            }
        }
        return next
    }
}

struct CommandBarFolderMove: Equatable, Identifiable {
    let source: CommandBarFolderMoveSource
    let folder: CommandBarFolderAction
    let destination: SidebarHierarchySnapshot
    var id: String { "pin-to:" + folder.id }
    var title: String { "Pin to" }
    var tabIDs: [UUID] { source.tabIDs }

    init?(source: CommandBarFolderMoveSource, folder: CommandBarFolderAction, state: BrowserState) {
        guard source.isCurrent(in: state), folder.isCurrent(in: state, profileID: source.profileID),
              let destination = SidebarHierarchySnapshot(state: state, spaceID: folder.spaceID, profileID: source.profileID),
              let projected = source.projected(state),
              source.roots.allSatisfy({ SidebarHierarchy.location(of: $0, state: projected, spaceID: source.spaceID)?.folderID != folder.folderID }) else { return nil }
        self.source = source; self.folder = folder; self.destination = destination
        guard proposal(in: state) != nil else { return nil }
    }
    func isCurrent(in state: BrowserState) -> Bool {
        source.isCurrent(in: state) && folder.isCurrent(in: state, profileID: source.profileID)
            && SidebarHierarchySnapshot(state: state, spaceID: destination.spaceID, profileID: destination.profileID) == destination
    }
    func applying(to state: BrowserState) -> BrowserState? {
        guard isCurrent(in: state) else { return nil }
        return proposal(in: state)
    }
    private func proposal(in state: BrowserState) -> BrowserState? {
        guard var next = source.projected(state),
              let original = SidebarHierarchySnapshot(state: next, spaceID: source.spaceID, profileID: source.profileID) else { return nil }
        if source.spaceID != folder.spaceID {
            guard let relocation = SidebarSpaceMove(items: source.roots, from: original, to: destination, state: next),
                  let relocated = relocation.applying(to: next) else { return nil }
            next = relocated
        }
        guard let current = SidebarHierarchySnapshot(state: next, spaceID: folder.spaceID, profileID: source.profileID) else { return nil }
        return SidebarHierarchy.moving(source.roots, to: .init(spaceID: folder.spaceID, folderID: folder.folderID, section: .pinned),
                                       before: nil, expected: current, state: next)
    }
    static func snapshot(source: CommandBarFolderMoveSource, state: BrowserState) -> [Self] {
        CommandBarFolderAction.snapshot(state: state, profileID: source.profileID).compactMap {
            Self(source: source, folder: $0, state: state)
        }
    }
    static func matching(_ actions: [Self], query: String) -> [Self] {
        let query = normalize(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return actions.enumerated().filter { _, action in
            let text = normalize("Pin to Move to Folder \(action.folder.name) \(action.folder.detail)")
            return words.allSatisfy { text.contains($0) }
        }.sorted { lhs, rhs in
            let left = normalize(lhs.element.folder.name).hasPrefix(query)
            let right = normalize(rhs.element.folder.name).hasPrefix(query)
            return left != right ? left : lhs.offset < rhs.offset
        }.map(\.element)
    }
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

@MainActor
struct CommandBarFolderCopy {
    let move: CommandBarFolderMove
    private let sources: SidebarCopySources
    let roots: [SidebarItemReference]
    let folders: [BrowserFolder]
    let tabs: [BrowserTab]
    let groups: [BrowserSplitLayout]
    let childOrder: [String: [SidebarItemReference]]
    let openTabIDs: [UUID]
    var tabIDs: [UUID] { tabs.map(\.id) }

    init?(move: CommandBarFolderMove, destinations: [UUID: String],
          documents: [UUID: SidebarDocumentReference] = [:], creation: TabCreationProvenance? = nil,
          state: BrowserState, now: Date) {
        let sources = SidebarCopySources(destinations: destinations, documents: documents)
        let originals = move.tabIDs.compactMap { id in state.tab(id) }
        guard move.isCurrent(in: state), originals.count == move.tabIDs.count, sources.validates(originals),
              let projected = move.source.projected(state) else { return nil }
        self.move = move; self.sources = sources
        var copiedFolders: [BrowserFolder] = [], copiedTabs: [BrowserTab] = []
        var copiedGroups: [BrowserSplitLayout] = [], order: [String: [SidebarItemReference]] = [:]
        var eager: [UUID] = []
        let spaceID = move.folder.spaceID, profileID = move.source.profileID
        let previous = creation?.validated(profileID: profileID, state: state).activeTabBeforeCreationID
        func copyTab(_ id: UUID, parent: UUID, shouldOpen: Bool) -> UUID? {
            guard let original = state.tab(id, where: { $0.profileID == profileID && $0.archivedAt == nil }),
                  let url = destinations[id] else { return nil }
            var copy = original
            copy.id = UUID(); copy.spaceID = spaceID; copy.folderID = parent; copy.kind = .pinned
            copy.referrerID = nil; copy.activeTabBeforeCreationID = previous
            copy.url = url; copy.savedURL = url; copy.title = original.savedTitle
            copy.createdAt = now; copy.lastAccessed = now; copy.isUnread = true
            copy.archivedAt = nil; copy.archiveProvenance = nil
            copiedTabs.append(copy)
            if shouldOpen && InternalPage(urlString: original.savedURL) == nil { eager.append(copy.id) }
            return copy.id
        }
        func copyItem(_ item: SidebarItemReference, parent: UUID, shouldOpen: Bool) -> SidebarItemReference? {
            switch item {
            case .tab(let id): return copyTab(id, parent: parent, shouldOpen: shouldOpen).map(SidebarItemReference.tab)
            case .folder(let id):
                guard var copy = state.folders.first(where: { $0.id == id && $0.spaceID == move.source.spaceID }) else { return nil }
                copy.id = UUID(); copy.spaceID = spaceID; copy.parentID = parent
                copiedFolders.append(copy)
                let old = SidebarContainerLocation(spaceID: move.source.spaceID, folderID: id, section: .pinned)
                let destination = SidebarContainerLocation(spaceID: spaceID, folderID: copy.id, section: .pinned)
                var children: [SidebarItemReference] = []
                for child in SidebarHierarchy.children(in: old, state: projected) {
                    guard let result = copyItem(child, parent: copy.id, shouldOpen: false) else { return nil }
                    children.append(result)
                }
                order[destination.key] = children
                return .folder(copy.id)
            case .split(let id):
                guard let group = state.splitLayouts.first(where: { $0.id == id }),
                      let anchor = group.sidebarAnchorID, group.tabIDs.contains(anchor) else { return nil }
                var map: [UUID: UUID] = [:]
                for child in group.tabIDs {
                    guard let copied = copyTab(child, parent: parent, shouldOpen: true) else { return nil }
                    map[child] = copied
                }
                let copy = BrowserSplitLayout(id: UUID(), sidebarAnchorID: map[anchor], customTitle: group.customTitle, customIcon: group.customIcon,
                    spaceID: spaceID, tabIDs: group.tabIDs.compactMap { map[$0] },
                    orientation: group.orientation, widthFactors: group.widthFactors)
                copiedGroups.append(copy)
                return .split(copy.id)
            }
        }
        var roots: [SidebarItemReference] = []
        for (index, original) in move.source.roots.enumerated() {
            guard let copy = copyItem(original, parent: move.folder.folderID, shouldOpen: index < 5) else { return nil }
            roots.append(copy)
        }
        guard copiedTabs.count == move.tabIDs.count else { return nil }
        func stored(_ item: SidebarItemReference) -> SidebarItemReference {
            if case .split(let id) = item, let anchor = copiedGroups.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
            return item
        }
        self.roots = roots; folders = copiedFolders; tabs = copiedTabs; groups = copiedGroups
        childOrder = order.mapValues { $0.map(stored) }; openTabIDs = eager
    }

    func applying(to state: BrowserState) -> BrowserState? {
        let originals = move.tabIDs.compactMap { id in state.tab(id) }
        guard move.isCurrent(in: state), originals.count == move.tabIDs.count, sources.validates(originals),
              tabs.allSatisfy({ copy in !state.containsTab(copy.id) }),
              folders.allSatisfy({ copy in !state.folders.contains { $0.id == copy.id } }),
              groups.allSatisfy({ copy in !state.splitLayouts.contains { $0.id == copy.id } }) else { return nil }
        var next = state
        next.tabs += tabs; next.folders += folders; next.splitLayouts += groups
        for (key, values) in childOrder { next.sidebarItemOrder[key] = values }
        let destination = SidebarContainerLocation(spaceID: move.folder.spaceID, folderID: move.folder.folderID, section: .pinned)
        let items = SidebarHierarchy.children(in: destination, state: state) + roots
        next.sidebarItemOrder[destination.key] = items.map { item in
            if case .split(let id) = item, let anchor = next.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
            return item
        }
        if let index = next.folders.firstIndex(where: { $0.id == move.folder.folderID }) { next.folders[index].isExpanded = true }
        return next
    }
}
