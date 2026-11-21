import Testing
@testable import ParcCore

struct HistoryScanSkipTests {
    typealias Skip = CommandBarHistoryScanSkip

    func key(query: String = "", revision: UInt64 = 3, excluded: String? = "https://now.test",
             tabs: [String] = ["https://tab.test"]) -> Skip.Key {
        Skip.key(query: query, historyRevision: revision, excludedURL: excluded, tabURLs: tabs)
    }

    var ranked: [(url: String, title: String)] {
        [
            ("https://open.test", "Open"), ("ftp://skip.test", "FTP"), ("https://a.test", "A"), ("https://b.test", "B"),
            ("https://c.test", ""), ("https://d.test", "D"), ("https://e.test", "E"), ("https://f.test", "F"),
            ("https://g.test", "G"), ("https://h.test", "H"), ("https://i.test", "I"),
        ]
    }

    var visits: [Skip.Visit] {
        Skip.emptyQueryVisits(rankedURLsAndTitles: ranked, tabURLs: ["https://open.test"], limit: 8)
    }

    @Test func theFirstHistoryScanNeverReuses() {
        #expect(!Skip.shouldReuse(previous: nil, next: key()))
    }

    @Test func anIdenticalHistoryScanKeyReuses() {
        #expect(Skip.shouldReuse(previous: key(), next: key()))
    }

    @Test func typingACharacterDoesNotReuseTheHistoryScan() {
        #expect(!Skip.shouldReuse(previous: key(), next: key(query: "a")))
    }

    @Test func aHistoryRevisionChangeDoesNotReuse() {
        #expect(!Skip.shouldReuse(previous: key(), next: key(revision: 4)))
    }

    @Test func anExcludedCurrentURLChangeDoesNotReuse() {
        #expect(!Skip.shouldReuse(previous: key(), next: key(excluded: "https://other.test")))
    }

    @Test func aTabURLMembershipChangeDoesNotReuse() {
        #expect(!Skip.shouldReuse(previous: key(), next: key(tabs: ["https://tab.test", "https://new.test"])))
    }

    @Test func emptyQueryTopEightSkipsTabCollisionsAndNonWebSchemesAndKeepsOrder() {
        #expect(visits.map(\.url) == [
            "https://a.test", "https://b.test", "https://c.test", "https://d.test",
            "https://e.test", "https://f.test", "https://g.test", "https://h.test",
        ])
    }

    @Test func emptyTitlesAreRetainedForResultRebuild() {
        #expect(visits[2].title == "")
    }

    @Test func theCombinedEmptyQueryBudgetTakesAPrefixOfTheCachedHistorySlice() {
        #expect(Array(visits.prefix(max(0, 8 - 3))).map(\.url) == [
            "https://a.test", "https://b.test", "https://c.test", "https://d.test", "https://e.test",
        ])
    }

    @Test func eightTabRowsLeaveNoHistoryBudget() {
        #expect(Array(visits.prefix(max(0, 8 - 8))).isEmpty)
    }

    @Test func recentsSkipTheSameTitledPageUnderOtherParametersAndPagesAnOpenTabAlreadyShows() {
        let samePage: (String, String) -> String? = { title, url in
            title.isEmpty ? nil : title + "|" + String(url.prefix { $0 != "?" })
        }
        let paged = Skip.emptyQueryVisits(rankedURLsAndTitles: [
            ("https://a.test/x?login=1", "A"), ("https://a.test/x?login=2", "A"), ("https://a.test/x?v=3", "Other"),
            ("https://b.test/y?z=1", "Open"), ("https://c.test/?q=1", ""), ("https://c.test/?q=2", ""),
        ], tabURLs: [], tabPages: ["Open|https://b.test/y"], samePage: samePage, limit: 8)
        #expect(paged.map(\.url) == ["https://a.test/x?login=1", "https://a.test/x?v=3", "https://c.test/?q=1", "https://c.test/?q=2"])
    }

    @Test func aTabTitleChangeDoesNotReuse() {
        let before = Skip.key(query: "", historyRevision: 1, excludedURL: nil, tabURLs: ["https://t.test"], tabTitles: ["A"])
        let after = Skip.key(query: "", historyRevision: 1, excludedURL: nil, tabURLs: ["https://t.test"], tabTitles: ["B"])
        #expect(!Skip.shouldReuse(previous: before, next: after))
    }

    @Test func stableMembershipTokensMatch() {
        #expect(Skip.historyMembershipToken(revision: 1, excludedURL: nil) == Skip.historyMembershipToken(revision: 1, excludedURL: nil))
    }

    @Test func aRevisionChangeAltersTheMembershipToken() {
        #expect(Skip.historyMembershipToken(revision: 1, excludedURL: nil) != Skip.historyMembershipToken(revision: 2, excludedURL: nil))
    }

    @Test func anExcludedURLChangeAltersTheMembershipToken() {
        #expect(Skip.historyMembershipToken(revision: 1, excludedURL: nil)
                != Skip.historyMembershipToken(revision: 1, excludedURL: "https://x.test"))
    }
}
