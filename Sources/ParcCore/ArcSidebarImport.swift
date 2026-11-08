import Foundation

///
/// tree, and each Profile's Favorites (`topApps`). Today tabs, notes, easels
/// and links Parc cannot open are left behind. Field names and shapes follow
///
/// skipped rather than failing the whole file.
struct ArcSidebarImport: Equatable {
    ///
    /// directory name under "User Data".
    enum ProfileKey: Hashable { case standard; case custom(directory: String) }

    struct Tab: Equatable {
        let title: String
        let url: String
        ///
        var customTitle: String? = nil
        var isMuted = false
    }

    indirect enum Item: Equatable {
        case tab(Tab)
        case folder(title: String, icon: SidebarGroupIcon?, children: [Item])
        case split(title: String?, icon: SidebarGroupIcon?, tabs: [Tab], orientation: SplitOrientation, widthFactors: [Double])
    }

    struct Space: Equatable {
        let title: String?
        let icon: SidebarGroupIcon?
        ///
        let theme: SpaceTheme?
        let profile: ProfileKey
        let pinned: [Item]
    }

    let spaces: [Space]
    let favorites: [ProfileKey: [Item]]
    /// Sidebar entries Parc cannot represent or that were malformed.
    let skippedItemCount: Int

    var profiles: [ProfileKey] {
        let referenced = spaces.map(\.profile) + favoriteOrder
        var result: [ProfileKey] = []
        for key in (referenced.contains(.standard) ? [.standard] : []) + referenced where !result.contains(key) {
            result.append(key)
        }
        return result
    }
    private let favoriteOrder: [ProfileKey]

    static func profileKey(directory: String) -> ProfileKey {
        directory == "Default" ? .standard : .custom(directory: directory)
    }

    static let maximumDepth = 128
    static let maximumItems = 50_000

