import Foundation

@main struct HistorySpotlightTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ reason: String) { checks += 1; precondition(value(), reason) }
        let work = UUID(), home = UUID()
        func visit(_ url: String, _ title: String, _ seconds: TimeInterval, _ profile: UUID) -> BrowserHistoryEntry {
            BrowserHistoryEntry(id: UUID(), url: url, title: title, visitedAt: Date(timeIntervalSince1970: seconds), profileID: profile)
        }

        expect(HistorySpotlight.site(of: "https://www.google.com/search?q=uggs") == "google.com", "A site drops its www")
        expect(HistorySpotlight.site(of: "HTTP://Example.TEST/a") == "example.test", "Schemes and hosts compare without case")
        expect(HistorySpotlight.site(of: "https://www./") == "www.", "A bare www host is kept")
        for address in ["parc://history/", "chrome://settings/", "file:///Users/me/a.pdf", "about:blank", "mailto:a@b.test", "https:///path"] {
            expect(HistorySpotlight.site(of: address) == nil, "\(address) stays out of Spotlight")
        }

        let history = [
            visit("https://www.google.com/search?q=uggs", "uggs - Google Search", 100, work),
            visit("parc://history/", "History", 110, work),
            visit("https://example.test/a", "", 120, home),
            visit("https://example.test/b", "Older title", 130, work),
            visit("https://example.test/b", "  ", 160, home),
            visit("https://example.test/b", "Newest title", 150, work),
            visit("https://example.test/b", "Out of order", 140, home),
        ]
        let items = HistorySpotlight.items(from: history)
        expect(Set(items.keys) == ["https://www.google.com/search?q=uggs", "https://example.test/a", "https://example.test/b"],
               "Only web pages are listed, once per address across Profiles")
        expect(items["https://www.google.com/search?q=uggs"] == HistorySpotlightItem(
            url: "https://www.google.com/search?q=uggs", title: "uggs - Google Search", site: "google.com",
            lastVisit: Date(timeIntervalSince1970: 100), visits: 1), "A single visit keeps its title, site and time")
        expect(items["https://example.test/a"]?.title == "example.test", "An untitled page is named by its site")
        let repeated = items["https://example.test/b"]
        expect(repeated?.visits == 4, "Every visit to an address counts")
        expect(repeated?.lastVisit == Date(timeIntervalSince1970: 160), "The newest visit dates the page even out of order")
        expect(repeated?.title == "Newest title", "The newest real title wins over blank and older ones")
        expect(HistorySpotlight.items(from: []).isEmpty, "No history lists nothing")

        let unchanged = HistorySpotlight.changes(from: items, to: items)
        expect(unchanged.upserts.isEmpty && unchanged.removals.isEmpty, "Unchanged history sends nothing")
        let fresh = HistorySpotlight.changes(from: [:], to: items)
        expect(fresh.upserts.map(\.url) == items.keys.sorted() && fresh.removals.isEmpty, "A new index receives every page")

        var next = history.filter { $0.url != "https://example.test/a" }
        next.append(visit("https://example.test/b", "Newest title", 170, work))
        next.append(visit("https://new.test/", "New", 180, home))
        let updated = HistorySpotlight.items(from: next)
        let delta = HistorySpotlight.changes(from: items, to: updated)
        expect(delta.removals == ["https://example.test/a"], "Deleted history leaves Spotlight")
        expect(delta.upserts.map(\.url) == ["https://example.test/b", "https://new.test/"],
               "Revisited and new pages are sent, untouched pages are not")
        let cleared = HistorySpotlight.changes(from: updated, to: [:])
        expect(cleared.upserts.isEmpty && cleared.removals == updated.keys.sorted(), "Clearing history removes every page")

        let state = HistorySpotlight.clientState(for: items)
        expect(state.count < 250, "The saved index state fits Spotlight's limit")
        expect(state.starts(with: HistorySpotlight.format), "The saved index state names its format")
        expect(state == HistorySpotlight.clientState(for: HistorySpotlight.items(from: history.reversed())),
               "The same history always saves the same state")
        expect(state != HistorySpotlight.clientState(for: updated), "Changed history saves a different state")
        var retitled = items
        retitled["https://example.test/a"]?.title = "Renamed"
        expect(state != HistorySpotlight.clientState(for: retitled), "A new title saves a different state")
        expect(HistorySpotlight.clientState(for: [:]) != state, "Empty history has its own state")

        print("History in Spotlight: \(checks) checks passed")
    }
}
