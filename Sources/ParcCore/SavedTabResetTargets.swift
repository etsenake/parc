import Foundation

/// Reset All follows the original visible saved hierarchy, not storage order.
/// Disclosure affects folders; a whole split contributes its original children.
enum SavedTabResetTargets {
    static func collect(in state: BrowserState, spaceID: UUID) -> [BrowserTab] {
        guard let space = state.spaces.first(where: { $0.id == spaceID }),
              state.profiles.contains(where: { $0.id == space.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == space.profileID }) else { return [] }
        let tabs = Dictionary(state.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let splits = SidebarSplitItems.groups(in: state, spaceID: spaceID)
        var result: [BrowserTab] = [], seen = Set<UUID>(), folders = Set<UUID>()
        func append(_ id: UUID) {
            guard seen.insert(id).inserted, let tab = tabs[id],
                  tab.profileID == space.profileID,
                  tab.kind == .favorite || tab.spaceID == spaceID,
                  tab.resetDestination != nil else { return }
            result.append(tab)
        }
        func visit(_ item: SidebarItemReference) {
            switch item {
            case .tab(let id): append(id)
            case .split(let id):
                guard let split = splits.first(where: { $0.id == id }) else { return }
                split.tabIDs.forEach(append)
            case .folder(let id):
                guard folders.insert(id).inserted,
                      let folder = state.folders.first(where: { $0.id == id && $0.spaceID == spaceID }),
                      folder.isExpanded else { return }
                SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: id, section: .pinned), state: state).forEach(visit)
            }
        }
        SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: nil, section: .favorite, profileID: space.profileID), state: state).forEach(visit)
        SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: nil, section: .pinned), state: state).forEach(visit)
        return result
    }
}
