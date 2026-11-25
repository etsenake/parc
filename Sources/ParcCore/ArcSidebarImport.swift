import Foundation

extension SidebarImport {
    package init(arcData data: Data, windows: Data? = nil, archive: Data? = nil, routing: Data? = nil,
                 notes: [Note] = []) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let containers = (root["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let container = Self.arcMainContainer(containers) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let layout = ArcWindowLayout(windows)
        var parser = Parser(container: container, expanded: layout.expanded, notes: notes)
        var spaces: [Space] = []
        for (_, value) in Self.arcPairs(container["spaces"]) {
            guard let space = value as? [String: Any], let profile = Self.profile(space["profile"]) else {
                parser.skipped += 1; continue
            }
            let customInfo = space["customInfo"] as? [String: Any]
            let pinned = Self.containerID(space, "pinned").flatMap { parser.items[$0] }
            let today = Self.containerID(space, "unpinned").flatMap { parser.items[$0] }
            let id = (space["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            spaces.append(Space(title: (space["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                icon: Self.icon(customInfo?["iconType"]),
                theme: Self.theme(customInfo?["windowTheme"] ?? NSNull()),
                profile: profile, pinned: pinned.map { parser.children(of: $0, depth: 0, section: .pinned) } ?? [],
                id: id,
                today: today.map { parser.children(of: $0, depth: 0, section: .today) } ?? [],
                pinnedCollapsed: id.map { layout.collapsedPinned.contains($0) } ?? false))
        }
        var favorites: [ProfileKey: [Item]] = [:], order: [ProfileKey] = []
        for (key, id) in Self.arcPairs(container["topAppsContainerIDs"]) {
            guard let key = Self.profile(key), favorites[key] == nil,
                  let id = id as? String, let item = parser.items[id] else { continue }
            favorites[key] = parser.children(of: item, depth: 0, section: .favorites)
            order.append(key)
        }
        var spaceProfiles: [String: ProfileKey] = [:]
        for space in spaces { if let id = space.id, spaceProfiles[id] == nil { spaceProfiles[id] = space.profile } }
        let routed = Self.arcRoutes(routing, spaces: Set(spaceProfiles.keys))
        let archived = Self.arcArchive(archive, spaces: spaceProfiles)
        self.init(spaces: spaces, favorites: order.compactMap { key in favorites[key].map { (key, $0) } },
                  archive: archived.tabs, routes: routed.routes,
                  skippedItemCount: parser.skipped + archived.skipped)
        warnings = routed.warnings
        self.notes = notes.filter { !parser.claimed.contains($0.id) }
        if parser.missingNotes > 0 {
            warnings.append(parser.missingNotes == 1 ? "1 Arc note wasn’t saved on this Mac, so it stayed behind."
                : "\(parser.missingNotes) Arc notes weren’t saved on this Mac, so they stayed behind.")
        }
        let pictures = notes.reduce(0) { $0 + $1.droppedImages }
        if pictures > 0 {
            warnings.append(pictures == 1 ? "1 picture in your Arc notes couldn’t be read, so it stayed behind."
                : "\(pictures) pictures in your Arc notes couldn’t be read, so they stayed behind.")
        }
    }

    private static func containerID(_ space: [String: Any], _ section: String) -> String? {
        for key in ["containerIDs", "newContainerIDs"] {
            for (label, id) in arcPairs(space[key]) {
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
        for (key, value) in arcPairs(map) {
            if let key = profile(key), let value = hours(value) { perProfile[key] = value }
        }
        var result: [ProfileKey: Double] = [:]
        for key in profiles { result[key] = perProfile[key] ?? global }
        return result
    }

    static func profile(_ value: Any?) -> ProfileKey? {
        guard let value = value as? [String: Any] else { return nil }
        if value["default"] != nil { return .standard }
        guard let id = (value["custom"] as? [String: Any])?["_0"] as? [String: Any],
              let directory = id["directoryBasename"] as? String, !directory.isEmpty, directory.utf8.count <= 255,
              !directory.hasPrefix("."), !directory.contains("/"),
              !directory.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return profileKey(directory: directory)
    }

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
        return ThemeColor(red: encoded(0.8224619687 * r + 0.1775380313 * g),
                          green: encoded(0.0331941989 * r + 0.9668058011 * g),
                          blue: encoded(0.0170826307 * r + 0.0723974407 * g + 0.9105199286 * b),
                          colorSpace: .displayP3)
    }

    private struct Parser {
        enum Section { case pinned, today, favorites }

        var items: [String: [String: Any]] = [:]
        var skipped = 0
        var missingNotes = 0
        private(set) var claimed = Set<String>()
        private var used = Set<String>()
        private let expanded: Set<String>?
        private var notes: [String: Note] = [:]
        private var notesByTitle: [String: [String]] = [:]

        init(container: [String: Any], expanded: Set<String>?, notes: [Note] = []) {
            self.expanded = expanded
            for note in notes where self.notes[note.id] == nil {
                self.notes[note.id] = note
                notesByTitle[note.title, default: []].append(note.id)
            }
            for (id, value) in SidebarImport.arcPairs(container["items"]) {
                guard let id = id as? String, let item = value as? [String: Any], items[id] == nil,
                      items.count < SidebarImport.maximumItems else { skipped += 1; continue }
                items[id] = item
            }
        }

        private mutating func take(_ id: Any) -> (id: String, item: [String: Any])? {
            guard let id = id as? String, let item = items[id], used.insert(id).inserted else { skipped += 1; return nil }
            return (id, item)
        }

        private static func data(_ item: [String: Any], _ kind: String) -> [String: Any]? {
            (item["data"] as? [String: Any])?[kind] as? [String: Any]
        }

        mutating func children(of container: [String: Any], depth: Int, section: Section) -> [Item] {
            guard depth < SidebarImport.maximumDepth else { skipped += 1; return [] }
            var result: [Item] = []
            for child in container["childrenIds"] as? [Any] ?? [] {
                guard let taken = take(child) else { continue }
                result += item(taken.item, id: taken.id, depth: depth + 1, section: section)
            }
            return result
        }

        private mutating func item(_ item: [String: Any], id: String, depth: Int, section: Section) -> [Item] {
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if Self.data(item, "tab") != nil { return tab(item).map { [.tab($0)] } ?? [] }
            if let document = Self.data(item, "arcDocument") { return note(document, title: title).map { [.tab($0)] } ?? [] }
            if let list = Self.data(item, "list"), section != .favorites {
                let icon = SidebarImport.icon((list["customInfo"] as? [String: Any])?["iconType"])
                return [.folder(title: title ?? "Imported folder", icon: icon,
                                children: children(of: item, depth: depth, section: section),
                                isExpanded: expanded?.contains(id) ?? true)]
            }
            if let group = Self.data(item, "tabGroup") {
                let tabs = children(of: item, depth: depth, section: section)
                guard section == .pinned else { return tabs }
                let named = (group["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return [.folder(title: title ?? named ?? "Tab Group", icon: nil, children: tabs,
                                isExpanded: expanded?.contains(id) ?? true)]
            }
            if let split = Self.data(item, "splitView") {
                var entries: [SplitEntry] = []
                for child in item["childrenIds"] as? [Any] ?? [] {
                    guard let taken = take(child) else { continue }
                    if let nested = Self.data(taken.item, "splitView"), depth + 1 < SidebarImport.maximumDepth {
                        let found = nestedTabs(of: taken.item, depth: depth + 1)
                        if found.tabs.isEmpty { skipped += 1; continue }
                        entries.append(SplitEntry(id: taken.id, tabs: found.tabs, orientation: Self.orientation(nested),
                                                  weights: Self.weights(nested), deeper: found.deeper))
                    } else if !Self.isLeaf(taken.item) { drop(taken.item, depth: depth + 1) }
                    else if let tab = leaf(taken.item) {
                        entries.append(SplitEntry(id: taken.id, tabs: [(taken.id, tab)], orientation: nil, weights: [:], deeper: false))
                    }
                }
                let tabs = entries.flatMap(\.tabs)
                let members = Array(tabs.prefix(4)), rest = tabs.dropFirst(4).map { Item.tab($0.tab) }
                guard members.count > 1 else { return members.map { .tab($0.tab) } }
                let weights = Self.weights(split)
                let orientation = Self.orientation(split)
                let icon = SidebarImport.icon((split["customInfo"] as? [String: Any])?["iconType"])
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
            for (key, value) in SidebarImport.arcPairs(split["itemWidthFactors"]) {
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
                if Self.data(taken.item, "splitView") != nil, depth + 1 < SidebarImport.maximumDepth {
                    let found = nestedTabs(of: taken.item, depth: depth + 1).tabs
                    if found.isEmpty { skipped += 1 } else { tabs += found; deeper = true }
                } else if !Self.isLeaf(taken.item) { drop(taken.item, depth: depth + 1) }
                else if let tab = leaf(taken.item) { tabs.append((taken.id, tab)) }
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
            guard depth < SidebarImport.maximumDepth else { return }
            for child in item["childrenIds"] as? [Any] ?? [] {
                if let taken = take(child) { drop(taken.item, depth: depth + 1) }
            }
        }

        private mutating func tab(_ item: [String: Any]) -> Tab? {
            guard let tab = SidebarImport.arcTab(item) else { skipped += 1; return nil }
            return tab
        }

        private static func isLeaf(_ item: [String: Any]) -> Bool {
            data(item, "tab") != nil || data(item, "arcDocument") != nil
        }

        private mutating func leaf(_ item: [String: Any]) -> Tab? {
            guard let document = Self.data(item, "arcDocument") else { return tab(item) }
            return note(document, title: (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }

        private mutating func note(_ document: [String: Any], title: String?) -> Tab? {
            let byID = (document["arcDocumentID"] as? String).flatMap { notes[$0] }
            let byTitle = title.flatMap { name in notesByTitle[name].flatMap { $0.count == 1 ? notes[$0[0]] : nil } }
            guard let note = byID ?? byTitle else { skipped += 1; missingNotes += 1; return nil }
            claimed.insert(note.id)
            return .note(note)
        }
    }
}
