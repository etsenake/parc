import Foundation

struct ZenSidebarSession {
    typealias Item = SidebarImport.Item
    typealias Tab = SidebarImport.Tab

    private enum Entry { case tab(String, Tab), folder(String), split(String) }

    private struct Folder {
        let name: String
        let collapsed: Bool
        let parent: String?
        let isLive: Bool
        let isEssential: Bool
        let icon: SidebarGroupIcon?
        let workspace: String?
        let previous: (kind: String, id: String?)?
    }

    private struct Split {
        var layout: Any?
        var gridType: String?
        var parent: String?
    }

    let profile: SidebarImport.ProfileKey
    let profileFolder: String
    let containers: [Int: String]
    let separateEssentials: Bool
    private(set) var spaceUUIDs: [String] = []
    private var spaceRecords: [String: [String: Any]] = [:]
    private var folders: [String: Folder] = [:]
    private var folderOrder: [String] = []
    private var splits: [String: Split] = [:]
    private var emptyTabIDs = Set<String>()
    private var lists: [String: [Entry]] = [:]
    private var placed = Set<String>()
    private var rootOf: [String: String] = [:]
    private var essentials: [(context: Int, tab: Tab)] = []
    private var skipped = 0

    static func spaceID(_ uuid: String) -> String { "zen:" + uuid }

