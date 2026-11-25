import Foundation

package enum ChromiumSidebarReader {
    static let customTitleKey = "vivaldi.fixedTitle"
    static let unnamedGroup = "Tab Group"
    static let minimumSplitShare = 0.1

    package static func read(flavor: ChromiumFlavor, root: URL, profiles: [SidebarImportProfile],
                             decrypt: SidebarDecryptor?) throws -> SidebarImport {
        SidebarImport.merged(profiles.map { read(flavor: flavor, profile: $0, decrypt: decrypt) })
    }

    static func read(flavor: ChromiumFlavor, profile: SidebarImportProfile, decrypt: SidebarDecryptor?) -> SidebarImport {
        let outcome = ChromiumSessionParser.read(profileDirectory: profile.directory, flavor: flavor, decrypt: decrypt)
        let session = outcome.session.map {
            ChromiumFlavorExtras.adjusted($0, flavor: flavor, profileDirectory: profile.directory)
        } ?? ChromiumSession()
        let folder = profile.directory.lastPathComponent
        let homeID = "\(prefix(flavor)):\(folder):home"
        var builder = Builder(session: session)
        var spaces: [SidebarImport.Space] = []

        if let custom = ChromiumFlavorExtras.spaces(session, flavor: flavor, profile: profile) {
            spaces = filled(custom, session: session, builder: &builder)
        } else {
            for window in session.windows {
                let content = builder.content(of: [window]) { _, _ in true }
                guard !content.pinned.isEmpty || !content.today.isEmpty else { continue }
                let home = spaces.isEmpty
                spaces.append(SidebarImport.Space(title: window.userTitle, icon: nil, theme: nil, profile: profile.key,
                    pinned: content.pinned, id: home ? homeID : "\(prefix(flavor)):\(folder):window:\(spaces.count)",
                    today: content.today, placement: home ? .profileHome : .new))
            }
        }

        let saved = savedGroupFolders((try? ChromiumSavedTabGroups.read(profileDirectory: profile.directory)) ?? [],
                                      session: session)
        if !saved.isEmpty {
            if let index = spaces.firstIndex(where: { $0.placement == .profileHome }) ?? spaces.indices.first {
                let space = spaces[index]
                spaces[index] = SidebarImport.Space(title: space.title, icon: space.icon, theme: space.theme,
                    profile: space.profile, pinned: space.pinned + saved, id: space.id, today: space.today,
                    pinnedCollapsed: space.pinnedCollapsed, placement: space.placement)
            } else {
                spaces.append(SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: profile.key, pinned: saved,
                                                  id: homeID, placement: .profileHome))
            }
        }

        let archive = session.closedTabs.compactMap { closed -> SidebarImport.ArchivedTab? in
            guard let closedAt = closed.closedAt, !ChromiumNewTabPage.matches(closed.url),
                  let tab = SidebarImport.Tab.web(url: closed.url, title: closed.title) else { return nil }
            return SidebarImport.ArchivedTab(tab: tab, archivedAt: closedAt, reason: .manual, spaceID: nil, profile: profile.key)
        }
        let favorites = ChromiumFlavorExtras.favorites(flavor: flavor, profileDirectory: profile.directory)
        var result = SidebarImport(spaces: spaces, favorites: favorites.isEmpty ? [] : [(profile.key, favorites)],
                                   archive: archive, skippedItemCount: builder.skipped)
        if outcome.encryptedUnreadable {
            result.warnings.append("\(name(flavor)) keeps the tabs in \(profile.name) encrypted, so they stayed behind.")
        }
        return result
    }

    static func filled(_ custom: [(space: SidebarImport.Space, windowTabs: [Int32: Set<Int32>])], session: ChromiumSession,
                       builder: inout Builder) -> [SidebarImport.Space] {
        custom.map { entry -> SidebarImport.Space in
            let space = entry.space, windowTabs = entry.windowTabs
            let content = builder.content(of: session.windows) { windowTabs[$0]?.contains($1) == true }
            return SidebarImport.Space(title: space.title, icon: space.icon, theme: space.theme, profile: space.profile,
                pinned: space.pinned + content.pinned, id: space.id, today: space.today + content.today,
                pinnedCollapsed: space.pinnedCollapsed, placement: space.placement)
        }
    }

    static func savedGroupFolders(_ groups: [ChromiumSavedTabGroup], session: ChromiumSession) -> [SidebarImport.Item] {
        let open = Set(session.groups.values.compactMap { $0.savedGUID?.lowercased() })
        return groups.enumerated()
            .filter { !open.contains($0.element.guid.lowercased()) }
            .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
            .compactMap { entry -> SidebarImport.Item? in
                let group = entry.element
                let children = group.tabs.enumerated()
                    .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
                    .compactMap { pair -> SidebarImport.Item? in
                        guard !ChromiumNewTabPage.matches(pair.element.url) else { return nil }
                        return SidebarImport.Tab.web(url: pair.element.url, title: pair.element.title).map(SidebarImport.Item.tab)
                    }
                guard !children.isEmpty else { return nil }
                return .folder(title: group.title.isEmpty ? unnamedGroup : group.title, icon: nil, children: children,
                               isExpanded: false)
            }
    }

    static func prefix(_ flavor: ChromiumFlavor) -> String {
        switch flavor {
        case .chrome: return "chrome"
        case .chromium: return "chromium"
        case .brave: return "brave"
        case .edge: return "edge"
        case .vivaldi: return "vivaldi"
        case .opera: return "opera"
        case .operaGX: return "opera-gx"
        case .comet: return "comet"
        case .helium: return "helium"
        }
    }

    static func name(_ flavor: ChromiumFlavor) -> String {
        switch flavor {
        case .chrome: return "Chrome"
        case .chromium: return "Chromium"
        case .brave: return "Brave"
        case .edge: return "Microsoft Edge"
        case .vivaldi: return "Vivaldi"
        case .opera: return "Opera"
        case .operaGX: return "Opera GX"
        case .comet: return "Comet"
        case .helium: return "Helium"
        }
    }

    struct Content {
        var pinned: [SidebarImport.Item] = []
        var today: [SidebarImport.Item] = []
    }

    struct Builder {
        let session: ChromiumSession
        var skipped = 0

        private enum Slot {
            case item(SidebarImport.Item)
            case folder(ChromiumToken)
        }

        mutating func content(of windows: [ChromiumSession.Window], including: (Int32, Int32) -> Bool) -> Content {
            var result = Content()
            for window in windows {
                let tabs = window.tabs.filter { including(window.id, $0.id) }
                var pinned: [Slot] = [], children: [ChromiumToken: [SidebarImport.Item]] = [:]
                var finishedSplits = Set<ChromiumToken>()
                for tab in tabs {
                    let items: [SidebarImport.Item]
                    if let token = tab.split {
                        guard finishedSplits.insert(token).inserted else { continue }
                        items = split(tabs.filter { $0.split == token }, token: token)
                    } else {
                        items = web(tab).map { [.tab($0)] } ?? []
                    }
                    guard !items.isEmpty else { continue }
                    if let group = tab.group {
                        if children[group] == nil { pinned.append(.folder(group)) }
                        children[group, default: []] += items
                    } else if tab.pinned {
                        pinned += items.map(Slot.item)
                    } else {
                        result.today += items
                    }
                }
                result.pinned += pinned.map { slot in
                    switch slot {
                    case .item(let item): return item
                    case .folder(let token):
                        let group = session.groups[token]
                        let title = group.flatMap { $0.title.isEmpty ? nil : $0.title } ?? ChromiumSidebarReader.unnamedGroup
                        return .folder(title: title, icon: nil, children: children[token] ?? [],
                                       isExpanded: !(group?.collapsed ?? false))
                    }
                }
            }
            return result
        }

        private mutating func web(_ tab: ChromiumSession.Tab) -> SidebarImport.Tab? {
            guard !ChromiumNewTabPage.matches(tab.url) else { return nil }
            guard let made = SidebarImport.Tab.web(url: tab.url, title: tab.title,
                                                   customTitle: tab.extraData[ChromiumSidebarReader.customTitleKey]) else {
                skipped += 1
                return nil
            }
            return made
        }

        private mutating func split(_ members: [ChromiumSession.Tab], token: ChromiumToken) -> [SidebarImport.Item] {
            let tabs = members.compactMap { web($0) }
            guard tabs.count > 1 else { return tabs.map(SidebarImport.Item.tab) }
            let panes = Array(tabs.prefix(4)), rest = tabs.dropFirst(4).map(SidebarImport.Item.tab)
            let layout = session.splits[token] ?? ChromiumSession.Split(ratio: 0.5, sideBySide: true)
            let factors: [Double]
            if panes.count == 2 {
                let ratio = layout.ratio.isFinite ? layout.ratio : 0.5
                let start = min(max(ratio, ChromiumSidebarReader.minimumSplitShare), 1 - ChromiumSidebarReader.minimumSplitShare)
                factors = [start, 1 - start]
            } else {
                factors = Array(repeating: 1 / Double(panes.count), count: panes.count)
            }
            return [.split(title: nil, icon: nil, tabs: panes, orientation: layout.sideBySide ? .horizontal : .vertical,
                           widthFactors: factors)] + rest
        }
    }
}
