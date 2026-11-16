import Foundation

enum InterProfileMoveDecision: Equatable {
    case abort, proceed, alwaysProceed
}

enum InterProfileMoveGate: Equatable {
    case proceed(remembersChoice: Bool)
    case confirm
    case abort

    static func resolve(sourceProfiles: Set<UUID>, destination: UUID,
                        decision: InterProfileMoveDecision?, bypass: Bool) -> InterProfileMoveGate? {
        guard sourceProfiles.count <= 1 else { return nil }
        guard let source = sourceProfiles.first, source != destination else { return .proceed(remembersChoice: false) }
        switch decision {
        case nil: return bypass ? .proceed(remembersChoice: false) : .confirm
        case .abort?: return .abort
        case .proceed?: return .proceed(remembersChoice: false)
        case .alwaysProceed?: return .proceed(remembersChoice: true)
        }
    }
}

struct InterProfileMovePrompt: Equatable {
    static let confirmTitle = "Move it"
    static let cancelTitle = "Cancel"
    static let suppressionTitle = "Don’t ask again"
    static let dialogWidth: Double = 455

    let destinationName: String
    let tabCount: Int

    init(tabCount: Int, spaceName: String) {
        self.tabCount = max(1, tabCount)
        destinationName = Self.displayName(spaceName)
    }

    init?(tabCount: Int, destinationSpaceID: UUID, state: BrowserState) {
        guard let index = state.spaces.firstIndex(where: { $0.id == destinationSpaceID }) else { return nil }
        self.init(tabCount: tabCount, spaceName: state.spaces[index].title ?? "Space \(index + 1)")
    }

    var title: String { "Move \(tabCount > 1 ? "tabs" : "tab") to \(destinationName)?" }
    var message: String {
        "\(destinationName) uses different data, so you might get logged out or lose your progress in "
            + (tabCount > 1 ? "these tabs" : "this tab") + ".\n\nThis can't be undone!"
    }

    var titleSegments: [(String, Bool)] {
        [("Move \(tabCount > 1 ? "tabs" : "tab") to ", false), (destinationName, true), ("?", false)]
    }
    var messageSegments: [(String, Bool)] {
        [(destinationName, true), (" uses different data, so you might get logged out or lose your progress in "
            + (tabCount > 1 ? "these tabs" : "this tab") + ".\n\nThis can't be undone!", false)]
    }

    static func displayName(_ name: String) -> String {
        guard name.count > 24 else { return name }
        return String(name.prefix(24)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func decision(confirmed: Bool, suppressed: Bool) -> InterProfileMoveDecision {
        confirmed ? (suppressed ? .alwaysProceed : .proceed) : .abort
    }
}

enum InterProfileMove {
    static func admits(_ tab: BrowserTab) -> Bool { tab.archivedAt == nil }

    static func documents(moving ids: Set<UUID>, after state: BrowserState) -> [InternalPage]? {
        var pages: [InternalPage] = []
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let tab = state.tab(id) else { return nil }
            for value in [tab.url, tab.savedURL] {
                guard InternalPage.isInternal(value) else { continue }
                guard let page = InternalPage(urlString: value) else { return nil }
                if !pages.contains(page) { pages.append(page) }
            }
            for page in pages {
                guard state.tabs.allSatisfy({ other in
                    other.url != page.urlString && other.savedURL != page.urlString || other.profileID == tab.profileID
                }) else { return nil }
            }
        }
        return pages
    }

    static func samePlacement(_ tab: BrowserTab, _ original: BrowserTab) -> Bool {
        guard tab.id == original.id && tab.spaceID == original.spaceID && tab.profileID == original.profileID
            && tab.kind == original.kind && tab.folderID == original.folderID && tab.archivedAt == original.archivedAt
            && tab.customTitle == original.customTitle else { return false }
        return tab.kind == .today || (tab.savedURL == original.savedURL && tab.savedTitle == original.savedTitle)
    }

    static func sourceProfile(of ids: [UUID], in state: BrowserState) -> UUID? {
        let profiles = Set(ids.compactMap { id in state.tab(id)?.profileID })
        guard profiles.count == 1, ids.allSatisfy({ id in state.containsTab(id) }) else { return nil }
        return profiles.first
    }

    static func profilesAvailable(_ source: UUID, _ destination: UUID, in state: BrowserState) -> Bool {
        source != destination
            && state.profiles.contains { $0.id == source } && state.profiles.contains { $0.id == destination }
            && !state.profileRemovals.contains { $0.profileID == source || $0.profileID == destination }
    }
}

enum ForeignSplitDrop {
    struct Request: Equatable {
        let source: BrowserTab
        let sourceHomeID: UUID
        let spaceID: UUID
        let profileID: UUID
        let selection: [UUID]
        let layout: BrowserSplitLayout?
        let target: SplitDropTarget
        let orientation: SplitOrientation
        let destinationHomeIDs: [UUID: UUID]
    }

