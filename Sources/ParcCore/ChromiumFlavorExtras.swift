import Foundation

package enum ChromiumFlavorExtras {
    private static let maxPreferencesBytes = 32 * 1024 * 1024
    private static let maxFavorites = 12
    private static let containerPrefix = "containers+"

    package static func adjusted(_ session: ChromiumSession, flavor: ChromiumFlavor, profileDirectory: URL) -> ChromiumSession {
        switch flavor {
        case .helium: return heliumAdjusted(session)
        case .brave: return braveAdjusted(session, preferences: preferences(in: profileDirectory))
        case .vivaldi: return VivaldiExtras.adjusted(session, preferences: preferences(in: profileDirectory))
        default: return session
        }
    }

    package static func favorites(flavor: ChromiumFlavor, profileDirectory: URL) -> [SidebarImport.Item] {
        guard flavor == .brave else { return [] }
        let items = sidebarItems(in: preferences(in: profileDirectory))
        var result: [SidebarImport.Item] = []
        for item in items where isWebItem(item) && !openInPanel(item) {
            guard let url = item["url"] as? String,
                  let tab = SidebarImport.Tab.web(url: url, title: item["title"] as? String) else { continue }
            result.append(.tab(tab))
            if result.count == maxFavorites { break }
        }
        return result
    }

    package static func spaces(_ session: ChromiumSession, flavor: ChromiumFlavor, profile: SidebarImportProfile)
        -> [(space: SidebarImport.Space, windowTabs: [Int32: Set<Int32>])]? {
        switch flavor {
        case .vivaldi: return VivaldiExtras.spaces(session, preferences: preferences(in: profile.directory), profile: profile)
        case .opera, .operaGX: return OperaExtras.spaces(session, preferences: preferences(in: profile.directory), profile: profile)
        default: return nil
        }
    }

    private static func heliumAdjusted(_ session: ChromiumSession) -> ChromiumSession {
        var result = session
        var seen = Set<String>()
        for index in result.windows.indices {
            var windowSeen = Set<String>()
            var kept: [ChromiumSession.Tab] = []
            for var tab in result.windows[index].tabs {
                guard tab.pinned else {
                    kept.append(tab)
                    continue
                }
                if let home = tab.extraData["helium.pinned_tab_url"], !home.isEmpty { tab.url = home }
                if let id = tab.extraData["helium.pinned_tab_id"], !id.isEmpty {
                    if seen.contains(id) { continue }
                    windowSeen.insert(id)
                }
                kept.append(tab)
            }
            seen.formUnion(windowSeen)
            result.windows[index] = replacingTabs(result.windows[index], with: kept)
        }
        return result
    }

    private static func braveAdjusted(_ session: ChromiumSession, preferences: [String: Any]?) -> ChromiumSession {
        let shared = (value(in: preferences, path: ["brave", "tabs", "shared_pinned_tab"]) as? Bool) == true
        let panelURLs = Set(sidebarItems(in: preferences).filter { isWebItem($0) && openInPanel($0) }
            .compactMap { ($0["url"] as? String).map(comparable) })
        var result = session
        var seenPinned = Set<String>()
        for index in result.windows.indices {
            var windowPinned = Set<String>()
            var kept: [ChromiumSession.Tab] = []
            for var tab in result.windows[index].tabs {
                tab.url = strippingContainer(tab.url)
                if tab.pinned {
                    let key = comparable(tab.url)
                    if panelURLs.contains(key) { continue }
                    if shared {
                        if seenPinned.contains(key) { continue }
                        windowPinned.insert(key)
                    }
                }
                kept.append(tab)
            }
            seenPinned.formUnion(windowPinned)
            result.windows[index] = replacingTabs(result.windows[index], with: kept)
        }
        result.closedTabs = result.closedTabs.map {
            var tab = $0
            tab.url = strippingContainer(tab.url)
            return tab
        }
        return result
    }

    private static func replacingTabs(_ window: ChromiumSession.Window, with tabs: [ChromiumSession.Tab]) -> ChromiumSession.Window {
        guard tabs.count != window.tabs.count else {
            var copy = window
            copy.tabs = tabs
            return copy
        }
        let keptIDs = Set(tabs.map(\.id))
        let removedBefore = window.tabs.prefix(max(window.selectedIndex, 0)).filter { !keptIDs.contains($0.id) }.count
        var copy = window
        copy.tabs = tabs
        copy.selectedIndex = min(max(window.selectedIndex - removedBefore, 0), max(tabs.count - 1, 0))
        return copy
    }

    private static func strippingContainer(_ url: String) -> String {
        guard url.hasPrefix(containerPrefix), let colon = url.firstIndex(of: ":") else { return url }
        return String(url[url.index(after: colon)...])
    }

    private static func comparable(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private static func isWebItem(_ item: [String: Any]) -> Bool {
        (item["type"] as? NSNumber)?.intValue == 1
    }

    private static func openInPanel(_ item: [String: Any]) -> Bool {
        (item["open_in_panel"] as? Bool) == true
    }

    private static func sidebarItems(in preferences: [String: Any]?) -> [[String: Any]] {
        (value(in: preferences, path: ["brave", "sidebar", "sidebar_items"]) as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    fileprivate static func value(in preferences: [String: Any]?, path: [String]) -> Any? {
        var current: Any? = preferences
        for key in path {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[key]
        }
        return current
    }

    private static func preferences(in directory: URL) -> [String: Any]? {
        let file = directory.appendingPathComponent("Preferences")
        guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0, size <= maxPreferencesBytes,
              let data = try? Data(contentsOf: file, options: .mappedIfSafe),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

private enum VivaldiExtras {
    static let extKey = "vivaldi.ext"
    static let fixedTitleKey = "vivaldi.fixedTitle"
    static let maxExtBytes = 1024 * 1024
    static let maxTileTabs = 4
    static let stackedLayouts: Set<String> = ["column"]

    struct Workspace {
        let id: Double
        let name: String
        let emoji: String?
    }

    static func parsedExt(of tab: ChromiumSession.Tab) -> [String: Any] {
        guard let text = tab.extraData[extKey], text.utf8.count <= maxExtBytes,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    static func string(_ ext: [String: Any], _ key: String) -> String? {
        guard let value = ext[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    static func isDropped(_ ext: [String: Any]) -> Bool {
        if string(ext, "panelId") != nil || string(ext, "purpose") == "mail" { return true }
        if let flag = number(ext["flag"]), let bits = Int64(exactly: flag.rounded()), bits & 1 == 1 { return true }
        return false
    }

    static func workspaceID(_ ext: [String: Any]) -> Double? {
        guard let value = number(ext["workspaceId"]), value > 0 else { return nil }
        return value
    }

    static func workspaceSuffix(_ ext: [String: Any]) -> String {
        workspaceID(ext).map { String(Int64($0)) } ?? ""
    }

    static func makeToken(_ text: String) -> ChromiumToken {
        func hash(_ seed: UInt64) -> UInt64 {
            var value = seed
            for byte in text.utf8 {
                value ^= UInt64(byte)
                value = value &* 0x100000001b3
            }
            return value
        }
        return ChromiumToken(high: hash(0xcbf29ce484222325), low: hash(0x84222325cbf29ce4))
    }

    static func workspaces(_ preferences: [String: Any]?) -> [Workspace] {
        guard (ChromiumFlavorExtras.value(in: preferences, path: ["vivaldi", "workspaces", "enabled"]) as? Bool) != false,
              let list = ChromiumFlavorExtras.value(in: preferences, path: ["vivaldi", "workspaces", "list"]) as? [Any] else { return [] }
        var seen = Set<Double>()
        var result: [Workspace] = []
        for case let entry as [String: Any] in list {
            guard let id = number(entry["id"]), id > 0, id < 9_007_199_254_740_992, id == id.rounded(),
                  seen.insert(id).inserted else { continue }
            result.append(Workspace(id: id, name: (entry["name"] as? String) ?? "", emoji: string(entry, "emoji")))
        }
        return result
    }

    static func adjusted(_ session: ChromiumSession, preferences: [String: Any]?) -> ChromiumSession {
        let open = Set((ChromiumFlavorExtras.value(in: preferences, path: ["vivaldi", "tabs", "stacking", "open_accordions"]) as? [Any])?
            .compactMap { $0 as? String } ?? [])
        var result = session
        result.groups = [:]
        result.splits = [:]
        for index in result.windows.indices {
            var tabs: [ChromiumSession.Tab] = []
            var exts: [Int32: [String: Any]] = [:]
            for var tab in result.windows[index].tabs {
                let ext = parsedExt(of: tab)
                if isDropped(ext) { continue }
                tab.group = nil
                tab.split = nil
                if let title = string(ext, "fixedTitle") { tab.extraData[fixedTitleKey] = title }
                exts[tab.id] = ext
                tabs.append(tab)
            }
            stack(&tabs, exts: exts, open: open, groups: &result.groups)
            tile(&tabs, exts: exts, window: result.windows[index].id, splits: &result.splits)
            result.windows[index] = replacing(result.windows[index], with: tabs)
        }
        return result
    }

    static func stack(_ tabs: inout [ChromiumSession.Tab], exts: [Int32: [String: Any]], open: Set<String>,
                      groups: inout [ChromiumToken: ChromiumSession.Group]) {
        for index in tabs.indices where tabs[index].pinned {
            let ext = exts[tabs[index].id] ?? [:]
            guard let stack = string(ext, "group") else { continue }
            let token = makeToken("stack|\(stack)|\(workspaceSuffix(ext))")
            tabs[index].group = token
            let title = string(ext, "fixedGroupTitle")
            if groups[token] == nil {
                groups[token] = ChromiumSession.Group(title: title ?? "", color: 0, collapsed: !open.contains(stack))
            } else if groups[token]?.title.isEmpty == true, let title {
                groups[token]?.title = title
            }
        }
    }

    static func tile(_ tabs: inout [ChromiumSession.Tab], exts: [Int32: [String: Any]], window: Int32,
                     splits: inout [ChromiumToken: ChromiumSession.Split]) {
        var members: [String: [(position: Int, order: Double)]] = [:]
        var keys: [String] = []
        for index in tabs.indices {
            let ext = exts[tabs[index].id] ?? [:]
            guard let tiling = ext["tiling"] as? [String: Any], let id = string(tiling, "id") else { continue }
            let key = "tile|\(window)|\(id)|\(workspaceSuffix(ext))"
            if members[key] == nil { keys.append(key) }
            members[key, default: []].append((index, number(tiling["index"]) ?? Double(index)))
        }
        for key in keys {
            guard let group = members[key], group.count >= 2 else { continue }
            let ordered = group.enumerated().sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
                .prefix(maxTileTabs).map { $0.element.position }
            let positions = group.map { $0.position }.sorted().prefix(ordered.count)
            let moved = ordered.map { tabs[$0] }
            for (slot, tab) in zip(positions, moved) { tabs[slot] = tab }
            let layout = ((exts[moved[0].id]?["tiling"] as? [String: Any])?["layout"] as? String) ?? ""
            let token = makeToken(key)
            for slot in positions { tabs[slot].split = token }
            splits[token] = ChromiumSession.Split(ratio: 0.5, sideBySide: !stackedLayouts.contains(layout))
        }
    }

    static func replacing(_ window: ChromiumSession.Window, with tabs: [ChromiumSession.Tab]) -> ChromiumSession.Window {
        var copy = window
        let keptIDs = Set(tabs.map(\.id))
        let removedBefore = window.tabs.prefix(max(window.selectedIndex, 0)).filter { !keptIDs.contains($0.id) }.count
        copy.tabs = tabs
        copy.selectedIndex = min(max(window.selectedIndex - removedBefore, 0), max(tabs.count - 1, 0))
        return copy
    }

    static func spaces(_ session: ChromiumSession, preferences: [String: Any]?, profile: SidebarImportProfile)
        -> [(space: SidebarImport.Space, windowTabs: [Int32: Set<Int32>])]? {
        let list = workspaces(preferences)
        guard !list.isEmpty else { return nil }
        let folder = profile.directory.lastPathComponent
        let known = Set(list.map(\.id))
        var perWorkspace: [Double: [Int32: Set<Int32>]] = [:]
        var home: [Int32: Set<Int32>] = [:]
        for window in session.windows {
            for tab in window.tabs {
                let ext = parsedExt(of: tab)
                if isDropped(ext) { continue }
                if let id = workspaceID(ext), known.contains(id) {
                    perWorkspace[id, default: [:]][window.id, default: []].insert(tab.id)
                } else {
                    home[window.id, default: []].insert(tab.id)
                }
            }
        }
        var result: [(space: SidebarImport.Space, windowTabs: [Int32: Set<Int32>])] = []
        if !home.isEmpty {
            let space = SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: profile.key, pinned: [],
                                            id: "vivaldi:\(folder):default", placement: .profileHome)
            result.append((space, home))
        }
        for workspace in list {
            let icon = workspace.emoji.map { SidebarGroupIcon.emoji($0) }
            let space = SidebarImport.Space(title: workspace.name.isEmpty ? nil : workspace.name, icon: icon, theme: nil,
                                            profile: profile.key, pinned: [], id: "vivaldi:\(folder):\(Int64(workspace.id))")
            result.append((space, perWorkspace[workspace.id] ?? [:]))
        }
        return result
    }
}

private enum OperaExtras {
    static let stateKey = "workspaces_state"
    static let customIcon = "add-custom-icon"

    struct Workspace {
        let id: Int
        let name: String?
        let emoji: String?
        let visible: Bool
    }

    static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            return double.isFinite && double == double.rounded() && abs(double) < 1e9 ? Int(double) : nil
        }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func entry(_ container: Any?, id: Int) -> Any? {
        if let dictionary = container as? [String: Any] { return dictionary[String(id)] }
        if let list = container as? [Any], id >= 0, id < list.count { return list[id] }
        return nil
    }

    static func ids(_ container: Any?) -> [Int] {
        if let dictionary = container as? [String: Any] { return dictionary.keys.compactMap { Int($0) } }
        if let list = container as? [Any] { return Array(list.indices) }
        return []
    }

    static func workspaces(_ preferences: [String: Any]?) -> [Workspace] {
        let path = ["ui", "workspaces", "config"]
        func config(_ key: String) -> Any? { ChromiumFlavorExtras.value(in: preferences, path: path + [key]) }
        guard (config("enabled") as? Bool) != false else { return [] }
        let names = config("names")
        var order: [Int] = []
        var seen = Set<Int>()
        for value in (config("order") as? [Any]) ?? [] {
            if let id = integer(value), id >= 0, seen.insert(id).inserted { order.append(id) }
        }
        for id in ids(names).sorted() where seen.insert(id).inserted { order.append(id) }
        return order.map { id in
            let name = (entry(names, id: id) as? String).flatMap { $0.isEmpty ? nil : $0 }
            let custom = (entry(config("icons"), id: id) as? String) == customIcon
            let emoji = custom ? (entry(config("emoji_icons"), id: id) as? String).flatMap { $0.isEmpty ? nil : $0 } : nil
            let visible = (entry(config("visible_in_ui"), id: id) as? Bool) != false
            return Workspace(id: id, name: name, emoji: emoji, visible: visible)
        }
    }

    static func spaces(_ session: ChromiumSession, preferences: [String: Any]?, profile: SidebarImportProfile)
        -> [(space: SidebarImport.Space, windowTabs: [Int32: Set<Int32>])]? {
        let list = workspaces(preferences)
        guard let first = list.first else { return nil }
        let known = Set(list.map(\.id))
        var membership: [Int: [Int32: Set<Int32>]] = [:]
        for window in session.windows {
            for tab in window.tabs {
                let wanted = integer(tab.extraData[stateKey])
                let id = wanted.flatMap { known.contains($0) ? $0 : nil } ?? first.id
                membership[id, default: [:]][window.id, default: []].insert(tab.id)
            }
        }
        let folder = profile.directory.lastPathComponent
        return list.compactMap { workspace in
            let tabs = membership[workspace.id] ?? [:]
            guard workspace.visible || !tabs.isEmpty else { return nil }
            let space = SidebarImport.Space(title: workspace.name, icon: workspace.emoji.map { SidebarGroupIcon.emoji($0) },
                                            theme: nil, profile: profile.key, pinned: [], id: "opera:\(folder):\(workspace.id)")
            return (space, tabs)
        }
    }
}
