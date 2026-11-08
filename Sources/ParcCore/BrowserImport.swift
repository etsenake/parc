import Foundation

/// Immutable source identities survive selection; duplicate titles and URLs
/// remain distinct bookmarks. Credentials never enter this application model.
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

    /// Every bookmark starts ticked. Setup also opens the top-level folders so
    /// their pages show.
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

    /// The import picker's Select All row owns this source's entire tree,
    /// including descendants that are currently collapsed.
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

    /// Pure preparation keeps the visible session unchanged until its real
    /// atomic write succeeds. No existing folder, split or tab is repurposed.
    func inserting(_ roots: [BrowserImportBookmark], into state: BrowserState, at date: Date) throws -> BrowserState {
        guard isCurrent(in: state) else { throw CocoaError(.userCancelled) }
        _ = try BrowserImportSelection(roots: roots)
        var next = state
        func append(_ items: [BrowserImportBookmark], parent: UUID?) throws {
            let location = SidebarContainerLocation(spaceID: spaceID, folderID: parent, section: .pinned)
            var order = SidebarHierarchy.children(in: location, state: next)
            for item in items {
                if let value = item.url {
                    let publicURL = BrowserInternalURL.publicString(value)
                    guard let url = URL(string: publicURL), let scheme = url.scheme,
                          !scheme.isEmpty, scheme.lowercased() != "arc" else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let id = UUID()
                    let title = item.title.isEmpty ? (url.host ?? value) : item.title
                    next.tabs.append(BrowserTab(id: id, spaceID: spaceID, profileID: profileID,
                        url: publicURL, title: title, kind: .pinned, folderID: parent,
                        createdAt: date, lastAccessed: date, savedURL: publicURL, savedTitle: title))
                    order.append(.tab(id))
                } else {
                    let id = UUID()
                    next.folders.append(BrowserFolder(id: id, spaceID: spaceID,
                        name: item.title.isEmpty ? "Imported folder" : item.title, parentID: parent))
                    order.append(.folder(id))
                    try append(item.children, parent: id)
                }
            }
            next.sidebarItemOrder[location.key] = order
        }
        try append(roots, parent: nil)
        return next
    }
}

/// The destination Profile is explicit. A Space is captured for sidebar
/// bookmarks; it never follows another window's current selection.
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
        // A formerly unused Profile gaining a Space requires a fresh choice,
        // rather than silently changing an issued destination.
        return !state.spaces.contains { $0.profileID == profileID }
    }
}

struct BrowserImportDestinationChoice: Equatable {
    enum Option: Equatable { case existing(BrowserImportProfileTarget), new }
    private(set) var option: Option?
    var newProfileName = ""
    private(set) var replaceExistingCookies = false

    var profileName: String { newProfileName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isNew: Bool { option == .new }

    /// A new Profile takes the imported cookies; an existing one keeps its own.
    mutating func select(_ option: Option) {
        self.option = option
        replaceExistingCookies = option == .new
    }

    mutating func appeared() { replaceExistingCookies = isNew }
    mutating func invalidate() { option = nil }

    func canSubmit(in state: BrowserState) -> Bool {
        switch option {
        case .existing(let target): return target.isCurrent(in: state)
        case .new: return !profileName.isEmpty
        case nil: return false
        }
    }
}
