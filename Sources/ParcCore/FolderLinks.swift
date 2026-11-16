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
        return Link(tabID: tab.id, title: SidebarTabTitle.display(tab), url: url.absoluteString)
    }

    static func text(for links: [Link], format: FolderLinkFormat) -> String? {
        guard !links.isEmpty else { return nil }
        return links.map { link in
            switch format {
            case .plain: return link.url
            case .markdown:
                let title = link.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? link.url : link.title
                let label = markdownLabel(title)
                let destination = link.url.replacingOccurrences(of: "<", with: "%3C")
                    .replacingOccurrences(of: ">", with: "%3E")
                    .replacingOccurrences(of: "\r", with: "%0D")
                    .replacingOccurrences(of: "\n", with: "%0A")
                return "[\(label)](<\(destination)>)"
            }
        }.joined(separator: "\n")
    }

    static func markdownLabel(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { $0 == "\r" || $0 == "\n" ? " " : $0 }
        func at(_ index: Int) -> Unicode.Scalar { index < 0 ? "[" : index >= scalars.count ? "]" : scalars[index] }
        func isSpace(_ scalar: Unicode.Scalar) -> Bool { CharacterSet.whitespaces.contains(scalar) }
        func isWord(_ scalar: Unicode.Scalar) -> Bool { CharacterSet.alphanumerics.contains(scalar) }
        func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool { scalar.isASCII && isWord(scalar) }
        func startsEntity(_ index: Int) -> Bool {
            var next = index + 1
            if next < scalars.count, scalars[next] == "#" { next += 1 }
            let name = next
            while next < scalars.count, isASCIIAlphanumeric(scalars[next]) { next += 1 }
            return next > name && next < scalars.count && scalars[next] == ";"
        }
        var label = String.UnicodeScalarView(), index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            var end = index + 1
            let escaped: Bool
            switch scalar {
            case "\\":
                let next = at(end)
                escaped = next.value > 0x20 && next.value < 0x7F && !isASCIIAlphanumeric(next)
            case "[", "]", "<", "`": escaped = true
            case "&": escaped = startsEntity(index)
            case "*", "_", "~":
                while end < scalars.count, scalars[end] == scalar { end += 1 }
                let before = at(index - 1), after = at(end)
                escaped = !(isSpace(before) && isSpace(after)) && !(scalar == "_" && isWord(before) && isWord(after))
            default: escaped = false
            }
            for character in scalars[index..<end] {
                if escaped { label.append("\\") }
                label.append(character)
            }
            index = end
        }
        return String(label)
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
