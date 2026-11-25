import Foundation

package enum SafariSidebarReader {
    package static func read(home: URL, profiles: [SidebarImportProfile]) throws -> SidebarImport {
        guard let primary = profiles.first?.key else { return SidebarImport(spaces: []) }
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let database = library.appendingPathComponent("Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db")
        let tabs = try SafariTabsDatabase.read(database) ?? SafariTabsDatabase()
        let bookmarks = SafariTabsBookmarks(file: library.appendingPathComponent("Safari/Bookmarks.plist"))
        var mapping = SafariTabsMapping(database: tabs, primary: primary)
        return mapping.sidebar(bookmarks: bookmarks)
    }
}

struct SafariTabsMapping {
    typealias Row = SafariTabsDatabase.Row
    typealias Tab = SidebarImport.Tab
    typealias Item = SidebarImport.Item
    typealias ProfileKey = SidebarImport.ProfileKey

    let database: SafariTabsDatabase
    let primary: ProfileKey
    private var budget = SidebarImport.maximumItems
    private var skipped = 0

    static let specialFolders: Set<String> = ["pinned", "privatePinned", "recentlyClosed"]

    init(database: SafariTabsDatabase, primary: ProfileKey) {
        self.database = database
        self.primary = primary
    }

    mutating func sidebar(bookmarks: SafariTabsBookmarks?) -> SidebarImport {
        let profileRows = children(0).filter { isProfile($0) && alive($0.id) }
        let extras = profileRows.filter { key(of: $0) != primary }
        var pinned: [ProfileKey: [Tab]] = [:], loose: [ProfileKey: [Tab]] = [:]
        for folder in pinnedFolders() {
            guard let key = profile(pinnedFolder: folder, profiles: profileRows) else { continue }
            for item in tabRows(folder.id).compactMap({ tab($0) }) where !(pinned[key] ?? []).contains(where: { $0.url == item.url }) {
                pinned[key, default: []].append(item)
            }
        }
        var seen = Set<Int64>()
        for window in database.windows where window.live {
            guard let key = profile(window: window) else { continue }
            for group in [window.local].compactMap({ $0 }) + (database.unnamed[window.id] ?? []) where seen.insert(group).inserted {
                guard let row = database.rows[group], row.type == 1, alive(group),
                      !database.privateGroups.contains(group) else { continue }
                loose[key, default: []] += tabRows(group).compactMap { tab($0) }
            }
        }
        var owners: [(key: ProfileKey, row: Row?)] = [(primary, nil)]
        for row in extras { owners.append((key(of: row), row)) }
        var spaces: [SidebarImport.Space] = []
        for owner in owners {
            let pinnedTabs = take(pinned[owner.key] ?? []), looseTabs = take(loose[owner.key] ?? [])
            if !pinnedTabs.isEmpty || !looseTabs.isEmpty {
                spaces.append(SidebarImport.Space(title: owner.row.map { name($0) }, icon: owner.row.flatMap { icon($0.attributes.symbol) },
                    theme: nil, profile: owner.key, pinned: pinnedTabs.map { Item.tab($0) },
                    id: "safari:loose:\(owner.row.map { identity($0) } ?? "DefaultProfile")", today: looseTabs.map { Item.tab($0) },
                    placement: owner.row == nil ? .profileHome : .new))
            }
            let containers = owner.row.map { [$0.id] } ?? ([0] + profileRows.filter { key(of: $0) == primary }.map(\.id))
            for group in containers.flatMap({ groups(in: $0) }) {
                spaces.append(space(group: group, profile: owner.key))
            }
        }
        var favorites: [(key: ProfileKey, items: [Item])] = []
        if let bookmarks {
            for owner in owners {
                let list: [String: Any]?
                if let row = owner.row { list = row.attributes.favoritesFolder.flatMap { bookmarks.list(identifier: $0) } }
                else { list = bookmarks.bar }
                let items = bookmarks.favorites(in: list)
                if !items.isEmpty { favorites.append((owner.key, items)) }
            }
        }
        var result = SidebarImport(spaces: spaces, favorites: favorites,
                                   extraProfiles: extras.map { SidebarImport.ExtraProfile(key: key(of: $0), name: name($0)) },
                                   skippedItemCount: skipped)
        if skipped > 0 {
            result.warnings.append("Safari has more open tabs than Parc can import in one go, so \(skipped) were left out.")
        }
        return result
    }

