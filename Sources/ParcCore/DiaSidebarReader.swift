import Foundation
import SQLite3

package enum DiaSidebarReader {
    private static let maximumBytes = 256 * 1024 * 1024
    private static let maximumSplitPanes = 4
    private static let unlockWarning = "Parc couldn't unlock Dia's tabs, so its Spaces, Favorites, pinned tabs and open tabs weren't imported."
    private static let unreadableWarning = "Parc couldn't read some of Dia's tab data, so part of its Spaces and tabs weren't imported."

    package static func read(profiles: [SidebarImportProfile], decrypt: SidebarDecryptor?) throws -> SidebarImport {
        var spaces: [SidebarImport.Space] = []
        var favorites: [(key: SidebarImport.ProfileKey, items: [SidebarImport.Item])] = []
        var skipped = 0
        var locked = false, unreadable = false
        for profile in profiles {
            let tabs = profile.directory.appendingPathComponent("tabs.db")
            guard FileManager.default.fileExists(atPath: tabs.path) else { continue }
            let folder = profile.directory.lastPathComponent
            guard let decrypt, let data = try? decrypt(tabs, .diaTabs(profileFolder: folder)), !data.isEmpty else {
                locked = true; continue
            }
            guard data.count <= maximumBytes, let parsed = parse(data, profile: profile, folder: folder) else {
                unreadable = true; continue
            }
            spaces += parsed.spaces
            if !parsed.favorites.isEmpty { favorites.append((profile.key, parsed.favorites)) }
            skipped += parsed.skipped
        }
        var result = SidebarImport(spaces: spaces, favorites: favorites, skippedItemCount: skipped)
        if locked { result.warnings.append(unlockWarning) }
        if unreadable { result.warnings.append(unreadableWarning) }
        return result
    }

    private struct Parsed {
        var spaces: [SidebarImport.Space] = []
        var favorites: [SidebarImport.Item] = []
        var skipped = 0
    }

    private static func parse(_ data: Data, profile: SidebarImportProfile, folder: String) -> Parsed? {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("parc-dia-" + UUID().uuidString, isDirectory: true)
        guard (try? files.createDirectory(at: directory, withIntermediateDirectories: false,
                                          attributes: [.posixPermissions: 0o700])) != nil else { return nil }
        defer { try? files.removeItem(at: directory) }
        var bytes = data
        if bytes.count > 19, bytes[18] == 2 || bytes[19] == 2 { bytes[18] = 1; bytes[19] = 1 }
        let file = directory.appendingPathComponent("tabs.sqlite")
        guard files.createFile(atPath: file.path, contents: bytes, attributes: [.posixPermissions: 0o600]),
              let database = Database(path: file.path), let tree = Tree(database: database) else { return nil }
        var parsed = Parsed()
        var builder = Builder(tree: tree)
        for space in tree.spaces {
            guard !space.id.isEmpty else { parsed.skipped += 1; continue }
            let pinned = builder.items(roots: tree.roots(kind: "pinned_container", space: space.id), flatten: false)
            let today = builder.items(roots: tree.roots(kind: "window", space: space.id), flatten: true)
            parsed.spaces.append(SidebarImport.Space(title: space.title, icon: nil, theme: theme(space),
                profile: profile.key, pinned: pinned, id: "dia:\(folder):\(space.id)", today: today))
            for tab in builder.flatTabs(roots: tree.roots(kind: "favorites", space: space.id)) {
                guard parsed.favorites.count < SidebarImport.maximumFavorites else { break }
                if !parsed.favorites.contains(where: { url($0) == tab.url }) { parsed.favorites.append(.tab(tab)) }
            }
        }
        parsed.skipped += builder.skipped
        return parsed
    }

    private static func url(_ item: SidebarImport.Item) -> String? {
        if case .tab(let tab) = item { return tab.url }
        return nil
    }

    private static func theme(_ space: Tree.SpaceRow) -> SpaceTheme? {
        let colors = ["red": "E5534B", "orange": "F0883E", "yellow": "E8C547", "green": "4CAF6A",
                      "blue": "4C8DF6", "pink": "EC6FA8", "purple": "9B6BDF"]
        guard let name = space.theme?.lowercased() else { return nil }
        if name == "neutral" { return SpaceTheme() }
        guard let hex = colors[name], let color = ThemeColor(hex: hex) else { return nil }
        var result = SpaceTheme.singleColor(color)
        if let intensity = space.intensity, intensity.isFinite, (0...1).contains(intensity) { result.intensity = intensity }
        return result
    }

    private struct Tree {
        struct Node {
            let id: Int64
            let kind: String
            let entity: String?
            let space: String
        }

        struct SpaceRow {
            let id: String
            let title: String?
            let theme: String?
            let intensity: Double?
        }

        struct Pane {
            let id: String?
            let nodeID: String?
            let customTitle: String?
            let variant: String?
        }

        struct Group {
            let title: String?
            let icon: String?
        }

        let spaces: [SpaceRow]
        let children: [Int64: [Node]]
        private let rootNodes: [Node]
        private let panesByKey: [String: Pane]
        private let panesByNode: [String: Pane]
        private let contentByPane: [String: (url: String, title: String?)]
        private let widthsByKey: [String: String]
        private let widthsByNode: [String: String]
        private let groupsByKey: [String: Group]
        private let groupsByNode: [String: Group]

        init?(database: Database) {
            guard !database.columns("nodes").isEmpty else { return nil }
            spaces = database.select("spaces", ["id", "title", "theme", "theme_intensity"], order: ["creation_date", "id"]).map {
                SpaceRow(id: $0[0] ?? "", title: $0[1].flatMap { $0.isEmpty ? nil : $0 }, theme: $0[2],
                         intensity: $0[3].flatMap(Double.init))
            }
            var children: [Int64: [Node]] = [:], roots: [Node] = []
            let rows = database.select("nodes", ["id", "kind", "entity_id", "parent_id", "deleted_at", "space_id"],
                                       order: ["order", "id"])
            for row in rows.prefix(SidebarImport.maximumItems) where row[4] == nil {
                guard let id = row[0].flatMap({ Int64($0) }), let kind = row[1] else { continue }
                let node = Node(id: id, kind: kind, entity: row[2], space: row[5] ?? "")
                if let text = row[3] {
                    if let parent = Int64(text) { children[parent, default: []].append(node) }
                } else {
                    roots.append(node)
                }
            }
            self.children = children
            rootNodes = roots
            var byKey: [String: Pane] = [:], byNode: [String: Pane] = [:]
            for row in database.select("content_panes", ["id", "node_id", "custom_title", "variant"]) {
                let pane = Pane(id: row[0], nodeID: row[1], customTitle: row[2].flatMap { $0.isEmpty ? nil : $0 }, variant: row[3])
                if let id = row[0] { byKey[id] = pane }
                if let node = row[1] { byNode[node] = pane }
            }
            panesByKey = byKey
            panesByNode = byNode
            var contents: [String: (url: String, title: String?)] = [:]
            for row in database.select("web_contents", ["id", "content_pane_id", "url", "title"], order: ["id"]) {
                if let pane = row[1], let url = row[2], !url.isEmpty { contents[pane] = (url, row[3]) }
            }
            contentByPane = contents
            var widthKeys: [String: String] = [:], widthNodes: [String: String] = [:]
            for row in database.select("tabs", ["id", "node_id", "split_view_widths"]) {
                guard let widths = row[2] else { continue }
                if let id = row[0] { widthKeys[id] = widths }
                if let node = row[1] { widthNodes[node] = widths }
            }
            widthsByKey = widthKeys
            widthsByNode = widthNodes
            var groupKeys: [String: Group] = [:], groupNodes: [String: Group] = [:]
            for row in database.select("tab_groups", ["id", "node_id", "title", "icon"]) {
                let group = Group(title: row[2].flatMap { $0.isEmpty ? nil : $0 }, icon: row[3])
                if let id = row[0] { groupKeys[id] = group }
                if let node = row[1] { groupNodes[node] = group }
            }
            groupsByKey = groupKeys
            groupsByNode = groupNodes
        }

        func roots(kind: String, space: String) -> [Node] {
            let known = Set(spaces.map(\.id))
            return rootNodes.filter { node in
                node.kind == kind && (node.space == space || (!known.contains(node.space) && spaces.count == 1))
            }
        }

        func pane(for node: Node) -> Pane? {
            panesByNode[String(node.id)] ?? node.entity.flatMap { panesByKey[$0] }
        }

        func content(for node: Node, pane: Pane?) -> (url: String, title: String?)? {
            for key in [pane?.id, node.entity, pane?.nodeID, String(node.id)].compactMap({ $0 }) {
                if let content = contentByPane[key] { return content }
            }
            return nil
        }

        func widths(for node: Node) -> [Double]? {
            guard let text = widthsByNode[String(node.id)] ?? node.entity.flatMap({ widthsByKey[$0] }),
                  let values = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Any] else { return nil }
            let numbers = values.compactMap { ($0 as? NSNumber)?.doubleValue }
            return numbers.count == values.count ? numbers : nil
        }

        func group(for node: Node) -> Group? {
            groupsByNode[String(node.id)] ?? node.entity.flatMap { groupsByKey[$0] }
        }
    }

    private struct Builder {
        let tree: Tree
        var skipped = 0
        private var visited = Set<Int64>()

        init(tree: Tree) { self.tree = tree }

        mutating func items(roots: [Tree.Node], flatten: Bool) -> [SidebarImport.Item] {
            roots.flatMap { items(under: $0, depth: 0, flatten: flatten) }
        }

        mutating func flatTabs(roots: [Tree.Node]) -> [SidebarImport.Tab] {
            items(roots: roots, flatten: true).flatMap { item -> [SidebarImport.Tab] in
                if case .tab(let tab) = item { return [tab] }
                return item.splitTabs ?? []
            }
        }

        private mutating func items(under parent: Tree.Node, depth: Int, flatten: Bool) -> [SidebarImport.Item] {
            guard depth < SidebarImport.maximumDepth, visited.insert(parent.id).inserted else { skipped += 1; return [] }
            var result: [SidebarImport.Item] = []
            for child in tree.children[parent.id] ?? [] {
                switch child.kind {
                case "tab": result += tabItems(child)
                case "group":
                    let nested = items(under: child, depth: depth + 1, flatten: flatten)
                    if flatten { result += nested }
                    else {
                        let group = tree.group(for: child)
                        result.append(.folder(title: group?.title ?? "Folder", icon: Self.icon(group?.icon),
                                              children: nested, isExpanded: true))
                    }
                default: continue
                }
            }
            return result
        }

        private mutating func tabItems(_ node: Tree.Node) -> [SidebarImport.Item] {
            guard visited.insert(node.id).inserted else { return [] }
            let panes = (tree.children[node.id] ?? []).filter { $0.kind == "content_pane" }
            var members: [(index: Int, tab: SidebarImport.Tab)] = []
            for (index, pane) in panes.enumerated() {
                let row = tree.pane(for: pane)
                if row?.variant == "new_tab_page" { continue }
                guard let content = tree.content(for: pane, pane: row) else { continue }
                guard let tab = SidebarImport.Tab.web(url: content.url, title: content.title, customTitle: row?.customTitle) else {
                    skipped += 1; continue
                }
                members.append((index, tab))
            }
            guard members.count > 1 else { return members.map { .tab($0.tab) } }
            let chosen = Array(members.prefix(DiaSidebarReader.maximumSplitPanes))
            let rest = members.dropFirst(DiaSidebarReader.maximumSplitPanes).map { SidebarImport.Item.tab($0.tab) }
            var factors = Array(repeating: 1 / Double(chosen.count), count: chosen.count)
            if let widths = tree.widths(for: node), widths.count == panes.count,
               let normalized = BrowserSplitLayout.normalized(chosen.map { widths[$0.index] }, count: chosen.count) {
                factors = normalized
            }
            return [.split(title: nil, icon: nil, tabs: chosen.map(\.tab), orientation: .horizontal, widthFactors: factors)] + rest
        }

        private static func icon(_ text: String?) -> SidebarGroupIcon? {
            guard let text, let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return nil }
            let icon: SidebarGroupIcon?
            if let emoji = object["emoji"] as? String { icon = .emoji(emoji) }
            else if let symbol = object["symbol"] as? String { icon = .symbol(symbol) }
            else { icon = nil }
            return icon?.isValid == true ? icon : nil
        }
    }

    private final class Database {
        private var handle: OpaquePointer?

        init?(path: String) {
            guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                sqlite3_close(handle)
                return nil
            }
        }

        deinit { sqlite3_close(handle) }

        func columns(_ table: String) -> Set<String> {
            Set((rows("PRAGMA table_info(\"\(table)\")") ?? []).compactMap { $0.count > 1 ? $0[1] : nil })
        }

        func select(_ table: String, _ wanted: [String], order: [String] = []) -> [[String?]] {
            let present = columns(table)
            guard !present.isEmpty else { return [] }
            let list = wanted.map { present.contains($0) ? "\"\($0)\"" : "NULL" }.joined(separator: ", ")
            let sort = order.filter(present.contains).map { "\"\($0)\"" }.joined(separator: ", ")
            return rows("SELECT \(list) FROM \"\(table)\"" + (sort.isEmpty ? "" : " ORDER BY " + sort)) ?? []
        }

        private func rows(_ sql: String) -> [[String?]]? {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            var result: [[String?]] = []
            while sqlite3_step(statement) == SQLITE_ROW, result.count < SidebarImport.maximumItems {
                result.append((0..<sqlite3_column_count(statement)).map { column in
                    guard sqlite3_column_type(statement, column) != SQLITE_NULL,
                          let text = sqlite3_column_text(statement, column) else { return nil }
                    return String(cString: text)
                })
            }
            return result
        }
    }
}
