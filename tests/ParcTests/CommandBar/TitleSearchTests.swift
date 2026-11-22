import Foundation
import Testing
@testable import ParcCore
@testable import ParcCommandBar

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

extension TitleSearchTests {
    private typealias Candidate = CommandBarRanking.Candidate

    private struct Ranked {
        var candidates: [Candidate] = []
        var titled: [(index: Int, key: String, score: CommandBarTitleMatch.Score, keepsWeak: Bool)] = []

        mutating func add(_ candidate: Candidate, score: CommandBarTitleMatch.Score? = nil, keepsWeak: Bool = false) {
            if let score { titled.append((candidates.count, candidate.key, score, keepsWeak)) }
            candidates.append(candidate)
        }

        mutating func addSearches(_ terms: [String]) {
            for (rank, term) in terms.enumerated() { add(Self.search(term, rank)) }
        }

        mutating func addTab(_ tab: BrowserTab, query: CommandBarTitleQuery?, now: Date) {
            let url = URL(string: tab.url)!
            let score = query.flatMap {
                CommandBarTitleMatch.score($0, CommandBarTitleTokens(titles: [tab.title], host: url.host), kind: .tab,
                                           lastUsed: tab.lastAccessed, visits: 0, now: now)
            }
            add(Candidate(archetype: .tab, key: CommandBarTitleIndex.tabKey(url: tab.url, title: tab.title, id: tab.id),
                          texts: [tab.title, url.host ?? "", tab.url], urlKey: CommandBarRowDiff.pageKey(url)),
                score: score)
        }

        mutating func addHits(_ index: CommandBarTitleIndex, _ query: CommandBarTitleQuery, now: Date) {
            let hits = index.search(query, now: now)
            for hit in hits.archived {
                add(Candidate(archetype: .archived, key: hit.entry.key, urlKey: hit.entry.urlKey), score: hit.score, keepsWeak: true)
            }
            for hit in hits.pages {
                add(Candidate(archetype: .history, key: hit.entry.key, urlKey: hit.entry.urlKey), score: hit.score, keepsWeak: true)
            }
        }

        func resolved() -> [Candidate] {
            var result = candidates
            let scores = CommandBarTitleMatch.resolve(titled.map { ($0.key, $0.score, $0.keepsWeak) })
            for (entry, score) in zip(titled, scores) { result[entry.index].titleScore = score }
            return result
        }

        static func search(_ terms: String, _ rank: Int) -> Candidate {
            Candidate(archetype: .chromium, key: CommandBarRowDiff.searchKey(terms), chromiumRank: rank)
        }

        static func page(_ url: String, _ rank: Int, title: String = "") -> Candidate {
            Candidate(archetype: .chromium, key: CommandBarRanking.pageKey(URL(string: url)!, title: title), chromiumRank: rank,
                      urlKey: CommandBarRowDiff.pageKey(URL(string: url)!))
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_900_000_000)
    private static let profile = UUID()

