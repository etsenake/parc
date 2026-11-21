import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct TitleSearchTests {
    private typealias Match = CommandBarTitleMatch
    private typealias Index = CommandBarTitleIndex

    @Test(arguments: [
        ("dashboard", "My Apps Dashboard", true), ("dash", "My Apps Dashboard", true),
        ("ashboard", "My Apps Dashboard", false), ("apps planner", "My Apps Dashboard", false),
        ("node.js", "Node.js documentation", true), ("cafe menu", "Café Menu", true),
        ("东京", "东京天气预报", true), ("phone手机", "iPhone手机", true),
    ])
    func titleWordsMatchOnlyTheirPrefixesOrScriptRuns(query: String, title: String, expected: Bool) throws {
        let words = try #require(CommandBarTitleQuery(query))
        let score = Match.quality(words, CommandBarTitleTokens(titles: [title], host: nil))
        #expect((score?.inTitle == true) == expected)
    }

    @Test(arguments: [("apps dash", "dash apps"), ("my apps", "apps dashboard"), ("apps dashboard", "apps dash")])
    func titleOrderAndWholeWordsImproveTheScore(stronger: String, weaker: String) throws {
        let title = CommandBarTitleTokens(titles: ["My Apps Dashboard"], host: nil)
        let strongWords = try #require(CommandBarTitleQuery(stronger))
        let weakWords = try #require(CommandBarTitleQuery(weaker))
        let strong = try #require(Match.quality(strongWords, title))
        let weak = try #require(Match.quality(weakWords, title))
        #expect(strong.value > weak.value)
    }

    @Test func aSiteNameCanMatchWithoutBeingInTheTitle() throws {
        let words = try #require(CommandBarTitleQuery("fullscript"))
        let tokens = CommandBarTitleTokens(titles: ["My Apps Dashboard"], host: "us.fullscript.com")
        #expect(Match.quality(words, tokens)?.inTitle == false)
    }

    @Test func aTopLevelDomainDoesNotCountAsATitleMatch() throws {
        let words = try #require(CommandBarTitleQuery("com"))
        let tokens = CommandBarTitleTokens(titles: ["My Apps Dashboard"], host: "us.fullscript.com")
        #expect(Match.quality(words, tokens) == nil)
    }

    @Test(arguments: [("dashboard", true, true, true), ("example.test/dash", true, false, false),
                      ("dashboard", true, nil, false), ("dashboard", false, true, false)] as [(String, Bool, Bool?, Bool)])
    func onlyACurrentSearchDefaultEnablesTitleWordScoring(query: String, answered: Bool, search: Bool?, expected: Bool) {
        #expect((Match.wordsQuery(query, nativeRowsAnswer: answered, defaultIsSearch: search) != nil) == expected)
    }

    @Test(arguments: [(30.0, "just now"), (90, "1 minute ago"), (7200, "2 hours ago"), (100_000, "yesterday"),
                      (259_200, "3 days ago"), (2_592_000, "4 weeks ago"), (5_184_000, "2 months ago")])
    func theAgeCaptionReflectsWhenTheTabWasArchived(seconds: Double, expected: String) {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(CommandBarTitleText.age(from: now.addingTimeInterval(-seconds), to: now) == expected)
    }

    @Test func archiveCaptionsGiveVoiceOverThePutBackAction() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let caption = CommandBarTitleText.archivedCaption(archivedAt: now.addingTimeInterval(-259_200), now: now)
        #expect(caption.text == "Archived · 3 days ago")
        #expect(caption.spoken == "Put Back, archived 3 days ago")
    }

    private struct Fixture {
        let profile = UUID()
        let space = UUID()
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        func tab(_ title: String, _ url: String, archivedAgo: TimeInterval? = nil, foreign: Bool = false) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: foreign ? UUID() : profile, url: url, title: title, kind: .today,
                       createdAt: now, lastAccessed: now, archivedAt: archivedAgo.map { now.addingTimeInterval(-$0) },
                       savedURL: url, savedTitle: title)
        }

        func visit(_ title: String, _ url: String, secondsAgo: TimeInterval = 15) -> BrowserHistoryEntry {
            BrowserHistoryEntry(id: UUID(), url: url, title: title, visitedAt: now.addingTimeInterval(-secondsAgo), profileID: profile)
        }

        func index(tabs: [BrowserTab] = [], history: [BrowserHistoryEntry] = [], revision: UInt64 = 1, removals: UInt64 = 0,
                   reusing: CommandBarTitleIndex? = nil) -> CommandBarTitleIndex {
            Index.build(profileID: profile, historyRevision: revision, historyRemovals: removals,
                        tabs: tabs, history: history, reusing: reusing)
        }
    }

    @Test func archivesKeepOnlyTheirProfilesTabsInNewestFirstOrder() {
        let fixture = Fixture()
        let recent = fixture.tab("Planning", "https://docs.example.test/", archivedAgo: 60)
        let older = fixture.tab("Planning poker", "https://poker.example.test/", archivedAgo: 120)
        let open = fixture.tab("Planning board", "https://board.example.test/")
        let foreign = fixture.tab("Planning elsewhere", "https://foreign.example.test/", archivedAgo: 10, foreign: true)
        let index = fixture.index(tabs: [older, open, foreign, recent])
        #expect(index.archived.map(\.tabID) == [recent.id, older.id])
    }

    @Test func aTitleWordHitKeepsTheArchivedTabsActualAddress() throws {
        let fixture = Fixture()
        let tab = fixture.tab("Quarterly Planning — Roadmap", "https://docs.example.test/planning", archivedAgo: 120)
        let words = try #require(CommandBarTitleQuery("planning"))
        let entry = try #require(fixture.index(tabs: [tab]).search(words, now: fixture.now).archived.first?.entry)
        #expect(entry.tabID == tab.id)
        #expect(entry.url == tab.url)
    }

    @Test func repeatVisitsMergeAndKeepTheirCount() {
        let fixture = Fixture()
        let a = fixture.visit("Planning", "https://wiki.example.test/")
        let b = fixture.visit("Planning", "https://www.wiki.example.test/", secondsAgo: 25)
        let index = fixture.index(history: [a, b])
        #expect(index.pages.map(\.url) == [a.url])
        #expect(index.visits(forKey: "page:wiki.example.test") == 2)
    }

    @Test func anUnchangedIndexIsReused() {
        let fixture = Fixture()
        let tab = fixture.tab("Quarterly Planning", "https://docs.example.test/planning", archivedAgo: 180)
        let visit = fixture.visit("Planning", "https://wiki.example.test/")
        let original = fixture.index(tabs: [tab], history: [visit])
        #expect(fixture.index(tabs: [tab], history: [visit], reusing: original) === original)
    }

    @Test func removingHistoryWithdrawsTheRemovedEntry() {
        let fixture = Fixture()
        let recent = fixture.visit("Planning", "https://wiki.example.test/")
        let older = fixture.visit("Roadmap", "https://docs.example.test/", secondsAgo: 45)
        let original = fixture.index(history: [recent, older])
        let changed = fixture.index(history: [older], removals: 1, reusing: original)
        #expect(changed.withdrawsEntries(of: original))
        #expect(changed.pages.map(\.url) == [older.url])
    }

    @Test func puttingBackATabWithdrawsItsArchivedRow() {
        let fixture = Fixture()
        var restored = fixture.tab("Quarterly Planning", "https://docs.example.test/planning", archivedAgo: 120)
        let original = fixture.index(tabs: [restored])
        restored.archivedAt = nil
        let changed = fixture.index(tabs: [restored], reusing: original)
        #expect(changed.withdrawsEntries(of: original))
        #expect(changed.archived.isEmpty)
    }
    @MainActor private final class Queue {
        private var work: [@Sendable () -> Void] = []

        func enqueue(_ job: @escaping @Sendable () -> Void) { work.append(job) }

        func runNext() throws {
            let job = try #require(work.first)
            work.removeFirst()
            job()
        }
    }

    @Test @MainActor func theIndexIsPublishedOnlyAfterBuildingAndDelivery() throws {
        let fixture = Fixture()
        let build = Queue(), deliver = Queue()
        let cache = CommandBarTitleIndexCache(scheduleBuild: build.enqueue, scheduleDelivery: deliver.enqueue)
        let stamp = Index.Stamp(profileID: fixture.profile, state: 1, history: 1, removals: 0)
        var received: CommandBarTitleIndex?
        cache.onBuilt = { received = $0 }
        let tab = fixture.tab("Quarterly Planning", "https://docs.example.test/planning", archivedAgo: 120)
        cache.request(stamp) { ([tab], []) }
        #expect(cache.index(for: stamp) == nil)
        try build.runNext()
        #expect(received == nil)
        try deliver.runNext()
        #expect(cache.index(for: stamp) === received)
        #expect(received?.archived.map(\.tabID) == [tab.id])
    }

    @Test @MainActor func anAlreadyBuiltStampDoesNotReadTheStoreAgain() throws {
        let fixture = Fixture()
        let build = Queue(), deliver = Queue()
        let cache = CommandBarTitleIndexCache(scheduleBuild: build.enqueue, scheduleDelivery: deliver.enqueue)
        let stamp = Index.Stamp(profileID: fixture.profile, state: 1, history: 1, removals: 0)
        var reads = 0
        func source() -> ([BrowserTab], [BrowserHistoryEntry]) { reads += 1; return ([], []) }
        cache.request(stamp, source: source)
        try build.runNext()
        try deliver.runNext()
        cache.request(stamp, source: source)
        #expect(reads == 1)
    }
}
