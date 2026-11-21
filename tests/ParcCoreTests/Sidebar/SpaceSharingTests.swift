import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SpaceSharingTests {
    @MainActor final class Folder {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-sharing-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }

        func write(_ state: BrowserState) throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: url.appendingPathComponent("session.json"))
        }

        func store(now: (() -> Date)? = nil) throws -> BrowserStore {
            if let now { return try BrowserStore(directory: url, now: now) }
            return try BrowserStore(directory: url)
        }
    }

    static func tab(_ space: BrowserSpace, _ url: String, kind: TabKind = .today, accessed: Date = Date()) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: url, kind: kind,
                   createdAt: accessed, lastAccessed: accessed, savedURL: url, savedTitle: url)
    }

    func tab(_ space: BrowserSpace, _ url: String, kind: TabKind = .today, accessed: Date = Date()) -> BrowserTab {
        Self.tab(space, url, kind: kind, accessed: accessed)
    }

    struct Upgrade {
        let folder: Folder
        let store: BrowserStore
        let work: BrowserProfile
        let leaving: BrowserProfile
        let shared: BrowserProfile
        let s1: BrowserSpace
        let s2: BrowserSpace
        let theme: SpaceTheme
        let elsewhere: UUID
        let made: [BrowserSpace]

        @MainActor init() throws {
            folder = try Folder()
            var state = BrowserState.initial()
            state.spaceSharingVersion = 0
            state.spaces[0].autoArchiveHours = nil
            var theme = state.spaces[0].theme
            theme.noise = 0.4
            state.spaces[0].theme = theme
            self.theme = theme
            work = BrowserProfile(id: UUID(), name: "Work", autoArchiveHours: AutoArchiveInterval.sevenDays.rawValue)
            leaving = BrowserProfile(id: UUID(), name: "Leaving")
            shared = BrowserProfile(id: UUID(), name: "Shared", autoArchiveHours: AutoArchiveInterval.thirtyDays.rawValue)
            state.profiles += [work, leaving, shared]
            state.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: leaving.id, profileName: leaving.name)]
            s1 = BrowserSpace(id: UUID(), name: "One", symbol: "circle", color: "B9B5D4", profileID: shared.id)
            s2 = BrowserSpace(id: UUID(), name: "Two", symbol: "circle", color: "B9B5D4", profileID: shared.id)
            state.spaces += [s1, s2]
            elsewhere = UUID()
            let routes = LinkRoutingState(rules: [
                LinkRoute(destination: .profile(work.id)), LinkRoute(destination: .profile(shared.id)),
                LinkRoute(destination: .profile(leaving.id)), LinkRoute(destination: .space(elsewhere)),
                LinkRoute(destination: .mostRecent)])
            try JSONEncoder().encode(routes).write(to: folder.url.appendingPathComponent("link-routing.json"))
            try folder.write(state)
            store = try folder.store()
            let workID = work.id
            made = store.state.spaces.filter { $0.profileID == workID }
        }
    }

    @Test func anUnusedProfileGetsItsOwnNamedSpace() throws {
        let upgrade = try Upgrade()
        #expect(upgrade.made.count == 1)
        #expect(upgrade.made[0].name == "Work")
        #expect(upgrade.made[0].symbol == "circle.fill")
    }

    @Test func aNewSpaceCopiesThemeAndProfileArchiveInterval() throws {
        let upgrade = try Upgrade()
        #expect(upgrade.made[0].theme == upgrade.theme)
        #expect(upgrade.made[0].autoArchiveHours == upgrade.work.autoArchiveHours)
    }

    @Test func aPendingRemovalGetsNoSpace() throws {
        let upgrade = try Upgrade()
        #expect(!upgrade.store.state.spaces.contains { $0.profileID == upgrade.leaving.id })
    }

    @Test func sharingSpacesKeepSharing() throws {
        let upgrade = try Upgrade()
        #expect(upgrade.store.state.spaces.filter { $0.profileID == upgrade.shared.id }.map(\.id) == [upgrade.s1.id, upgrade.s2.id])
    }

    @Test func spacesSeedTheArchiveIntervalFromTheirProfile() throws {
        let upgrade = try Upgrade()
        #expect(upgrade.store.state.spaces.first { $0.id == upgrade.s1.id }?.autoArchiveHours == upgrade.shared.autoArchiveHours)
        #expect(upgrade.store.state.spaces[0].autoArchiveHours == AutoArchiveInterval.twelveHours.rawValue)
    }

    @Test func theUpgradeDeletesNothingAndRecordsItsVersion() throws {
        let upgrade = try Upgrade()
        #expect(upgrade.store.state.spaceSharingVersion == SpaceSharing.version)
        #expect(upgrade.store.state.profiles.count == 4)
        #expect(upgrade.store.state.profilesWithoutSpaces.isEmpty)
    }

    @Test func profileRoutesConvertToTheFirstSpaceOrMostRecentAndPersist() throws {
        let upgrade = try Upgrade()
        let destinations = upgrade.store.linkRouting.state.rules.map(\.destination)
        #expect(destinations == [.space(upgrade.made[0].id), .space(upgrade.s1.id), .mostRecent, .space(upgrade.elsewhere), .mostRecent])
        #expect(LinkRoutingStore(directory: upgrade.folder.url).state.rules.map(\.destination) == destinations)
    }

    @Test func theUpgradePersistedOnceAndIsIdempotent() throws {
        let upgrade = try Upgrade()
        let reloaded = try upgrade.folder.store()
        #expect(reloaded.state == upgrade.store.state)
        var again = reloaded.state
        let upgradedAgain = again.upgradeSpaceSharing()
        #expect(!upgradedAgain)
        #expect(again == reloaded.state)
    }

    struct Archive {
        let folder: Folder
        let store: BrowserStore
        let first: BrowserSpace
        let second: BrowserSpace
        let a: BrowserTab

        @MainActor init() throws {
            folder = try Folder()
            let now = Date()
            var state = BrowserState.initial()
            first = state.spaces[0]
            var second = BrowserSpace(id: UUID(), name: "Later", symbol: "circle", color: "B9B5D4", profileID: first.profileID)
            second.autoArchiveHours = AutoArchiveInterval.sevenDays.rawValue
            self.second = second
            state.spaces.append(second)
            let old = now.addingTimeInterval(-2 * 86_400)
            a = SpaceSharingTests.tab(first, "https://a.example", accessed: old)
            let b = SpaceSharingTests.tab(second, "https://b.example", accessed: old)
            let kept = SpaceSharingTests.tab(first, "https://kept.example", kind: .pinned)
            state.tabs = [a, b, kept]
            state.selectedTabIDs = [kept.id]
            state.selectionBySpace[first.id.uuidString] = [kept.id]
            state.autoArchiveStartedAt = now.addingTimeInterval(-30 * 86_400)
            try folder.write(state)
            store = try folder.store(now: { now })
        }
    }

    @Test func archiveIntervalsArePerSpace() throws {
        let archive = try Archive()
        #expect(archive.store.autoArchiveInterval(forSpace: archive.first.id) == .twelveHours)
        #expect(archive.store.autoArchiveInterval(forSpace: archive.second.id) == .sevenDays)
    }

    @Test func theArchiveSweepFollowsEachSpacesOwnInterval() throws {
        let archive = try Archive()
        #expect(archive.store.archiveExpiredTabs() == [archive.a.id])
    }

    @Test func settingOneSpacesIntervalLeavesOthersAndTheProfileAlone() throws {
        let archive = try Archive()
        #expect(try archive.store.setAutoArchiveInterval(.thirtyDays, forSpace: archive.first.id))
        #expect(archive.store.autoArchiveInterval(forSpace: archive.first.id) == .thirtyDays)
        #expect(archive.store.autoArchiveInterval(forSpace: archive.second.id) == .sevenDays)
        #expect(archive.store.state.profiles[0].autoArchiveHours == AutoArchiveInterval.twelveHours.rawValue)
    }

    @Test func aSpaceIntervalPersistsAndAnUnchangedOneWritesNothing() throws {
        let archive = try Archive()
        _ = try archive.store.setAutoArchiveInterval(.thirtyDays, forSpace: archive.first.id)
        #expect(try archive.folder.store().autoArchiveInterval(forSpace: archive.first.id) == .thirtyDays)
        #expect(try !archive.store.setAutoArchiveInterval(.thirtyDays, forSpace: archive.first.id))
    }

    @Test func aNewSpaceInheritsTheCreatingSpacesInterval() throws {
        let archive = try Archive()
        _ = try archive.store.setAutoArchiveInterval(.thirtyDays, forSpace: archive.first.id)
        let created = archive.store.createSpace(name: "New")
        #expect(archive.store.autoArchiveInterval(forSpace: created) == .thirtyDays)
    }

    @Test func aProfileSettingReachesItsSpaces() throws {
        let archive = try Archive()
        _ = try archive.store.changeAutoArchiveInterval(.oneHour, for: archive.first.profileID)
        #expect(archive.store.state.spaces.allSatisfy { $0.autoArchiveHours == AutoArchiveInterval.oneHour.rawValue })
    }

    @Test func aMissingOrInvalidIntervalDecodesAsNil() throws {
        let archive = try Archive()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive.second)) as? [String: Any])
        json.removeValue(forKey: "autoArchiveHours")
        #expect(try JSONDecoder().decode(BrowserSpace.self, from: JSONSerialization.data(withJSONObject: json)).autoArchiveHours == nil)
        json["autoArchiveHours"] = 5
        #expect(try JSONDecoder().decode(BrowserSpace.self, from: JSONSerialization.data(withJSONObject: json)).autoArchiveHours == nil)
    }

    @Test func keepSeparateCreatesASpaceOnANewProfileNamedAfterIt() throws {
        let folder = try Folder()
        try folder.write(.initial())
        let store = try folder.store()
        let home = store.activeSpace
        let work = try store.createSpace(name: " Work ", sharing: .separate)
        let space = try #require(store.state.spaces.first { $0.id == work })
        #expect(space.profileID != home.profileID)
        #expect(store.state.profiles.count == 2)
        #expect(store.state.profiles.last?.name == "Work")
        #expect(space.name == "Work")
        #expect(store.activeSpaceID == work)
    }

    @Test func shareDataReusesTheSpacesProfileAndCreationPersists() throws {
        let folder = try Folder()
        try folder.write(.initial())
        let store = try folder.store()
        let home = store.activeSpace
        _ = try store.createSpace(name: "Work", sharing: .separate)
        let shared = try store.createSpace(name: "Play", sharing: .share(withSpace: home.id))
        #expect(store.state.spaces.first { $0.id == shared }?.profileID == home.profileID)
        #expect(store.state.profiles.count == 2)
        #expect(try folder.store().state.profiles.count == 2)
    }

    @Test func aFailedSaveCreatesNeitherSpaceNorProfile() throws {
        let folder = try Folder()
        try folder.write(.initial())
        let store = try folder.store()
        let before = store.state
        try FileManager.default.removeItem(at: folder.url)
        try Data().write(to: folder.url)
        #expect((try? store.createSpace(name: "Broken", sharing: .separate)) == nil)
        #expect(store.state == before)
        try FileManager.default.removeItem(at: folder.url)
    }

    struct Draft {
        let folder: Folder
        let store: BrowserStore
        let home: BrowserSpace
        let away: BrowserSpace
        let other: BrowserProfile
        let moving: BrowserTab
        let sharing: BrowserTab
        let source: SidebarHierarchySnapshot

        @MainActor init() throws {
            folder = try Folder()
            var state = BrowserState.initial()
            home = state.spaces[0]
            other = BrowserProfile(id: UUID(), name: "Other")
            var away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "B9B5D4", profileID: other.id)
            away.autoArchiveHours = other.autoArchiveHours
            self.away = away
            state.profiles.append(other)
            state.spaces.append(away)
            moving = SpaceSharingTests.tab(home, "https://move.example")
            sharing = SpaceSharingTests.tab(home, "https://share.example")
            state.tabs = [moving, sharing]
            try folder.write(state)
            store = try folder.store()
            source = SidebarHierarchySnapshot(state: store.state, spaceID: home.id, profileID: home.profileID)!
        }
    }

    @Test func choosingKeepSeparateCreatesNothingBeforeCommit() throws {
        let draft = try Draft()
        var empty = try #require(SidebarNewSpaceDraft(from: draft.source, state: draft.store.state))
        empty.name = "Solo"
        empty.keepSeparate()
        let untouched = draft.store.state
        #expect(empty.keepsSeparate)
        #expect(empty.applying(to: draft.store.state) != nil)
        #expect(draft.store.state == untouched)
    }

    @Test func commitAddsTheSpaceAndItsProfileTogether() throws {
        let draft = try Draft()
        var empty = try #require(SidebarNewSpaceDraft(from: draft.source, state: draft.store.state))
        empty.name = "Solo"
        empty.keepSeparate()
        var result: Result<UUID?, Error>?
        draft.store.createSpace(empty) { result = $0 }
        let solo = try result?.get()
        let soloSpace = draft.store.state.spaces.first { $0.id == solo }
        #expect(soloSpace != nil)
        #expect(soloSpace?.profileID == empty.profileID)
        #expect(draft.store.state.profiles.first { $0.id == empty.profileID }?.name == "Solo")
    }

    @Test func movedTabsCrossIntoTheNewSeparateProfile() throws {
        let draft = try Draft()
        var moved = try #require(SidebarNewSpaceDraft(items: [.tab(draft.moving.id)], from: draft.source, state: draft.store.state))
        moved.name = "Moved"
        moved.keepSeparate()
        #expect(moved.movesItemsAcrossProfiles)
        #expect(try draft.store.createSpaceAndMoveSidebarItems(moved) == nil)
        var result: Result<UUID?, Error>?
        draft.store.createSpace(moved) { result = $0 }
        let movedTab = draft.store.state.tabs.first { $0.id == draft.moving.id }
        #expect(try result?.get() == moved.spaceID)
        #expect(movedTab?.spaceID == moved.spaceID)
        #expect(movedTab?.profileID == moved.profileID)
    }

    @Test func sharingMovesTabsOntoTheSharedProfileWithoutANewOne() throws {
        let draft = try Draft()
        var joined = try #require(SidebarNewSpaceDraft(items: [.tab(draft.sharing.id)], from: draft.source, state: draft.store.state))
        joined.name = "Joined"
        let sharesData = joined.shareData(withSpace: draft.away.id, in: draft.store.state)
        #expect(sharesData)
        #expect(!joined.keepsSeparate)
        let profiles = draft.store.state.profiles.count
        var result: Result<UUID?, Error>?
        draft.store.createSpace(joined) { result = $0 }
        #expect(try result?.get() == joined.spaceID)
        #expect(draft.store.state.tabs.first { $0.id == draft.sharing.id }?.profileID == draft.other.id)
        #expect(draft.store.state.profiles.count == profiles)
    }

    struct Change {
        let folder: Folder
        let store: BrowserStore
        let a: BrowserSpace, b: BrowserSpace, c: BrowserSpace
        let p: BrowserProfile, q: BrowserProfile
        let page: BrowserTab
        var outcome: Result<SpaceSharingChange?, Error>?

        @MainActor init() throws {
            folder = try Folder()
            var state = BrowserState.initial()
            a = state.spaces[0]
            p = state.profiles[0]
            state.settings.defaultProfileID = p.id
            q = BrowserProfile(id: UUID(), name: "Q")
            b = BrowserSpace(id: UUID(), name: "B", symbol: "circle", color: "B9B5D4", profileID: p.id)
            c = BrowserSpace(id: UUID(), name: "C", symbol: "circle", color: "B9B5D4", profileID: q.id)
            state.profiles.append(q)
            state.spaces += [b, c]
            page = SpaceSharingTests.tab(c, "https://c.example", kind: .pinned)
            state.tabs = [page]
            try folder.write(state)
            store = try folder.store()
        }

        @MainActor func change(_ space: UUID, _ sharing: SpaceDataSharing) throws -> SpaceSharingChange? {
            var outcome: Result<SpaceSharingChange?, Error>?
            store.changeSharing(ofSpace: space, to: sharing) { outcome = $0 }
            return try #require(outcome).get()
        }
    }

    @Test func joiningAwayFromASoleProfileReportsIt() throws {
        let change = try Change()
        #expect(change.store.wouldOrphanProfile(ifSpace: change.c.id, joins: .share(withSpace: change.a.id)))
        #expect(change.store.unusedProfile(ifSpace: change.c.id, joins: .share(withSpace: change.a.id)) == UnusedProfile(id: change.q.id, name: "Q"))
    }

    @Test func aProfileStillUsedElsewhereIsNotReported() throws {
        let change = try Change()
        #expect(!change.store.wouldOrphanProfile(ifSpace: change.a.id, joins: .share(withSpace: change.c.id)))
    }

    @Test func keepSeparateNeverLeavesAProfileUnused() throws {
        let change = try Change()
        #expect(!change.store.wouldOrphanProfile(ifSpace: change.c.id, joins: .separate))
    }

    @Test func movingToASharedProfileReportsNothingUnused() throws {
        let change = try Change()
        let joined = try change.change(change.a.id, .share(withSpace: change.c.id))
        #expect(joined == SpaceSharingChange(spaceID: change.a.id, profileID: change.q.id, previousProfileID: change.p.id, unusedProfile: nil))
    }

    @Test func keepSeparateMovesTheSpaceToANewProfileNamedAfterItWithItsTabs() throws {
        let change = try Change()
        _ = try change.change(change.a.id, .share(withSpace: change.c.id))
        let profiles = change.store.state.profiles.count
        let split = try change.change(change.c.id, .separate)
        let fresh = try #require(change.store.state.spaces.first { $0.id == change.c.id }).profileID
        #expect(split?.previousProfileID == change.q.id)
        #expect(split?.unusedProfile == nil)
        #expect(fresh != change.q.id)
        #expect(change.store.state.profiles.count == profiles + 1)
        #expect(change.store.state.profiles.last?.name == "C")
        #expect(change.store.state.tabs.first { $0.id == change.page.id }?.profileID == fresh)
        #expect(try change.folder.store().state.spaces.first { $0.id == change.c.id }?.profileID == fresh)
    }

    @Test func aSpaceThatAlreadyKeepsSeparateIsLeftAlone() throws {
        let change = try Change()
        _ = try change.change(change.a.id, .share(withSpace: change.c.id))
        _ = try change.change(change.c.id, .separate)
        let profiles = change.store.state.profiles.count
        #expect(try change.change(change.b.id, .separate) == nil)
        #expect(change.store.state.profiles.count == profiles)
    }

    @Test func leavingAProfileEmptyReportsItAndItsRemovalStages() throws {
        let change = try Change()
        _ = try change.change(change.a.id, .share(withSpace: change.c.id))
        _ = try change.change(change.c.id, .separate)
        let left = try change.change(change.a.id, .share(withSpace: change.c.id))
        let unused = try #require(left?.unusedProfile)
        #expect(unused == UnusedProfile(id: change.q.id, name: "Q"))
        let record = try change.store.stageRemoval(of: unused)
        #expect(record.profileID == change.q.id)
        #expect(change.store.isProfileRemovalPending(change.q.id))
    }

    @Test func removingTheDefaultProfileHandsDefaultToASurvivingProfileInTheSameSave() throws {
        let change = try Change()
        _ = try change.change(change.a.id, .share(withSpace: change.c.id))
        let last = try change.change(change.b.id, .share(withSpace: change.c.id))
        #expect(last?.unusedProfile == UnusedProfile(id: change.p.id, name: change.p.name))
        let fallback = try #require(change.store.state.spaces.first { $0.id == change.c.id }).profileID
        let defaultRecord = try change.store.stageRemoval(of: try #require(last?.unusedProfile))
        #expect(change.store.isProfileRemovalPending(change.p.id))
        #expect(defaultRecord.fallbackProfileID == fallback)
        #expect(change.store.defaultProfileID == fallback)
    }

    final class Blocks {
        let folder: Folder
        let state: BrowserState
        let a: BrowserSpace, b: BrowserSpace, c: BrowserSpace
        let p: BrowserProfile, q: BrowserProfile
        let page = InternalPage.easel(UUID())
        let plans: BrowserTab
        let web: BrowserTab
        var relocated: [[InternalPage]] = []

        @MainActor init() throws {
            folder = try Folder()
            var state = BrowserState.initial()
            p = state.profiles[0]
            q = BrowserProfile(id: UUID(), name: "Q")
            state.spaces[0].name = "Alpha"
            a = state.spaces[0]
            b = BrowserSpace(id: UUID(), name: "Beta", symbol: "circle", color: "B9B5D4", profileID: p.id)
            c = BrowserSpace(id: UUID(), name: "Gamma", symbol: "circle", color: "B9B5D4", profileID: q.id)
            state.profiles.append(q)
            state.spaces += [b, c]
            self.state = state
            var plans = SpaceSharingTests.tab(a, page.urlString)
            plans.title = "Plans"
            plans.savedTitle = "Plans"
            self.plans = plans
            web = SpaceSharingTests.tab(a, "https://a.example")
        }

        @MainActor func load(_ extra: [BrowserTab]) throws -> BrowserStore {
            var next = state
            next.tabs = [plans, web] + extra
            try folder.write(next)
            let store = try folder.store()
            relocated = []
            store.relocateLocalDocuments = { [unowned self] _, pages, _, _ in relocated.append(pages); return {} }
            return store
        }

        @MainActor func change(_ store: BrowserStore, _ sharing: SpaceDataSharing) throws -> SpaceSharingChange? {
            var outcome: Result<SpaceSharingChange?, Error>?
            store.changeSharing(ofSpace: a.id, to: sharing) { outcome = $0 }
            return try #require(outcome).get()
        }

    }

    func assertBlocked(_ blocks: Blocks, extra: [BrowserTab], sharing: SpaceDataSharing, title: String, places: String) throws {
        let store = try blocks.load(extra)
        let before = store.state
        let block = store.sharingDocumentBlock(forSpace: blocks.a.id, to: sharing)
        #expect(block?.title == title)
        #expect(block?.message == "The Easel “Plans” is still used elsewhere on Alpha’s current data: " + places + ".")
        #expect(try blocks.change(store, sharing) == nil)
        #expect(store.state == before)
        #expect(blocks.relocated.isEmpty)
    }

    @Test func aFavoriteExplainsWhyTheDataCannotChange() throws {
        let blocks = try Blocks()
        try assertBlocked(blocks, extra: [Self.tab(blocks.a, blocks.page.urlString, kind: .favorite)], sharing: .separate,
                          title: "Can’t keep Alpha separate", places: "in Favorites")
    }

    @Test func anArchivedEntryExplainsWhyTheDataCannotChange() throws {
        let blocks = try Blocks()
        var archived = Self.tab(blocks.a, blocks.page.urlString)
        archived.archivedAt = Date()
        try assertBlocked(blocks, extra: [archived], sharing: .share(withSpace: blocks.c.id),
                          title: "Can’t share Gamma’s data with Alpha", places: "in the Archive")
    }

    @Test func anEntryInASpaceSharingTheOldDataExplainsWhyTheDataCannotChange() throws {
        let blocks = try Blocks()
        try assertBlocked(blocks, extra: [Self.tab(blocks.b, blocks.page.urlString)], sharing: .share(withSpace: blocks.c.id),
                          title: "Can’t share Gamma’s data with Alpha", places: "in Today in Beta")
    }

    @Test func anEaselUsedOnlyInTheChangingSpaceHasNothingToExplain() throws {
        let blocks = try Blocks()
        let store = try blocks.load([])
        #expect(store.sharingDocumentBlock(forSpace: blocks.a.id, to: .share(withSpace: blocks.c.id)) == nil)
        #expect(store.sharingDocumentBlock(forSpace: blocks.a.id, to: .separate) == nil)
    }

    @Test func aChoiceThatChangesNothingHasNothingToExplain() throws {
        let blocks = try Blocks()
        let store = try blocks.load([])
        #expect(store.sharingDocumentBlock(forSpace: blocks.b.id, to: .share(withSpace: blocks.a.id)) == nil)
        #expect(store.sharingDocumentBlock(forSpace: blocks.c.id, to: .separate) == nil)
        #expect(store.sharingDocumentBlock(forSpace: blocks.a.id, to: .share(withSpace: UUID())) == nil)
    }

    @Test func withoutBlockingEntriesTheDataWarningIsStillAsked() throws {
        let blocks = try Blocks()
        let store = try blocks.load([])
        #expect(store.sharingWarning(forSpace: blocks.a.id, to: .share(withSpace: blocks.c.id))
                == .share(target: "Gamma", space: "Alpha", discardsOwnData: false))
    }

    @Test func aDataChangeWithNoSharedEaselsProceedsAndCarriesItsEaselAlong() throws {
        let blocks = try Blocks()
        let store = try blocks.load([])
        let joined = try blocks.change(store, .share(withSpace: blocks.c.id))
        #expect(joined == SpaceSharingChange(spaceID: blocks.a.id, profileID: blocks.q.id, previousProfileID: blocks.p.id, unusedProfile: nil))
        #expect(store.state.tabs.allSatisfy { $0.profileID == blocks.q.id })
        #expect(blocks.relocated == [[blocks.page]])
    }

    struct Deletion {
        let folder: Folder
        let store: BrowserStore
        let b: BrowserSpace, c: BrowserSpace
        let q: BrowserProfile
        let defaultProfile: BrowserProfile

        @MainActor init() throws {
            folder = try Folder()
            var state = BrowserState.initial()
            q = BrowserProfile(id: UUID(), name: "Q")
            defaultProfile = state.profiles[0]
            b = BrowserSpace(id: UUID(), name: "B", symbol: "circle", color: "B9B5D4", profileID: state.profiles[0].id)
            c = BrowserSpace(id: UUID(), name: "C", symbol: "circle", color: "B9B5D4", profileID: q.id)
            state.profiles.append(q)
            state.spaces += [b, c]
            try folder.write(state)
            store = try folder.store()
        }

        @MainActor func delete(_ id: UUID) -> SpaceDeletionUndo? {
            var undo: SpaceDeletionUndo?
            store.deleteSpace(SpaceDeletionTarget(spaceID: id, state: store.state)!, documents: [:],
                              shouldCommit: { true }, didCommit: { undo = $0 }) { _ in }
            return undo
        }
    }

    @Test func deletingASharingSpaceReportsNothing() throws {
        let deletion = try Deletion()
        #expect(!deletion.store.wouldOrphanProfile(ifDeletingSpace: deletion.b.id))
    }

    @Test func deletingTheLastSpaceReportsItsProfile() throws {
        let deletion = try Deletion()
        #expect(deletion.store.unusedProfile(ifDeletingSpace: deletion.c.id) == UnusedProfile(id: deletion.q.id, name: "Q"))
    }

    @Test func aSharedDeletionLeavesTheProfileInUseAndKeepsItsUndo() throws {
        let deletion = try Deletion()
        let shared = deletion.delete(deletion.b.id)
        #expect(shared != nil)
        #expect(deletion.store.unusedProfile(deletion.defaultProfile.id) == nil)
        #expect(shared.flatMap { $0.restoring(in: deletion.store.state) } != nil)
    }

    @Test func theProfileIsUnusedAfterTheLastSpaceDeletesAndItsRemovalStages() throws {
        let deletion = try Deletion()
        #expect(deletion.delete(deletion.c.id) != nil)
        let unused = try #require(deletion.store.unusedProfile(deletion.q.id))
        #expect(unused == UnusedProfile(id: deletion.q.id, name: "Q"))
        #expect(try deletion.store.stageRemoval(of: unused).profileID == deletion.q.id)
        #expect(deletion.store.isProfileRemovalPending(deletion.q.id))
    }

    @Test func aLegacyRemovalKeepsTheDefaultItWasJournaledWith() throws {
        let folder = try Folder()
        var state = BrowserState.initial()
        let p = state.profiles[0]
        state.settings.defaultProfileID = p.id
        let r = BrowserProfile(id: UUID(), name: "R")
        state.profiles.append(r)
        state.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: r.id, profileName: "R", fallbackProfileID: nil)]
        try folder.write(state)
        let store = try folder.store()
        #expect(store.state.profileRemovals.first?.fallbackProfileID == p.id)
        #expect(try folder.store().state.profileRemovals.first?.fallbackProfileID == p.id)
    }

    struct Warnings {
        let store: BrowserStore
        let a: BrowserSpace, b: BrowserSpace, c: BrowserSpace
        let folder: Folder

        @MainActor init() throws {
            folder = try Folder()
            var state = BrowserState.initial()
            let p = state.profiles[0], q = BrowserProfile(id: UUID(), name: "Q")
            state.spaces[0].name = "Alpha"
            a = state.spaces[0]
            b = BrowserSpace(id: UUID(), name: "Beta", symbol: "circle", color: "B9B5D4", profileID: p.id)
            c = BrowserSpace(id: UUID(), name: "Gamma", symbol: "circle", color: "B9B5D4", profileID: q.id)
            state.profiles.append(q)
            state.spaces += [b, c]
            try folder.write(state)
            store = try folder.store()
        }
    }

    @Test func joiningOtherDataWhileTheOldDataStaysInUseOnlyWarnsAboutTheReload() throws {
        let warnings = try Warnings()
        let reload = warnings.store.sharingWarning(forSpace: warnings.a.id, to: .share(withSpace: warnings.c.id))
        #expect(reload == .share(target: "Gamma", space: "Alpha", discardsOwnData: false))
        #expect(reload?.title == "Share Gamma’s data with Alpha?")
        #expect(reload?.confirm == "Share Data")
        #expect(reload?.destructive == false)
        #expect(reload?.message == "Alpha’s pages will reload with Gamma’s logins, history, extensions and Favorites.")
    }

    @Test func joiningOtherDataWhileTheOldDataBecomesUnusedAsksForADestructiveConfirmation() throws {
        let warnings = try Warnings()
        let discard = warnings.store.sharingWarning(forSpace: warnings.c.id, to: .share(withSpace: warnings.a.id))
        #expect(discard == .share(target: "Alpha", space: "Gamma", discardsOwnData: true))
        #expect(discard?.title == "Share Alpha’s data with Gamma?")
        #expect(discard?.confirm == "Share Data")
        #expect(discard?.destructive == true)
        #expect(discard?.message == "Gamma’s pages will reload signed in as Alpha. Gamma’s own logins, saved passwords and history will be deleted. This can’t be undone.")
    }

    @Test func choosingTheDataASpaceAlreadyHasAsksNothing() throws {
        let warnings = try Warnings()
        #expect(warnings.store.sharingWarning(forSpace: warnings.b.id, to: .share(withSpace: warnings.a.id)) == nil)
    }

    @Test func anUnknownOrOwnSpaceAsksNothing() throws {
        let warnings = try Warnings()
        #expect(warnings.store.sharingWarning(forSpace: warnings.a.id, to: .share(withSpace: warnings.a.id)) == nil)
        #expect(warnings.store.sharingWarning(forSpace: warnings.a.id, to: .share(withSpace: UUID())) == nil)
    }

    @Test func separatingASharingSpaceWarnsThatItStartsFresh() throws {
        let warnings = try Warnings()
        let keep = warnings.store.sharingWarning(forSpace: warnings.a.id, to: .separate)
        #expect(keep == .keepSeparate(space: "Alpha"))
        #expect(keep?.title == "Keep Alpha separate?")
        #expect(keep?.confirm == "Keep Separate")
        #expect(keep?.destructive == false)
        #expect(keep?.message == "It starts fresh: signed out of every site, with no history, extensions or Favorites.")
    }

    @Test func keepingAnAlreadySeparateSpaceAsksNothing() throws {
        let warnings = try Warnings()
        #expect(warnings.store.sharingWarning(forSpace: warnings.c.id, to: .separate) == nil)
    }

    @Test func theDeletionNoteNamesWhatIsLost() {
        #expect(SpaceSharingWarning.deletionNote == "This also deletes its logins, saved passwords and history. This can’t be undone.")
    }

    @Test func anOldSettingsFileWithTheRetiredAppWideKeyStillLoads() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(BrowserState.initial())) as? [String: Any])
        var settings = object["settings"] as? [String: Any] ?? [:]
        settings["appWidePreferences"] = ["searchKeyword": "g", "promptForDownload": true, "version": 1]
        object["settings"] = settings
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect((try? decoder.decode(BrowserState.self, from: data)) != nil)
    }
}
