import Foundation

extension SidebarImport {
    package struct Result {
        var state: BrowserState
        var destinations: [ProfileKey: BrowserImportDestination]
        var routes: [LinkRoute] = []

        init(state: BrowserState, destinations: [ProfileKey: BrowserImportDestination], routes: [LinkRoute] = []) {
            self.state = state
            self.destinations = destinations
            self.routes = routes
        }
    }

    func inserting(into state: BrowserState, profiles: [(key: ProfileKey, name: String)],
                   standardProfileID: UUID, target: (key: ProfileKey, profileID: UUID)? = nil,
                   homeSpaceID: UUID? = nil, at date: Date) throws -> Result {
        func live(_ id: UUID) -> Bool {
            state.profiles.contains { $0.id == id } && !state.profileRemovals.contains { $0.profileID == id }
        }
        guard live(standardProfileID), target.map({ live($0.profileID) }) != false else { throw CocoaError(.userCancelled) }
        var next = state
        var mapped: [ProfileKey: UUID] = [:], names: [ProfileKey: String] = [:]
        let named = profiles + extraProfiles.filter { extra in !profiles.contains { $0.key == extra.key } }
            .map { (key: $0.key, name: $0.name) }
        for (key, rawName) in named where mapped[key] == nil {
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
        let homeProfileID = target?.profileID ?? standardProfileID
        let home = homeSpaceID.flatMap { id in next.spaces.first { $0.id == id && $0.profileID == homeProfileID } }

        var destinations: [ProfileKey: BrowserImportDestination] = [:]
        var spaceIDs: [String: UUID] = [:]
        func appendSpace(title: String?, icon: SidebarGroupIcon?, theme: SpaceTheme?, profileID: UUID,
                         pinnedCollapsed: Bool = false) -> UUID {
            var space = BrowserSpace(id: UUID(), name: title ?? "", symbol: "circle.fill", color: "B9B5D4", profileID: profileID)
            space.customIcon = icon
            if let theme { space.theme = theme }
            space.pinnedCollapsed = pinnedCollapsed
            space.updateDisplayName(position: next.spaces.count)
            next.spaces.append(space)
            return space.id
        }
        func makeTab(_ tab: Tab, spaceID: UUID, profileID: UUID, kind: TabKind, folderID: UUID?,
                     archivedAt: Date? = nil, provenance: ArchiveProvenance? = nil) -> UUID {
            let id = UUID()
            next.tabs.append(BrowserTab(id: id, spaceID: spaceID, profileID: profileID, url: tab.url, title: tab.title,
                kind: kind, folderID: folderID, createdAt: date, lastAccessed: date, archivedAt: archivedAt,
                savedURL: tab.url, savedTitle: tab.title, customTitle: tab.customTitle, isMuted: tab.isMuted,
                isUnread: tab.isUnread, archiveProvenance: provenance))
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
        func fresh(_ tab: Tab, _ known: inout Set<String>?) -> Bool {
            guard var keys = known else { return true }
            let inserted = keys.insert(SavedTabURLComparison.key(tab.url)).inserted
            known = keys
            return inserted
        }
        func appendSplit(_ item: Item, kind: TabKind, spaceID: UUID, profileID: UUID, folderID: UUID?,
                         known: inout Set<String>?, into order: inout [SidebarItemReference]) {
            guard let tabs = item.splitTabs else { return }
            let kept = tabs.filter { fresh($0, &known) }
            if kept.count == 1 {
                order.append(.tab(makeTab(kept[0], spaceID: spaceID, profileID: profileID, kind: kind, folderID: folderID)))
                return
            }
            guard kept.count > 1 else { return }
            switch item {
            case let .split(title, icon, _, orientation, factors):
                let widths = kept.count == tabs.count ? factors : Array(repeating: 1 / Double(kept.count), count: kept.count)
                order.append(makeSplit(title: title, icon: icon, tabs: kept, orientation: orientation, factors: widths,
                                       spaceID: spaceID, profileID: profileID, kind: kind, folderID: folderID))
            case let .stackedSplit(title, icon, _, orientation, stacks) where kept.count == tabs.count:
                order.append(makeSplit(title: title, icon: icon, tabs: kept, orientation: orientation,
                                       factors: stacks.flattenedFactors, stacks: stacks,
                                       spaceID: spaceID, profileID: profileID, kind: kind, folderID: folderID))
            case let .stackedSplit(title, icon, _, orientation, _):
                order.append(makeSplit(title: title, icon: icon, tabs: kept, orientation: orientation,
                                       factors: Array(repeating: 1 / Double(kept.count), count: kept.count),
                                       spaceID: spaceID, profileID: profileID, kind: kind, folderID: folderID))
            case .tab, .folder: break
            }
        }
        func insertPinned(_ items: [Item], spaceID: UUID, profileID: UUID, folderID: UUID?, known: inout Set<String>?) {
            let location = SidebarContainerLocation(spaceID: spaceID, folderID: folderID, section: .pinned)
            var order = next.sidebarItemOrder[location.key] ?? []
            for item in items {
                switch item {
                case .tab(let tab):
                    guard fresh(tab, &known) else { continue }
                    order.append(.tab(makeTab(tab, spaceID: spaceID, profileID: profileID, kind: .pinned, folderID: folderID)))
                case let .folder(title, icon, children, isExpanded):
                    if known != nil, let match = next.folders.first(where: { $0.spaceID == spaceID && $0.parentID == folderID
                        && $0.name.caseInsensitiveCompare(title) == .orderedSame }) {
                        insertPinned(children, spaceID: spaceID, profileID: profileID, folderID: match.id, known: &known)
                        continue
                    }
                    let folder = BrowserFolder(id: UUID(), spaceID: spaceID, name: title, parentID: folderID,
                                               isExpanded: isExpanded, customIcon: icon)
                    next.folders.append(folder)
                    order.append(.folder(folder.id))
                    insertPinned(children, spaceID: spaceID, profileID: profileID, folderID: folder.id, known: &known)
                case .split, .stackedSplit:
                    appendSplit(item, kind: .pinned, spaceID: spaceID, profileID: profileID, folderID: folderID,
                                known: &known, into: &order)
                }
            }
            next.sidebarItemOrder[location.key] = order
        }

        func insertToday(_ items: [Item], spaceID: UUID, profileID: UUID, known: inout Set<String>?) {
            let location = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .today)
            var order = next.sidebarItemOrder[location.key] ?? []
            func append(_ items: [Item]) {
                for item in items {
                    switch item {
                    case .tab(let tab):
                        guard fresh(tab, &known) else { continue }
                        order.append(.tab(makeTab(tab, spaceID: spaceID, profileID: profileID, kind: .today, folderID: nil)))
                    case .folder(_, _, let children, _): append(children)
                    case .split, .stackedSplit:
                        appendSplit(item, kind: .today, spaceID: spaceID, profileID: profileID, folderID: nil,
                                    known: &known, into: &order)
                    }
                }
            }
            append(items)
            next.sidebarItemOrder[location.key] = order
        }
        func openKeys(in spaceID: UUID) -> Set<String>? {
            Set(next.openTabs(where: { $0.spaceID == spaceID }).map { SavedTabURLComparison.key($0.savedURL) })
        }
        func pinnedKeys(_ items: [Item]) -> [String] {
            items.flatMap { item -> [String] in
                switch item {
                case .tab(let tab): return [SavedTabURLComparison.key(tab.url)]
                case .folder(_, _, let children, _): return pinnedKeys(children)
                case .split(_, _, let tabs, _, _), .stackedSplit(_, _, let tabs, _, _): return tabs.map { SavedTabURLComparison.key($0.url) }
                }
            }.sorted()
        }
        func alreadyImported(_ space: Space, profileID: UUID) -> BrowserSpace? {
            if let sourceID = space.id, let spaceID = state.arcImportedSpaces[sourceID] {
                return state.spaces.first { $0.id == spaceID && $0.profileID == profileID }
            }
            let keys = pinnedKeys(space.pinned)
            guard !keys.isEmpty else { return nil }
            return state.spaces.first { existing in
                existing.profileID == profileID && !next.arcImportedSpaces.values.contains(existing.id)
                    && (space.placement == .profileHome || existing.title?.lowercased() == space.title?.lowercased())
                    && state.openTabs(where: { $0.spaceID == existing.id && $0.kind == .pinned })
                        .map { SavedTabURLComparison.key($0.savedURL) }.sorted() == keys
            }
        }

        var homeUsed = false
        for space in spaces {
            guard let profileID = mapped[space.profile] else { continue }
            if let existing = alreadyImported(space, profileID: profileID) {
                if let sourceID = space.id { next.arcImportedSpaces[sourceID] = existing.id; spaceIDs[sourceID] = existing.id }
                if destinations[space.profile] == nil { destinations[space.profile] = .init(spaceID: existing.id, profileID: profileID) }
                if space.placement == .profileHome, existing.id == home?.id { homeUsed = true }
                var known = openKeys(in: existing.id)
                insertPinned(space.pinned, spaceID: existing.id, profileID: profileID, folderID: nil, known: &known)
                insertToday(space.today, spaceID: existing.id, profileID: profileID, known: &known)
                continue
            }
            let id: UUID
            var known: Set<String>?
            if space.placement == .profileHome, !homeUsed, let home, home.profileID == profileID {
                homeUsed = true
                id = home.id
                known = openKeys(in: id)
                if space.pinnedCollapsed, let index = next.spaces.firstIndex(where: { $0.id == id }) {
                    next.spaces[index].pinnedCollapsed = true
                }
            } else {
                id = appendSpace(title: space.title ?? (space.placement == .profileHome ? names[space.profile] : nil),
                                 icon: space.icon, theme: space.theme, profileID: profileID,
                                 pinnedCollapsed: space.pinnedCollapsed)
            }
            if destinations[space.profile] == nil { destinations[space.profile] = .init(spaceID: id, profileID: profileID) }
            insertPinned(space.pinned, spaceID: id, profileID: profileID, folderID: nil, known: &known)
            insertToday(space.today, spaceID: id, profileID: profileID, known: &known)
            if let sourceID = space.id { next.arcImportedSpaces[sourceID] = id; spaceIDs[sourceID] = id }
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
        for (key, _) in named where destinations[key] == nil {
            guard let profileID = mapped[key] else { continue }
            let spaceID = (profileID == homeProfileID ? home?.id : nil)
                ?? next.spaces.first { $0.profileID == profileID }?.id
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
                guard order.count < Self.maximumFavorites else { continue }
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
        let cutoff = date.addingTimeInterval(-BrowserStore.archiveRetention)
        var archived = Set(next.tabs.compactMap { tab in
            tab.archivedAt.map { "\(tab.profileID.uuidString) \($0.timeIntervalSince1970) \(SavedTabURLComparison.key(tab.savedURL))" }
        })
        for item in archive where item.archivedAt > cutoff && item.archivedAt <= date {
            guard let profileID = mapped[item.profile],
                  let spaceID = item.spaceID.flatMap({ spaceIDs[$0] }) ?? destinations[item.profile]?.spaceID,
                  next.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { continue }
            let key = "\(profileID.uuidString) \(item.archivedAt.timeIntervalSince1970) \(SavedTabURLComparison.key(item.tab.url))"
            guard archived.insert(key).inserted else { continue }
            let spaceName = next.spaces.first { $0.id == spaceID }?.name ?? "Space"
            _ = makeTab(item.tab, spaceID: spaceID, profileID: profileID, kind: .today, folderID: nil,
                        archivedAt: item.archivedAt,
                        provenance: ArchiveProvenance(reason: item.reason, spaceID: spaceID, spaceName: spaceName))
        }
        let resolvedRoutes = routes.compactMap { route -> LinkRoute? in
            let conditions = route.conditions.map { LinkRouteCondition(style: $0.style, pattern: $0.pattern) }
            guard !conditions.isEmpty else { return nil }
            switch route.destination {
            case .mostRecent: return LinkRoute(conditions: conditions, destination: .mostRecent)
            case .space(let source):
                return spaceIDs[source].map { LinkRoute(conditions: conditions, destination: .space($0)) }
            case .profile(let key):
                return destinations[key].map { LinkRoute(conditions: conditions, destination: .space($0.spaceID)) }
            }
        }
        return Result(state: next, destinations: destinations, routes: resolvedRoutes)
    }
}
