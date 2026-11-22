import Foundation

package enum SidebarKeyboardAnnouncement {
    static let endOfList = "End of list"
    static let topOfList = "Top of list"
    static let emptyList = "Sidebar is empty"
    static let unnamedItem = "Sidebar item"

    package static func highlight(_ cursor: SidebarKeyboardCursor?, in items: [SidebarKeyboardNavigation.Item],
                          state: BrowserState) -> String? {
        guard let id = cursor?.highlightedID, let item = items.first(where: { $0.id == id }) else { return nil }
        return text(item, state: state) ?? unnamedItem
    }

    package static func move(_ delta: Int, cursor: inout SidebarKeyboardCursor, in items: [SidebarKeyboardNavigation.Item],
                     state: BrowserState) -> String {
        cursor.move(delta, in: items.map(\.id))
        guard cursor.highlightedID != nil else { return items.isEmpty ? emptyList : delta > 0 ? endOfList : topOfList }
        return highlight(cursor, in: items, state: state) ?? unnamedItem
    }

    static func text(_ item: SidebarKeyboardNavigation.Item, state: BrowserState) -> String? {
        switch item.reference {
        case .tab(let id):
            return state.tab(id).map(SidebarTabTitle.display)
        case .folder:
            guard let folder = item.folder else { return nil }
            let disclosure = folder.isExpanded ? "expanded" : "collapsed"
            return folder.name.isEmpty ? "Folder, " + disclosure : folder.name + ", folder, " + disclosure
        case .split(let id):
            let layout = state.splitLayouts.first { $0.id == id }
            let tabIDs = item.selection?.tabIDs ?? layout?.tabIDs ?? []
            if let title = layout?.customTitle, !title.isEmpty { return "\(title), Split View, \(tabIDs.count) tabs" }
            let titles = layout?.customIcon == nil ? tabIDs.compactMap { state.tab($0).map(SidebarTabTitle.display) } : []
            return titles.isEmpty ? "Split View, \(tabIDs.count) tabs" : (titles + ["Split View"]).joined(separator: ", ")
        }
    }
}