    static func proposal(_ request: Request, state: BrowserState, now: Date,
                         creation: TabCreationProvenance?) -> BrowserState? {
        let original = request.source
        guard let tab = state.tab(original.id), InterProfileMove.samePlacement(tab, original),
              InterProfileMove.admits(tab), tab.kind == .pinned || tab.kind == .today,
              tab.profileID == request.profileID
                || InterProfileMove.profilesAvailable(tab.profileID, request.profileID, in: state),
              state.spaces.contains(where: { $0.id == tab.spaceID && $0.profileID == tab.profileID }),
              state.spaces.contains(where: { $0.id == request.spaceID && $0.profileID == request.profileID }),
              !request.selection.contains(tab.id),
              SidebarHierarchySnapshot(state: state, spaceID: tab.spaceID, profileID: tab.profileID) != nil else { return nil }
        var homes = request.destinationHomeIDs
        var staged = state
        if tab.spaceID == request.spaceID {
            if tab.kind == .pinned { homes[tab.id] = request.sourceHomeID }
        } else {
            guard let detached = detach(tab, homeID: request.sourceHomeID, spaceID: request.spaceID,
                                        profileID: request.profileID, state: state, now: now) else { return nil }
            staged = detached
        }
        staged.activeSpaceID = request.spaceID
        staged.selectedTabIDs = request.selection
        return OriginalSplitDrop.proposal(source: tab.id, state: staged, selection: request.selection,
            layout: request.layout, target: request.target, orientation: request.orientation,
            spaceID: request.spaceID, profileID: request.profileID, now: now,
            savedHomeIDs: homes, creation: creation)
    }

    static func destinationHomes(_ request: Request, state: BrowserState) -> [BrowserTab]? {
        OriginalSplitDrop.savedHomes(source: request.source.id, state: state, selection: request.selection,
            layout: request.layout, target: request.target, orientation: request.orientation, spaceID: request.spaceID)
    }