    private mutating func space(group: Row, profile: ProfileKey) -> SidebarImport.Space {
        let rows = tabRows(group.id)
        let pinned = take(rows.filter(\.attributes.isPinned).compactMap { pinnedTab($0) })
        let today = take(rows.filter { !$0.attributes.isPinned }.compactMap { tab($0) })
        let saved = take(children(group.id).filter { $0.type == 1 && $0.subtype == 1 && alive($0.id) }
            .flatMap { tabRows($0.id) }.compactMap { tab($0) })
        let folder: [Item] = saved.isEmpty ? []
            : [.folder(title: "Favorites", icon: nil, children: saved.map { Item.tab($0) }, isExpanded: false)]
        return SidebarImport.Space(title: group.title.flatMap { $0.isEmpty ? nil : $0 }, icon: icon(group.attributes.symbol),
                                   theme: nil, profile: profile, pinned: pinned.map { Item.tab($0) } + folder,
                                   id: group.uuid.isEmpty ? nil : "safari:\(group.uuid)", today: today.map { Item.tab($0) })
    }

    private mutating func take(_ tabs: [Tab]) -> [Tab] {
        let kept = Array(tabs.prefix(max(budget, 0)))
        budget -= kept.count
        skipped += tabs.count - kept.count
        return kept
    }

    private func children(_ id: Int64) -> [Row] {
        (database.children[id] ?? []).compactMap { database.rows[$0] }
    }

    private func tabRows(_ folder: Int64) -> [Row] {
        children(folder).filter { $0.type == 0 && $0.special == 0 && !$0.deleted && !$0.closed }
    }

    private func alive(_ id: Int64) -> Bool {
        var current = id
        for _ in 0...SidebarImport.maximumDepth {
            guard let row = database.rows[current] else { return current == 0 }
            if row.deleted || row.closed || row.special > 0 || [4, 5].contains(row.subtype) { return false }
            guard let parent = row.parent, parent != current else { return true }
            current = parent
        }
        return false
    }

    private func isProfile(_ row: Row) -> Bool {
        row.type == 1 && row.subtype == 2 && row.parent == 0
    }

    private func identity(_ profile: Row) -> String {
        profile.uuid.isEmpty ? String(profile.id) : profile.uuid
    }

    private func key(of profile: Row) -> ProfileKey {
        profile.uuid == "DefaultProfile" ? primary : .extra("safari:\(identity(profile))")
    }

    private func name(_ profile: Row) -> String {
        profile.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Safari Profile"
    }

    private func icon(_ symbol: String?) -> SidebarGroupIcon? {
        symbol.map { SidebarGroupIcon.symbol($0) }.flatMap { $0.isValid ? $0 : nil }
    }

    private func profile(window: SafariTabsDatabase.Window) -> ProfileKey? {
        guard let id = window.profile, id != 0 else { return primary }
        guard let row = database.rows[id], isProfile(row), alive(id) else { return nil }
        return key(of: row)
    }

    private func pinnedFolders() -> [Row] {
        database.rows.values.filter { row in
            row.type == 1 && (row.uuid == "pinned" || row.uuid.hasPrefix("pinned-")) && alive(row.id)
        }.sorted { first, second in
            (first.uuid == "pinned") != (second.uuid == "pinned") ? first.uuid == "pinned" : first.id < second.id
        }
    }

