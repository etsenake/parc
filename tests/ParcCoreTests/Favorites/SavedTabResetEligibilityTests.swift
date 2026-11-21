import Foundation
import Testing
@testable import ParcCore

struct SavedTabResetEligibilityTests {
    struct Pair: Sendable, CustomTestStringConvertible {
        let left: String
        let right: String
        init(_ left: String, _ right: String) { self.left = left; self.right = right }
        var testDescription: String { "\(left) versus \(right)" }
    }

    static let equivalent: [Pair] = [
        Pair("https://example.test/home", "https://example.test/home"),
        Pair("http://example.test/home", "https://example.test/home"),
        Pair("https://www.example.test/home", "https://example.test/home"),
        Pair("https://WWW.Example.test/HOME?Mode=FULL", "https://example.test/home?mode=full"),
        Pair("https://example.test/home#section", "https://example.test/home#other"),
        Pair("https://example.test/home/", "https://example.test/home"),
        Pair("https://example.test/", "https://example.test"),
        Pair("https://example.test/home#", "https://example.test/home"),
        Pair("https://example.test/home?utm_source=mail&x=1", "https://example.test/home?x=1"),
        Pair("https://example.test/home?x=1&UTM_CAMPAIGN=MAIL", "https://example.test/home?x=1"),
        Pair("https://example.test/home?empty=&flag&x=1", "https://example.test/home?x=1"),
        Pair("https://example.test/home?utm_source=mail&empty=", "https://example.test/home"),
        Pair("https://example.test/home?", "https://example.test/home"),
        Pair("https://example.test/home/#!/route/", "https://example.test/home/#!/route"),
        Pair("//www.example.test/home", "https://example.test/home"),
        Pair("www.example.test/home", "https://example.test/home"),
    ]

    static let distinct: [Pair] = [
        Pair("https://example.test/home", "https://example.test/other"),
        Pair("https://example.test/home", "https://other.test/home"),
        Pair("https://example.test/home?x=1", "https://example.test/home?x=2"),
        Pair("https://example.test/home?a=1&b=2", "https://example.test/home?b=2&a=1"),
        Pair("https://example.test/home?x=1&x=1", "https://example.test/home?x=1"),
        Pair("https://example.test/home?gclid=id", "https://example.test/home"),
        Pair("https://example.test/home?utm=keep", "https://example.test/home"),
        Pair("https://example.test/home?flag=%20", "https://example.test/home"),
        Pair("https://example.test/home//", "https://example.test/home"),
        Pair("https://example.test/home/#!/route", "https://example.test/home#!/route"),
        Pair("https://example.test/home#!/one", "https://example.test/home#!/two"),
        Pair("https://example.test/home#!/route//", "https://example.test/home#!/route"),
        Pair("https://example.test/home#!", "https://example.test/home"),
        Pair("https://example.test:443/home", "https://example.test/home"),
        Pair("https://person:secret@example.test/home", "https://example.test/home"),
        Pair("https://www.www.example.test/home", "https://example.test/home"),
        Pair("ftp://example.test/home", "https://example.test/home"),
        Pair("https://example.test/home?x=%61", "https://example.test/home?x=a"),
        Pair("www.example.test/home/", "https://example.test/home"),
    ]

    @Test(arguments: equivalent)
    func equivalentAddressesAreNotAway(pair: Pair) {
        #expect(!SavedTabURLComparison.isAway(current: URL(string: pair.left), saved: URL(string: pair.right)))
        #expect(!SavedTabURLComparison.isAway(current: URL(string: pair.right), saved: URL(string: pair.left)))
    }

    @Test(arguments: distinct)
    func distinctAddressesAreAway(pair: Pair) {
        #expect(SavedTabURLComparison.isAway(current: URL(string: pair.left), saved: URL(string: pair.right)))
        #expect(SavedTabURLComparison.isAway(current: URL(string: pair.right), saved: URL(string: pair.left)))
    }

    @Test func missingCurrentMetadataHasNoAwayVerdict() {
        #expect(!SavedTabURLComparison.isAway(current: nil, saved: URL(string: "https://example.test")))
    }

    @Test func aMissingHomeHasNoAwayVerdict() {
        #expect(!SavedTabURLComparison.isAway(current: URL(string: "https://example.test"), saved: nil))
    }

