import Foundation

@main @MainActor struct SpaceSharingTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        try upgrade()
        try archiveInterval()
        try separateCreation()
        try draftCreation()
        try changeSharing()
        try documentBlocks()
        try warnings()
        try legacyAppWideKey()
        try deletion()
        try legacyRemovalFallback()
        print("SpaceSharingTests: \(count) assertions passed")
    }

    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-sharing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ state: BrowserState, to directory: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
    }

    static func tab(_ space: BrowserSpace, _ url: String, kind: TabKind = .today, accessed: Date = Date()) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: url, kind: kind,
                   createdAt: accessed, lastAccessed: accessed, savedURL: url, savedTitle: url)
    }

    static func upgrade() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var state = BrowserState.initial()
        state.spaceSharingVersion = 0
        state.spaces[0].autoArchiveHours = nil
        var theme = state.spaces[0].theme; theme.noise = 0.4; state.spaces[0].theme = theme
        let work = BrowserProfile(id: UUID(), name: "Work", autoArchiveHours: AutoArchiveInterval.sevenDays.rawValue)
        let leaving = BrowserProfile(id: UUID(), name: "Leaving")
        let shared = BrowserProfile(id: UUID(), name: "Shared", autoArchiveHours: AutoArchiveInterval.thirtyDays.rawValue)
        state.profiles += [work, leaving, shared]
        state.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: leaving.id, profileName: leaving.name)]
        let s1 = BrowserSpace(id: UUID(), name: "One", symbol: "circle", color: "B9B5D4", profileID: shared.id)
        let s2 = BrowserSpace(id: UUID(), name: "Two", symbol: "circle", color: "B9B5D4", profileID: shared.id)
        state.spaces += [s1, s2]
        let elsewhere = UUID()
        let routes = LinkRoutingState(rules: [
            LinkRoute(destination: .profile(work.id)), LinkRoute(destination: .profile(shared.id)),
            LinkRoute(destination: .profile(leaving.id)), LinkRoute(destination: .space(elsewhere)),
            LinkRoute(destination: .mostRecent)])
        try JSONEncoder().encode(routes).write(to: directory.appendingPathComponent("link-routing.json"))
        try write(state, to: directory)

        let store = try BrowserStore(directory: directory)
        let made = store.state.spaces.filter { $0.profileID == work.id }
        try check(made.count == 1 && made[0].name == "Work" && made[0].symbol == "circle.fill", "unused Profile gets its own named Space")
        try check(made[0].theme == theme && made[0].autoArchiveHours == work.autoArchiveHours, "new Space copies theme and Profile archive interval")
        try check(!store.state.spaces.contains { $0.profileID == leaving.id }, "pending removal gets no Space")
        try check(store.state.spaces.filter { $0.profileID == shared.id }.map(\.id) == [s1.id, s2.id], "sharing Spaces keep sharing")
        try check(store.state.spaces.first { $0.id == s1.id }?.autoArchiveHours == shared.autoArchiveHours
            && store.state.spaces[0].autoArchiveHours == AutoArchiveInterval.twelveHours.rawValue, "Spaces seed archive interval from their Profile")
        try check(store.state.spaceSharingVersion == SpaceSharing.version && store.state.profiles.count == 4, "upgrade deletes nothing and records its version")
        try check(store.state.profilesWithoutSpaces.isEmpty, "no orphan Profile survives the upgrade")
        let destinations = store.linkRouting.state.rules.map(\.destination)
        try check(destinations == [.space(made[0].id), .space(s1.id), .mostRecent, .space(elsewhere), .mostRecent], "Profile routes convert to the first Space or most recent")
        try check(LinkRoutingStore(directory: directory).state.rules.map(\.destination) == destinations, "converted routes persist")

        let reloaded = try BrowserStore(directory: directory)
        try check(reloaded.state == store.state, "upgrade persisted once and is idempotent")
        var again = reloaded.state
        try check(!again.upgradeSpaceSharing() && again == reloaded.state, "upgraded state never upgrades twice")
    }

    static func archiveInterval() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        var state = BrowserState.initial()
        let first = state.spaces[0]
        var second = BrowserSpace(id: UUID(), name: "Later", symbol: "circle", color: "B9B5D4", profileID: first.profileID)
        second.autoArchiveHours = AutoArchiveInterval.sevenDays.rawValue
        state.spaces.append(second)
        let old = now.addingTimeInterval(-2 * 86_400)
        let a = tab(first, "https://a.example", accessed: old), b = tab(second, "https://b.example", accessed: old)
        let kept = tab(first, "https://kept.example", kind: .pinned)
        state.tabs = [a, b, kept]
        state.selectedTabIDs = [kept.id]; state.selectionBySpace[first.id.uuidString] = [kept.id]
        state.autoArchiveStartedAt = now.addingTimeInterval(-30 * 86_400)
        try write(state, to: directory)
        let store = try BrowserStore(directory: directory, now: { now })
        try check(store.autoArchiveInterval(forSpace: first.id) == .twelveHours
            && store.autoArchiveInterval(forSpace: second.id) == .sevenDays, "intervals are per Space")
        let archived = store.archiveExpiredTabs()
        try check(archived == [a.id], "archive sweep follows each Space's own interval")

        try check(try store.setAutoArchiveInterval(.thirtyDays, forSpace: first.id), "Space interval changes")
        try check(store.autoArchiveInterval(forSpace: first.id) == .thirtyDays
            && store.autoArchiveInterval(forSpace: second.id) == .sevenDays
            && store.state.profiles[0].autoArchiveHours == AutoArchiveInterval.twelveHours.rawValue, "setting one Space leaves others and the Profile alone")
        try check(try BrowserStore(directory: directory).autoArchiveInterval(forSpace: first.id) == .thirtyDays, "Space interval persists")
        try check(!(try store.setAutoArchiveInterval(.thirtyDays, forSpace: first.id)), "unchanged interval writes nothing")

        let created = store.createSpace(name: "New")
        try check(store.autoArchiveInterval(forSpace: created) == .thirtyDays, "new Space inherits the creating Space's interval")
        _ = try store.changeAutoArchiveInterval(.oneHour, for: first.profileID)
        try check(store.state.spaces.allSatisfy { $0.autoArchiveHours == AutoArchiveInterval.oneHour.rawValue }, "Profile setting reaches its Spaces")

        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(second)) as! [String: Any]
        json.removeValue(forKey: "autoArchiveHours")
        try check(try JSONDecoder().decode(BrowserSpace.self, from: JSONSerialization.data(withJSONObject: json)).autoArchiveHours == nil, "missing interval decodes as nil")
        json["autoArchiveHours"] = 5
        try check(try JSONDecoder().decode(BrowserSpace.self, from: JSONSerialization.data(withJSONObject: json)).autoArchiveHours == nil, "invalid interval decodes as nil")
    }

    static func separateCreation() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        try write(.initial(), to: directory)
        let store = try BrowserStore(directory: directory)
        let home = store.activeSpace
        let work = try store.createSpace(name: " Work ", sharing: .separate)
        let space = store.state.spaces.first { $0.id == work }!
        try check(space.profileID != home.profileID && store.state.profiles.count == 2
            && store.state.profiles.last?.name == "Work" && space.name == "Work", "Keep separate creates a Space on a new Profile named after it")
        try check(store.activeSpaceID == work, "created Space becomes active")
        let shared = try store.createSpace(name: "Play", sharing: .share(withSpace: home.id))
        try check(store.state.spaces.first { $0.id == shared }?.profileID == home.profileID && store.state.profiles.count == 2, "Share data reuses the Space's Profile")
        try check(try BrowserStore(directory: directory).state.profiles.count == 2, "creation persisted")
        let before = store.state
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        let failed = (try? store.createSpace(name: "Broken", sharing: .separate)) == nil
        try check(failed && store.state == before, "failed save creates neither Space nor Profile")
        try FileManager.default.removeItem(at: directory)
    }

    static func draftCreation() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var state = BrowserState.initial()
        let home = state.spaces[0]
        let other = BrowserProfile(id: UUID(), name: "Other")
        var away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "B9B5D4", profileID: other.id)
        away.autoArchiveHours = other.autoArchiveHours
        state.profiles.append(other); state.spaces.append(away)
        let moving = tab(home, "https://move.example"), sharing = tab(home, "https://share.example")
        state.tabs = [moving, sharing]
        try write(state, to: directory)
        let store = try BrowserStore(directory: directory)
        let source = SidebarHierarchySnapshot(state: store.state, spaceID: home.id, profileID: home.profileID)!

        var empty = SidebarNewSpaceDraft(from: source, state: store.state)!
        empty.name = "Solo"; empty.keepSeparate()
        let untouched = store.state
        try check(empty.keepsSeparate && empty.applying(to: store.state) != nil && store.state == untouched, "choosing Keep separate creates nothing before commit")
        var result: Result<UUID?, Error>?
        store.createSpace(empty) { result = $0 }
        let solo = try result?.get()
        let soloSpace = store.state.spaces.first { $0.id == solo }
        try check(soloSpace != nil && soloSpace?.profileID == empty.profileID
            && store.state.profiles.first { $0.id == empty.profileID }?.name == "Solo", "commit adds Space and Profile together")

        var moved = SidebarNewSpaceDraft(items: [.tab(moving.id)], from: source, state: store.state)!
        moved.name = "Moved"; moved.keepSeparate()
        try check(moved.movesItemsAcrossProfiles && (try store.createSpaceAndMoveSidebarItems(moved)) == nil, "synchronous path refuses a Profile crossing")
        result = nil
        store.createSpace(moved) { result = $0 }
        let movedTab = store.state.tabs.first { $0.id == moving.id }
        try check(try result?.get() == moved.spaceID && movedTab?.spaceID == moved.spaceID
            && movedTab?.profileID == moved.profileID, "moved tabs cross into the new separate Profile")

        let fresh = SidebarHierarchySnapshot(state: store.state, spaceID: home.id, profileID: home.profileID)!
        var joined = SidebarNewSpaceDraft(items: [.tab(sharing.id)], from: fresh, state: store.state)!
        joined.name = "Joined"
        try check(joined.shareData(withSpace: away.id, in: store.state) && !joined.keepsSeparate, "Share data picks the other Space's Profile")
        let profiles = store.state.profiles.count
        result = nil
        store.createSpace(joined) { result = $0 }
        try check(try result?.get() == joined.spaceID && store.state.tabs.first { $0.id == sharing.id }?.profileID == other.id
            && store.state.profiles.count == profiles, "sharing moves tabs onto the shared Profile without a new one")
    }

    static func changeSharing() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var state = BrowserState.initial()
        let a = state.spaces[0], p = state.profiles[0]
        state.settings.defaultProfileID = p.id
        let q = BrowserProfile(id: UUID(), name: "Q")
        let b = BrowserSpace(id: UUID(), name: "B", symbol: "circle", color: "B9B5D4", profileID: p.id)
        let c = BrowserSpace(id: UUID(), name: "C", symbol: "circle", color: "B9B5D4", profileID: q.id)
        state.profiles.append(q); state.spaces += [b, c]
        let page = tab(c, "https://c.example", kind: .pinned)
        state.tabs = [page]
        try write(state, to: directory)
        let store = try BrowserStore(directory: directory)
        var outcome: Result<SpaceSharingChange?, Error>?
        func change(_ space: UUID, _ sharing: SpaceDataSharing) throws -> SpaceSharingChange? {
            outcome = nil
            store.changeSharing(ofSpace: space, to: sharing) { outcome = $0 }
            return try outcome!.get()
        }

        try check(store.wouldOrphanProfile(ifSpace: c.id, joins: .share(withSpace: a.id))
            && store.unusedProfile(ifSpace: c.id, joins: .share(withSpace: a.id)) == UnusedProfile(id: q.id, name: "Q"), "joining away from a sole Profile reports it")
        try check(!store.wouldOrphanProfile(ifSpace: a.id, joins: .share(withSpace: c.id)), "a Profile still used elsewhere is not reported")
        try check(!store.wouldOrphanProfile(ifSpace: c.id, joins: .separate), "Keep separate never leaves a Profile unused")

        let joined = try change(a.id, .share(withSpace: c.id))
        try check(joined == SpaceSharingChange(spaceID: a.id, profileID: q.id, previousProfileID: p.id, unusedProfile: nil), "moving to a shared Profile reports nothing unused")

        let profiles = store.state.profiles.count
        let split = try change(c.id, .separate)
        let fresh = store.state.spaces.first { $0.id == c.id }!.profileID
        try check(split?.previousProfileID == q.id && split?.unusedProfile == nil && fresh != q.id
            && store.state.profiles.count == profiles + 1 && store.state.profiles.last?.name == "C", "Keep separate moves the Space to a new Profile named after it")
        try check(store.state.tabs.first { $0.id == page.id }?.profileID == fresh, "the Space's tabs move with it")
        try check(try BrowserStore(directory: directory).state.spaces.first { $0.id == c.id }?.profileID == fresh, "new Profile and assignment persist together")
        try check(try change(b.id, .separate) == nil && store.state.profiles.count == profiles + 1, "a Space that already keeps separate is left alone")

        let left = try change(a.id, .share(withSpace: c.id))
        try check(left?.unusedProfile == UnusedProfile(id: q.id, name: "Q"), "leaving a Profile empty reports it")
        let record = try store.stageRemoval(of: left!.unusedProfile!)
        try check(record.profileID == q.id && store.isProfileRemovalPending(q.id), "unused Profile removal stages")

        let last = try change(b.id, .share(withSpace: c.id))
        try check(last?.unusedProfile == UnusedProfile(id: p.id, name: p.name), "the default Profile is reported like any other")
        let fallback = store.state.spaces.first { $0.id == c.id }!.profileID
        let defaultRecord = try store.stageRemoval(of: last!.unusedProfile!)
        try check(store.isProfileRemovalPending(p.id) && defaultRecord.fallbackProfileID == fallback
            && store.defaultProfileID == fallback, "removing the default Profile hands Default to a surviving Profile in the same save")
    }

    static func documentBlocks() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var state = BrowserState.initial()
        let p = state.profiles[0], q = BrowserProfile(id: UUID(), name: "Q")
        state.spaces[0].name = "Alpha"
        let a = state.spaces[0]
        let b = BrowserSpace(id: UUID(), name: "Beta", symbol: "circle", color: "B9B5D4", profileID: p.id)
        let c = BrowserSpace(id: UUID(), name: "Gamma", symbol: "circle", color: "B9B5D4", profileID: q.id)
        state.profiles.append(q); state.spaces += [b, c]
        let page = InternalPage.note(UUID())
        var plans = tab(a, page.urlString); plans.title = "Plans"; plans.savedTitle = "Plans"
        let web = tab(a, "https://a.example")
        var relocated: [[InternalPage]] = []
        func load(_ extra: [BrowserTab]) throws -> BrowserStore {
            var next = state; next.tabs = [plans, web] + extra
            try write(next, to: directory)
            let store = try BrowserStore(directory: directory)
            relocated = []
            store.relocateLocalDocuments = { _, pages, _, _ in relocated.append(pages); return {} }
            return store
        }
        func change(_ store: BrowserStore, _ sharing: SpaceDataSharing) throws -> SpaceSharingChange? {
            var outcome: Result<SpaceSharingChange?, Error>?
            store.changeSharing(ofSpace: a.id, to: sharing) { outcome = $0 }
            return try outcome!.get()
        }
        var archived = tab(a, page.urlString); archived.archivedAt = Date()

        let blocked: [(extra: [BrowserTab], sharing: SpaceDataSharing, title: String, places: String, reason: String)] = [
            ([tab(a, page.urlString, kind: .favorite)], .separate, "Can’t keep Alpha separate", "in Favorites", "a Favorite"),
            ([archived], .share(withSpace: c.id), "Can’t share Gamma’s data with Alpha", "in the Archive", "an archived entry"),
            ([tab(b, page.urlString)], .share(withSpace: c.id), "Can’t share Gamma’s data with Alpha", "in Today in Beta", "an entry in a Space sharing the old data"),
        ]
        for (extra, sharing, title, places, reason) in blocked {
            let store = try load(extra)
            let before = store.state
            let block = store.sharingDocumentBlock(forSpace: a.id, to: sharing)
            try check(block?.title == title && block?.message == "The Note “Plans” is still used elsewhere on Alpha’s current data: " + places + ".",
                      reason + " explains why the data can’t change")
            try check(try change(store, sharing) == nil && store.state == before && relocated.isEmpty,
                      reason + " still refuses the change exactly as before")
        }

        let store = try load([])
        try check(store.sharingDocumentBlock(forSpace: a.id, to: .share(withSpace: c.id)) == nil
                  && store.sharingDocumentBlock(forSpace: a.id, to: .separate) == nil,
                  "a Note used only in the changing Space has nothing to explain")
        try check(store.sharingDocumentBlock(forSpace: b.id, to: .share(withSpace: a.id)) == nil
                  && store.sharingDocumentBlock(forSpace: c.id, to: .separate) == nil
                  && store.sharingDocumentBlock(forSpace: a.id, to: .share(withSpace: UUID())) == nil,
                  "a choice that changes nothing has nothing to explain")
        try check(store.sharingWarning(forSpace: a.id, to: .share(withSpace: c.id)) == .share(target: "Gamma", space: "Alpha", discardsOwnData: false),
                  "without blocking entries the data warning is still asked")
        let joined = try change(store, .share(withSpace: c.id))
        try check(joined == SpaceSharingChange(spaceID: a.id, profileID: q.id, previousProfileID: p.id, unusedProfile: nil)
                  && store.state.tabs.allSatisfy { $0.profileID == q.id } && relocated == [[page]],
                  "a data change with no shared Notes or Easels proceeds and carries its Note along")
    }

    static func deletion() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var state = BrowserState.initial()
        let q = BrowserProfile(id: UUID(), name: "Q")
        let b = BrowserSpace(id: UUID(), name: "B", symbol: "circle", color: "B9B5D4", profileID: state.profiles[0].id)
        let c = BrowserSpace(id: UUID(), name: "C", symbol: "circle", color: "B9B5D4", profileID: q.id)
        state.profiles.append(q); state.spaces += [b, c]
        try write(state, to: directory)
        let store = try BrowserStore(directory: directory)
        try check(!store.wouldOrphanProfile(ifDeletingSpace: b.id), "deleting a sharing Space reports nothing")
        try check(store.unusedProfile(ifDeletingSpace: c.id) == UnusedProfile(id: q.id, name: "Q"), "deleting the last Space reports its Profile")
        func delete(_ id: UUID) throws -> SpaceDeletionUndo? {
            var undo: SpaceDeletionUndo?
            store.deleteSpace(SpaceDeletionTarget(spaceID: id, state: store.state)!, documents: [:],
                              shouldCommit: { true }, didCommit: { undo = $0 }) { _ in }
            return undo
        }
        let shared = try delete(b.id)
        try check(shared != nil && store.unusedProfile(state.profiles[0].id) == nil, "shared deletion leaves the Profile in use")
        try check(shared.flatMap { $0.restoring(in: store.state) } != nil, "shared deletion keeps its Undo")
        try check(try delete(c.id) != nil, "last Space deletes")
        let unused = store.unusedProfile(q.id)
        try check(unused == UnusedProfile(id: q.id, name: "Q"), "Profile is unused after deletion")
        try check(try store.stageRemoval(of: unused!).profileID == q.id && store.isProfileRemovalPending(q.id), "removal stages right after deletion")
    }

    static func legacyRemovalFallback() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var state = BrowserState.initial()
        let p = state.profiles[0]
        state.settings.defaultProfileID = p.id
        let r = BrowserProfile(id: UUID(), name: "R")
        state.profiles.append(r)
        state.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: r.id, profileName: "R", fallbackProfileID: nil)]
        try write(state, to: directory)
        let store = try BrowserStore(directory: directory)
        try check(store.state.profileRemovals.first?.fallbackProfileID == p.id,
                  "a removal pending from before sharing keeps the Default it was journaled with")
        try check(try BrowserStore(directory: directory).state.profileRemovals.first?.fallbackProfileID == p.id,
                  "that recorded fallback persists, so a later Default handoff cannot change it")
    }

    static func warnings() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var state = BrowserState.initial()
        let p = state.profiles[0], q = BrowserProfile(id: UUID(), name: "Q")
        state.spaces[0].name = "Alpha"
        let a = state.spaces[0]
        let b = BrowserSpace(id: UUID(), name: "Beta", symbol: "circle", color: "B9B5D4", profileID: p.id)
        let c = BrowserSpace(id: UUID(), name: "Gamma", symbol: "circle", color: "B9B5D4", profileID: q.id)
        state.profiles.append(q); state.spaces += [b, c]
        try write(state, to: directory)
        let store = try BrowserStore(directory: directory)

        let reload = store.sharingWarning(forSpace: a.id, to: .share(withSpace: c.id))
        try check(reload == .share(target: "Gamma", space: "Alpha", discardsOwnData: false)
            && reload?.title == "Share Gamma’s data with Alpha?" && reload?.confirm == "Share Data" && reload?.destructive == false
            && reload?.message == "Alpha’s pages will reload with Gamma’s logins, history, extensions and Favorites.",
                  "joining other data while the old data stays in use only warns about the reload")
        let discard = store.sharingWarning(forSpace: c.id, to: .share(withSpace: a.id))
        try check(discard == .share(target: "Alpha", space: "Gamma", discardsOwnData: true)
            && discard?.title == "Share Alpha’s data with Gamma?" && discard?.confirm == "Share Data" && discard?.destructive == true
            && discard?.message == "Gamma’s pages will reload signed in as Alpha. Gamma’s own logins, saved passwords and history will be deleted. This can’t be undone.",
                  "joining other data while the old data becomes unused asks for a destructive confirmation")
        try check(store.sharingWarning(forSpace: b.id, to: .share(withSpace: a.id)) == nil, "choosing the data a Space already has asks nothing")
        try check(store.sharingWarning(forSpace: a.id, to: .share(withSpace: a.id)) == nil
            && store.sharingWarning(forSpace: a.id, to: .share(withSpace: UUID())) == nil, "an unknown or own Space asks nothing")
        let keep = store.sharingWarning(forSpace: a.id, to: .separate)
        try check(keep == .keepSeparate(space: "Alpha") && keep?.title == "Keep Alpha separate?" && keep?.confirm == "Keep Separate" && keep?.destructive == false
            && keep?.message == "It starts fresh: signed out of every site, with no history, extensions or Favorites.",
                  "separating a sharing Space warns that it starts fresh")
        try check(store.sharingWarning(forSpace: c.id, to: .separate) == nil, "keeping an already separate Space asks nothing")
        try check(SpaceSharingWarning.deletionNote == "This also deletes its logins, saved passwords and history. This can’t be undone.",
                  "the deletion note names what is lost")
    }

    static func legacyAppWideKey() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var object = try JSONSerialization.jsonObject(with: encoder.encode(BrowserState.initial())) as! [String: Any]
        var settings = object["settings"] as? [String: Any] ?? [:]
        settings["appWidePreferences"] = ["searchKeyword": "g", "promptForDownload": true, "version": 1]
        object["settings"] = settings
        let data = try JSONSerialization.data(withJSONObject: object)
        try check((try? decoder.decode(BrowserState.self, from: data)) != nil, "an old settings file with the retired app-wide key still loads")
    }
}
