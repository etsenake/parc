import Foundation

@main
struct HistoryScanSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func main() {
        typealias Skip = CommandBarHistoryScanSkip

        let idle = Skip.key(query: "", historyRevision: 3, excludedURL: "https://now.test",
                            tabURLs: ["https://tab.test"])
        expect(Skip.shouldReuse(previous: nil, next: idle) == false, "First history scan never reuses")
        expect(Skip.shouldReuse(previous: idle, next: idle), "Identical history scan key reuses")
        expect(Skip.shouldReuse(previous: idle,
                                next: Skip.key(query: "a", historyRevision: 3,
                                               excludedURL: "https://now.test",
                                               tabURLs: ["https://tab.test"])) == false,
               "Typing a character must not reuse history scan")
        expect(Skip.shouldReuse(previous: idle,
                                next: Skip.key(query: "", historyRevision: 4,
                                               excludedURL: "https://now.test",
                                               tabURLs: ["https://tab.test"])) == false,
               "historyRevision change must not reuse")
        expect(Skip.shouldReuse(previous: idle,
                                next: Skip.key(query: "", historyRevision: 3,
                                               excludedURL: "https://other.test",
                                               tabURLs: ["https://tab.test"])) == false,
               "Excluded current-URL change must not reuse")
        expect(Skip.shouldReuse(previous: idle,
                                next: Skip.key(query: "", historyRevision: 3,
                                               excludedURL: "https://now.test",
                                               tabURLs: ["https://tab.test", "https://new.test"])) == false,
               "Tab URL membership change must not reuse")

        let tabs = Set(["https://open.test"])
        let ranked: [(url: String, title: String)] = [
            ("https://open.test", "Open"),
            ("ftp://skip.test", "FTP"),
            ("https://a.test", "A"),
            ("https://b.test", "B"),
            ("https://c.test", ""),
            ("https://d.test", "D"),
            ("https://e.test", "E"),
            ("https://f.test", "F"),
            ("https://g.test", "G"),
            ("https://h.test", "H"),
            ("https://i.test", "I"),
        ]
        let visits = Skip.emptyQueryVisits(rankedURLsAndTitles: ranked, tabURLs: tabs, limit: 8)
        expect(visits.map(\.url) == [
            "https://a.test", "https://b.test", "https://c.test", "https://d.test",
            "https://e.test", "https://f.test", "https://g.test", "https://h.test",
        ], "Empty-query top-8 skips tab collisions and non-http(s), keeps order")
        expect(visits[2].title == "", "Empty titles are retained for Result rebuild")

        let remainingAfterThreeTabs = Array(visits.prefix(max(0, 8 - 3)))
        expect(remainingAfterThreeTabs.map(\.url) == [
            "https://a.test", "https://b.test", "https://c.test", "https://d.test", "https://e.test",
        ], "Combined empty-query budget takes a prefix of the cached history slice")
        expect(Array(visits.prefix(max(0, 8 - 8))).isEmpty,
               "Eight tab rows leave no history budget")

        let tokenA = Skip.historyMembershipToken(revision: 1, excludedURL: nil)
        let tokenB = Skip.historyMembershipToken(revision: 1, excludedURL: nil)
        let tokenRev = Skip.historyMembershipToken(revision: 2, excludedURL: nil)
        let tokenURL = Skip.historyMembershipToken(revision: 1, excludedURL: "https://x.test")
        expect(tokenA == tokenB, "Stable membership tokens match")
        expect(tokenA != tokenRev, "Revision change alters membership token")
        expect(tokenA != tokenURL, "Excluded URL change alters membership token")

        print("\(assertions) command-bar history scan skip assertions passed")
    }
}