    let now = Date(timeIntervalSince1970: 1000)
    let saved = "http://WWW.Example.test/Home/?utm_source=Mail#Saved"
    let profile: UUID
    let space: UUID
    var state = BrowserState.initial()
    let tab: BrowserTab

    init() {
        let state = BrowserState.initial()
        profile = state.profiles[0].id
        space = state.activeSpaceID
        self.state = state
        tab = BrowserTab(id: UUID(), spaceID: space, profileID: profile,
            url: "https://example.test/home#current", title: "Live", kind: .pinned,
            createdAt: now, lastAccessed: now, savedURL: saved, savedTitle: "Saved", customTitle: "Mine")
    }

    @Test func aPinnedEquivalentHomeHasNoReset() {
        #expect(tab.resetDestination == nil)
    }

    @Test func aFavoriteSharesTheExactSamePredicate() {
        var tab = tab
        tab.kind = .favorite
        #expect(tab.resetDestination == nil)
    }

    @Test func resetReturnsTheUntouchedOriginalSavedURLAndNeverMutatesNavigation() {
        var tab = tab
        tab.kind = .favorite
        tab.url = "https://example.test/other?utm_source=Current"
        #expect(tab.resetDestination?.absoluteString == saved)
        #expect(tab.url == "https://example.test/other?utm_source=Current")
    }

    @Test func todayNeverGainsASavedReset() {
        var tab = tab
        tab.url = "https://example.test/other"
        tab.kind = .today
        #expect(tab.resetDestination == nil)
    }

    @Test func anArchivedItemCannotReset() {
        var tab = tab
        tab.url = "https://example.test/other"
        tab.archivedAt = now
        #expect(tab.resetDestination == nil)
    }

    @Test func aLocalCurrentDocumentIsExcluded() {
        var tab = tab
        tab.url = "parc://note/" + UUID().uuidString
        #expect(tab.resetDestination == nil)
    }

    @Test func aLocalSavedDocumentIsExcluded() {
        var tab = tab
        tab.url = "https://example.test/other"
        tab.savedURL = "parc://easel/" + UUID().uuidString
        #expect(tab.resetDestination == nil)
    }

    @Test func aStoredDestinationStillRequiresAnActualScheme() {
        var tab = tab
        tab.url = "https://example.test/other"
        tab.savedURL = "example.test/home"
        #expect(tab.resetDestination == nil)
    }

    final class Persisted {
        let directory: URL
        let store: BrowserStore