    private static func detach(_ tab: BrowserTab, homeID: UUID, spaceID destination: UUID, profileID: UUID,
                               state: BrowserState, now: Date) -> BrowserState? {
        guard !state.containsTab(homeID) else { return nil }
        var next = state
        let spaceID = tab.spaceID, prefix = spaceID.uuidString + ":"
        let parents = state.splitLayouts.filter { $0.tabIDs.contains(tab.id) }
        guard parents.count <= 1, parents.allSatisfy({ $0.spaceID == spaceID }) else { return nil }
        let saved = tab.kind == .pinned
        if saved {
            guard FolderDuplicateTarget.validSource(tab.savedURL) else { return nil }
            if let parent = parents.first {
                guard let index = next.splitLayouts.firstIndex(where: { $0.id == parent.id }),
                      let child = parent.tabIDs.firstIndex(of: tab.id) else { return nil }
                next.splitLayouts[index].tabIDs[child] = homeID
                if parent.sidebarAnchorID == tab.id { next.splitLayouts[index].sidebarAnchorID = homeID }
            } else {
                guard let location = SidebarHierarchy.location(of: .tab(tab.id), state: state, spaceID: spaceID),
                      SidebarHierarchy.children(in: location, state: state).contains(.tab(tab.id)) else { return nil }
                next.sidebarItemOrder[location.key] = SidebarHierarchy.children(in: location, state: state).map {
                    $0 == .tab(tab.id) ? .tab(homeID) : stored($0, state: state)
                }
            }
            for key in next.sidebarItemOrder.keys where key.hasPrefix(prefix) {
                next.sidebarItemOrder[key] = next.sidebarItemOrder[key]?.map { $0 == .tab(tab.id) ? .tab(homeID) : $0 }
            }
            var home = tab
            home.id = homeID; home.url = tab.savedURL; home.title = tab.savedTitle
            home.createdAt = now; home.lastAccessed = now; home.isUnread = false
            home.referrerID = nil; home.activeTabBeforeCreationID = nil; home.archiveProvenance = nil
            next.tabs.append(home)
        } else {
            if let parent = parents.first, let index = next.splitLayouts.firstIndex(where: { $0.id == parent.id }),
               let child = parent.tabIDs.firstIndex(of: tab.id) {
                var kept = parent
                kept.tabIDs.remove(at: child); kept.widthFactors.remove(at: child)
                if kept.tabIDs.count < 2 {
                    next.splitLayouts.remove(at: index)
                    if parent.sidebarAnchorID == tab.id, let survivor = kept.tabIDs.first {
                        for key in next.sidebarItemOrder.keys where key.hasPrefix(prefix) {
                            next.sidebarItemOrder[key] = next.sidebarItemOrder[key]?.map { $0 == .tab(tab.id) ? .tab(survivor) : $0 }
                        }
                    }
                } else {
                    guard let factors = BrowserSplitLayout.normalized(kept.widthFactors, count: kept.tabIDs.count) else { return nil }
                    kept.widthFactors = factors
                    if kept.sidebarAnchorID == tab.id {
                        kept.sidebarAnchorID = kept.tabIDs.first
                        for key in next.sidebarItemOrder.keys where key.hasPrefix(prefix) {
                            next.sidebarItemOrder[key] = next.sidebarItemOrder[key]?.map { $0 == .tab(tab.id) ? .tab(kept.tabIDs[0]) : $0 }
                        }
                    }
                    next.splitLayouts[index] = kept
                }
            }
            for key in next.sidebarItemOrder.keys where key.hasPrefix(prefix) {
                next.sidebarItemOrder[key]?.removeAll { $0 == .tab(tab.id) }
            }
        }
        for key in next.selectionBySpace.keys {
            next.selectionBySpace[key] = next.selectionBySpace[key]?.compactMap { id in
                id == tab.id ? (saved && key == spaceID.uuidString ? homeID : nil) : id
            }
        }
        guard let index = next.tabIndex(tab.id) else { return nil }
        next.tabs[index].kind = .today; next.tabs[index].folderID = nil
        next.tabs[index].spaceID = destination; next.tabs[index].profileID = profileID
        return next
    }

    private static func stored(_ item: SidebarItemReference, state: BrowserState) -> SidebarItemReference {
        if case .split(let id) = item, let anchor = state.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
        return item
    }
}


@MainActor
final class LocalDocumentRelocationRollback {
    private var reversals: [() -> Bool] = []
    private var cleanups: [() -> Void] = []
    private var finished = false

    func append(reverse: @escaping () -> Bool, cleanup: @escaping () -> Void = {}) {
        precondition(!finished)
        reversals.append(reverse); cleanups.append(cleanup)
    }

    func run() {
        guard !finished else { return }
        finished = true
        var restored = true
        for reverse in reversals.reversed() {
            if !reverse() { restored = false }
        }
        if restored { cleanups.forEach { $0() } }
        reversals.removeAll(); cleanups.removeAll()
    }
}
