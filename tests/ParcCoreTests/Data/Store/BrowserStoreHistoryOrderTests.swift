import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreHistoryOrderTests {
    private static func commandBarEmptyQueryRecents(
        history: [BrowserHistoryEntry], tabURLs: [String], alreadyShown: Int = 0
    ) -> [BrowserHistoryEntry] {
        var results: [BrowserHistoryEntry] = []
        var seen = Set(tabURLs)
        let shown = alreadyShown
        for visit in BrowserHistoryOrder.newestFirst(history) {
            guard shown + results.count < 8 else { break }
            guard seen.insert(visit.url).inserted, let url = URL(string: visit.url),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            results.append(visit)
        }
        return results
    }

    private static func commandBarEmptyQueryRecentsSorted(
        history: [BrowserHistoryEntry], tabURLs: [String], alreadyShown: Int = 0
    ) -> [BrowserHistoryEntry] {
        var results: [BrowserHistoryEntry] = []
        var seen = Set(tabURLs)
        let shown = alreadyShown
        for visit in history.sorted(by: { $0.visitedAt > $1.visitedAt }) {
            guard shown + results.count < 8 else { break }
            guard seen.insert(visit.url).inserted, let url = URL(string: visit.url),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            results.append(visit)
        }
        return results
    }

    private static func profileVisits() -> [BrowserHistoryEntry] {
        let profile = UUID()
        let other = UUID()
        var history: [BrowserHistoryEntry] = []
        for index in 0..<40 {
            let date = Date(timeIntervalSince1970: TimeInterval(index))
            history.append(BrowserHistoryEntry(
                id: UUID(), url: "https://other.test/\(index)", title: "Other \(index)",
                visitedAt: date, profileID: other))
            history.append(BrowserHistoryEntry(
                id: UUID(), url: index % 7 == 0 ? "parc://settings" : "https://example.test/\(index)",
                title: "Visit \(index)", visitedAt: date, profileID: profile))
        }
        history.append(BrowserHistoryEntry(
            id: UUID(), url: "HTTPS://Example.test/cased", title: "Cased",
            visitedAt: Date(timeIntervalSince1970: 40), profileID: profile))
        return history.filter { $0.profileID == profile }
    }

    private static func tiedVisits() -> [BrowserHistoryEntry] {
        let profile = UUID()
        let tie = Date(timeIntervalSince1970: 100)
        return [
            BrowserHistoryEntry(id: UUID(), url: "https://tie.test/a", title: "A", visitedAt: tie, profileID: profile),
            BrowserHistoryEntry(id: UUID(), url: "https://tie.test/b", title: "B", visitedAt: tie, profileID: profile),
            BrowserHistoryEntry(id: UUID(), url: "https://tie.test/c", title: "C", visitedAt: tie.addingTimeInterval(1), profileID: profile)
        ]
    }

    @Test static func newestFirstKeepsDateSortedIdentitiesAndURLs() {
        let profileHistory = profileVisits()
        let sorted = profileHistory.sorted { $0.visitedAt > $1.visitedAt }
        let walked = BrowserHistoryOrder.newestFirst(profileHistory)
        #expect(walked.map(\.id) == sorted.map(\.id), "Newest-first walk keeps sorted-by-date identity and order")
        #expect(walked.map(\.url) == sorted.map(\.url), "Newest-first walk keeps sorted-by-date URLs")
    }

    @Test static func uniqueVisitTimestampsAreStrictlyChronological() {
        let profileHistory = profileVisits()
        #expect(BrowserHistoryOrder.isStrictlyChronological(profileHistory), "Unique timestamps stay strictly chronological")
    }

    @Test static func emptyQueryRecentsFillTheRemainingSlotsWithUnofferedWebVisits() {
        let profileHistory = profileVisits()
        let tabURLs = ["https://example.test/39", "https://example.test/38"]
        let recents = commandBarEmptyQueryRecents(history: profileHistory, tabURLs: tabURLs, alreadyShown: 2)
        let sortedRecents = commandBarEmptyQueryRecentsSorted(history: profileHistory, tabURLs: tabURLs, alreadyShown: 2)
        #expect(recents.map(\.id) == sortedRecents.map(\.id), "Empty-query recents match the previous sort, skip open tabs, and keep http(s) matching")
        #expect(recents.count == 6, "Remaining empty-query slots stay filled to 8")
        #expect(!recents.contains { $0.url == "parc://settings" }, "Non-web visits stay excluded")
        #expect(recents.contains { $0.url == "HTTPS://Example.test/cased" }, "Scheme matching still uses URL() lowercased host checks")
    }

    @Test static func tiedVisitTimestampsAreNotStrictlyChronological() {
        let tied = tiedVisits()
        #expect(!BrowserHistoryOrder.isStrictlyChronological(tied), "Same-second visits are not strictly chronological")
    }

    @Test static func newestFirstKeepsTheDateSortOrderForTiedTimestamps() {
        let tied = tiedVisits()
        #expect(BrowserHistoryOrder.newestFirst(tied).map(\.id) == tied.sorted { $0.visitedAt > $1.visitedAt }.map(\.id), "Tied timestamps keep the previous date-desc sort identity and order")
    }

    @Test static func emptyQueryRecentsKeepTheDateSortOrderForTiedTimestamps() {
        let tied = tiedVisits()
        #expect(commandBarEmptyQueryRecents(history: tied, tabURLs: []).map(\.id)
                    == commandBarEmptyQueryRecentsSorted(history: tied, tabURLs: []).map(\.id), "Empty-query recents keep sort identity when timestamps collide")
    }

    @Test @MainActor static func historyNewestFirstMatchesISO8601RoundTrip() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let profile: UUID
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
            profile = store.activeSpace.profileID
            let first = store.openResolvedURL(URL(string: "https://roundtrip.test/a")!, kind: .today)
            store.updateTab(first, title: "A", url: "https://roundtrip.test/a")
            let second = store.openResolvedURL(URL(string: "https://roundtrip.test/b")!, kind: .today)
            store.updateTab(second, title: "B", url: "https://roundtrip.test/b")
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            let loaded = reopened.state.history.filter { $0.profileID == profile }
            #expect(BrowserHistoryOrder.newestFirst(loaded).map(\.id)
                        == loaded.sorted { $0.visitedAt > $1.visitedAt }.map(\.id), "Reloaded same-second visits keep the previous date-desc sort")
            #expect(commandBarEmptyQueryRecents(history: loaded, tabURLs: []).map(\.url)
                        == commandBarEmptyQueryRecentsSorted(history: loaded, tabURLs: []).map(\.url), "Empty-query recents keep sort identity after ISO-8601 reload")
        }
    }
}
