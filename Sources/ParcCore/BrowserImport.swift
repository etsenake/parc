import Foundation

struct BrowserImportBookmark: Equatable, Identifiable {
    let id: String
    let title: String
    let url: String?
    let children: [BrowserImportBookmark]
}

struct BrowserImportSelection {
    let roots: [BrowserImportBookmark]
    private(set) var selected: Set<String>
    private(set) var expanded = Set<String>()
    private let nodes: [String: BrowserImportBookmark]

    init(roots: [BrowserImportBookmark], expandsTopFolders: Bool = false) throws {
        var nodes: [String: BrowserImportBookmark] = [:]
        func visit(_ items: [BrowserImportBookmark], depth: Int) throws {
            guard depth <= 128 else { throw CocoaError(.fileReadCorruptFile) }
            for item in items {
                guard !item.id.isEmpty, nodes[item.id] == nil, nodes.count < 50_000,
                      item.url == nil || item.children.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                nodes[item.id] = item
                try visit(item.children, depth: depth + 1)
            }
        }
        try visit(roots, depth: 0)
        self.roots = roots; self.nodes = nodes
        selected = Set(nodes.keys)
        if expandsTopFolders { expanded = Set(roots.filter { $0.url == nil }.map(\.id)) }
    }

    mutating func toggle(_ id: String) {
        guard let original = nodes[id] else { return }
        let selecting = !selected.contains(id)
        func apply(_ item: BrowserImportBookmark) {
            if selecting { selected.insert(item.id) } else { selected.remove(item.id) }
            item.children.forEach(apply)
        }
        apply(original)
    }

    mutating func toggleExpanded(_ id: String) {
        guard let node = nodes[id], node.url == nil else { return }
        if !expanded.insert(id).inserted { expanded.remove(id) }
    }

    var allSelected: Bool { !nodes.isEmpty && selected.count == nodes.count }

    mutating func toggleAll() {
        if allSelected { selected.removeAll() }
        else { selected = Set(nodes.keys) }
    }

    var includedRoots: [BrowserImportBookmark] {
        func include(_ item: BrowserImportBookmark) -> BrowserImportBookmark? {
            let children = item.children.compactMap(include)
            guard selected.contains(item.id) || !children.isEmpty else { return nil }
            return BrowserImportBookmark(id: item.id, title: item.title, url: item.url, children: children)
        }
        return roots.compactMap(include)
    }

    var selectedPageCount: Int { nodes.values.filter { $0.url != nil && selected.contains($0.id) }.count }
}

struct BrowserImportDestination: Equatable {
    let spaceID: UUID
    let profileID: UUID

    func isCurrent(in state: BrowserState) -> Bool {
        state.spaces.contains { $0.id == spaceID && $0.profileID == profileID }
            && state.profiles.contains { $0.id == profileID }
            && !state.profileRemovals.contains { $0.profileID == profileID }
    }

    func inserting(_ roots: [BrowserImportBookmark], into state: BrowserState, at date: Date) throws -> BrowserState {
        try replacing(BrowserImportPlacement(), with: roots, in: state, at: date).state
    }