    private static func tab(_ title: String, _ url: String, archivedAgo: TimeInterval? = nil) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: UUID(), profileID: profile, url: url, title: title, kind: .today, folderID: nil,
                   createdAt: now.addingTimeInterval(-86_400 * 30), lastAccessed: now,
                   archivedAt: archivedAgo.map { now.addingTimeInterval(-$0) }, savedURL: url, savedTitle: title)
    }

    private static func visit(_ url: String, _ title: String, _ secondsAgo: Double) -> BrowserHistoryEntry {
        BrowserHistoryEntry(id: UUID(), url: url, title: title, visitedAt: now.addingTimeInterval(-secondsAgo), profileID: profile)
    }

    private static func build(tabs: [BrowserTab] = [], history: [BrowserHistoryEntry] = [], revision: UInt64 = 1,
                              removals: UInt64 = 0, reusing: CommandBarTitleIndex? = nil) -> CommandBarTitleIndex {
        Index.build(profileID: profile, historyRevision: revision, historyRemovals: removals,
                    tabs: tabs, history: history, reusing: reusing)
    }

    private static let suggestions = ["dashboard", "dashboard meaning", "dashboard camera", "dashboard lights",
                                      "dashboard design", "dashboard ui"]

    @Test(arguments: ["da", "  ||  "])
    func aTooShortOrPunctuationOnlyInputIsNotATitleQuery(input: String) {
        #expect(CommandBarTitleQuery(input) == nil)
    }

    @Test func aWordIsATitleQuery() throws {
        #expect(try #require(CommandBarTitleQuery("dashboard")).words.count == 1)
    }

    @Test func twentyDaysReadAsTwoWeeks() {
        #expect(CommandBarTitleText.age(from: Self.now.addingTimeInterval(-1_728_000), to: Self.now) == "2 weeks ago")
    }

    @Test func aTitleMatchRanksAMidTitleWordBelowSuggestionsOnlyWithoutScoring() throws {
        let dashboard = Self.tab("My Apps Dashboard | Fullscript", "https://us.fullscript.com/dashboard")
        let query = Match.wordsQuery("dashboard", nativeRowsAnswer: true, defaultIsSearch: true)
        var plain = Ranked(), scored = Ranked()
        plain.addSearches(Self.suggestions)
        scored.addSearches(Self.suggestions)
        plain.addTab(dashboard, query: nil, now: Self.now)
        scored.addTab(dashboard, query: query, now: Self.now)
        let before = CommandBarRanking.rank(plain.resolved(), query: "dashboard")
        let after = CommandBarRanking.rank(scored.resolved(), query: "dashboard")
        #expect(try #require(before.firstIndex(of: 6)) >= 5)
        #expect(after.prefix(2).elementsEqual([0, 6]))
    }

    @Test func aTypedAddressGetsNoTitleScoresAndKeepsChromiumsOrder() {
        var ranked = Ranked()
        ranked.add(Ranked.page("https://us.fullscript.com/dashboard", 0, title: "My Apps Dashboard | Fullscript"))
        ranked.add(Ranked.search("us.fullscript.com/dash", 1))
        ranked.add(Ranked.page("https://us.fullscript.com/dashboard/orders", 2))
        let query = Match.wordsQuery("us.fullscript.com/dash", nativeRowsAnswer: true, defaultIsSearch: false)
        ranked.addTab(Self.tab("Fullscript dash notes", "https://notes.example.com/fullscript"), query: query, now: Self.now)
        #expect(ranked.titled.isEmpty)
        #expect(CommandBarRanking.rank(ranked.resolved(), query: "us.fullscript.com/dash").prefix(3).elementsEqual([0, 1, 2]))
    }

    private struct Planning {
        let planning = TitleSearchTests.tab("Quarterly Planning — Roadmap", "https://docs.example.com/planning", archivedAgo: 3 * 86_400)
        let older = TitleSearchTests.tab("Planning poker", "https://poker.example.com/", archivedAgo: 20 * 86_400)
        let open = TitleSearchTests.tab("Planning board", "https://board.example.com/")
        let history = [
            TitleSearchTests.visit("https://docs.example.com/planning", "Quarterly Planning — Roadmap", 4 * 86_400),
            TitleSearchTests.visit("https://wiki.example.com/q3", "Q3 planning notes", 9 * 86_400),
            TitleSearchTests.visit("https://www.wiki.example.com/q3", "Q3 planning notes", 8 * 86_400),
            TitleSearchTests.visit("https://board.example.com/", "Planning board", 60),
            TitleSearchTests.visit("https://news.example.com/", "Morning news", 30),
        ]
        var index: CommandBarTitleIndex { TitleSearchTests.build(tabs: [open, planning, older], history: history) }
        let query = CommandBarTitleQuery("planning")!

        func merged() -> (candidates: [Candidate], order: [Int]) {
            var ranked = Ranked()
            ranked.add(Ranked.search("planning", 0))
            for rank in 1...5 { ranked.add(Ranked.search("planning \(rank)", rank)) }
            ranked.add(Ranked.page("https://wiki.example.com/q3", 6, title: "Q3 planning notes"))
            ranked.add(Ranked.page("https://docs.example.com/planning", 7))
            ranked.addTab(open, query: query, now: TitleSearchTests.now)
            ranked.addHits(index, query, now: TitleSearchTests.now)
            let candidates = ranked.resolved()
            return (candidates, CommandBarRanking.rank(candidates, query: "planning"))
        }
    }

    @Test func pastVisitsOfTheSamePageMergeIntoOnePage() {
        let planning = Planning()
        #expect(planning.index.pages.count == 4)
        #expect(planning.index.visits(forKey: CommandBarRanking.pageKey(URL(string: "https://wiki.example.com/q3")!, title: "")) == 2)
    }

    @Test func aMergedListNeverShowsTheSamePageTwice() {
        let (candidates, order) = Planning().merged()
        let keys = order.map { candidates[$0].key }
        #expect(Set(keys).count == keys.count)
    }

    @Test(arguments: [
        ("https://board.example.com/", "Planning board", [CommandBarRanking.Archetype.tab]),
        ("https://docs.example.com/planning", "Quarterly Planning — Roadmap", [.archived]),
        ("https://wiki.example.com/q3", "", [.chromium]),
    ])
    func theMostSpecificOwnerWinsAPageThatSeveralSourcesOffer(url: String, title: String, expected: [CommandBarRanking.Archetype]) {
        let (candidates, order) = Planning().merged()
        let key = CommandBarRanking.pageKey(URL(string: url)!, title: title)
        #expect(order.filter { candidates[$0].key == key }.map { candidates[$0].archetype } == expected)
    }

    @Test func threeStrongTitleMatchesFollowTheDefaultThenTheSuggestions() {
        let (candidates, order) = Planning().merged()
        #expect(order.first == 0)
        #expect(order.prefix(5).map { candidates[$0].archetype } == [.chromium, .tab, .archived, .archived, .chromium])
    }

    @Test func aPastPagesTitleMatchLiftsChromiumsRowForItAboveTheSuggestions() throws {
        let planning = Planning()
        var ranked = Ranked()
        ranked.add(Ranked.search("notes", 0))
        for rank in 1...5 { ranked.add(Ranked.search("notes \(rank)", rank)) }
        ranked.add(Ranked.page("https://wiki.example.com/q3", 6, title: "Q3 planning notes"))
        ranked.addHits(planning.index, try #require(CommandBarTitleQuery("notes")), now: Self.now)
        #expect(CommandBarRanking.rank(ranked.resolved(), query: "notes").prefix(2).elementsEqual([0, 6]))
    }

    @Test func atMostThreePagesRiseAboveSuggestionsAndDuplicatesStayWithThem() {
        let resolved = Match.resolve([
            ("a", .init(strong: 0.9, weak: 0.5), false), ("b", .init(strong: 0.88, weak: 0.5), true),
            ("c", .init(strong: 0.86, weak: 0.5), true), ("d", .init(strong: 0.84, weak: 0.5), true),
            ("e", .init(strong: 0.83, weak: 0.4), false), ("a", .init(strong: 0.8, weak: 0.4), true),
        ])
        #expect(resolved == [0.9, 0.88, 0.86, 0.5, nil, 0.8])
    }

    @Test func searchingLeavesOutTheCurrentPageAndTheArchiveWhenAsked() throws {
        let planning = Planning()
        let news = try #require(CommandBarTitleQuery("news"))
        #expect(planning.index.search(news, now: Self.now, excludingURLKey: "page:news.example.com").pages.isEmpty)
        #expect(planning.index.search(planning.query, now: Self.now, includesArchive: false).archived.isEmpty)
    }

    @Test func archivedTabsComeNewestFirstAndKeepTheirRealAddress() throws {
        let planning = Planning()
        #expect(planning.index.archived.map(\.tabID) == [planning.planning.id, planning.older.id])
        let hit = try #require(planning.index.search(planning.query, now: Self.now).archived.first)
        #expect(hit.entry.tabID == planning.planning.id)
        #expect(hit.entry.url == planning.planning.url)
    }

    private struct Crowd {
        let archived = (0..<5_000).map { number in
            TitleSearchTests.tab("Report \(number) planning", "https://reports.example.com/\(number)", archivedAgo: Double(number) * 60 + 1)
        }
        let visits = (0..<30_000).map { number in
            TitleSearchTests.visit("https://pages.example.com/\(number % 12_000)", "Page \(number % 12_000) planning", Double(number))
        }
        var large: CommandBarTitleIndex {
            TitleSearchTests.build(tabs: archived.shuffled(), history: visits.reversed(), revision: 2)
        }
    }

    @Test func onlyTheNewestArchivedTabsAreSearched() {
        let crowd = Crowd()
        let index = crowd.large
        #expect(index.archived.count == Index.archiveWindow)
        #expect(index.archived.first?.tabID == crowd.archived[0].id)
        #expect(index.archived.last?.tabID == crowd.archived[Index.archiveWindow - 1].id)
    }

    @Test func onlyTheNewestPastPagesAreSearchedAndCounted() {
        let index = Crowd().large
        #expect(index.pages.count == Index.historyWindow)
        #expect(index.pages.first?.url == "https://pages.example.com/0")
        #expect(index.visits(forKey: "page:pages.example.com/0") == 1)
    }

    @Test func eachKeystrokeHandsTheRankerAtMostTenMatchesOfEachKind() throws {
        let hits = Crowd().large.search(try #require(CommandBarTitleQuery("planning")), now: Self.now)
        #expect(hits.archived.count == Index.hitLimit)
        #expect(hits.pages.count == Index.hitLimit)
    }

    @Test func floodedMatchesAreCappedAtThreePerKindAndFifteenInAll() throws {
        let query = try #require(CommandBarTitleQuery("planning"))
        var ranked = Ranked()
        ranked.add(Ranked.search("planning", 0))
        for rank in 1...7 { ranked.add(Ranked.search("planning \(rank)", rank)) }
        ranked.addHits(Crowd().large, query, now: Self.now)
        let candidates = ranked.resolved()
        let order = CommandBarRanking.rank(candidates, query: "planning")
        #expect(order.filter { candidates[$0].archetype == .archived }.count == 3)
        #expect(order.filter { candidates[$0].archetype == .history }.count == 3)
        #expect(order.prefix(5).filter { candidates[$0].archetype == .chromium }.count == 2)
        #expect(order.count <= CommandBarRanking.limit)
    }

    @Test func anIndexRebuildsWhenHistoryOrTheArchiveChanges() {
        let crowd = Crowd()
        let large = crowd.large
        #expect(Self.build(tabs: crowd.archived, history: crowd.visits.reversed(), revision: 2, reusing: large) === large)
        let deleted = Self.build(tabs: crowd.archived, history: Array(crowd.visits.reversed().dropLast(1)), revision: 2,
                                 removals: 1, reusing: large)
        #expect(deleted !== large)
        #expect(deleted.pages.first?.url == "https://pages.example.com/1")
        #expect(deleted.withdrawsEntries(of: large))
        #expect(!large.withdrawsEntries(of: large))
        let fresh = Self.build(tabs: crowd.archived, history: crowd.visits.reversed() + [Self.visit("https://fresh.example.com/", "Fresh planning", -5)],
                               revision: 3, reusing: large)
        #expect(fresh !== large)
        #expect(fresh.pages.first?.url == "https://fresh.example.com/")
    }

    @Test func aTabPutBackLeavesTheArchiveWindow() {
        let crowd = Crowd()
        var restored = crowd.archived
        restored[0].archivedAt = nil
        let index = Self.build(tabs: restored, history: [], revision: 3)
        #expect(index.archived.first?.tabID == crowd.archived[1].id)
    }
}
