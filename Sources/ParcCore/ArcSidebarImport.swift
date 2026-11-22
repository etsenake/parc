import Foundation

package struct ArcSidebarImport: Equatable {
    package enum ProfileKey: Hashable { case standard; case custom(directory: String) }

    package struct Tab: Equatable {
        package let title: String
        package let url: String
        package var customTitle: String? = nil
        package var isMuted = false

        package init(title: String, url: String, customTitle: String? = nil, isMuted: Bool = false) {
            self.title = title
            self.url = url
            self.customTitle = customTitle
            self.isMuted = isMuted
        }
    }

    package indirect enum Item: Equatable {
        case tab(Tab)
        case folder(title: String, icon: SidebarGroupIcon?, children: [Item])
        case split(title: String?, icon: SidebarGroupIcon?, tabs: [Tab], orientation: SplitOrientation, widthFactors: [Double])
        case stackedSplit(title: String?, icon: SidebarGroupIcon?, tabs: [Tab], orientation: SplitOrientation, stacks: BrowserSplitStacks)

        package var splitTabs: [Tab]? {
            switch self {
            case .split(_, _, let tabs, _, _), .stackedSplit(_, _, let tabs, _, _): return tabs
            case .tab, .folder: return nil
            }
        }
    }

    package struct Space: Equatable {
        package let title: String?
        package let icon: SidebarGroupIcon?
        package let theme: SpaceTheme?
        package let profile: ProfileKey
        package let pinned: [Item]
        package var id: String? = nil
        package var today: [Item] = []

        package init(title: String?, icon: SidebarGroupIcon?, theme: SpaceTheme?, profile: ProfileKey, pinned: [Item], id: String? = nil, today: [Item] = []) {
            self.title = title
            self.icon = icon
            self.theme = theme
            self.profile = profile
            self.pinned = pinned
            self.id = id
            self.today = today
        }
    }

    package let spaces: [Space]
    package let favorites: [ProfileKey: [Item]]
    package var autoArchiveHours: [ProfileKey: Double] = [:]
    let skippedItemCount: Int

    package var profiles: [ProfileKey] {
        let referenced = spaces.map(\.profile) + favoriteOrder
        var result: [ProfileKey] = []
        for key in (referenced.contains(.standard) ? [.standard] : []) + referenced where !result.contains(key) {
            result.append(key)
        }
        return result
    }
    private let favoriteOrder: [ProfileKey]

    package static func profileKey(directory: String) -> ProfileKey {
        directory == "Default" ? .standard : .custom(directory: directory)
    }

    static let maximumDepth = 128
    static let maximumItems = 50_000

    package init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let containers = (root["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let container = containers.lazy.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] is [Any] }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var parser = Parser(container: container)
        var spaces: [Space] = []
        for (_, value) in Parser.pairs(container["spaces"]) {
            guard let space = value as? [String: Any], let profile = Self.profile(space["profile"]) else {
                parser.skipped += 1; continue
            }
            let customInfo = space["customInfo"] as? [String: Any]
            let pinned = Self.containerID(space, "pinned").flatMap { parser.items[$0] }
            let today = Self.containerID(space, "unpinned").flatMap { parser.items[$0] }
            spaces.append(Space(title: (space["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                icon: Self.icon(customInfo?["iconType"]),
                theme: Self.theme(customInfo?["windowTheme"] ?? NSNull()),
                profile: profile, pinned: pinned.map { parser.children(of: $0, depth: 0, inFavorites: false) } ?? [],
                id: (space["id"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                today: today.map { parser.children(of: $0, depth: 0, inFavorites: false) } ?? []))
        }
        var favorites: [ProfileKey: [Item]] = [:], order: [ProfileKey] = []
        for (key, id) in Parser.pairs(container["topAppsContainerIDs"]) {
            guard let key = Self.profile(key), favorites[key] == nil,
                  let id = id as? String, let item = parser.items[id] else { continue }
            favorites[key] = parser.children(of: item, depth: 0, inFavorites: true)
            order.append(key)
        }
        self.spaces = spaces
        self.favorites = favorites
        favoriteOrder = order
        skippedItemCount = parser.skipped
    }

    private static func containerID(_ space: [String: Any], _ section: String) -> String? {
        for key in ["containerIDs", "newContainerIDs"] {
            for (label, id) in Parser.pairs(space[key]) {
                let matches = label as? String == section || (label as? [String: Any])?[section] != nil
                if matches, let id = id as? String { return id }
            }
        }
        return nil
    }

    package static func autoArchiveHours(preferences: [String: Any], profiles: [ProfileKey]) -> [ProfileKey: Double] {
        func hours(_ value: Any?) -> Double? {
            let name = value as? String ?? (value as? [String: Any]).flatMap { $0.count == 1 ? $0.keys.first : nil }
            switch name {
            case "twentySeconds", "oneHour": return AutoArchiveInterval.oneHour.rawValue
            case "sixHours": return AutoArchiveInterval.sixHours.rawValue
            case "twelveHours": return AutoArchiveInterval.twelveHours.rawValue
            case "twentyFourHours": return AutoArchiveInterval.twentyFourHours.rawValue
            case "sevenDays": return AutoArchiveInterval.sevenDays.rawValue
            case "thirtyDays": return AutoArchiveInterval.thirtyDays.rawValue
            case "never": return AutoArchiveInterval.never.rawValue
            default: return nil
            }
        }
        func decoded(_ value: Any?) -> Any? {
            guard let text = value as? String, let data = text.data(using: .utf8) else { return value }
            return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? value
        }
        let global = hours(decoded(preferences["autoArchiveTimeThreshold"]))
        var perProfile: [ProfileKey: Double] = [:]
        let map = (decoded(preferences["autoArchiveTimeThresholdsPerProfile"]) as? [String: Any])?["thresholds"]
        for (key, value) in Parser.pairs(map) {
            if let key = profile(key), let value = hours(value) { perProfile[key] = value }
        }
        var result: [ProfileKey: Double] = [:]
        for key in profiles { result[key] = perProfile[key] ?? global }
        return result
    }

    package static func profile(_ value: Any?) -> ProfileKey? {
        guard let value = value as? [String: Any] else { return nil }
        if value["default"] != nil { return .standard }
        guard let id = (value["custom"] as? [String: Any])?["_0"] as? [String: Any],
              let directory = id["directoryBasename"] as? String, !directory.isEmpty, directory.utf8.count <= 255,
              !directory.hasPrefix("."), !directory.contains("/"),
              !directory.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return profileKey(directory: directory)
    }

    package static func icon(_ value: Any?) -> SidebarGroupIcon? {
        guard let value = value as? [String: Any] else { return nil }
        let icon: SidebarGroupIcon?
        if let emoji = value["emoji_v2"] as? String { icon = .emoji(emoji) }
        else if let number = value["emoji"] as? NSNumber, let scalar = Unicode.Scalar(number.uint32Value) {
            icon = .emoji(String(Character(scalar)))
        }
        else if let name = value["icon"] as? String { icon = SidebarIconType(rawValue: name).map { .icon($0) } }
        else if let name = value["symbol"] as? String { icon = .symbol(name) }
        else { icon = nil }
        return icon?.isValid == true ? icon : nil
    }

    package static func theme(_ value: Any) -> SpaceTheme? {
        if value is NSNull { return SpaceTheme() }
        guard let background = value as? [String: Any],
              let based = background["background"] as? [String: Any],
              let single = ((based["single"] as? [String: Any])?["_0"]
                ?? (based["appearanceBased"] as? [String: Any])?["light"]) as? [String: Any],
              let color = ((single["style"] as? [String: Any])?["color"] as? [String: Any])?["_0"] as? [String: Any],
              color.count == 1, let kind = color.keys.first,
              let configuration = (color[kind] as? [String: Any])?["_0"] as? [String: Any] else { return nil }
        let modifiers = configuration["modifiers"] as? [String: Any]
        var theme = SpaceTheme()
        switch kind {
        case "basicColor", "blendedSingleColor":
            guard let primary = Self.color(configuration["color"]) else { return nil }
            theme.primaryColor = primary; theme.colorCount = 1
        case "blendedGradient":
            guard let base = configuration["baseColors"] as? [Any], !base.isEmpty,
                  let primary = Self.color(base[0]) else { return nil }
            let overlay = (configuration["overlayColors"] as? [Any] ?? []).contains {
                (($0 as? [String: Any])?["alpha"] as? Double ?? 0) > 0
            }
            theme.primaryColor = primary
            theme.colorCount = min(3, base.count + (overlay ? 1 : 0))
            if theme.colorCount > 1, (configuration["wheel"] as? [String: Any])?["analogous"] != nil {
                theme.wheel = .analogous
            }
        default: return nil
        }
        if kind != "basicColor" {
            guard let modifiers, let noise = modifiers["noiseFactor"] as? Double, noise.isFinite,
                  let intensity = modifiers["intensityFactor"] as? Double, intensity.isFinite else { return nil }
            theme.noise = min(1, max(0, noise))
            theme.intensity = min(1, max(0, intensity))
            theme.texture = (modifiers["overlay"] as? String).flatMap(SpaceTheme.Texture.init(rawValue:)) ?? .grain
        }
        return theme.isValid ? theme : nil
    }

    package static func color(_ value: Any?) -> ThemeColor? {
        guard let value = value as? [String: Any],
              let red = value["red"] as? Double, let green = value["green"] as? Double,
              let blue = value["blue"] as? Double, [red, green, blue].allSatisfy(\.isFinite) else { return nil }
        if let color = ThemeColor(red: red, green: green, blue: blue) { return color }
        func linear(_ c: Double) -> Double {
            let m = abs(c)
            return (m <= 0.04045 ? m / 12.92 : pow((m + 0.055) / 1.055, 2.4)) * (c < 0 ? -1 : 1)
        }
        func encoded(_ c: Double) -> Double {
            let m = min(1, max(0, c))
            return m <= 0.0031308 ? m * 12.92 : 1.055 * pow(m, 1 / 2.4) - 0.055
        }
        let r = linear(red), g = linear(green), b = linear(blue)
        return ThemeColor(red: encoded(0.8224619687 * r + 0.1775380313 * g),
                          green: encoded(0.0331941989 * r + 0.9668058011 * g),
                          blue: encoded(0.0170826307 * r + 0.0723974407 * g + 0.9105199286 * b),
                          colorSpace: .displayP3)
    }

    private struct Parser {
        var items: [String: [String: Any]] = [:]
        var skipped = 0
        private var used = Set<String>()

        init(container: [String: Any]) {
            for (id, value) in Self.pairs(container["items"]) {
                guard let id = id as? String, let item = value as? [String: Any], items[id] == nil,
                      items.count < ArcSidebarImport.maximumItems else { skipped += 1; continue }
                items[id] = item
            }
        }

        static func pairs(_ value: Any?) -> [(Any, Any)] {
            guard let array = value as? [Any] else { return [] }
            return stride(from: 0, to: array.count - 1, by: 2).map { (array[$0], array[$0 + 1]) }
        }

        private mutating func take(_ id: Any) -> (id: String, item: [String: Any])? {
            guard let id = id as? String, let item = items[id], used.insert(id).inserted else { skipped += 1; return nil }
            return (id, item)
        }

        private static func data(_ item: [String: Any], _ kind: String) -> [String: Any]? {
            (item["data"] as? [String: Any])?[kind] as? [String: Any]
        }

        mutating func children(of container: [String: Any], depth: Int, inFavorites: Bool) -> [Item] {
            guard depth < ArcSidebarImport.maximumDepth else { skipped += 1; return [] }
            var result: [Item] = []
            for child in container["childrenIds"] as? [Any] ?? [] {
                guard let taken = take(child) else { continue }
                result += item(taken.item, depth: depth + 1, inFavorites: inFavorites)
            }
            return result
        }

        private mutating func item(_ item: [String: Any], depth: Int, inFavorites: Bool) -> [Item] {
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if Self.data(item, "tab") != nil { return tab(item).map { [.tab($0)] } ?? [] }
            if let list = Self.data(item, "list"), !inFavorites {
                let icon = ArcSidebarImport.icon((list["customInfo"] as? [String: Any])?["iconType"])
                return [.folder(title: title ?? "Imported folder", icon: icon,
                                children: children(of: item, depth: depth, inFavorites: false))]
            }
            if let split = Self.data(item, "splitView") {
                var entries: [SplitEntry] = []
                for child in item["childrenIds"] as? [Any] ?? [] {
                    guard let taken = take(child) else { continue }
                    if let nested = Self.data(taken.item, "splitView"), depth + 1 < ArcSidebarImport.maximumDepth {
                        let found = nestedTabs(of: taken.item, depth: depth + 1)
                        if found.tabs.isEmpty { skipped += 1; continue }
                        entries.append(SplitEntry(id: taken.id, tabs: found.tabs, orientation: Self.orientation(nested),
                                                  weights: Self.weights(nested), deeper: found.deeper))
                    } else if Self.data(taken.item, "tab") == nil { drop(taken.item, depth: depth + 1) }
                    else if let tab = tab(taken.item) {
                        entries.append(SplitEntry(id: taken.id, tabs: [(taken.id, tab)], orientation: nil, weights: [:], deeper: false))
                    }
                }
                let tabs = entries.flatMap(\.tabs)
                let members = Array(tabs.prefix(4)), rest = tabs.dropFirst(4).map { Item.tab($0.tab) }
                guard members.count > 1 else { return members.map { .tab($0.tab) } }
                let weights = Self.weights(split)
                let orientation = Self.orientation(split)
                let icon = ArcSidebarImport.icon((split["customInfo"] as? [String: Any])?["iconType"])
                if entries.contains(where: { $0.orientation != nil }) {
                    return Self.nestedSplit(title: title, icon: icon, orientation: orientation, weights: weights, entries: entries)
                }
                let factors = BrowserSplitLayout.normalized(members.map { weights[$0.id] ?? 1 }, count: members.count)
                    ?? Array(repeating: 1 / Double(members.count), count: members.count)
                return [.split(title: title, icon: icon, tabs: members.map(\.tab), orientation: orientation,
                               widthFactors: factors)] + rest
            }
            drop(item, depth: depth)
            return []
        }

        private struct SplitEntry {
            let id: String
            let tabs: [(id: String, tab: Tab)]
            let orientation: SplitOrientation?
            let weights: [String: Double]
            let deeper: Bool
        }

        private static func weights(_ split: [String: Any]) -> [String: Double] {
            var weights: [String: Double] = [:]
            for (key, value) in pairs(split["itemWidthFactors"]) {
                if let key = key as? String, let value = value as? Double { weights[key] = value }
            }
            return weights
        }

        private static func orientation(_ split: [String: Any]) -> SplitOrientation {
            (split["layoutOrientation"] as? String).flatMap(SplitOrientation.init(rawValue:)) ?? .horizontal
        }

        private mutating func nestedTabs(of item: [String: Any], depth: Int) -> (tabs: [(id: String, tab: Tab)], deeper: Bool) {
            var tabs: [(id: String, tab: Tab)] = [], deeper = false
            for child in item["childrenIds"] as? [Any] ?? [] {
                guard let taken = take(child) else { continue }
                if Self.data(taken.item, "splitView") != nil, depth + 1 < ArcSidebarImport.maximumDepth {
                    let found = nestedTabs(of: taken.item, depth: depth + 1).tabs
                    if found.isEmpty { skipped += 1 } else { tabs += found; deeper = true }
                } else if Self.data(taken.item, "tab") == nil { drop(taken.item, depth: depth + 1) }
                else if let tab = tab(taken.item) { tabs.append((taken.id, tab)) }
            }
            return (tabs, deeper)
        }

        private static func nestedSplit(title: String?, icon: SidebarGroupIcon?, orientation: SplitOrientation,
                                        weights: [String: Double], entries: [SplitEntry]) -> [Item] {
            var units: [(tabs: [Tab], factor: Double, stack: [Double])] = []
            for entry in entries where !entry.tabs.isEmpty {
                let outer = weights[entry.id] ?? 1
                guard let nested = entry.orientation else { units.append(([entry.tabs[0].tab], outer, [1])); continue }
                let raw = entry.tabs.map { entry.weights[$0.id] ?? 1 }
                let inner = BrowserSplitLayout.settled(raw) ?? Array(repeating: 1 / Double(raw.count), count: raw.count)
                if nested == orientation {
                    for (offset, member) in entry.tabs.enumerated() { units.append(([member.tab], outer * inner[offset], [1])) }
                } else {
                    units.append((entry.tabs.map(\.tab), outer, inner))
                }
            }
            if units.reduce(0, { $0 + $1.tabs.count }) <= 4, !entries.contains(where: \.deeper) {
                let shaped = BrowserSplitLayout.shape(orientation: orientation, sizes: units.map(\.tabs.count),
                                                      factors: units.map(\.factor), stackFactors: units.map(\.stack))
                let tabs = units.flatMap(\.tabs)
                if let stacks = shaped.stacks {
                    return [.stackedSplit(title: title, icon: icon, tabs: tabs, orientation: shaped.orientation, stacks: stacks)]
                }
                return [.split(title: title, icon: icon, tabs: tabs, orientation: shaped.orientation, widthFactors: shaped.widthFactors)]
            }
            let flat = units.flatMap { unit in unit.tabs.indices.map { (tab: unit.tabs[$0], weight: unit.factor * unit.stack[$0]) } }
            let members = Array(flat.prefix(4)), rest = flat.dropFirst(4).map { Item.tab($0.tab) }
            let factors = BrowserSplitLayout.normalized(members.map(\.weight), count: members.count)
                ?? Array(repeating: 1 / Double(members.count), count: members.count)
            return [.split(title: title, icon: icon, tabs: members.map(\.tab), orientation: orientation, widthFactors: factors)] + rest
        }

        private mutating func drop(_ item: [String: Any], depth: Int) {
            skipped += 1
            guard depth < ArcSidebarImport.maximumDepth else { return }
            for child in item["childrenIds"] as? [Any] ?? [] {
                if let taken = take(child) { drop(taken.item, depth: depth + 1) }
            }
        }

        private mutating func tab(_ item: [String: Any]) -> Tab? {
            let tab = Self.data(item, "tab") ?? [:]
            let saved = tab["savedURL"] as? String ?? ""
            let value = BrowserInternalURL.publicString(saved)
            guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
                  ["https", "http", "file"].contains(scheme) || (scheme == "parc" && saved.lowercased().hasPrefix("chrome://")),
                  scheme == "file" || url.host?.isEmpty == false else { skipped += 1; return nil }
            let savedTitle = (tab["savedTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Tab(title: savedTitle ?? url.host ?? value, url: value,
                       customTitle: (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                       isMuted: tab["savedMuteStatus"] as? String == "mute")
        }
    }
}

extension ArcSidebarImport {
    package struct Result {
        package var state: BrowserState
        package var destinations: [ProfileKey: BrowserImportDestination]

        package init(state: BrowserState, destinations: [ProfileKey: BrowserImportDestination]) {
            self.state = state
            self.destinations = destinations
        }
    }

    func inserting(into state: BrowserState, profiles: [(key: ProfileKey, name: String)],
                   standardProfileID: UUID, target: (key: ProfileKey, profileID: UUID)? = nil, at date: Date) throws -> Result {
        func live(_ id: UUID) -> Bool {
            state.profiles.contains { $0.id == id } && !state.profileRemovals.contains { $0.profileID == id }
        }
        guard live(standardProfileID), target.map({ live($0.profileID) }) != false else { throw CocoaError(.userCancelled) }
        var next = state
        var mapped: [ProfileKey: UUID] = [:], names: [ProfileKey: String] = [:]
        for (key, rawName) in profiles where mapped[key] == nil {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            names[key] = name.isEmpty ? "Imported Profile" : name
            if let target, target.key == key {
                mapped[key] = target.profileID
                names[key] = next.profiles.first { $0.id == target.profileID }?.name ?? names[key]
                continue
            }
            if key == .standard && target == nil { mapped[key] = standardProfileID; continue }
            if let existing = next.profiles.first(where: { profile in live(profile.id)
                && profile.id != standardProfileID && profile.id != target?.profileID && !mapped.values.contains(profile.id)
                && profile.name.caseInsensitiveCompare(names[key]!) == .orderedSame }) {
                mapped[key] = existing.id
            } else {
                let profile = BrowserProfile(id: UUID(), name: names[key]!, autoArchiveHours: next.autoArchiveDefaultHours)
                next.profiles.append(profile); mapped[key] = profile.id
            }
        }

        var destinations: [ProfileKey: BrowserImportDestination] = [:]
        func appendSpace(title: String?, icon: SidebarGroupIcon?, theme: SpaceTheme?, profileID: UUID) -> UUID {
            var space = BrowserSpace(id: UUID(), name: title ?? "", symbol: "circle.fill", color: "B9B5D4", profileID: profileID)
            space.customIcon = icon
            if let theme { space.theme = theme }
            space.updateDisplayName(position: next.spaces.count)
            next.spaces.append(space)
            return space.id
        }
        func makeTab(_ tab: Tab, spaceID: UUID, profileID: UUID, kind: TabKind, folderID: UUID?) -> UUID {
            let id = UUID()
            next.tabs.append(BrowserTab(id: id, spaceID: spaceID, profileID: profileID, url: tab.url, title: tab.title,
                kind: kind, folderID: folderID, createdAt: date, lastAccessed: date,
                savedURL: tab.url, savedTitle: tab.title, customTitle: tab.customTitle, isMuted: tab.isMuted))
            return id
        }
        func makeSplit(title: String?, icon: SidebarGroupIcon?, tabs: [Tab], orientation: SplitOrientation,
                       factors: [Double], stacks: BrowserSplitStacks? = nil,
                       spaceID: UUID, profileID: UUID, kind: TabKind, folderID: UUID?) -> SidebarItemReference {
            let ids = tabs.map { makeTab($0, spaceID: spaceID, profileID: profileID, kind: kind, folderID: folderID) }
            next.splitLayouts.append(BrowserSplitLayout(id: UUID(), customTitle: title, customIcon: icon, spaceID: spaceID,
                tabIDs: ids, orientation: orientation, widthFactors: stacks?.flattenedFactors ?? factors, stacks: stacks))
            return .tab(ids[0])
        }
        func insertPinned(_ items: [Item], spaceID: UUID, profileID: UUID, folderID: UUID?) {
            let location = SidebarContainerLocation(spaceID: spaceID, folderID: folderID, section: .pinned)
            var order = next.sidebarItemOrder[location.key] ?? []
            for item in items {
                switch item {
                case .tab(let tab):
                    order.append(.tab(makeTab(tab, spaceID: spaceID, profileID: profileID, kind: .pinned, folderID: folderID)))
                case let .folder(title, icon, children):
                    let folder = BrowserFolder(id: UUID(), spaceID: spaceID, name: title, parentID: folderID, customIcon: icon)
                    next.folders.append(folder)
                    order.append(.folder(folder.id))
                    insertPinned(children, spaceID: spaceID, profileID: profileID, folderID: folder.id)
                case let .split(title, icon, tabs, orientation, factors):
                    order.append(makeSplit(title: title, icon: icon, tabs: tabs, orientation: orientation, factors: factors,
                                           spaceID: spaceID, profileID: profileID, kind: .pinned, folderID: folderID))
                case let .stackedSplit(title, icon, tabs, orientation, stacks):
                    order.append(makeSplit(title: title, icon: icon, tabs: tabs, orientation: orientation,
                                           factors: stacks.flattenedFactors, stacks: stacks,
                                           spaceID: spaceID, profileID: profileID, kind: .pinned, folderID: folderID))
                }
            }
            next.sidebarItemOrder[location.key] = order
        }

        func insertToday(_ items: [Item], spaceID: UUID, profileID: UUID) {
            let location = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .today)
            var order = next.sidebarItemOrder[location.key] ?? []
            func append(_ items: [Item]) {
                for item in items {
                    switch item {
                    case .tab(let tab):
                        order.append(.tab(makeTab(tab, spaceID: spaceID, profileID: profileID, kind: .today, folderID: nil)))
                    case .folder(_, _, let children): append(children)
                    case let .split(title, icon, tabs, orientation, factors):
                        order.append(makeSplit(title: title, icon: icon, tabs: tabs, orientation: orientation, factors: factors,
                                               spaceID: spaceID, profileID: profileID, kind: .today, folderID: nil))
                    case let .stackedSplit(title, icon, tabs, orientation, stacks):
                        order.append(makeSplit(title: title, icon: icon, tabs: tabs, orientation: orientation,
                                               factors: stacks.flattenedFactors, stacks: stacks,
                                               spaceID: spaceID, profileID: profileID, kind: .today, folderID: nil))
                    }
                }
            }
            append(items)
            next.sidebarItemOrder[location.key] = order
        }
        func pinnedKeys(_ items: [Item]) -> [String] {
            items.flatMap { item -> [String] in
                switch item {
                case .tab(let tab): return [SavedTabURLComparison.key(tab.url)]
                case .folder(_, _, let children): return pinnedKeys(children)
                case .split(_, _, let tabs, _, _), .stackedSplit(_, _, let tabs, _, _): return tabs.map { SavedTabURLComparison.key($0.url) }
                }
            }.sorted()
        }
        func alreadyImported(_ space: Space, profileID: UUID) -> BrowserSpace? {
            if let arcID = space.id, let spaceID = state.arcImportedSpaces[arcID] {
                return state.spaces.first { $0.id == spaceID && $0.profileID == profileID }
            }
            let keys = pinnedKeys(space.pinned)
            guard !keys.isEmpty else { return nil }
            return state.spaces.first { existing in
                existing.profileID == profileID && !next.arcImportedSpaces.values.contains(existing.id)
                    && existing.title?.lowercased() == space.title?.lowercased()
                    && state.openTabs(where: { $0.spaceID == existing.id && $0.kind == .pinned })
                        .map { SavedTabURLComparison.key($0.savedURL) }.sorted() == keys
            }
        }

        for space in spaces {
            guard let profileID = mapped[space.profile] else { continue }
            if let existing = alreadyImported(space, profileID: profileID) {
                if let arcID = space.id { next.arcImportedSpaces[arcID] = existing.id }
                if destinations[space.profile] == nil { destinations[space.profile] = .init(spaceID: existing.id, profileID: profileID) }
                continue
            }
            let id = appendSpace(title: space.title, icon: space.icon, theme: space.theme, profileID: profileID)
            if destinations[space.profile] == nil { destinations[space.profile] = .init(spaceID: id, profileID: profileID) }
            insertPinned(space.pinned, spaceID: id, profileID: profileID, folderID: nil)
            insertToday(space.today, spaceID: id, profileID: profileID)
            if let arcID = space.id { next.arcImportedSpaces[arcID] = id }
        }
        var archiveChanged = false
        for (key, hours) in autoArchiveHours {
            guard let profileID = mapped[key], let index = next.profiles.firstIndex(where: { $0.id == profileID }),
                  next.profiles[index].autoArchiveHours != hours else { continue }
            next.profiles[index].autoArchiveHours = hours
            archiveChanged = true
        }
        if archiveChanged {
            next.autoArchiveEducationEligible = false
            let shared = Set(next.profiles.map(\.autoArchiveHours))
            if shared.count == 1, let hours = shared.first { next.autoArchiveDefaultHours = hours }
        }
        for (key, _) in profiles where destinations[key] == nil {
            guard let profileID = mapped[key] else { continue }
            let spaceID = next.spaces.first { $0.profileID == profileID }?.id
                ?? appendSpace(title: names[key], icon: nil, theme: nil, profileID: profileID)
            destinations[key] = .init(spaceID: spaceID, profileID: profileID)
        }
        for key in self.profiles {
            guard let items = favorites[key], !items.isEmpty else { continue }
            guard let destination = destinations[key] else { continue }
            let profileID = destination.profileID
            let location = SidebarContainerLocation(spaceID: destination.spaceID, folderID: nil, section: .favorite,
                                                    profileID: profileID)
            var order = SidebarHierarchy.children(in: location, state: next).map { item -> SidebarItemReference in
                if case .split(let id) = item, let anchor = next.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID {
                    return .tab(anchor)
                }
                return item
            }
            var existing = Set(next.openTabs(where: { $0.profileID == profileID && $0.kind == .favorite })
                .map { SavedTabURLComparison.key($0.savedURL) })
            for item in items {
                if case .tab(let tab) = item, existing.contains(SavedTabURLComparison.key(tab.url)) { continue }
                if let tabs = item.splitTabs, tabs.allSatisfy({ existing.contains(SavedTabURLComparison.key($0.url)) }) { continue }
                guard order.count < 12 else { continue }
                switch item {
                case .tab(let tab):
                    existing.insert(SavedTabURLComparison.key(tab.url))
                    order.append(.tab(makeTab(tab, spaceID: destination.spaceID, profileID: profileID, kind: .favorite, folderID: nil)))
                case let .split(title, icon, tabs, orientation, factors):
                    let fresh = tabs.indices.filter { existing.insert(SavedTabURLComparison.key(tabs[$0].url)).inserted }
                    if fresh.count == 1 {
                        order.append(.tab(makeTab(tabs[fresh[0]], spaceID: destination.spaceID, profileID: profileID,
                                                  kind: .favorite, folderID: nil)))
                    } else {
                        let widths = fresh.count == tabs.count ? factors
                            : Array(repeating: 1 / Double(fresh.count), count: fresh.count)
                        order.append(makeSplit(title: title, icon: icon, tabs: fresh.map { tabs[$0] }, orientation: orientation,
                            factors: widths, spaceID: destination.spaceID, profileID: profileID, kind: .favorite, folderID: nil))
                    }
                case let .stackedSplit(title, icon, tabs, orientation, stacks):
                    let fresh = tabs.indices.filter { existing.insert(SavedTabURLComparison.key(tabs[$0].url)).inserted }
                    if fresh.count == 1 {
                        order.append(.tab(makeTab(tabs[fresh[0]], spaceID: destination.spaceID, profileID: profileID,
                                                  kind: .favorite, folderID: nil)))
                    } else {
                        let shape = tabs.map { _ in UUID() }
                        let whole = BrowserSplitLayout(id: UUID(), spaceID: destination.spaceID, tabIDs: shape,
                            orientation: orientation, widthFactors: stacks.flattenedFactors, stacks: stacks)
                        var part = BrowserSplitLayout(id: whole.id, spaceID: destination.spaceID, tabIDs: fresh.map { shape[$0] },
                            orientation: orientation, widthFactors: Array(repeating: 1 / Double(fresh.count), count: fresh.count),
                            stacks: nil)
                        part.restack(from: whole)
                        order.append(makeSplit(title: title, icon: icon, tabs: fresh.map { tabs[$0] }, orientation: part.orientation,
                            factors: part.widthFactors, stacks: part.stacks,
                            spaceID: destination.spaceID, profileID: profileID, kind: .favorite, folderID: nil))
                    }
                case .folder: break
                }
            }
            next.sidebarItemOrder[location.key] = order
        }
        return Result(state: next, destinations: destinations)
    }
}