    func replacing(_ placed: BrowserImportPlacement, with roots: [BrowserImportBookmark],
                   in state: BrowserState, at date: Date) throws -> (state: BrowserState, placement: BrowserImportPlacement) {
        guard isCurrent(in: state) else { throw CocoaError(.userCancelled) }
        _ = try BrowserImportSelection(roots: roots)
        var included = Set<String>()
        func collect(_ items: [BrowserImportBookmark]) { for item in items { included.insert(item.id); collect(item.children) } }
        collect(roots)
        var next = state, placement = placed
        var removedTabs = Set<UUID>(), removedFolders = Set<UUID>()
        let selected = Set(state.selectedTabIDs + state.selectionBySpace.values.flatMap { $0 })
        for (sourceID, written) in placed.tabs where !included.contains(sourceID) {
            guard let current = next.tabs.first(where: { $0.id == written.id }) else { placement.tabs[sourceID] = nil; continue }
            guard current == written, !selected.contains(current.id),
                  !next.splitLayouts.contains(where: { $0.tabIDs.contains(current.id) }) else { continue }
            removedTabs.insert(current.id); placement.tabs[sourceID] = nil
        }
        next.tabs.removeAll { removedTabs.contains($0.id) }
        next.recentlyClosedIDs.removeAll { removedTabs.contains($0) }
        var removing = true
        while removing {
            removing = false
            for (sourceID, written) in placement.folders where !included.contains(sourceID) {
                guard let current = next.folders.first(where: { $0.id == written.id }) else {
                    placement.folders[sourceID] = nil; continue
                }
                var unchanged = current; unchanged.isExpanded = written.isExpanded
                guard unchanged == written, !next.tabs.contains(where: { $0.folderID == current.id }),
                      !next.folders.contains(where: { $0.parentID == current.id }) else { continue }
                next.folders.removeAll { $0.id == current.id }
                removedFolders.insert(current.id); placement.folders[sourceID] = nil; removing = true
            }
        }
        let prefix = spaceID.uuidString + ":"
        for folder in removedFolders {
            next.sidebarItemOrder[SidebarContainerLocation(spaceID: spaceID, folderID: folder, section: .pinned).key] = nil
        }
        for key in next.sidebarItemOrder.keys where key.hasPrefix(prefix) {
            next.sidebarItemOrder[key]?.removeAll { item in
                switch item {
                case .tab(let id): return removedTabs.contains(id)
                case .folder(let id): return removedFolders.contains(id)
                case .split: return false
                }
            }
        }

        func add(_ items: [BrowserImportBookmark], parent: UUID?) throws {
            let location = SidebarContainerLocation(spaceID: spaceID, folderID: parent, section: .pinned)
            let before = SidebarHierarchy.children(in: location, state: next)
            var order = before
            func existing(_ item: BrowserImportBookmark) -> SidebarItemReference? {
                if item.url != nil {
                    guard let id = placement.tabs[item.id]?.id,
                          next.tabs.contains(where: { $0.id == id && $0.archivedAt == nil }) else { return nil }
                    let group = next.splitLayouts.first { $0.tabIDs.contains(id) }
                    return group.map { .split($0.id) } ?? .tab(id)
                }
                guard let id = placement.folders[item.id]?.id,
                      next.folders.contains(where: { $0.id == id && $0.spaceID == spaceID }) else { return nil }
                return .folder(id)
            }
            var anchor: SidebarItemReference?
            for (position, item) in items.enumerated() {
                if item.url == nil, let id = placement.folders[item.id]?.id,
                   next.folders.contains(where: { $0.id == id && $0.spaceID != spaceID }) { continue }
                if let kept = existing(item) {
                    if order.contains(kept) { anchor = kept }
                    if case .folder(let id) = kept { try add(item.children, parent: id) }
                    continue
                }
                let reference: SidebarItemReference
                if let value = item.url {
                    let publicURL = BrowserInternalURL.publicString(value)
                    guard let url = URL(string: publicURL), let scheme = url.scheme,
                          !scheme.isEmpty, scheme.lowercased() != "arc" else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let title = item.title.isEmpty ? (url.host ?? value) : item.title
                    let tab = BrowserTab(id: UUID(), spaceID: spaceID, profileID: profileID,
                        url: publicURL, title: title, kind: .pinned, folderID: parent,
                        createdAt: date, lastAccessed: date, savedURL: publicURL, savedTitle: title)
                    next.tabs.append(tab); placement.tabs[item.id] = tab
                    reference = .tab(tab.id)
                } else {
                    let folder = BrowserFolder(id: UUID(), spaceID: spaceID,
                        name: item.title.isEmpty ? "Imported folder" : item.title, parentID: parent)
                    next.folders.append(folder); placement.folders[item.id] = folder
                    reference = .folder(folder.id)
                }
                if let anchor, let index = order.firstIndex(of: anchor) {
                    order.insert(reference, at: index + 1)
                } else if let later = items[(position + 1)...].lazy.compactMap(existing).first(where: { order.contains($0) }),
                          let index = order.firstIndex(of: later) {
                    order.insert(reference, at: index)
                } else { order.append(reference) }
                anchor = reference
                if case .folder(let id) = reference { try add(item.children, parent: id) }
            }
            if order != before { next.sidebarItemOrder[location.key] = order }
        }
        try add(roots, parent: nil)
        return (next, placement)
    }
}

struct BrowserImportPlacement: Equatable {
    fileprivate(set) var tabs: [String: BrowserTab] = [:]
    fileprivate(set) var folders: [String: BrowserFolder] = [:]
    var isEmpty: Bool { tabs.isEmpty && folders.isEmpty }
}

struct BrowserImportProfileTarget: Equatable {
    let profileID: UUID
    let spaceID: UUID?

    static func choices(in state: BrowserState, original: BrowserImportDestination) -> [Self] {
        state.profiles.compactMap { profile in
            guard !state.profileRemovals.contains(where: { $0.profileID == profile.id }) else { return nil }
            let spaceID = profile.id == original.profileID ? original.spaceID :
                state.spaces.first(where: { $0.profileID == profile.id })?.id
            let target = Self(profileID: profile.id, spaceID: spaceID)
            return target.isCurrent(in: state) ? target : nil
        }
    }

    func isCurrent(in state: BrowserState) -> Bool {
        guard state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }) else { return false }
        if let spaceID {
            return state.spaces.contains { $0.id == spaceID && $0.profileID == profileID }
        }
        return !state.spaces.contains { $0.profileID == profileID }
    }
}