    init(data: Data) throws {
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
            let pinned = Self.pinnedContainerID(space).flatMap { parser.items[$0] }
            spaces.append(Space(title: (space["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                icon: Self.icon(customInfo?["iconType"]),
                theme: Self.theme(customInfo?["windowTheme"] ?? NSNull()),
                profile: profile, pinned: pinned.map { parser.children(of: $0, depth: 0, inFavorites: false) } ?? []))
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

    /// The `pinned` entry of `containerIDs` (label, id pairs in either order),
    /// else the `{"pinned":{}}` entry of `newContainerIDs`.
    private static func pinnedContainerID(_ space: [String: Any]) -> String? {
        for key in ["containerIDs", "newContainerIDs"] {
            for (label, id) in Parser.pairs(space[key]) {
                let isPinned = label as? String == "pinned" || (label as? [String: Any])?["pinned"] != nil
                if isPinned, let id = id as? String { return id }
            }
        }
        return nil
    }

    static func profile(_ value: Any?) -> ProfileKey? {
        guard let value = value as? [String: Any] else { return nil }
        if value["default"] != nil { return .standard }
        // The directory is joined under the source's "User Data" folder.
        guard let id = (value["custom"] as? [String: Any])?["_0"] as? [String: Any],
              let directory = id["directoryBasename"] as? String, !directory.isEmpty, directory.utf8.count <= 255,
              !directory.hasPrefix("."), !directory.contains("/"),
              !directory.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return profileKey(directory: directory)
    }

    ///
    ///
    static func icon(_ value: Any?) -> SidebarGroupIcon? {
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

    ///
    ///
    ///
    /// gradient, and three as a two-color gradient whose overlay is
    /// `[clear, third]`. Its translucency is always light and the content
    ///
    /// automatic appearance computes, so neither is carried over.
    static func theme(_ value: Any) -> SpaceTheme? {
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

    ///
    /// others are converted exactly to Display P3 and clamped to its gamut.
    static func color(_ value: Any?) -> ThemeColor? {
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
        // Linear sRGB to linear Display P3, both D65.
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

        ///
        static func pairs(_ value: Any?) -> [(Any, Any)] {
            guard let array = value as? [Any] else { return [] }
            return stride(from: 0, to: array.count - 1, by: 2).map { (array[$0], array[$0 + 1]) }
        }

        /// Each item is placed once, so a cycle or shared child cannot repeat.
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
                var tabs: [(id: String, tab: Tab)] = []
                for child in item["childrenIds"] as? [Any] ?? [] {
                    guard let taken = take(child) else { continue }
                    if Self.data(taken.item, "tab") == nil { drop(taken.item, depth: depth + 1) }
                    else if let tab = tab(taken.item) { tabs.append((taken.id, tab)) }
                }
                // Parc's splits hold two to four pages; the rest stay as tabs.
                let members = Array(tabs.prefix(4)), rest = tabs.dropFirst(4).map { Item.tab($0.tab) }
                guard members.count > 1 else { return members.map { .tab($0.tab) } }
                var weights: [String: Double] = [:]
                for (key, value) in Self.pairs(split["itemWidthFactors"]) {
                    if let key = key as? String, let value = value as? Double { weights[key] = value }
                }
                let factors = BrowserSplitLayout.normalized(members.map { weights[$0.id] ?? 1 }, count: members.count)
                    ?? Array(repeating: 1 / Double(members.count), count: members.count)
                let orientation = (split["layoutOrientation"] as? String).flatMap(SplitOrientation.init(rawValue:)) ?? .horizontal
                let icon = ArcSidebarImport.icon((split["customInfo"] as? [String: Any])?["iconType"])
                return [.split(title: title, icon: icon, tabs: members.map(\.tab), orientation: orientation,
                               widthFactors: factors)] + rest
            }
            drop(item, depth: depth)
            return []
        }

        /// Counts an item that can't come over together with everything under it.
        private mutating func drop(_ item: [String: Any], depth: Int) {
            skipped += 1
            guard depth < ArcSidebarImport.maximumDepth else { return }
            for child in item["childrenIds"] as? [Any] ?? [] {
                if let taken = take(child) { drop(taken.item, depth: depth + 1) }
            }
        }

        /// The same public-URL and scheme rules as a bookmark import.
        private mutating func tab(_ item: [String: Any]) -> Tab? {
            let tab = Self.data(item, "tab") ?? [:]
            let saved = tab["savedURL"] as? String ?? ""
            let value = BrowserInternalURL.publicString(saved)
            //
            //
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
    struct Result {
        var state: BrowserState
        var destinations: [ProfileKey: BrowserImportDestination]
        var warnings: [String]
    }

    /// The pure state transform behind `BrowserStore.importArcSidebar`.
    func inserting(into state: BrowserState, profiles: [(key: ProfileKey, name: String)],
                   standardProfileID: UUID, at date: Date) throws -> Result {
        func live(_ id: UUID) -> Bool {
            state.profiles.contains { $0.id == id } && !state.profileRemovals.contains { $0.profileID == id }
        }
        guard live(standardProfileID) else { throw CocoaError(.userCancelled) }
        var next = state, warnings: [String] = []
        var mapped: [ProfileKey: UUID] = [:], names: [ProfileKey: String] = [:]
        //
        for (key, rawName) in profiles where mapped[key] == nil {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            names[key] = name.isEmpty ? "Imported Profile" : name
            if key == .standard { mapped[key] = standardProfileID; continue }
            if let existing = next.profiles.first(where: { profile in live(profile.id)
                && profile.id != standardProfileID && !mapped.values.contains(profile.id)
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
        /// A split is ordered by its first page, as Parc stores split anchors.
        func makeSplit(title: String?, icon: SidebarGroupIcon?, tabs: [Tab], orientation: SplitOrientation,
                       factors: [Double], spaceID: UUID, profileID: UUID, kind: TabKind, folderID: UUID?) -> SidebarItemReference {
            let ids = tabs.map { makeTab($0, spaceID: spaceID, profileID: profileID, kind: kind, folderID: folderID) }
            next.splitLayouts.append(BrowserSplitLayout(customTitle: title, customIcon: icon, spaceID: spaceID,
                tabIDs: ids, orientation: orientation, widthFactors: factors))
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
                }
            }
            next.sidebarItemOrder[location.key] = order
        }

        func pinnedKeys(_ items: [Item]) -> [String] {
            items.flatMap { item -> [String] in
                switch item {
                case .tab(let tab): return [SavedTabURLComparison.key(tab.url)]
                case .folder(_, _, let children): return pinnedKeys(children)
                case .split(_, _, let tabs, _, _): return tabs.map { SavedTabURLComparison.key($0.url) }
                }
            }.sorted()
        }
        /// A Space this import already brought over: same name, Profile and pinned pages.
        func alreadyImported(_ space: Space, profileID: UUID) -> BrowserSpace? {
            let keys = pinnedKeys(space.pinned)
            guard !keys.isEmpty else { return nil }
            return state.spaces.first { existing in
                existing.profileID == profileID
                    && existing.title?.lowercased() == space.title?.lowercased()
                    && state.tabs.filter { $0.spaceID == existing.id && $0.kind == .pinned && $0.archivedAt == nil }
                        .map { SavedTabURLComparison.key($0.savedURL) }.sorted() == keys
            }
        }

        var unmapped = 0, repeated = 0
        for space in spaces {
            guard let profileID = mapped[space.profile] else { unmapped += 1; continue }
            if let existing = alreadyImported(space, profileID: profileID) {
                repeated += 1
                if destinations[space.profile] == nil { destinations[space.profile] = .init(spaceID: existing.id, profileID: profileID) }
                continue
            }
            let id = appendSpace(title: space.title, icon: space.icon, theme: space.theme, profileID: profileID)
            if destinations[space.profile] == nil { destinations[space.profile] = .init(spaceID: id, profileID: profileID) }
            insertPinned(space.pinned, spaceID: id, profileID: profileID, folderID: nil)
        }
        for (key, _) in profiles where destinations[key] == nil {
            guard let profileID = mapped[key] else { continue }
            let spaceID = next.spaces.first { $0.profileID == profileID }?.id
                ?? appendSpace(title: names[key], icon: nil, theme: nil, profileID: profileID)
            destinations[key] = .init(spaceID: spaceID, profileID: profileID)
        }
        if unmapped > 0 {
            warnings.append(unmapped == 1 ? "1 Arc Space belongs to a Profile that wasn't imported."
                                          : "\(unmapped) Arc Spaces belong to Profiles that weren't imported.")
        }
        if repeated > 0 {
            warnings.append(repeated == 1 ? "1 Arc Space was already in Parc, so it wasn't added again."
                                          : "\(repeated) Arc Spaces were already in Parc, so they weren't added again.")
        }

        for key in self.profiles {
            guard let items = favorites[key], !items.isEmpty else { continue }
            guard let destination = destinations[key] else {
                warnings.append("Favorites from a Profile that wasn't imported were left out.")
                continue
            }
            let profileID = destination.profileID
            let location = SidebarContainerLocation(spaceID: destination.spaceID, folderID: nil, section: .favorite,
                                                    profileID: profileID)
            var order = SidebarHierarchy.children(in: location, state: next).map { item -> SidebarItemReference in
                if case .split(let id) = item, let anchor = next.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID {
                    return .tab(anchor)
                }
                return item
            }
            var existing = Set(next.tabs.filter { $0.profileID == profileID && $0.kind == .favorite && $0.archivedAt == nil }
                .map { SavedTabURLComparison.key($0.savedURL) })
            var skipped = 0
            for item in items {
                if case .tab(let tab) = item, existing.contains(SavedTabURLComparison.key(tab.url)) { continue }
                if case .split(_, _, let tabs, _, _) = item,
                   tabs.allSatisfy({ existing.contains(SavedTabURLComparison.key($0.url)) }) { continue }
                guard order.count < 12 else { skipped += 1; continue }
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
                case .folder: skipped += 1
                }
            }
            next.sidebarItemOrder[location.key] = order
            if skipped > 0 {
                let name = names[key] ?? "Profile"
                warnings.append(skipped == 1 ? "1 Favorite from \(name) wasn't added: Favorites are limited to 12."
                                             : "\(skipped) Favorites from \(name) weren't added: Favorites are limited to 12.")
            }
        }
        if skippedItemCount > 0 {
            warnings.append(skippedItemCount == 1 ? "1 Parc sidebar item couldn't be brought over."
                                                  : "\(skippedItemCount) Parc sidebar items couldn't be brought over.")
        }
        return Result(state: next, destinations: destinations, warnings: warnings)
    }
}
