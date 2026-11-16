import Foundation

struct FolderLinkTarget: Equatable {
    let folderID: UUID
    let spaceID: UUID
    let profileID: UUID
}

enum FolderLinkFormat { case plain, markdown }

enum FolderLinks {
    struct Link: Equatable {
        let tabID: UUID
        let title: String
        let url: String
    }

    static func links(in state: BrowserState, target: FolderLinkTarget) -> [Link]? {
        guard state.spaces.contains(where: { $0.id == target.spaceID && $0.profileID == target.profileID }),
              state.profiles.contains(where: { $0.id == target.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == target.profileID }),
              state.folders.contains(where: { $0.id == target.folderID && $0.spaceID == target.spaceID }) else { return nil }
        let tabs = state.openTabs(where: { $0.spaceID == target.spaceID && $0.profileID == target.profileID && $0.kind != .favorite })
        var seenFolders: Set<UUID> = [], seenTabs: Set<UUID> = [], result: [Link] = []
        func append(_ folderID: UUID) {
            guard seenFolders.insert(folderID).inserted else { return }
            for item in SidebarHierarchy.children(in: .init(spaceID: target.spaceID, folderID: folderID, section: .pinned), state: state) {
                if case .folder(let child) = item { append(child); continue }
                for id in SidebarHierarchy.tabIDs(in: item, state: state, spaceID: target.spaceID) {
                    guard seenTabs.insert(id).inserted, let tab = tabs.first(where: { $0.id == id }),
                          let found = link(for: tab) else { continue }
                    result.append(found)
                }
            }
        }
        append(target.folderID)
        return result
    }

    static func links(in state: BrowserState, items: [SidebarItemReference],
                      spaceID: UUID, profileID: UUID) -> [Link]? {
        guard SidebarHierarchySnapshot(state: state, spaceID: spaceID, profileID: profileID) != nil,
              let roots = SidebarHierarchy.roots(items, state: state, spaceID: spaceID) else { return nil }
        return links(in: state, tabIDs: roots.flatMap { SidebarHierarchy.tabIDs(in: $0, state: state, spaceID: spaceID) },
                     spaceID: spaceID, profileID: profileID)
    }

    static func links(in state: BrowserState, tabIDs: [UUID], spaceID: UUID, profileID: UUID) -> [Link] {
        var seen = Set<UUID>()
        return tabIDs.compactMap { id in
            guard seen.insert(id).inserted, let tab = state.tab(id, where: {
                $0.archivedAt == nil && $0.profileID == profileID && ($0.kind == .favorite || $0.spaceID == spaceID)
            }) else { return nil }
            return link(for: tab)
        }
    }

    private static func link(for tab: BrowserTab) -> Link? {
        guard let url = URL(string: tab.url), ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return Link(tabID: tab.id, title: tab.customTitle.flatMap(SidebarTabTitle.customValue) ?? tab.title, url: url.absoluteString)
    }

    static func text(for links: [Link], format: FolderLinkFormat) -> String? {
        guard !links.isEmpty else { return nil }
        return links.map { link in
            switch format {
            case .plain: return link.url
            case .markdown:
                let title = link.title.isEmpty ? link.url : link.title
                let label = title.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "[", with: "\\[")
                    .replacingOccurrences(of: "]", with: "\\]")
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                let destination = link.url.replacingOccurrences(of: "<", with: "%3C")
                    .replacingOccurrences(of: ">", with: "%3E")
                    .replacingOccurrences(of: "\r", with: "%0D")
                    .replacingOccurrences(of: "\n", with: "%0A")
                return "[\(label)](<\(destination)>)"
            }
        }.joined(separator: "\n")
    }

    static func html(for links: [Link]) -> String? {
        guard !links.isEmpty else { return nil }
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        let lines = links.map { link in
            let title = link.title.components(separatedBy: .newlines).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return "<a href=\"\(escaped(link.url))\">\(escaped(title.isEmpty ? link.url : title))</a>"
        }
        return "<meta charset=\"utf-8\">" + lines.joined(separator: "<br>\n")
    }
}
