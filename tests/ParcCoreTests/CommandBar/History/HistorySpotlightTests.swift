import Foundation
import Testing
@testable import ParcCore

struct HistorySpotlightTests {
    let work = UUID()
    let home = UUID()

    func visit(_ url: String, _ title: String, _ seconds: TimeInterval, _ profile: UUID) -> BrowserHistoryEntry {
        BrowserHistoryEntry(id: UUID(), url: url, title: title, visitedAt: Date(timeIntervalSince1970: seconds), profileID: profile)
    }

    var history: [BrowserHistoryEntry] {
        [
            visit("https://www.google.com/search?q=uggs", "uggs - Google Search", 100, work),
            visit("parc://history/", "History", 110, work),
            visit("https://example.test/a", "", 120, home),
            visit("https://example.test/b", "Older title", 130, work),
            visit("https://example.test/b", "  ", 160, home),
            visit("https://example.test/b", "Newest title", 150, work),
            visit("https://example.test/b", "Out of order", 140, home),
        ]
    }

    var updatedHistory: [BrowserHistoryEntry] {
        var next = history.filter { $0.url != "https://example.test/a" }
        next.append(visit("https://example.test/b", "Newest title", 170, work))
        next.append(visit("https://new.test/", "New", 180, home))
        return next
    }

    @Test func aSiteDropsItsWww() {
        #expect(HistorySpotlight.site(of: "https://www.google.com/search?q=uggs") == "google.com")
    }

    @Test func schemesAndHostsCompareWithoutCase() {
        #expect(HistorySpotlight.site(of: "HTTP://Example.TEST/a") == "example.test")
    }

    @Test func aBareWwwHostIsKept() {
        #expect(HistorySpotlight.site(of: "https://www./") == "www.")
    }

    @Test(arguments: ["parc://history/", "chrome://settings/", "file:///Users/me/a.pdf", "about:blank", "mailto:a@b.test", "https:///path"])
    func nonWebAddressesStayOutOfSpotlight(address: String) {
        #expect(HistorySpotlight.site(of: address) == nil)
    }

    @Test func onlyWebPagesAreListedOncePerAddressAcrossProfiles() {
        let items = HistorySpotlight.items(from: history)
        #expect(Set(items.keys) == ["https://www.google.com/search?q=uggs", "https://example.test/a", "https://example.test/b"])
    }

    @Test func aSingleVisitKeepsItsTitleSiteAndTime() {
        let items = HistorySpotlight.items(from: history)
        #expect(items["https://www.google.com/search?q=uggs"] == HistorySpotlightItem(
            url: "https://www.google.com/search?q=uggs", title: "uggs - Google Search", site: "google.com",
            lastVisit: Date(timeIntervalSince1970: 100), visits: 1))
    }

    @Test func anUntitledPageIsNamedByItsSite() {
        #expect(HistorySpotlight.items(from: history)["https://example.test/a"]?.title == "example.test")
    }

    @Test func everyVisitToAnAddressCounts() {
        #expect(HistorySpotlight.items(from: history)["https://example.test/b"]?.visits == 4)
    }

    @Test func theNewestVisitDatesThePageEvenWhenVisitsAreOutOfOrder() {
        #expect(HistorySpotlight.items(from: history)["https://example.test/b"]?.lastVisit == Date(timeIntervalSince1970: 160))
    }

    @Test func theNewestRealTitleWinsOverBlankAndOlderOnes() {
        #expect(HistorySpotlight.items(from: history)["https://example.test/b"]?.title == "Newest title")
    }

    @Test func noHistoryListsNothing() {
        #expect(HistorySpotlight.items(from: []).isEmpty)
    }

    @Test func unchangedHistorySendsNothing() {
        let items = HistorySpotlight.items(from: history)
        let unchanged = HistorySpotlight.changes(from: items, to: items)
        #expect(unchanged.upserts.isEmpty)
        #expect(unchanged.removals.isEmpty)
    }

    @Test func aNewIndexReceivesEveryPage() {
        let items = HistorySpotlight.items(from: history)
        let fresh = HistorySpotlight.changes(from: [:], to: items)
        #expect(fresh.upserts.map(\.url) == items.keys.sorted())
        #expect(fresh.removals.isEmpty)
    }

    @Test func deletedHistoryLeavesSpotlight() {
        let delta = HistorySpotlight.changes(from: HistorySpotlight.items(from: history), to: HistorySpotlight.items(from: updatedHistory))
        #expect(delta.removals == ["https://example.test/a"])
    }

    @Test func revisitedAndNewPagesAreSentAndUntouchedPagesAreNot() {
        let delta = HistorySpotlight.changes(from: HistorySpotlight.items(from: history), to: HistorySpotlight.items(from: updatedHistory))
        #expect(delta.upserts.map(\.url) == ["https://example.test/b", "https://new.test/"])
    }

    @Test func clearingHistoryRemovesEveryPage() {
        let updated = HistorySpotlight.items(from: updatedHistory)
        let cleared = HistorySpotlight.changes(from: updated, to: [:])
        #expect(cleared.upserts.isEmpty)
        #expect(cleared.removals == updated.keys.sorted())
    }

    @Test func theSavedIndexStateFitsSpotlightsLimitAndNamesItsFormat() {
        let state = HistorySpotlight.clientState(for: HistorySpotlight.items(from: history))
        #expect(state.count < 250)
        #expect(state.starts(with: HistorySpotlight.format))
    }

    @Test func theSameHistoryAlwaysSavesTheSameState() {
        let items = HistorySpotlight.items(from: history)
        #expect(HistorySpotlight.clientState(for: items) == HistorySpotlight.clientState(for: HistorySpotlight.items(from: history.reversed())))
    }

    @Test func changedHistorySavesADifferentState() {
        let state = HistorySpotlight.clientState(for: HistorySpotlight.items(from: history))
        #expect(state != HistorySpotlight.clientState(for: HistorySpotlight.items(from: updatedHistory)))
    }

    @Test func aNewTitleSavesADifferentState() {
        let items = HistorySpotlight.items(from: history)
        var retitled = items
        retitled["https://example.test/a"]?.title = "Renamed"
        #expect(HistorySpotlight.clientState(for: items) != HistorySpotlight.clientState(for: retitled))
    }

    @Test func emptyHistoryHasItsOwnState() {
        let state = HistorySpotlight.clientState(for: HistorySpotlight.items(from: history))
        #expect(HistorySpotlight.clientState(for: [:]) != state)
    }
}