        @MainActor init(state: BrowserState, now: Date) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("SavedReset-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: directory, now: { now })
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @MainActor func persisted() throws -> Persisted {
        var state = state
        state.tabs = [tab]
        state.selectedTabIDs = [tab.id]
        state.settings.restoreSession = true
        return try Persisted(state: state, now: now)
    }

    @MainActor @Test func anUnclaimedEquivalentDormantItemIsUntouched() throws {
        let store = try persisted().store
        let before = store.state
        store.resetDormantSavedTab(store.state.tabs[0])
        #expect(store.state == before)
    }

    @MainActor @Test func aDormantResetPreservesTheExactOriginalDestinationIdentityAndCustomTitle() throws {
        let store = try persisted().store
        let before = store.state
        store.updateTab(tab.id, title: "Different", url: "https://example.test/other")
        let away = try #require(store.state.tabs.first { $0.id == tab.id })
        store.resetDormantSavedTab(away)
        let reset = try #require(store.state.tabs.first { $0.id == tab.id })
        #expect(reset.url == saved)
        #expect(reset.savedURL == saved)
        #expect(reset.id == tab.id)
        #expect(reset.profileID == profile)
        #expect(reset.customTitle == "Mine")
        #expect(store.state.selectedTabIDs == before.selectedTabIDs)
    }

    @MainActor @Test func anOldSnapshotCannotResetAReplacementState() throws {
        let store = try persisted().store
        store.updateTab(tab.id, title: "Different", url: "https://example.test/other")
        let away = try #require(store.state.tabs.first { $0.id == tab.id })
        store.resetDormantSavedTab(away)
        let reset = try #require(store.state.tabs.first { $0.id == tab.id })
        store.resetDormantSavedTab(away)
        #expect(store.state.tabs.first { $0.id == tab.id } == reset)
    }

    struct Separation {
        let persisted: SavedTabResetEligibilityTests.Persisted
        let today: UUID
        let away: BrowserTab
        let pinned: BrowserTab
        let selection: [UUID]

        @MainActor init(_ suite: SavedTabResetEligibilityTests) throws {
            persisted = try suite.persisted()
            let store = persisted.store
            store.updateTab(suite.tab.id, title: "Different", url: "https://example.test/other")
            away = try #require(store.state.tabs.first { $0.id == suite.tab.id })
            store.resetDormantSavedTab(away)
            today = store.openResolvedURL(URL(string: "https://today.test/")!)
            store.updateTab(suite.tab.id, title: "Away", url: "https://example.test/away")
            pinned = try #require(store.state.tabs.first { $0.id == suite.tab.id })
            selection = store.state.selectedTabIDs
        }
    }

    @MainActor @Test func aStalePinnedSnapshotCannotSeparate() throws {
        let separation = try Separation(self)
        #expect(!separation.persisted.store.separateFromPinnedTab(separation.away, todayID: UUID(), title: "Away"))
    }

    @MainActor @Test func aNavigatedAwayPinnedTabSeparatesIntoAPlainTodayTab() throws {
        let separation = try Separation(self)
        let store = separation.persisted.store
        let separated = UUID()
        #expect(store.separateFromPinnedTab(separation.pinned, todayID: separated, title: "Away page"))
        let moved = try #require(store.state.tabs.first { $0.id == separated })
        #expect(moved.kind == .today)
        #expect(moved.url == "https://example.test/away")
        #expect(moved.title == "Away page")
        #expect(moved.savedURL == moved.url)
        #expect(moved.customTitle == nil)
        #expect(moved.referrerID == nil)
        #expect(moved.spaceID == space)
        #expect(moved.profileID == profile)
    }

    @MainActor @Test func theSeparatedPinnedItemKeepsItsIdentityAndReturnsHome() throws {
        let separation = try Separation(self)
        let store = separation.persisted.store
        #expect(store.separateFromPinnedTab(separation.pinned, todayID: UUID(), title: "Away page"))
        let home = try #require(store.state.tabs.first { $0.id == tab.id })
        #expect(home.url == saved)
        #expect(home.title == "Saved")
        #expect(home.kind == .pinned)
        #expect(home.customTitle == "Mine")
        #expect(home.savedURL == saved)
        #expect(home.folderID == separation.pinned.folderID)
    }

    @MainActor @Test func theSeparatedTabEntersTheTopOfTodayAndLeavesSelectionToTheWindow() throws {
        let separation = try Separation(self)
        let store = separation.persisted.store
        let separated = UUID()
        #expect(store.separateFromPinnedTab(separation.pinned, todayID: separated, title: "Away page"))
        let todayItems = SidebarHierarchy.children(in: .init(spaceID: space, folderID: nil, section: .today), state: store.state)
        #expect(todayItems == [.tab(separated), .tab(separation.today)])
        #expect(store.state.selectedTabIDs == separation.selection)
    }

    @MainActor @Test func aPinnedItemAtHomeAndATodayTabHaveNothingToSeparate() throws {
        let separation = try Separation(self)
        let store = separation.persisted.store
        let separated = UUID()
        #expect(store.separateFromPinnedTab(separation.pinned, todayID: separated, title: "Away page"))
        let home = try #require(store.state.tabs.first { $0.id == tab.id })
        let moved = try #require(store.state.tabs.first { $0.id == separated })
        #expect(!store.separateFromPinnedTab(home, todayID: UUID(), title: ""))
        #expect(!store.separateFromPinnedTab(moved, todayID: UUID(), title: ""))
    }

    @MainActor @Test func anExistingIdentityIsNeverReused() throws {
        let separation = try Separation(self)
        let store = separation.persisted.store
        let separated = UUID()
        #expect(store.separateFromPinnedTab(separation.pinned, todayID: separated, title: "Away page"))
        store.updateTab(tab.id, url: "https://example.test/again")
        let again = try #require(store.state.tabs.first { $0.id == tab.id })
        #expect(!store.separateFromPinnedTab(again, todayID: separated, title: ""))
    }

    @MainActor @Test func aSplitChildHasNoResetTargetToSeparate() throws {
        let separation = try Separation(self)
        let store = separation.persisted.store
        store.updateTab(tab.id, url: "https://example.test/again")
        let again = try #require(store.state.tabs.first { $0.id == tab.id })
        store.setSplit([tab.id, separation.today])
        #expect(!store.separateFromPinnedTab(again, todayID: UUID(), title: ""))
    }
}
