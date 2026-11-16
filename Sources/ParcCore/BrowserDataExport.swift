import Foundation

struct BrowserDataExport {
    private let state: BrowserState

    init(state: BrowserState) { self.state = state }

    var markdown: String {
        state.spaces.enumerated().map { index, space in
            let title = space.name.isEmpty ? "Space \(index + 1)" : space.name
            var lines = ["# " + Self.heading(title)]
            let favorites = state.openTabs(where: { $0.profileID == space.profileID && $0.kind == .favorite }).compactMap(urlLine)
            if !favorites.isEmpty { lines += ["", "## Favorites"] + favorites }

            let items = children(space: space.id, folder: nil, section: .pinned)
                + children(space: space.id, folder: nil, section: .today)
            var visitedFolders = Set<UUID>()
            lines += render(items, space: space, depth: 2, visited: &visitedFolders)
            return lines.joined(separator: "\n") + "\n"
        }.joined(separator: "\n")
    }

    func write(to destination: URL) throws {
        guard destination.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        try Data(markdown.utf8).write(to: destination, options: .atomic)
    }

    private static func heading(_ value: String) -> String {
        value.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
    }

    private func children(space: UUID, folder: UUID?, section: TabKind) -> [SidebarItemReference] {
        SidebarHierarchy.children(in: .init(spaceID: space, folderID: folder, section: section), state: state)
    }

    private func urlLine(_ tab: BrowserTab) -> String? {
        guard !InternalPage.isInternal(tab.savedURL) else { return nil }
        return "- " + (URL(string: tab.savedURL)?.absoluteString ?? "")
    }

    private func render(_ items: [SidebarItemReference], space: BrowserSpace,
                        depth: Int, visited: inout Set<UUID>) -> [String] {
        var lines: [String] = []
        for item in items {
            if case .folder = item { continue }
            for id in SidebarHierarchy.tabIDs(in: item, state: state, spaceID: space.id) {
                guard let tab = state.tab(id, where: { $0.profileID == space.profileID && $0.archivedAt == nil }), let line = urlLine(tab) else { continue }
                lines.append(line)
            }
        }
        for item in items {
            guard case .folder(let id) = item, visited.insert(id).inserted,
                  let folder = state.folders.first(where: { $0.id == id && $0.spaceID == space.id }) else { continue }
            lines += ["", String(repeating: "#", count: min(depth, 6)) + " " + Self.heading(folder.name)]
            lines += render(children(space: space.id, folder: id, section: .pinned),
                            space: space, depth: min(depth + 1, 6), visited: &visited)
        }
        return lines
    }
}