    private func profile(pinnedFolder folder: Row, profiles: [Row]) -> ProfileKey? {
        if folder.uuid == "pinned" { return primary }
        if let parent = folder.parent.flatMap({ database.rows[$0] }), isProfile(parent) { return key(of: parent) }
        let suffix = String(folder.uuid.dropFirst("pinned-".count))
        if suffix == "DefaultProfile" { return primary }
        return profiles.first { $0.uuid == suffix }.map { key(of: $0) }
    }

    private func groups(in container: Int64) -> [Row] {
        let inProfile = database.rows[container].map { isProfile($0) } ?? false
        return children(container).flatMap { child -> [Row] in
            if isGroup(child) { return [child] }
            if inProfile && child.type == 1 && child.subtype == 3 && alive(child.id) { return children(child.id).filter { isGroup($0) } }
            return []
        }
    }

    private func isGroup(_ row: Row) -> Bool {
        guard row.type == 1, row.subtype == 0, row.special == 0, !row.hidden, row.syncable, !row.attributes.isUnnamed,
              !Self.specialFolders.contains(row.uuid), !row.uuid.hasPrefix("pinned-"), !row.uuid.hasPrefix("fvs-"),
              row.title != "TopScopedBookmarkList" else { return false }
        let windowGroups = [database.unnamedGroups, database.localGroups, database.privateGroups]
        return !windowGroups.contains { $0.contains(row.id) } && alive(row.id)
    }

    private func tab(_ row: Row) -> Tab? {
        guard let url = webAddress(row.attributes.localURL) ?? webAddress(row.url) else { return nil }
        return .web(url: url, title: title(row))
    }

    private func pinnedTab(_ row: Row) -> Tab? {
        let pageTitle = title(row), pinnedTitle = row.attributes.pinnedTitle
        let custom = pinnedTitle == pageTitle ? nil : pinnedTitle
        if let address = row.attributes.pinnedAddress, let pinned = Tab.web(url: address, title: pageTitle, customTitle: custom) {
            return pinned
        }
        return tab(row).flatMap { Tab.web(url: $0.url, title: pageTitle, customTitle: custom) }
    }

    private func title(_ row: Row) -> String? {
        row.attributes.localTitle ?? row.title.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func webAddress(_ raw: String?) -> String? {
        guard let raw, let scheme = URL(string: raw)?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return raw
    }
}

struct SafariTabsBookmarks {
    let root: [String: Any]

    static let maximumBytes = 64 << 20

    init?(file: URL) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber,
              size.intValue <= Self.maximumBytes, let data = try? Data(contentsOf: file),
              let root = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        self.root = root
    }

    var bar: [String: Any]? {
        Self.nodes(root["Children"]).first { Self.isList($0) && $0["Title"] as? String == "BookmarksBar" }
    }

    func list(identifier: String) -> [String: Any]? {
        find(identifier, in: root, depth: 0)
    }

    func favorites(in list: [String: Any]?) -> [SidebarImport.Item] {
        var items: [SidebarImport.Item] = []
        for leaf in Self.nodes(list?["Children"]) where items.count < SidebarImport.maximumFavorites {
            guard leaf["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf", let url = leaf["URLString"] as? String,
                  let tab = SidebarImport.Tab.web(url: url, title: (leaf["URIDictionary"] as? [String: Any])?["title"] as? String)
            else { continue }
            items.append(.tab(tab))
        }
        return items
    }

    private func find(_ identifier: String, in node: [String: Any], depth: Int) -> [String: Any]? {
        guard depth <= SidebarImport.maximumDepth else { return nil }
        for child in Self.nodes(node["Children"]) where Self.isList(child) {
            if child["WebBookmarkUUID"] as? String == identifier
                || (child["Sync"] as? [String: Any])?["ServerID"] as? String == identifier { return child }
            if let found = find(identifier, in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func isList(_ node: [String: Any]) -> Bool {
        node["WebBookmarkType"] as? String == "WebBookmarkTypeList"
    }

    private static func nodes(_ value: Any?) -> [[String: Any]] {
        (value as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }
}