    init(root: [String: Any], profile: SidebarImport.ProfileKey, profileFolder: String, containers: [Int: String],
         separateEssentials: Bool) {
        self.profile = profile
        self.profileFolder = profileFolder
        self.containers = containers
        self.separateEssentials = separateEssentials
        for value in root["spaces"] as? [Any] ?? [] {
            guard let space = value as? [String: Any], let uuid = space["uuid"] as? String, !uuid.isEmpty,
                  spaceRecords[uuid] == nil else { skipped += 1; continue }
            spaceRecords[uuid] = space
            spaceUUIDs.append(uuid)
        }
        var splitParents: [String: String?] = [:]
        for case let folder as [String: Any] in root["folders"] as? [Any] ?? [] {
            guard let id = Self.identifier(folder["id"]) else { continue }
            for value in folder["emptyTabIds"] as? [Any] ?? [] {
                if let tabID = Self.identifier(value) { emptyTabIDs.insert(tabID) }
            }
            let parent = Self.identifier(folder["parentId"])
            if folder["splitViewGroup"] as? Bool == true { splitParents[id] = parent; continue }
            guard folders[id] == nil else { continue }
            let name = (folder["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let icon = (folder["userIcon"] as? String).map { SidebarGroupIcon.emoji($0) }.flatMap { $0.isValid ? $0 : nil }
            let info = folder["prevSiblingInfo"] as? [String: Any]
            folders[id] = Folder(name: name.isEmpty ? "Imported folder" : name, collapsed: folder["collapsed"] as? Bool == true,
                                 parent: parent, isLive: folder["isLiveFolder"] as? Bool == true,
                                 isEssential: folder["essential"] as? Bool == true, icon: icon,
                                 workspace: folder["workspaceId"] as? String,
                                 previous: (info?["type"] as? String).map { (kind: $0, id: Self.identifier(info?["id"])) })
            folderOrder.append(id)
        }
        for case let split as [String: Any] in root["splitViewData"] as? [Any] ?? [] {
            guard let id = Self.identifier(split["groupId"]), splits[id] == nil else { continue }
            splits[id] = Split(layout: split["layoutTree"], gridType: split["gridType"] as? String, parent: nil)
        }
        for (id, parent) in splitParents {
            splits[id, default: Split(layout: nil, gridType: nil, parent: nil)].parent = parent
        }
        walk(root["tabs"] as? [Any] ?? [])
        placeFoldersWithoutTabs()
    }

    private static func identifier(_ value: Any?) -> String? {
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func present(_ value: Any?) -> Bool {
        if let text = value as? String { return !text.isEmpty }
        return value is NSNumber
    }

    private mutating func walk(_ tabs: [Any]) {
        var seen = Set<String>()
        for (offset, value) in tabs.prefix(SidebarImport.maximumItems).enumerated() {
            guard let tab = value as? [String: Any] else { skipped += 1; continue }
            var id = Self.identifier(tab["zenSyncId"]) ?? "#\(offset)"
            if !seen.insert(id).inserted { id = "#\(offset)" }
            if tab["zenIsGlance"] as? Bool == true || Self.present(tab["zenLiveFolderItemId"]) { skipped += 1; continue }
            let placeholder = tab["zenIsEmpty"] as? Bool == true || emptyTabIDs.contains(id)
            if tab["zenEssential"] as? Bool == true {
                guard !placeholder else { continue }
                guard let parsed = Self.tab(tab, pinned: true) else { skipped += 1; continue }
                essentials.append((context: (tab["userContextId"] as? NSNumber)?.intValue ?? 0, tab: parsed))
                continue
            }
            guard let space = (tab["zenWorkspace"] as? String).flatMap({ spaceRecords[$0] == nil ? nil : $0 })
                    ?? spaceUUIDs.first else { skipped += 1; continue }
            let pinned = tab["pinned"] as? Bool == true
            let root = "\(space)|\(pinned ? "pinned" : "today")"
            let path = groupPath(Self.identifier(tab["groupId"]))
            if placeholder { place(path: path, root: root, tab: nil); continue }
            guard let parsed = Self.tab(tab, pinned: pinned) else {
                skipped += 1
                place(path: path, root: root, tab: nil)
                continue
            }
            place(path: path, root: root, tab: (id, parsed))
        }
    }

    private static func tab(_ tab: [String: Any], pinned: Bool) -> Tab? {
        let entries = (tab["entries"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let index = (tab["index"] as? NSNumber)?.intValue ?? entries.count
        let live = entries.isEmpty ? nil : entries[min(max(index, 1), entries.count) - 1]
        var url = live?["url"] as? String, title = live?["title"] as? String
        if pinned, let initial = (tab["_zenPinnedInitialState"] as? [String: Any])?["entry"] as? [String: Any],
           let saved = initial["url"] as? String, !saved.isEmpty, saved != "about:blank" {
            title = initial["title"] as? String ?? (saved == url ? title : nil)
            url = saved
        }
        guard let url else { return nil }
        return Tab.web(url: url, title: title, customTitle: tab["zenStaticLabel"] as? String,
                       isMuted: tab["muted"] as? Bool == true)
    }

    private func groupPath(_ groupID: String?) -> [String] {
        var chain: [String] = [], current = groupID
        if let id = current, let split = splits[id] {
            chain.append(id)
            current = split.parent
        }
        while let id = current, let folder = folders[id], !folder.isEssential, !chain.contains(id),
              chain.count < SidebarImport.maximumDepth {
            chain.append(id)
            current = folder.parent
        }
        return chain.reversed()
    }

    private mutating func place(path: [String], root: String, tab: (id: String, tab: Tab)?) {
        var list = root
        for group in path {
            let key = "\(root)|\(group)"
            if placed.insert(key).inserted {
                lists[list, default: []].append(splits[group] == nil ? .folder(group) : .split(group))
                if rootOf[group] == nil { rootOf[group] = root }
            }
            list = key
        }
        if let tab { lists[list, default: []].append(.tab(tab.id, tab.tab)) }
    }

    private mutating func placeFoldersWithoutTabs() {
        var pending = folderOrder.filter { rootOf[$0] == nil && folders[$0]?.isEssential == false }
        var progressed = true
        while progressed && !pending.isEmpty {
            progressed = false
            for id in pending {
                guard let folder = folders[id] else { continue }
                let root: String, list: String
                if let parent = folder.parent, folders[parent] != nil {
                    guard let parentRoot = rootOf[parent] else { continue }
                    root = parentRoot
                    list = "\(root)|\(parent)"
                } else {
                    guard let space = folder.workspace.flatMap({ spaceRecords[$0] == nil ? nil : $0 }) ?? spaceUUIDs.first
                    else { pending.removeAll { $0 == id }; continue }
                    root = "\(space)|pinned"
                    list = root
                }
                var entries = lists[list] ?? []
                var index = entries.count
                switch folder.previous?.kind {
                case "start": index = 0
                case "tab":
                    if let previous = folder.previous?.id, let found = entries.firstIndex(where: { entry in
                        if case .tab(let other, _) = entry { return other == previous }
                        return false
                    }) { index = found + 1 }
                case "group":
                    if let found = entries.firstIndex(where: { entry in
                        switch entry {
                        case .folder(let other), .split(let other): return other == folder.previous?.id
                        case .tab: return false
                        }
                    }) { index = found + 1 }
                default: break
                }
                entries.insert(.folder(id), at: index)
                lists[list] = entries
                placed.insert("\(root)|\(id)")
                rootOf[id] = root
                pending.removeAll { $0 == id }
                progressed = true
            }
        }
    }

    private mutating func items(list: String, root: String, depth: Int) -> [Item] {
        guard depth < SidebarImport.maximumDepth else { return [] }
        var result: [Item] = []
        for entry in lists[list] ?? [] {
            switch entry {
            case .tab(_, let tab): result.append(.tab(tab))
            case .folder(let id):
                guard let folder = folders[id] else { continue }
                let children = items(list: "\(root)|\(id)", root: root, depth: depth + 1)
                if folder.isLive && children.isEmpty { skipped += 1; continue }
                result.append(.folder(title: folder.name, icon: folder.icon, children: children, isExpanded: !folder.collapsed))
            case .split(let id):
                let members = (lists["\(root)|\(id)"] ?? []).compactMap { entry -> (id: String, tab: Tab)? in
                    if case .tab(let tabID, let tab) = entry { return (tabID, tab) }
                    return nil
                }
                result += Self.split(members, layout: splits[id].flatMap { ZenSplitLayout.parse($0.layout, depth: 0) },
                                     gridType: splits[id]?.gridType)
            }
        }
        return result
    }

    private static func split(_ members: [(id: String, tab: Tab)], layout parsed: ZenSplitLayout?, gridType: String?) -> [Item] {
        guard members.count > 1 else { return members.map { .tab($0.tab) } }
        var tabs: [String: Tab] = [:]
        for member in members where tabs[member.id] == nil { tabs[member.id] = member.tab }
        var remaining = Set(tabs.keys)
        let layout: ZenSplitLayout
        if let pruned = parsed?.pruned(keeping: &remaining), remaining.isEmpty, case .splitter = pruned {
            layout = pruned
        } else {
            layout = ZenSplitLayout.grid(gridType, ids: members.map(\.id))
        }
        return layout.items(tabs: tabs)
    }

    private func containerKey(_ context: Int) -> SidebarImport.ProfileKey {
        context != 0 && containers[context] != nil ? .extra("zen:\(profileFolder):\(context)") : profile
    }

    mutating func sidebar() -> SidebarImport {
        var spaces: [SidebarImport.Space] = [], used: [Int] = []
        for uuid in spaceUUIDs {
            guard let record = spaceRecords[uuid] else { continue }
            let context = (record["containerTabId"] as? NSNumber)?.intValue ?? 0
            let key = containerKey(context)
            if key != profile, !used.contains(context) { used.append(context) }
            let name = (record["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let icon = (record["icon"] as? String).map { SidebarGroupIcon.emoji($0) }.flatMap { $0.isValid ? $0 : nil }
            let pinnedRoot = "\(uuid)|pinned", todayRoot = "\(uuid)|today"
            let pinned = items(list: pinnedRoot, root: pinnedRoot, depth: 0)
            let today = items(list: todayRoot, root: todayRoot, depth: 0)
            spaces.append(SidebarImport.Space(title: name.isEmpty ? nil : name, icon: icon, theme: Self.theme(record["theme"]),
                profile: key, pinned: pinned, id: Self.spaceID(uuid), today: today,
                pinnedCollapsed: record["hasCollapsedPinnedTabs"] as? Bool == true))
        }
        var favorites: [(key: SidebarImport.ProfileKey, items: [Item])] = []
        for essential in essentials {
            let context = separateEssentials ? essential.context : 0
            let key = containerKey(context)
            if key != profile, !used.contains(context) { used.append(context) }
            if let index = favorites.firstIndex(where: { $0.key == key }) { favorites[index].items.append(.tab(essential.tab)) }
            else { favorites.append((key: key, items: [.tab(essential.tab)])) }
        }
        let extras = used.compactMap { context in
            containers[context].map { SidebarImport.ExtraProfile(key: containerKey(context), name: $0) }
        }
        return SidebarImport(spaces: spaces, favorites: favorites, extraProfiles: extras, skippedItemCount: skipped)
    }

    static func theme(_ value: Any?) -> SpaceTheme? {
        guard let theme = value as? [String: Any] else { return nil }
        let colors = (theme["gradientColors"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        guard let chosen = colors.first(where: { $0["isPrimary"] as? Bool == true }) ?? colors.first else { return nil }
        let channels = (chosen["c"] as? [Any] ?? []).prefix(3).compactMap { ($0 as? NSNumber)?.doubleValue }
        guard channels.count == 3,
              let color = ThemeColor(red: channels[0] / 255, green: channels[1] / 255, blue: channels[2] / 255) else { return nil }
        var result = SpaceTheme.singleColor(color)
        result.colorCount = min(3, colors.count)
        if let texture = (theme["texture"] as? NSNumber)?.doubleValue, texture.isFinite { result.noise = min(1, max(0, texture)) }
        return result.isValid ? result : nil
    }
}
