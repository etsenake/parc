import Foundation

package enum FirefoxSidebarReader {
    typealias Item = SidebarImport.Item
    typealias Tab = SidebarImport.Tab

    package static func read(profiles: [SidebarImportProfile]) throws -> SidebarImport {
        SidebarImport.merged(profiles.map(read(profile:)))
    }

    static func read(profile: SidebarImportProfile) -> SidebarImport {
        var builder = Builder()
        var warnings: [String] = []
        var session: FirefoxSession?
        do { session = try FirefoxSession.read(profile: profile.directory) } catch {
            warnings.append("Firefox keeps the open tabs in \(profile.name) encrypted, so they stayed behind.")
        }
        let folder = profile.directory.lastPathComponent
        var spaces: [SidebarImport.Space] = []
        var spaceIDs: [Int: String] = [:]
        for (index, window) in (session?.windows ?? []).enumerated() {
            let items = builder.window(window)
            guard !items.pinned.isEmpty || !items.today.isEmpty else { continue }
            let id = spaces.isEmpty ? "firefox:\(folder):home" : "firefox:\(folder):window:\(spaces.count)"
            spaceIDs[index] = id
            spaces.append(SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: profile.key, pinned: items.pinned,
                                              id: id, today: items.today, placement: spaces.isEmpty ? .profileHome : .new))
        }
        let saved = (session?.savedGroups ?? []).compactMap { builder.savedGroup($0) }
        if let first = spaces.first, !saved.isEmpty {
            spaces[0] = SidebarImport.Space(title: first.title, icon: first.icon, theme: first.theme, profile: first.profile,
                                            pinned: first.pinned + saved, id: first.id, today: first.today,
                                            placement: first.placement)
        } else if !saved.isEmpty {
            spaces.append(SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: profile.key, pinned: saved,
                                              id: "firefox:\(folder):home", placement: .profileHome))
        }
        let open = Set(spaces.flatMap { urls($0.pinned) + urls($0.today) }.map { SavedTabURLComparison.key($0) })
        var archive: [SidebarImport.ArchivedTab] = []
        for closed in session?.closedTabs ?? [] where !open.contains(SavedTabURLComparison.key(closed.tab.url)) {
            guard builder.take() else { continue }
            archive.append(SidebarImport.ArchivedTab(tab: closed.tab, archivedAt: closed.closedAt, reason: .manual,
                                                     spaceID: closed.window.flatMap { spaceIDs[$0] }, profile: profile.key))
        }
        let shortcuts = favorites(profile: profile.directory)
        var result = SidebarImport(spaces: spaces, favorites: shortcuts.isEmpty ? [] : [(key: profile.key, items: shortcuts)],
                                   archive: archive, skippedItemCount: builder.skipped)
        result.warnings = warnings
        return result
    }

    static func favorites(profile directory: URL) -> [Item] {
        let file = directory.appendingPathComponent("prefs.js")
        guard ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .max) <= 16 * 1024 * 1024,
              let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let prefix = "user_pref(\"browser.newtabpage.pinned\","
        guard let line = text.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix(prefix) }) else { return [] }
        let call = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard call.hasSuffix(");") else { return [] }
        let literal = call.dropLast(2).trimmingCharacters(in: .whitespaces)
        guard let json = (try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed)) as? String,
              let slots = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any] else { return [] }
        let tabs = slots.compactMap { slot -> Item? in
            guard let slot = slot as? [String: Any], let url = slot["url"] as? String,
                  let tab = Tab.web(url: url, title: slot["label"] as? String) else { return nil }
            return .tab(tab)
        }
        return Array(tabs.prefix(SidebarImport.maximumFavorites))
    }

    static func urls(_ items: [Item]) -> [String] {
        items.flatMap { item -> [String] in
            switch item {
            case .tab(let tab): return [tab.url]
            case .folder(_, _, let children, _): return urls(children)
            case .split(_, _, let tabs, _, _), .stackedSplit(_, _, let tabs, _, _): return tabs.map(\.url)
            }
        }
    }

    private struct Container {
        var entries: [(split: String?, tabs: [Tab])] = []

        mutating func add(_ tab: Tab, split: String?) {
            if let split, let index = entries.firstIndex(where: { $0.split == split }) {
                entries[index].tabs.append(tab)
            } else {
                entries.append((split, [tab]))
            }
        }

        var items: [Item] {
            entries.flatMap { entry -> [Item] in
                guard entry.split != nil, entry.tabs.count > 1 else { return entry.tabs.map { Item.tab($0) } }
                let members = Array(entry.tabs.prefix(4))
                return [.split(title: nil, icon: nil, tabs: members, orientation: .horizontal,
                               widthFactors: Array(repeating: 1 / Double(members.count), count: members.count))]
                    + entry.tabs.dropFirst(4).map { Item.tab($0) }
            }
        }
    }

    private struct Builder {
        private enum Slot { case tab(Tab), group(String) }

        var skipped = 0
        private var remaining = SidebarImport.maximumItems

        mutating func take(_ count: Int = 1) -> Bool {
            guard remaining >= count else { skipped += 1; return false }
            remaining -= count
            return true
        }

        mutating func window(_ window: [String: Any]) -> (pinned: [Item], today: [Item]) {
            var groups: [String: [String: Any]] = [:]
            for group in FirefoxSession.list(window["groups"]).prefix(SidebarImport.maximumItems) {
                if let id = FirefoxSession.key(group["id"]), groups[id] == nil { groups[id] = group }
            }
            var slots: [Slot] = []
            var members: [String: Container] = [:]
            var today = Container()
            let states = FirefoxSession.list(window["tabs"])
            for (offset, state) in states.enumerated() {
                guard remaining > 0 else { skipped += states.count - offset; break }
                guard let tab = FirefoxSession.tab(state) else { skipped += 1; continue }
                if state["pinned"] as? Bool == true {
                    if take() { slots.append(.tab(tab)) }
                    continue
                }
                let split = FirefoxSession.key(state["splitViewId"])
                if let group = FirefoxSession.key(state["groupId"]), groups[group] != nil {
                    let opens = members[group] == nil
                    guard take(opens ? 2 : 1) else { continue }
                    if opens { slots.append(.group(group)) }
                    members[group, default: Container()].add(tab, split: split)
                } else if take() {
                    today.add(tab, split: split)
                }
            }
            let pinned = slots.compactMap { slot -> Item? in
                switch slot {
                case .tab(let tab): return .tab(tab)
                case .group(let id):
                    guard let group = groups[id], let children = members[id]?.items else { return nil }
                    return Self.folder(group, children: children, isExpanded: group["collapsed"] as? Bool != true)
                }
            }
            return (pinned, today.items)
        }

        mutating func savedGroup(_ group: [String: Any]) -> Item? {
            let records = FirefoxSession.list(group["tabs"])
            guard !records.isEmpty else { return nil }
            guard take() else { skipped += records.count - 1; return nil }
            var container = Container()
            for (offset, record) in records.enumerated() {
                guard remaining > 0 else { skipped += records.count - offset; break }
                guard let state = record["state"] as? [String: Any], let tab = FirefoxSession.tab(state) else {
                    skipped += 1; continue
                }
                remaining -= 1
                container.add(tab, split: FirefoxSession.key(state["splitViewId"]))
            }
            let children = container.items
            if children.isEmpty { remaining += 1 }
            return children.isEmpty ? nil : Self.folder(group, children: children, isExpanded: false)
        }

        private static func folder(_ group: [String: Any], children: [Item], isExpanded: Bool) -> Item {
            let name = (group["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .folder(title: name.isEmpty ? "Tab Group" : name, icon: nil, children: children, isExpanded: isExpanded)
        }
    }
}
