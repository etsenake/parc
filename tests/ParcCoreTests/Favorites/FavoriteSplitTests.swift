import Foundation
import Testing
@testable import ParcCore

struct FavoriteSplitTests {
    let now = Date(timeIntervalSince1970: 1000)
    var state = BrowserState.initial()
    let space: UUID
    let profile: UUID
    let favorite: BrowserTab
    let first: BrowserTab, second: BrowserTab, fourth: BrowserTab
    let trayHome = UUID()

    init() {
        var state = BrowserState.initial()
        let space = state.activeSpaceID, profile = state.profiles[0].id
        let now = self.now
        func tab(_ kind: TabKind, _ name: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile,
                url: "https://example.test/" + name, title: name, kind: kind,
                createdAt: now, lastAccessed: now, savedURL: "https://example.test/" + name, savedTitle: name)
        }
        var favorite = tab(.favorite, "home")
        favorite.customTitle = "My app"
        first = tab(.today, "first")
        second = tab(.today, "second")
        fourth = tab(.today, "fourth")
        state.tabs = [favorite, first, second, fourth]
        state.selectedTabIDs = [first.id]
        self.state = state
        self.space = space
        self.profile = profile
        self.favorite = favorite
    }

    func tab(_ kind: TabKind, _ name: String) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: space, profileID: profile,
            url: "https://example.test/" + name, title: name, kind: kind,
            createdAt: now, lastAccessed: now, savedURL: "https://example.test/" + name, savedTitle: name)
    }

    func request(_ snapshot: BrowserState, focus: UUID, url: String? = nil, id: UUID = UUID(),
                 target: BrowserTab? = nil, homes: [UUID: UUID] = [:]) -> FavoriteSplitRequest? {
        FavoriteSplitRequest(favorite: snapshot.tabs.first { $0.id == (target ?? favorite).id }!,
            spaceID: space, selection: snapshot.selectedTabIDs, focusedID: focus,
            state: snapshot, duplicateURL: url, duplicateTitle: "Live title", newID: id, homeIDs: homes)
    }

    var original: FavoriteSplitRequest { request(state, focus: first.id, homes: [favorite.id: trayHome])! }

    var opened: BrowserState { original.applying(to: state, retiring: [], now: now.addingTimeInterval(1))! }

    var already: BrowserState {
        var already = state
        already.tabs.append(partner)
        already.splitLayouts = [favoriteGroup]
        already.selectedTabIDs = favoriteGroup.tabIDs
        return already
    }

    var partner: BrowserTab { Self.partnerTab(space: space, profile: profile, now: now) }

    static func partnerTab(space: UUID, profile: UUID, now: Date) -> BrowserTab {
        BrowserTab(id: partnerID, spaceID: space, profileID: profile,
            url: "https://example.test/partner", title: "partner", kind: .favorite,
            createdAt: now, lastAccessed: now, savedURL: "https://example.test/partner", savedTitle: "partner")
    }

    static let partnerID = UUID()
    static let favoriteGroupID = UUID()

    var favoriteGroup: BrowserSplitLayout {
        BrowserSplitLayout(id: Self.favoriteGroupID, spaceID: space, tabIDs: [favorite.id, partner.id], widthFactors: [0.5, 0.5], stacks: nil)
    }

    @Test func theReleasedFavoriteNeedsASavedHome() throws {
        let request = try #require(request(state, focus: first.id))
        #expect(request.savedHomeSources(in: state).map(\.id) == [favorite.id])
    }

    @Test func aSavedMemberIsNeverMovedWithoutItsFixedHomeIdentity() throws {
        let request = try #require(request(state, focus: first.id))
        #expect(request.applying(to: state, retiring: [], now: now) == nil)
    }

    @Test func theOriginalFollowsFocus() {
        #expect(opened.selectedTabIDs == [first.id, favorite.id])
    }

    @Test func theOriginalFavoriteIDJoinsTheTodaySplitWithItsPage() throws {
        let joined = try #require(opened.tabs.first { $0.id == favorite.id })
        #expect(joined.kind == .today)
        #expect(joined.spaceID == space)
        #expect(joined.savedURL == favorite.savedURL)
    }

    @Test func theTrayKeepsAFreshHomeAtTheSavedPageAndCustomTitle() throws {
        let home = try #require(opened.tabs.first { $0.id == trayHome })
        #expect(home.kind == .favorite)
        #expect(home.savedURL == favorite.savedURL)
        #expect(home.customTitle == favorite.customTitle)
        #expect(home.url == favorite.savedURL)
        let trayLocation = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
        #expect(SidebarHierarchy.children(in: trayLocation, state: opened) == [.tab(trayHome)])
    }

    @Test func openingFabricatesNoHistoryOrUndo() {
        #expect(opened.history == state.history)
        #expect(opened.recentlyClosedIDs == state.recentlyClosedIDs)
    }

    @Test func openingCreatesOneGenuineTodaySplitAnchoredAtItsOrdinaryMember() {
        #expect(opened.splitLayouts.count == 1)
        #expect(opened.splitLayouts[0].sidebarAnchorID == first.id)
        #expect(opened.selectionBySpace[space.uuidString] == opened.selectedTabIDs)
    }

    func insertedIntoExisting() -> (BrowserSplitLayout, BrowserState) {
        var split = state
        let group = BrowserSplitLayout(customTitle: "Existing group", spaceID: space,
            tabIDs: [first.id, second.id], orientation: .vertical, widthFactors: [0.3, 0.7])
        split.splitLayouts = [group]
        split.selectedTabIDs = group.tabIDs
        return (group, request(split, focus: first.id, homes: [favorite.id: trayHome])!.applying(to: split, retiring: [], now: now)!)
    }

    @Test func insertionIsAfterTheFocusedPaneNotAppended() {
        #expect(insertedIntoExisting().1.selectedTabIDs == [first.id, favorite.id, second.id])
    }

    @Test func anExistingContainerKeepsItsIdentityTitleOrientationAndNormalizedWeights() {
        let (group, inserted) = insertedIntoExisting()
        #expect(inserted.splitLayouts[0].id == group.id)
        #expect(inserted.splitLayouts[0].customTitle == group.customTitle)
        #expect(inserted.splitLayouts[0].orientation == .vertical)
        #expect(abs(inserted.splitLayouts[0].widthFactors.reduce(0, +) - 1) < 0.00001)
    }

    @Test func joiningAnExistingTodaySplitAlsoLeavesTheTrayHome() {
        let inserted = insertedIntoExisting().1
        #expect(inserted.tabs.first { $0.id == favorite.id }?.kind == .today)
        #expect(inserted.tabs.contains { $0.id == trayHome })
    }

    @Test func anAlreadyVisibleTargetRequestsOriginalFocusWithoutADuplicateGroup() throws {
        let already = already
        let focusExisting = try #require(request(already, focus: partner.id))
        #expect(focusExisting.targetID == favorite.id)
        #expect(focusExisting.applying(to: already, retiring: [], now: now)?.splitLayouts == already.splitLayouts)
    }

    func duplicate(url: String = "https://example.test/current") -> (UUID, BrowserState) {
        let already = already
        let newID = UUID()
        let dup = request(already, focus: favorite.id, url: url, id: newID)!
        return (newID, dup.applying(to: already, retiring: [], now: now)!)
    }

    @Test func theDuplicateIsTheItemBeingAddedAndMembersStay() throws {
        let dup = try #require(request(already, focus: favorite.id, url: "https://example.test/current"))
        #expect(dup.savedHomeSources(in: already).isEmpty)
    }

    @Test func aFocusedFavoriteCreatesAnAdjacentCopyInTheDisplayedContainer() throws {
        let (newID, duplicated) = duplicate()
        let copy = try #require(duplicated.tabs.first { $0.id == newID })
        #expect(duplicated.selectedTabIDs == [favorite.id, newID, Self.partnerID])
        #expect(copy.kind == .favorite)
        #expect(copy.folderID == nil)
        #expect(copy.profileID == profile)
    }

    @Test func theLiveDestinationIsCopiedWithoutResetAndAwayHomeUsesTheLiveTitle() throws {
        let (newID, duplicated) = duplicate()
        let copy = try #require(duplicated.tabs.first { $0.id == newID })
        #expect(copy.url == "https://example.test/current")
        #expect(copy.savedURL == copy.url)
        #expect(copy.title == "Live title")
        #expect(copy.customTitle == nil)
    }

    @Test func theOriginalFocusedFavoriteRecordAndSplitIdentityRemainUnchanged() {
        let (_, duplicated) = duplicate()
        #expect(duplicated.tabs.first { $0.id == favorite.id } == already.tabs.first { $0.id == favorite.id })
        #expect(duplicated.splitLayouts.map(\.id) == [Self.favoriteGroupID])
    }

    @Test func aNewSplitFromALoneFavoriteIsATodaySplitAndTheTrayKeepsAFreshHome() throws {
        var lone = state
        lone.selectedTabIDs = [favorite.id]
        let loneID = UUID(), loneHome = UUID()
        let loneRequest = try #require(request(lone, focus: favorite.id, url: "https://example.test/current", id: loneID, homes: [favorite.id: loneHome]))
        #expect(loneRequest.savedHomeSources(in: lone).map(\.id) == [favorite.id])
        let loneSplit = try #require(loneRequest.applying(to: lone, retiring: [], now: now))
        #expect(loneSplit.selectedTabIDs == [favorite.id, loneID])
        #expect(loneSplit.tabs.first { $0.id == loneID }?.kind == .today)
        #expect(loneSplit.tabs.first { $0.id == favorite.id }?.kind == .today)
        #expect(loneSplit.tabs.contains { $0.id == loneHome && $0.kind == .favorite })
        #expect(loneSplit.splitLayouts.first?.sidebarAnchorID == loneID)
        #expect(SidebarHierarchy.children(in: .init(spaceID: space, folderID: nil, section: .today), state: loneSplit).first
                == .split(loneSplit.splitLayouts[0].id))
    }

    @Test func anAtHomeCopyRetainsSavedPresentation() throws {
        let homeCopy = try #require(request(already, focus: favorite.id, url: favorite.savedURL)?.applying(to: already, retiring: [], now: now)?.tabs.last)
        #expect(homeCopy.customTitle == favorite.customTitle)
        #expect(homeCopy.savedTitle == favorite.savedTitle)
    }

    @Test func anEquivalentHomeCopyRetainsPresentationWithoutNormalizingTheDestination() throws {
        let equivalentURL = "http://WWW.Example.test/HOME/?utm_source=Mail#section"
        let equivalentCopy = try #require(request(already, focus: favorite.id, url: equivalentURL)?.applying(to: already, retiring: [], now: now)?.tabs.last)
        #expect(equivalentCopy.customTitle == favorite.customTitle)
        #expect(equivalentCopy.savedTitle == favorite.savedTitle)
        #expect(equivalentCopy.url == equivalentURL)
        #expect(equivalentCopy.savedURL == equivalentURL)
    }

    @Test func aMeaningfulQueryRemainsAwayHome() throws {
        let queryCopy = try #require(request(already, focus: favorite.id, url: favorite.savedURL + "?view=other")?.applying(to: already, retiring: [], now: now)?.tabs.last)
        #expect(queryCopy.customTitle == nil)
        #expect(queryCopy.title == "Live title")
    }

    @Test func noURLIsInventedForADuplicate() {
        #expect(request(already, focus: favorite.id) == nil)
    }

    @Test func noLocalDocumentSurrogateIsAccepted() {
        #expect(request(already, focus: favorite.id, url: "parc://note/" + UUID().uuidString) == nil)
    }

    @Test func aFreshIdentityIsRequired() {
        #expect(request(already, focus: favorite.id, url: favorite.url, id: first.id) == nil)
    }

    @Test func retiringTheTargetAPaneOrTheHomeIdentityIsRefused() {
        #expect(original.applying(to: state, retiring: [favorite.id], now: now) == nil)
        #expect(original.applying(to: state, retiring: [first.id], now: now) == nil)
        #expect(original.applying(to: state, retiring: [trayHome], now: now) == nil)
    }

    @Test func anInterveningSelectionWins() {
        var stale = state
        stale.selectedTabIDs = [second.id]
        #expect(original.applying(to: stale, retiring: [], now: now) == nil)
    }

    @Test func anOriginalItemEditInvalidatesTheCapturedRequest() {
        var stale = state
        stale.tabs[0].savedURL += "/changed"
        #expect(original.applying(to: stale, retiring: [], now: now) == nil)
    }

    @Test func profileReplacementAndRetirementAreRefused() {
        var stale = state
        stale.spaces[0].profileID = UUID()
        #expect(original.applying(to: stale, retiring: [], now: now) == nil)
        stale = state
        stale.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: profile, profileName: "Default")]
        #expect(original.applying(to: stale, retiring: [], now: now) == nil)
        stale = state
        stale.profiles.removeAll()
        #expect(original.applying(to: stale, retiring: [], now: now) == nil)
    }

    @Test func deletionCannotRecreateTheOldOriginal() {
        var stale = state
        stale.tabs.removeAll { $0.id == favorite.id }
        #expect(original.applying(to: stale, retiring: [], now: now) == nil)
    }

    @Test func changedContainerOwnershipIsRefused() {
        var stale = state
        stale.splitLayouts.append(BrowserSplitLayout(customTitle: "Existing group", spaceID: space,
            tabIDs: [first.id, second.id], orientation: .vertical, widthFactors: [0.3, 0.7]))
        #expect(original.applying(to: stale, retiring: [], now: now) == nil)
    }

    @Test func aFifthPaneOrImplicitReplacementIsRefusedButExistingPaneFocusRemainsPossible() {
        var full = state
        full.selectedTabIDs = [first.id, second.id, fourth.id, favorite.id]
        full.splitLayouts = [BrowserSplitLayout(spaceID: space, tabIDs: full.selectedTabIDs, widthFactors: [0.25, 0.25, 0.25, 0.25])]
        #expect(request(full, focus: favorite.id, url: favorite.url) == nil)
        #expect(request(full, focus: first.id) != nil)
    }

    @Test func anUnrelatedSplitIsUntouchedAndMembershipNeverOverlaps() throws {
        let other = tab(.today, "other")
        var oldGroups = state
        oldGroups.tabs.append(other)
        let old = BrowserSplitLayout(spaceID: space, tabIDs: [second.id, other.id, fourth.id], widthFactors: [0.2, 0.3, 0.5])
        oldGroups.splitLayouts = [old]
        let relocated = try #require(request(oldGroups, focus: first.id, target: oldGroups.tabs.first { $0.id == favorite.id },
                                             homes: [favorite.id: trayHome])?.applying(to: oldGroups, retiring: [], now: now))
        #expect(relocated.splitLayouts.first { $0.id == old.id } == old)
        #expect(relocated.splitLayouts.flatMap(\.tabIDs).filter { $0 == favorite.id }.count == 1)
    }

    final class Persisted {
        let directory: URL
        let store: BrowserStore

        @MainActor init(state: BrowserState, now: Date) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("FavoriteSplit-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var state = state
            state.settings.restoreSession = true
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: directory, now: { now })
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @MainActor @Test func theStoreCommitsTheActualCopyAndPublishesTheDurableSession() throws {
        let persisted = try Persisted(state: already, now: now)
        let store = persisted.store
        let savedRequest = try #require(request(store.state, focus: favorite.id, url: favorite.url))
        #expect(try store.commitFavoriteSplit(savedRequest) == savedRequest.targetID)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let disk = try decoder.decode(BrowserState.self, from: Data(contentsOf: persisted.directory.appendingPathComponent("session.json")))
        #expect(disk == store.state)
    }

    @MainActor @Test func aWriteFailureLeavesIdentityAndSelectionUntouchedAndStaysVisibleToTheOwner() throws {
        let persisted = try Persisted(state: already, now: now)
        let store = persisted.store
        let failedRequest = try #require(request(store.state, focus: favorite.id, url: favorite.url))
        let beforeFailure = store.state
        try FileManager.default.removeItem(at: persisted.directory)
        try Data("blocked".utf8).write(to: persisted.directory)
        #expect(throws: (any Error).self) { try store.commitFavoriteSplit(failedRequest) }
        #expect(store.state == beforeFailure)
        #expect(store.persistenceError != nil)
        try FileManager.default.removeItem(at: persisted.directory)
    }

    let a = UUID(), b = UUID(), c = UUID(), d = UUID(), target = UUID()

    func route(_ selection: [UUID], _ focus: UUID?) -> FavoriteOptionRoute {
        FavoriteOptionRoute(favoriteID: target, selection: selection, focusedID: focus)
    }

    @Test func withoutAPresentationTheSelectionPresentsTheFavoriteItself() {
        #expect(route([], nil) == .present)
    }

    @Test func noFocusedPaneToFollowPresentsTheFavorite() {
        #expect(route([a], nil) == .present)
        #expect(route([a], b) == .present)
    }

    @Test func belowCapacityANewPaneFollowsFocus() {
        #expect(route([a], a) == .split)
        #expect(route([a, b, c], b) == .split)
    }

    @Test func anExistingPaneReceivesFocusEvenAtCapacity() {
        #expect(route([a, target], a) == .split)
        #expect(route([a, b, c, target], a) == .split)
    }

    @Test func theFocusedFavoriteIsDuplicatedBelowCapacity() {
        #expect(route([target], target) == .split)
        #expect(route([a, b, target], target) == .split)
    }

    @Test func theFocusedFavoriteAtCapacityIsNotDuplicated() {
        #expect(route([a, b, c, target], target) == .unchanged)
    }

    @Test func aFifthPaneIsRefused() {
        #expect(route([a, b, c, d], b) == .paneLimit)
    }
}
